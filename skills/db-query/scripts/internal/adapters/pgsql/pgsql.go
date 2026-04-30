package pgsql

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	_ "github.com/jackc/pgx/v5/stdlib"

	"db_query/internal/core"
)

func Query(ctx context.Context, cfg core.SQLConnConfig, query string) ([]string, []map[string]any, error) {
	if cfg.User == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "pgsql user is required")
	}
	if cfg.Database == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "pgsql database is required")
	}

	host := cfg.Host
	if host == "" {
		host = "127.0.0.1"
	}
	port := cfg.Port
	if port <= 0 {
		port = 5432
	}
	sslMode := strings.TrimSpace(cfg.SSLMode)
	if sslMode == "" {
		sslMode = "disable"
	}

	connParts := []string{
		fmt.Sprintf("host=%s", host),
		fmt.Sprintf("port=%d", port),
		fmt.Sprintf("user=%s", cfg.User),
		fmt.Sprintf("dbname=%s", cfg.Database),
		fmt.Sprintf("sslmode=%s", sslMode),
	}
	if cfg.Password != "" {
		connParts = append(connParts, fmt.Sprintf("password=%s", cfg.Password))
	}
	if cfg.TimeoutSeconds > 0 {
		connParts = append(connParts, fmt.Sprintf("connect_timeout=%d", cfg.TimeoutSeconds))
	}

	db, err := sql.Open("pgx", strings.Join(connParts, " "))
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeConnectionError, "failed to open pgsql connection", err)
	}
	defer db.Close()

	if err := db.PingContext(ctx); err != nil {
		return nil, nil, core.WrapAppError(core.CodeConnectionError, "failed to ping pgsql", err)
	}

	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "pgsql query failed", err)
	}
	defer rows.Close()

	return core.RowsToMaps(rows)
}
