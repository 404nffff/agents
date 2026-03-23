package core

import (
	"database/sql"
	"fmt"
	"time"
)

func RowsToMaps(rows *sql.Rows) ([]string, []map[string]any, error) {
	columns, err := rows.Columns()
	if err != nil {
		return nil, nil, WrapAppError(CodeExecutionError, "failed to read query columns", err)
	}

	out := make([]map[string]any, 0)
	for rows.Next() {
		raw := make([]any, len(columns))
		ptrs := make([]any, len(columns))
		for i := range raw {
			ptrs[i] = &raw[i]
		}

		if err := rows.Scan(ptrs...); err != nil {
			return nil, nil, WrapAppError(CodeExecutionError, "failed to scan query row", err)
		}

		rowMap := make(map[string]any, len(columns))
		for i, col := range columns {
			rowMap[col] = normalizeDBValue(raw[i])
		}
		out = append(out, rowMap)
	}

	if err := rows.Err(); err != nil {
		return nil, nil, WrapAppError(CodeExecutionError, "row iteration failed", err)
	}

	return columns, out, nil
}

func normalizeDBValue(v any) any {
	switch t := v.(type) {
	case nil:
		return nil
	case []byte:
		return string(t)
	case time.Time:
		return t.Format(time.RFC3339Nano)
	case fmt.Stringer:
		return t.String()
	default:
		return t
	}
}
