package cli

import (
	"flag"
	"fmt"
	"strings"

	"db_query/internal/core"
)

type Options struct {
	Driver       string
	Profile      string
	ConfigPath   string
	Host         string
	Port         int
	User         string
	Password     string
	Database     string
	Socket       string
	Timeout      int
	Query        string
	Target       string
	Fields       string
	Sort         string
	Table        string
	Columns      string
	Where        string
	WhereClauses []string
	OrderBy      string
	Limit        int
	MaxRows      int
	Format       string
	URI          string
	Addr         string
	SSLMode      string
	Command      string
	Pipeline     string
	Key          string
	Keys         string
	Field        string
	Pattern      string
	Start        int64
	Stop         int64
	Count        int64
}

func Parse(args []string) (Options, error) {
	var opts Options
	var whereValues stringSliceFlag

	fs := flag.NewFlagSet("db-query", flag.ContinueOnError)
	fs.StringVar(&opts.Driver, "driver", "", "database driver: mysql|pgsql|mongo|redis|es")
	fs.StringVar(&opts.Profile, "profile", "", "connection profile name")
	fs.StringVar(&opts.ConfigPath, "config", "", "config.env absolute path")
	fs.StringVar(&opts.Host, "host", "", "database host")
	fs.IntVar(&opts.Port, "port", 0, "database port")
	fs.StringVar(&opts.User, "user", "", "database user")
	fs.StringVar(&opts.Password, "password", "", "database password")
	fs.StringVar(&opts.Database, "database", "", "database name")
	fs.StringVar(&opts.Socket, "socket", "", "database unix socket path")
	fs.IntVar(&opts.Timeout, "timeout", 0, "connect timeout seconds")
	fs.StringVar(&opts.Query, "query", "", "query statement or json expression")
	fs.StringVar(&opts.Target, "target", "", "structured query target, such as table/collection/key")
	fs.StringVar(&opts.Fields, "fields", "", "structured query fields/columns/projection")
	fs.StringVar(&opts.Sort, "sort", "", "structured query sort expression")
	fs.StringVar(&opts.Table, "table", "", "structured SQL mode table name")
	fs.StringVar(&opts.Columns, "columns", "", "structured SQL mode columns, default *")
	fs.Var(&whereValues, "where", "structured query condition, repeatable")
	fs.StringVar(&opts.OrderBy, "order-by", "", "structured SQL mode order by expression")
	fs.IntVar(&opts.Limit, "limit", core.DefaultLimit, "maximum result limit, 1-1000")
	fs.IntVar(&opts.MaxRows, "max-rows", core.DefaultMaxRows, "maximum allowed rows")
	fs.StringVar(&opts.Format, "format", "json", "output format, only json")
	fs.StringVar(&opts.URI, "uri", "", "uri for mongo")
	fs.StringVar(&opts.Addr, "addr", "", "addr for redis")
	fs.StringVar(&opts.SSLMode, "sslmode", "", "ssl mode for postgresql")
	fs.StringVar(&opts.Command, "command", "", "structured redis command")
	fs.StringVar(&opts.Pipeline, "pipeline", "", "structured mongo aggregate pipeline json")
	fs.StringVar(&opts.Key, "key", "", "structured redis key")
	fs.StringVar(&opts.Keys, "keys", "", "structured redis keys, comma separated")
	fs.StringVar(&opts.Field, "field", "", "structured redis field")
	fs.StringVar(&opts.Pattern, "pattern", "", "structured redis pattern")
	fs.Int64Var(&opts.Start, "start", 0, "structured redis range start")
	fs.Int64Var(&opts.Stop, "stop", 0, "structured redis range stop")
	fs.Int64Var(&opts.Count, "count", 0, "structured redis count")

	if err := fs.Parse(args); err != nil {
		return Options{}, core.WrapAppError(core.CodeInvalidArgument, "failed to parse command arguments", err)
	}

	opts.Driver = strings.ToLower(strings.TrimSpace(opts.Driver))
	opts.Profile = strings.TrimSpace(opts.Profile)
	opts.Format = strings.ToLower(strings.TrimSpace(opts.Format))
	opts.Target = strings.TrimSpace(opts.Target)
	opts.Fields = strings.TrimSpace(opts.Fields)
	opts.Sort = strings.TrimSpace(opts.Sort)
	opts.Columns = strings.TrimSpace(opts.Columns)
	opts.Command = strings.TrimSpace(opts.Command)
	opts.Pipeline = strings.TrimSpace(opts.Pipeline)
	opts.Key = strings.TrimSpace(opts.Key)
	opts.Keys = strings.TrimSpace(opts.Keys)
	opts.Field = strings.TrimSpace(opts.Field)
	opts.Pattern = strings.TrimSpace(opts.Pattern)
	opts.WhereClauses = whereValues.Values()

	// 统一新旧参数别名，保证旧脚本仍可工作。
	opts.Target = firstNonEmpty(opts.Target, opts.Table)
	opts.Table = firstNonEmpty(opts.Table, opts.Target)
	opts.Fields = firstNonEmpty(opts.Fields, opts.Columns)
	opts.Columns = firstNonEmpty(opts.Columns, opts.Fields)
	opts.Sort = firstNonEmpty(opts.Sort, opts.OrderBy)
	opts.OrderBy = firstNonEmpty(opts.OrderBy, opts.Sort)
	opts.Where = strings.Join(opts.WhereClauses, " AND ")

	if opts.Driver == "" {
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "--driver is required")
	}

	switch opts.Driver {
	case "mysql", "pgsql", "mongo", "redis", "es":
	default:
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "--driver must be one of mysql|pgsql|mongo|redis|es")
	}

	if opts.Limit <= 0 {
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "--limit must be greater than 0")
	}
	if opts.Limit > core.MaxLimit {
		return Options{}, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("--limit cannot exceed %d", core.MaxLimit))
	}
	if opts.MaxRows <= 0 {
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "--max-rows must be greater than 0")
	}
	if opts.Format == "" {
		opts.Format = "json"
	}
	if opts.Format != "json" {
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "only --format json is allowed")
	}

	return opts, nil
}

// stringSliceFlag 用于收集可重复传入的 --where 参数。
type stringSliceFlag struct {
	values []string
}

func (f *stringSliceFlag) String() string {
	return strings.Join(f.values, ",")
}

func (f *stringSliceFlag) Set(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	f.values = append(f.values, value)
	return nil
}

func (f *stringSliceFlag) Values() []string {
	out := make([]string, 0, len(f.values))
	for _, item := range f.values {
		item = strings.TrimSpace(item)
		if item != "" {
			out = append(out, item)
		}
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}
