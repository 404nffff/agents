package mysql

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	driver "github.com/go-sql-driver/mysql"

	"db_query/internal/core"
)

func Query(ctx context.Context, cfg core.SQLConnConfig, query string) ([]string, []map[string]any, error) {
	if cfg.User == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "mysql user is required")
	}
	if cfg.Database == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "mysql database is required")
	}

	host := cfg.Host
	if host == "" {
		host = "127.0.0.1"
	}
	port := cfg.Port
	if port <= 0 {
		port = 3306
	}

	dsn := driver.NewConfig()
	dsn.User = cfg.User
	dsn.Passwd = cfg.Password
	dsn.DBName = cfg.Database
	dsn.ParseTime = true
	dsn.Params = map[string]string{"charset": "utf8mb4"}
	if cfg.TimeoutSeconds > 0 {
		timeout := time.Duration(cfg.TimeoutSeconds) * time.Second
		dsn.Timeout = timeout
		dsn.ReadTimeout = timeout
		dsn.WriteTimeout = timeout
	}
	if cfg.Socket != "" {
		dsn.Net = "unix"
		dsn.Addr = cfg.Socket
	} else {
		dsn.Net = "tcp"
		dsn.Addr = fmt.Sprintf("%s:%d", host, port)
	}

	db, err := sql.Open("mysql", dsn.FormatDSN())
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeConnectionError, "failed to open mysql connection", err)
	}
	defer db.Close()

	if err := db.PingContext(ctx); err != nil {
		return nil, nil, core.WrapAppError(core.CodeConnectionError, "failed to ping mysql", err)
	}

	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "mysql query failed", err)
	}
	defer rows.Close()

	return core.RowsToMaps(rows)
}
