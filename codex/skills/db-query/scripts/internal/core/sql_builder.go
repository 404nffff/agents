package core

import (
	"fmt"
	"regexp"
	"strings"
)

var identifierPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

func IsIdentifier(s string) bool {
	return identifierPattern.MatchString(s)
}

func BuildStructuredSQL(table, columns, whereExpr, orderBy string, limit int) (string, error) {
	table = strings.TrimSpace(table)
	if table == "" {
		return "", NewAppError(CodeInvalidArgument, "either --query or --table is required")
	}
	if !IsIdentifier(table) {
		return "", NewAppError(CodeInvalidArgument, fmt.Sprintf("invalid table: %s", table))
	}

	columns = strings.TrimSpace(columns)
	if columns == "" {
		columns = "*"
	}

	selectExpr := "*"
	if columns != "*" {
		parts := strings.Split(columns, ",")
		quoted := make([]string, 0, len(parts))
		for _, col := range parts {
			name := strings.TrimSpace(col)
			if name == "" {
				continue
			}
			if !IsIdentifier(name) {
				return "", NewAppError(CodeInvalidArgument, fmt.Sprintf("invalid column: %s", name))
			}
			quoted = append(quoted, fmt.Sprintf("`%s`", name))
		}
		if len(quoted) == 0 {
			return "", NewAppError(CodeInvalidArgument, "columns cannot be empty")
		}
		selectExpr = strings.Join(quoted, ", ")
	}

	query := fmt.Sprintf("SELECT %s FROM `%s`", selectExpr, table)
	if strings.TrimSpace(whereExpr) != "" {
		query += " WHERE " + whereExpr
	}
	if strings.TrimSpace(orderBy) != "" {
		query += " ORDER BY " + orderBy
	}
	query += fmt.Sprintf(" LIMIT %d", limit)
	return query, nil
}
