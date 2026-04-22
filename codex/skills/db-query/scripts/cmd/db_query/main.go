package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"db_query/internal/adapters/es"
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
	case "es":
		if configErr != nil {
			printErrorAndExit(opts.Driver, core.WrapAppError(core.CodeInvalidConfig, configErr.Error(), configErr))
		}
		profile, pErr := config.ResolveProfile(opts.Driver, opts.Profile, envVars)
		if pErr != nil {
			printErrorAndExit(opts.Driver, core.WrapAppError(core.CodeInvalidConfig, pErr.Error(), pErr))
		}
		runESDriver(startedAt, profile, opts, envVars)
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
			RawSQL:   validation.NormalizedSQL,
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
		RawSQL:   validation.NormalizedSQL,
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

	queryRaw, err := buildMongoQuery(opts)
	if err != nil {
		printErrorAndExit("mongo", err)
	}

	columns, rows, err := mongo.Query(ctx, connCfg, queryRaw, opts.MaxRows)
	if err != nil {
		printErrorAndExit("mongo", err)
	}
	if len(rows) > opts.MaxRows {
		printErrorAndExit("mongo", core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), opts.MaxRows)))
	}

	rawSQL, err := buildMongoRawSQL(connCfg.Database, queryRaw)
	if err != nil {
		rawSQL = queryRaw
	}

	payload := core.SuccessPayload{
		Driver:   "mongo",
		Profile:  profile,
		Query:    queryRaw,
		RawSQL:   rawSQL,
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

	queryRaw, err := buildRedisQuery(opts)
	if err != nil {
		printErrorAndExit("redis", err)
	}

	columns, rows, err := redis.Query(ctx, connCfg, queryRaw, opts.MaxRows)
	if err != nil {
		printErrorAndExit("redis", err)
	}
	if len(rows) > opts.MaxRows {
		printErrorAndExit("redis", core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), opts.MaxRows)))
	}

	rawSQL, err := buildRedisRawSQL(queryRaw)
	if err != nil {
		rawSQL = queryRaw
	}

	payload := core.SuccessPayload{
		Driver:   "redis",
		Profile:  profile,
		Query:    queryRaw,
		RawSQL:   rawSQL,
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

func runESDriver(startedAt time.Time, profile string, opts cli.Options, envVars map[string]string) {
	connCfg, err := resolveESConnConfig(profile, opts, envVars)
	if err != nil {
		printErrorAndExit("es", err)
	}

	timeout := connCfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()

	queryRaw, err := buildESQuery(opts)
	if err != nil {
		printErrorAndExit("es", err)
	}
	canonicalQuery, err := canonicalizeESQuery(connCfg.DefaultIndex, queryRaw)
	if err != nil {
		printErrorAndExit("es", err)
	}

	columns, rows, err := es.Query(ctx, connCfg, canonicalQuery, opts.MaxRows)
	if err != nil {
		printErrorAndExit("es", err)
	}
	if len(rows) > opts.MaxRows {
		printErrorAndExit("es", core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), opts.MaxRows)))
	}

	rawSQL, err := buildESRawSQL(connCfg.URL, canonicalQuery)
	if err != nil {
		rawSQL = canonicalQuery
	}

	payload := core.SuccessPayload{
		Driver:   "es",
		Profile:  profile,
		Query:    canonicalQuery,
		RawSQL:   rawSQL,
		RowCount: len(rows),
		Columns:  columns,
		Rows:     rows,
		Meta: map[string]any{
			"elapsed_ms": time.Since(startedAt).Milliseconds(),
		},
	}
	if err := core.PrintJSON(payload); err != nil {
		printErrorAndExit("es", core.WrapAppError(core.CodeInternalError, "failed to write output", err))
	}
}

func resolveSQLQuery(opts cli.Options) (string, error) {
	if err := validateStructuredQueryConflict("sql", opts); err != nil {
		return "", err
	}
	if strings.TrimSpace(opts.Query) != "" {
		return strings.TrimSpace(opts.Query), nil
	}
	table := firstNonEmpty(opts.Target, opts.Table)
	columns := firstNonEmpty(opts.Fields, opts.Columns)
	whereExpr := firstNonEmpty(strings.TrimSpace(opts.Where), strings.Join(opts.WhereClauses, " AND "))
	orderBy := firstNonEmpty(opts.Sort, opts.OrderBy)
	return core.BuildStructuredSQL(table, columns, whereExpr, orderBy, opts.Limit)
}

func buildMongoQuery(opts cli.Options) (string, error) {
	if err := validateStructuredQueryConflict("mongo", opts); err != nil {
		return "", err
	}
	if strings.TrimSpace(opts.Query) != "" {
		return strings.TrimSpace(opts.Query), nil
	}

	collection := firstNonEmpty(opts.Target, opts.Table)
	if collection == "" {
		return "", core.NewAppError(core.CodeInvalidArgument, "mongo requires --target or --query")
	}
	if strings.TrimSpace(opts.Pipeline) != "" && (len(opts.WhereClauses) > 0 || strings.TrimSpace(opts.Fields) != "" || strings.TrimSpace(opts.Sort) != "") {
		return "", core.NewAppError(core.CodeInvalidArgument, "mongo --pipeline cannot be used with --where, --fields or --sort")
	}

	payload := map[string]any{
		"collection": collection,
		"limit":      opts.Limit,
	}

	if strings.TrimSpace(opts.Pipeline) != "" {
		var pipeline []map[string]any
		if err := json.Unmarshal([]byte(opts.Pipeline), &pipeline); err != nil {
			return "", core.WrapAppError(core.CodeInvalidArgument, "mongo --pipeline must be valid json array", err)
		}
		payload["operation"] = "aggregate"
		payload["pipeline"] = pipeline
		return marshalStructuredQuery(payload)
	}

	filter, err := mongo.BuildFilterFromWhereClauses(opts.WhereClauses)
	if err != nil {
		return "", err
	}
	projection, err := parseMongoProjection(firstNonEmpty(opts.Fields, opts.Columns))
	if err != nil {
		return "", err
	}
	sortExpr, err := parseMongoSort(firstNonEmpty(opts.Sort, opts.OrderBy))
	if err != nil {
		return "", err
	}

	payload["operation"] = "find"
	payload["filter"] = filter
	if len(projection) > 0 {
		payload["projection"] = projection
	}
	if len(sortExpr) > 0 {
		payload["sort"] = sortExpr
	}
	return marshalStructuredQuery(payload)
}

func buildRedisQuery(opts cli.Options) (string, error) {
	if err := validateStructuredQueryConflict("redis", opts); err != nil {
		return "", err
	}
	if strings.TrimSpace(opts.Query) != "" {
		return strings.TrimSpace(opts.Query), nil
	}

	command := strings.ToUpper(strings.TrimSpace(opts.Command))
	if command == "" {
		return "", core.NewAppError(core.CodeInvalidArgument, "redis requires --command or --query")
	}

	payload := map[string]any{
		"command": command,
	}
	target := firstNonEmpty(opts.Target, opts.Key)

	switch command {
	case "SCAN":
		if strings.TrimSpace(target) != "" {
			payload["pattern"] = target
		} else if strings.TrimSpace(opts.Pattern) != "" {
			payload["pattern"] = opts.Pattern
		}
		if opts.Count > 0 {
			payload["count"] = opts.Count
		} else if opts.Limit > 0 {
			payload["count"] = opts.Limit
		}
	case "MGET":
		keys := splitAndTrim(firstNonEmpty(opts.Keys, target))
		if len(keys) == 0 {
			return "", core.NewAppError(core.CodeInvalidArgument, "redis MGET requires --target, --keys or --query")
		}
		payload["keys"] = keys
	default:
		if target != "" {
			payload["key"] = target
		}
		if opts.Field != "" {
			payload["field"] = opts.Field
		}
		if opts.Start != 0 {
			payload["start"] = opts.Start
		}
		if opts.Stop != 0 {
			payload["stop"] = opts.Stop
		}
		if opts.Count > 0 {
			payload["count"] = opts.Count
		}
	}

	return marshalStructuredQuery(payload)
}

func buildESQuery(opts cli.Options) (string, error) {
	if err := validateStructuredQueryConflict("es", opts); err != nil {
		return "", err
	}
	if strings.TrimSpace(opts.Query) != "" {
		return strings.TrimSpace(opts.Query), nil
	}

	index := firstNonEmpty(opts.Target, opts.Table)
	if !isESIndexTarget(index) {
		return "", core.NewAppError(core.CodeInvalidArgument, "es requires valid --target or configured default index")
	}

	filterClauses, err := es.BuildFilterFromWhereClauses(opts.WhereClauses)
	if err != nil {
		return "", err
	}
	sourceFields, err := parseESFields(firstNonEmpty(opts.Fields, opts.Columns))
	if err != nil {
		return "", err
	}
	sortExpr, err := parseESSort(firstNonEmpty(opts.Sort, opts.OrderBy))
	if err != nil {
		return "", err
	}

	body := map[string]any{
		"size": opts.Limit,
	}
	if len(sourceFields) > 0 {
		body["_source"] = sourceFields
	}
	if len(filterClauses) > 0 {
		body["query"] = map[string]any{
			"bool": map[string]any{
				"filter": filterClauses,
			},
		}
	}
	if len(sortExpr) > 0 {
		body["sort"] = sortExpr
	}

	return marshalStructuredQuery(map[string]any{
		"index": index,
		"body":  body,
	})
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

func resolveESConnConfig(profile string, opts cli.Options, envVars map[string]string) (core.ESConnConfig, error) {
	baseURL := firstNonEmpty(opts.URI, config.GetProfileValue(envVars, "ES_URL", profile))
	user := firstNonEmpty(opts.User, config.GetProfileValue(envVars, "ES_USERNAME", profile))
	password := firstNonEmpty(opts.Password, config.GetProfileValue(envVars, "ES_PASSWORD", profile))
	defaultIndex := firstNonEmpty(config.GetProfileValue(envVars, "ES_INDEX", profile))
	timeout := firstNonZero(opts.Timeout, parseIntDefault(config.GetProfileValue(envVars, "ES_TIMEOUT", profile), 0))

	if strings.TrimSpace(baseURL) == "" {
		return core.ESConnConfig{}, core.NewAppError(core.CodeInvalidConfig, fmt.Sprintf("es url is required (use --uri or ES_URL_%s)", profile))
	}
	return core.ESConnConfig{
		URL:            strings.TrimRight(baseURL, "/"),
		User:           user,
		Password:       password,
		DefaultIndex:   defaultIndex,
		TimeoutSeconds: timeout,
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

func validateStructuredQueryConflict(driver string, opts cli.Options) error {
	if strings.TrimSpace(opts.Query) == "" {
		return nil
	}

	conflicts := make([]string, 0)
	addConflict := func(flagName string, enabled bool) {
		if enabled && !contains(conflicts, flagName) {
			conflicts = append(conflicts, flagName)
		}
	}

	addConflict("--target", strings.TrimSpace(firstNonEmpty(opts.Target, opts.Table)) != "")
	addConflict("--fields", strings.TrimSpace(firstNonEmpty(opts.Fields, opts.Columns)) != "")
	addConflict("--where", len(opts.WhereClauses) > 0 || strings.TrimSpace(opts.Where) != "")
	addConflict("--sort", strings.TrimSpace(firstNonEmpty(opts.Sort, opts.OrderBy)) != "")

	switch driver {
	case "mongo":
		addConflict("--pipeline", strings.TrimSpace(opts.Pipeline) != "")
	case "redis":
		addConflict("--command", strings.TrimSpace(opts.Command) != "")
		addConflict("--key", strings.TrimSpace(opts.Key) != "")
		addConflict("--keys", strings.TrimSpace(opts.Keys) != "")
		addConflict("--field", strings.TrimSpace(opts.Field) != "")
		addConflict("--pattern", strings.TrimSpace(opts.Pattern) != "")
		addConflict("--count", opts.Count != 0)
		addConflict("--start", opts.Start != 0)
		addConflict("--stop", opts.Stop != 0)
	}

	if len(conflicts) == 0 {
		return nil
	}
	return core.NewAppError(core.CodeInvalidArgument, "--query cannot be used with "+strings.Join(conflicts, ", "))
}

func parseMongoProjection(fields string) (map[string]int, error) {
	fields = strings.TrimSpace(fields)
	if fields == "" {
		return map[string]int{}, nil
	}

	items := splitAndTrim(fields)
	if len(items) == 0 {
		return map[string]int{}, nil
	}

	projection := make(map[string]int, len(items))
	for _, item := range items {
		if !core.IsIdentifier(item) {
			return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("mongo --fields contains invalid field: %s", item))
		}
		projection[item] = 1
	}
	return projection, nil
}

func parseMongoSort(sortRaw string) (map[string]int, error) {
	sortRaw = strings.TrimSpace(sortRaw)
	if sortRaw == "" {
		return map[string]int{}, nil
	}
	if strings.HasPrefix(sortRaw, "{") || strings.HasPrefix(sortRaw, "[") {
		return nil, core.NewAppError(core.CodeInvalidArgument, "mongo --sort must use field:asc or field:desc")
	}

	sortMap := make(map[string]int)
	for _, item := range splitAndTrim(sortRaw) {
		parts := strings.SplitN(item, ":", 2)
		if len(parts) != 2 {
			return nil, core.NewAppError(core.CodeInvalidArgument, "mongo --sort must use field:asc or field:desc")
		}
		field := strings.TrimSpace(parts[0])
		direction := strings.ToLower(strings.TrimSpace(parts[1]))
		if !core.IsIdentifier(field) {
			return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("mongo --sort contains invalid field: %s", field))
		}
		switch direction {
		case "asc", "1":
			sortMap[field] = 1
		case "desc", "-1":
			sortMap[field] = -1
		default:
			return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("mongo --sort direction %s is not supported", direction))
		}
	}
	return sortMap, nil
}

func parseESFields(fields string) ([]string, error) {
	fields = strings.TrimSpace(fields)
	if fields == "" {
		return nil, nil
	}

	items := splitAndTrim(fields)
	out := make([]string, 0, len(items))
	for _, item := range items {
		if !isESFieldName(item) {
			return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("es --fields contains invalid field: %s", item))
		}
		out = append(out, item)
	}
	return out, nil
}

func parseESSort(sortRaw string) ([]map[string]any, error) {
	sortRaw = strings.TrimSpace(sortRaw)
	if sortRaw == "" {
		return nil, nil
	}
	if strings.HasPrefix(sortRaw, "{") || strings.HasPrefix(sortRaw, "[") {
		return nil, core.NewAppError(core.CodeInvalidArgument, "es --sort must use field:asc or field:desc")
	}

	out := make([]map[string]any, 0)
	for _, item := range splitAndTrim(sortRaw) {
		parts := strings.SplitN(item, ":", 2)
		if len(parts) != 2 {
			return nil, core.NewAppError(core.CodeInvalidArgument, "es --sort must use field:asc or field:desc")
		}
		field := strings.TrimSpace(parts[0])
		direction := strings.ToLower(strings.TrimSpace(parts[1]))
		if !isESFieldName(field) {
			return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("es --sort contains invalid field: %s", field))
		}
		switch direction {
		case "asc", "desc":
		default:
			return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("es --sort direction %s is not supported", direction))
		}
		out = append(out, map[string]any{
			field: map[string]any{
				"order": direction,
			},
		})
	}
	return out, nil
}

func marshalStructuredQuery(payload map[string]any) (string, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return "", core.WrapAppError(core.CodeInternalError, "failed to encode structured query", err)
	}
	return string(data), nil
}

func splitAndTrim(raw string) []string {
	items := strings.Split(raw, ",")
	out := make([]string, 0, len(items))
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item != "" {
			out = append(out, item)
		}
	}
	return out
}

type mongoRawSQLRequest struct {
	Operation  string           `json:"operation"`
	Collection string           `json:"collection"`
	Filter     map[string]any   `json:"filter"`
	Projection map[string]any   `json:"projection"`
	Sort       map[string]any   `json:"sort"`
	Limit      int              `json:"limit"`
	Pipeline   []map[string]any `json:"pipeline"`
}

type redisRawSQLRequest struct {
	Command string   `json:"command"`
	Key     string   `json:"key"`
	Keys    []string `json:"keys"`
	Field   string   `json:"field"`
	Start   int64    `json:"start"`
	Stop    int64    `json:"stop"`
	Pattern string   `json:"pattern"`
	Count   int64    `json:"count"`
}

type esRawSQLRequest struct {
	Index string         `json:"index"`
	Body  map[string]any `json:"body"`
}

func buildMongoRawSQL(database, queryRaw string) (string, error) {
	req := mongoRawSQLRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &req); err != nil {
		return "", core.WrapAppError(core.CodeInvalidArgument, "mongo raw_sql requires valid query json", err)
	}

	req.Operation = strings.ToLower(strings.TrimSpace(req.Operation))
	if req.Operation == "" {
		req.Operation = "find"
	}
	if strings.TrimSpace(req.Collection) == "" {
		return "", core.NewAppError(core.CodeInvalidArgument, "mongo raw_sql requires collection")
	}

	base := fmt.Sprintf(`db.getSiblingDB(%q).getCollection(%q)`, database, req.Collection)
	switch req.Operation {
	case "find":
		filterText := renderRawJSON(req.Filter)
		if filterText == "" {
			filterText = "{}"
		}
		findExpr := base + ".find(" + filterText
		if len(req.Projection) > 0 {
			findExpr += ", " + renderRawJSON(req.Projection)
		}
		findExpr += ")"
		if len(req.Sort) > 0 {
			findExpr += ".sort(" + renderRawJSON(req.Sort) + ")"
		}
		if req.Limit > 0 {
			findExpr += fmt.Sprintf(".limit(%d)", req.Limit)
		}
		return findExpr, nil
	case "aggregate":
		pipelineText := renderRawJSON(req.Pipeline)
		if pipelineText == "" {
			pipelineText = "[]"
		}
		return base + ".aggregate(" + pipelineText + ")", nil
	default:
		return "", core.NewAppError(core.CodeInvalidArgument, "mongo raw_sql only supports find or aggregate")
	}
}

func buildRedisRawSQL(queryRaw string) (string, error) {
	req := redisRawSQLRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &req); err != nil {
		return "", core.WrapAppError(core.CodeInvalidArgument, "redis raw_sql requires valid query json", err)
	}

	command := strings.ToUpper(strings.TrimSpace(req.Command))
	if command == "" {
		return "", core.NewAppError(core.CodeInvalidArgument, "redis raw_sql requires command")
	}

	switch command {
	case "GET":
		return fmt.Sprintf("GET %s", req.Key), nil
	case "MGET":
		return "MGET " + strings.Join(req.Keys, " "), nil
	case "HGET":
		return fmt.Sprintf("HGET %s %s", req.Key, req.Field), nil
	case "HGETALL":
		return fmt.Sprintf("HGETALL %s", req.Key), nil
	case "SMEMBERS":
		return fmt.Sprintf("SMEMBERS %s", req.Key), nil
	case "ZRANGE":
		return fmt.Sprintf("ZRANGE %s %d %d", req.Key, req.Start, req.Stop), nil
	case "LRANGE":
		return fmt.Sprintf("LRANGE %s %d %d", req.Key, req.Start, req.Stop), nil
	case "SCAN":
		pattern := req.Pattern
		if strings.TrimSpace(pattern) == "" {
			pattern = "*"
		}
		if req.Count > 0 {
			return fmt.Sprintf("SCAN 0 MATCH %s COUNT %d", pattern, req.Count), nil
		}
		return fmt.Sprintf("SCAN 0 MATCH %s", pattern), nil
	default:
		return "", core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("redis raw_sql does not support command %s", command))
	}
}

func canonicalizeESQuery(defaultIndex, queryRaw string) (string, error) {
	queryRaw = strings.TrimSpace(queryRaw)
	if queryRaw == "" {
		return "", core.NewAppError(core.CodeInvalidQuery, "es --query is required")
	}

	var raw map[string]any
	if err := json.Unmarshal([]byte(queryRaw), &raw); err != nil {
		return "", core.WrapAppError(core.CodeInvalidQuery, "es --query must be valid json object", err)
	}

	req := esRawSQLRequest{}
	hasBody := false
	if body, ok := raw["body"].(map[string]any); ok {
		req.Body = body
		hasBody = true
	}
	if index, ok := raw["index"].(string); ok {
		req.Index = strings.TrimSpace(index)
	}
	if !hasBody {
		req.Body = raw
	}
	req.Index = firstNonEmpty(req.Index, defaultIndex)

	if !isESIndexTarget(req.Index) {
		return "", core.NewAppError(core.CodeInvalidArgument, "es query index is required; use --target for structured query or configure ES_INDEX_<profile>")
	}
	if len(req.Body) == 0 {
		return "", core.NewAppError(core.CodeInvalidQuery, "es query body cannot be empty")
	}
	return marshalStructuredQuery(map[string]any{
		"index": req.Index,
		"body":  req.Body,
	})
}

func buildESRawSQL(baseURL, queryRaw string) (string, error) {
	req := esRawSQLRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &req); err != nil {
		return "", core.WrapAppError(core.CodeInvalidArgument, "es raw_sql requires valid query json", err)
	}
	if !isESIndexTarget(req.Index) {
		return "", core.NewAppError(core.CodeInvalidArgument, "es raw_sql requires index")
	}
	if len(req.Body) == 0 {
		return "", core.NewAppError(core.CodeInvalidArgument, "es raw_sql requires body")
	}
	bodyText := renderRawJSON(req.Body)
	if bodyText == "" {
		return "", core.NewAppError(core.CodeInvalidArgument, "es raw_sql failed to encode body")
	}
	return fmt.Sprintf("curl -X POST '%s/%s/_search' -H 'Content-Type: application/json' -d '%s'", strings.TrimRight(baseURL, "/"), req.Index, bodyText), nil
}

func renderRawJSON(value any) string {
	if value == nil {
		return ""
	}
	data, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return string(data)
}

func isESIndexTarget(value string) bool {
	value = strings.TrimSpace(value)
	return value != "" && !strings.ContainsAny(value, " /")
}

func isESFieldName(value string) bool {
	value = strings.TrimSpace(value)
	return value != "" && !strings.ContainsAny(value, " ,:/")
}
