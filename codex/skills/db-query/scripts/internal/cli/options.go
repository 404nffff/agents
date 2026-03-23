package cli

import (
	"flag"
	"fmt"
	"strings"

	"db_query/internal/core"
)

type Options struct {
	Driver     string
	Profile    string
	ConfigPath string
	Host       string
	Port       int
	User       string
	Password   string
	Database   string
	Socket     string
	Timeout    int
	Query      string
	Table      string
	Columns    string
	Where      string
	OrderBy    string
	Limit      int
	MaxRows    int
	Format     string
	URI        string
	Addr       string
	SSLMode    string
}

func Parse(args []string) (Options, error) {
	var opts Options

	fs := flag.NewFlagSet("db-query", flag.ContinueOnError)
	fs.StringVar(&opts.Driver, "driver", "", "database driver: mysql|pgsql|mongo|redis")
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
	fs.StringVar(&opts.Table, "table", "", "structured SQL mode table name")
	fs.StringVar(&opts.Columns, "columns", "*", "structured SQL mode columns, default *")
	fs.StringVar(&opts.Where, "where", "", "structured SQL mode where expression")
	fs.StringVar(&opts.OrderBy, "order-by", "", "structured SQL mode order by expression")
	fs.IntVar(&opts.Limit, "limit", core.DefaultLimit, "maximum result limit, 1-1000")
	fs.IntVar(&opts.MaxRows, "max-rows", core.DefaultMaxRows, "maximum allowed rows")
	fs.StringVar(&opts.Format, "format", "json", "output format, only json")
	fs.StringVar(&opts.URI, "uri", "", "uri for mongo")
	fs.StringVar(&opts.Addr, "addr", "", "addr for redis")
	fs.StringVar(&opts.SSLMode, "sslmode", "", "ssl mode for postgresql")

	if err := fs.Parse(args); err != nil {
		return Options{}, core.WrapAppError(core.CodeInvalidArgument, "failed to parse command arguments", err)
	}

	opts.Driver = strings.ToLower(strings.TrimSpace(opts.Driver))
	opts.Profile = strings.TrimSpace(opts.Profile)
	opts.Format = strings.ToLower(strings.TrimSpace(opts.Format))
	opts.Columns = strings.TrimSpace(opts.Columns)

	if opts.Driver == "" {
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "--driver is required")
	}

	switch opts.Driver {
	case "mysql", "pgsql", "mongo", "redis":
	default:
		return Options{}, core.NewAppError(core.CodeInvalidArgument, "--driver must be one of mysql|pgsql|mongo|redis")
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
