package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"db_query/internal/adapters/mongo"
	"db_query/internal/adapters/mysql"
	"db_query/internal/adapters/pgsql"
	"db_query/internal/adapters/redis"
	"db_query/internal/cli"
	"db_query/internal/config"
	"db_query/internal/core"
)

func main() {
	opts, err := cli.Parse(os.Args[1:])
	if err != nil {
		printErrorAndExit("", err)
	}

	envVars := map[string]string{}
	var configErr error
	configPath, err := config.ResolveConfigPath(opts.ConfigPath)
	if err != nil {
		configErr = err
	} else {
		loaded, loadErr := config.LoadEnvFile(configPath)
		if loadErr != nil {
			configErr = loadErr
		} else {
			envVars = loaded
		}
	}

	startedAt := time.Now()
	switch opts.Driver {
	case "mysql":
		runSQLDriver(startedAt, "mysql", opts, envVars, configErr)
	case "pgsql":
		runSQLDriver(startedAt, "pgsql", opts, envVars, configErr)
	case "mongo":
		if configErr != nil {
			printErrorAndExit(opts.Driver, core.WrapAppError(core.CodeInvalidConfig, configErr.Error(), configErr))
		}
		profile, pErr := config.ResolveProfile(opts.Driver, opts.Profile, envVars)
		if pErr != nil {
			printErrorAndExit(opts.Driver, core.WrapAppError(core.CodeInvalidConfig, pErr.Error(), pErr))
		}
		runMongoDriver(startedAt, profile, opts, envVars)
	case "redis":
		if configErr != nil {
			printErrorAndExit(opts.Driver, core.WrapAppError(core.CodeInvalidConfig, configErr.Error(), configErr))
		}
		profile, pErr := config.ResolveProfile(opts.Driver, opts.Profile, envVars)
		if pErr != nil {
			printErrorAndExit(opts.Driver, core.WrapAppError(core.CodeInvalidConfig, pErr.Error(), pErr))
		}
		runRedisDriver(startedAt, profile, opts, envVars)
	default:
		printErrorAndExit(opts.Driver, core.NewAppError(core.CodeInvalidArgument, "unsupported driver"))
	}
}

func runSQLDriver(startedAt time.Time, driver string, opts cli.Options, envVars map[string]string, configErr error) {
	query, err := resolveSQLQuery(opts)
	if err != nil {
		printErrorAndExit(driver, err)
	}

	rulesPrefix := strings.ToUpper(driver)
	rules := core.BuildSQLRulesFromEnv(envVars, rulesPrefix)
	validation, err := core.ValidateSQL(query, rules)
	if err != nil {
		printErrorAndExit(driver, err)
	}

	if validation.ShouldGenerateFile {
		filePath, err := core.GenerateSQLFile(validation.NormalizedSQL, validation.FileKind)
		if err != nil {
			printErrorAndExit(driver, err)
		}
		payload := core.SQLFilePayload{
			Status:   "sql_file_generated",
			Action:   validation.Action,
			FilePath: filePath,
			Message:  "检测到 DDL/DML 请求，已生成 SQL 文件，请执行该文件中的 DDL/DML 操作。",
			Query:    validation.NormalizedSQL,
		}
		if err := core.PrintJSON(payload); err != nil {
			printErrorAndExit(driver, core.WrapAppError(core.CodeInternalError, "failed to write output", err))
		}
		return
	}

	if configErr != nil {
		printErrorAndExit(driver, core.WrapAppError(core.CodeInvalidConfig, configErr.Error(), configErr))
	}
	profile, err := config.ResolveProfile(driver, opts.Profile, envVars)
	if err != nil {
		printErrorAndExit(driver, core.WrapAppError(core.CodeInvalidConfig, err.Error(), err))
	}

	connCfg, err := resolveSQLConnConfig(driver, profile, opts, envVars)
	if err != nil {
		printErrorAndExit(driver, err)
	}

	timeout := connCfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()

	var columns []string
	var rows []map[string]any
	switch driver {
	case "mysql":
		columns, rows, err = mysql.Query(ctx, connCfg, validation.NormalizedSQL)
	case "pgsql":
		columns, rows, err = pgsql.Query(ctx, connCfg, validation.NormalizedSQL)
	default:
		err = core.NewAppError(core.CodeInvalidArgument, "unsupported sql driver")
	}
	if err != nil {
		printErrorAndExit(driver, err)
	}
	if len(rows) > opts.MaxRows {
		printErrorAndExit(driver, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), opts.MaxRows)))
	}

	payload := core.SuccessPayload{
		Driver:   driver,
		Profile:  profile,
		Query:    validation.NormalizedSQL,
		RowCount: len(rows),
		Columns:  columns,
		Rows:     rows,
		Meta: map[string]any{
			"elapsed_ms": time.Since(startedAt).Milliseconds(),
		},
	}
	if err := core.PrintJSON(payload); err != nil {
		printErrorAndExit(driver, core.WrapAppError(core.CodeInternalError, "failed to write output", err))
	}
}

func runMongoDriver(startedAt time.Time, profile string, opts cli.Options, envVars map[string]string) {
	connCfg, err := resolveMongoConnConfig(profile, opts, envVars)
	if err != nil {
		printErrorAndExit("mongo", err)
	}

	timeout := connCfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()

	columns, rows, err := mongo.Query(ctx, connCfg, opts.Query, opts.MaxRows)
	if err != nil {
		printErrorAndExit("mongo", err)
	}
	if len(rows) > opts.MaxRows {
		printErrorAndExit("mongo", core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), opts.MaxRows)))
	}

	payload := core.SuccessPayload{
		Driver:   "mongo",
		Profile:  profile,
		Query:    strings.TrimSpace(opts.Query),
		RowCount: len(rows),
		Columns:  columns,
		Rows:     rows,
		Meta: map[string]any{
			"elapsed_ms": time.Since(startedAt).Milliseconds(),
		},
	}
	if err := core.PrintJSON(payload); err != nil {
		printErrorAndExit("mongo", core.WrapAppError(core.CodeInternalError, "failed to write output", err))
	}
}

func runRedisDriver(startedAt time.Time, profile string, opts cli.Options, envVars map[string]string) {
	connCfg, err := resolveRedisConnConfig(profile, opts, envVars)
	if err != nil {
		printErrorAndExit("redis", err)
	}

	timeout := connCfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()

	columns, rows, err := redis.Query(ctx, connCfg, opts.Query, opts.MaxRows)
	if err != nil {
		printErrorAndExit("redis", err)
	}
	if len(rows) > opts.MaxRows {
		printErrorAndExit("redis", core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), opts.MaxRows)))
	}

	payload := core.SuccessPayload{
		Driver:   "redis",
		Profile:  profile,
		Query:    strings.TrimSpace(opts.Query),
		RowCount: len(rows),
		Columns:  columns,
		Rows:     rows,
		Meta: map[string]any{
			"elapsed_ms": time.Since(startedAt).Milliseconds(),
		},
	}
	if err := core.PrintJSON(payload); err != nil {
		printErrorAndExit("redis", core.WrapAppError(core.CodeInternalError, "failed to write output", err))
	}
}

func resolveSQLQuery(opts cli.Options) (string, error) {
	if strings.TrimSpace(opts.Query) != "" {
		return strings.TrimSpace(opts.Query), nil
	}
	return core.BuildStructuredSQL(opts.Table, opts.Columns, opts.Where, opts.OrderBy, opts.Limit)
}

func resolveSQLConnConfig(driver, profile string, opts cli.Options, envVars map[string]string) (core.SQLConnConfig, error) {
	prefix := strings.ToUpper(driver)

	host := firstNonEmpty(opts.Host, config.GetProfileValue(envVars, prefix+"_HOST", profile))
	port := firstNonZero(opts.Port, parseIntDefault(config.GetProfileValue(envVars, prefix+"_PORT", profile), 0))
	user := firstNonEmpty(opts.User, config.GetProfileValue(envVars, prefix+"_USER", profile))
	password := firstNonEmpty(opts.Password, config.GetProfileValue(envVars, prefix+"_PASSWORD", profile))
	socket := firstNonEmpty(opts.Socket, config.GetProfileValue(envVars, prefix+"_SOCKET", profile))
	timeout := firstNonZero(opts.Timeout, parseIntDefault(config.GetProfileValue(envVars, prefix+"_TIMEOUT", profile), 0))
	sslMode := firstNonEmpty(opts.SSLMode, config.GetProfileValue(envVars, prefix+"_SSLMODE", profile))

	rawDatabases := config.GetProfileValue(envVars, prefix+"_DATABASE", profile)
	dbCandidates := config.ParseCSV(rawDatabases)
	database := strings.TrimSpace(opts.Database)
	switch {
	case len(dbCandidates) == 0:
		database = firstNonEmpty(database, "")
	case database == "":
		if len(dbCandidates) == 1 {
			database = dbCandidates[0]
		} else {
			return core.SQLConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("multiple databases configured in %s_DATABASE_%s; pass --database (%s)", prefix, profile, strings.Join(dbCandidates, ", ")))
		}
	default:
		if !contains(dbCandidates, database) {
			return core.SQLConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("--database must be one of %s_DATABASE_%s: %s", prefix, profile, strings.Join(dbCandidates, ", ")))
		}
	}

	if user == "" {
		return core.SQLConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("%s user is required (use --user or %s_USER_%s)", driver, prefix, profile))
	}
	if database == "" {
		return core.SQLConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("%s database is required (use --database or %s_DATABASE_%s)", driver, prefix, profile))
	}

	return core.SQLConnConfig{
		Host:           host,
		Port:           port,
		User:           user,
		Password:       password,
		Database:       database,
		Socket:         socket,
		TimeoutSeconds: timeout,
		SSLMode:        sslMode,
	}, nil
}

func resolveMongoConnConfig(profile string, opts cli.Options, envVars map[string]string) (core.MongoConnConfig, error) {
	uri := firstNonEmpty(opts.URI, config.GetProfileValue(envVars, "MONGO_URI", profile))
	database := firstNonEmpty(opts.Database, config.GetProfileValue(envVars, "MONGO_DATABASE", profile))
	timeout := firstNonZero(opts.Timeout, parseIntDefault(config.GetProfileValue(envVars, "MONGO_TIMEOUT", profile), 0))
	allowedOperations := normalizeLowerCSV(config.ParseCSV(firstNonEmpty(
		config.GetProfileValue(envVars, "MONGO_ALLOWED_OPERATIONS", profile),
		envVars["MONGO_ALLOWED_OPERATIONS"],
	)))
	if len(allowedOperations) == 0 {
		allowedOperations = []string{"find", "aggregate"}
	}

	forbiddenAggStages := normalizeMongoStages(config.ParseCSV(firstNonEmpty(
		config.GetProfileValue(envVars, "MONGO_FORBIDDEN_AGG_STAGES", profile),
		envVars["MONGO_FORBIDDEN_AGG_STAGES"],
	)))
	if len(forbiddenAggStages) == 0 {
		forbiddenAggStages = []string{"$out", "$merge"}
	}

	if uri == "" {
		return core.MongoConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("mongo uri is required (use --uri or MONGO_URI_%s)", profile))
	}
	if database == "" {
		return core.MongoConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("mongo database is required (use --database or MONGO_DATABASE_%s)", profile))
	}
	return core.MongoConnConfig{
		URI:                uri,
		Database:           database,
		TimeoutSeconds:     timeout,
		AllowedOperations:  allowedOperations,
		ForbiddenAggStages: forbiddenAggStages,
	}, nil
}

func resolveRedisConnConfig(profile string, opts cli.Options, envVars map[string]string) (core.RedisConnConfig, error) {
	addr := firstNonEmpty(opts.Addr, config.GetProfileValue(envVars, "REDIS_ADDR", profile))
	user := firstNonEmpty(opts.User, config.GetProfileValue(envVars, "REDIS_USER", profile))
	password := firstNonEmpty(opts.Password, config.GetProfileValue(envVars, "REDIS_PASSWORD", profile))
	timeout := firstNonZero(opts.Timeout, parseIntDefault(config.GetProfileValue(envVars, "REDIS_TIMEOUT", profile), 0))
	allowedCommands := normalizeUpperCSV(config.ParseCSV(firstNonEmpty(
		config.GetProfileValue(envVars, "REDIS_ALLOWED_COMMANDS", profile),
		envVars["REDIS_ALLOWED_COMMANDS"],
	)))
	if len(allowedCommands) == 0 {
		allowedCommands = []string{"GET", "MGET", "HGET", "HGETALL", "SMEMBERS", "ZRANGE", "LRANGE", "SCAN"}
	}

	db := parseIntDefault(config.GetProfileValue(envVars, "REDIS_DB", profile), 0)
	if strings.TrimSpace(opts.Database) != "" {
		parsedDB, err := strconv.Atoi(strings.TrimSpace(opts.Database))
		if err != nil {
			return core.RedisConnConfig{}, core.WrapAppError(core.CodeInvalidArgument, "--database for redis must be integer db index", err)
		}
		db = parsedDB
	}
	if addr == "" {
		return core.RedisConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("redis addr is required (use --addr or REDIS_ADDR_%s)", profile))
	}

	return core.RedisConnConfig{
		Addr:            addr,
		User:            user,
		Password:        password,
		DB:              db,
		TimeoutSeconds:  timeout,
		AllowedCommands: allowedCommands,
	}, nil
}

func printErrorAndExit(driver string, err error) {
	var appErr *core.AppError
	if !errors.As(err, &appErr) {
		appErr = core.WrapAppError(core.CodeInternalError, "unexpected error", err)
	}

	message := appErr.Message
	if detailed := collectErrorDetails(appErr); detailed != "" {
		message = message + ": " + detailed
	}

	payload := core.ErrorPayload{
		Error: core.ErrorDetail{
			Code:    appErr.Code,
			Message: message,
			Driver:  driver,
		},
	}
	_ = core.PrintJSON(payload)
	os.Exit(1)
}

func collectErrorDetails(err error) string {
	if err == nil {
		return ""
	}

	current := errors.Unwrap(err)
	for current != nil {
		msg := strings.TrimSpace(current.Error())
		if msg != "" {
			return msg
		}
		current = errors.Unwrap(current)
	}
	return ""
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func firstNonZero(values ...int) int {
	for _, v := range values {
		if v != 0 {
			return v
		}
	}
	return 0
}

func parseIntDefault(raw string, fallback int) int {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return fallback
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return v
}

func contains(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}

func normalizeLowerCSV(items []string) []string {
	out := make([]string, 0, len(items))
	seen := make(map[string]struct{})
	for _, item := range items {
		v := strings.ToLower(strings.TrimSpace(item))
		if v == "" {
			continue
		}
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

func normalizeUpperCSV(items []string) []string {
	out := make([]string, 0, len(items))
	seen := make(map[string]struct{})
	for _, item := range items {
		v := strings.ToUpper(strings.TrimSpace(item))
		if v == "" {
			continue
		}
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

func normalizeMongoStages(items []string) []string {
	out := make([]string, 0, len(items))
	seen := make(map[string]struct{})
	for _, item := range items {
		v := strings.ToLower(strings.TrimSpace(item))
		if v == "" {
			continue
		}
		if !strings.HasPrefix(v, "$") {
			v = "$" + v
		}
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}
