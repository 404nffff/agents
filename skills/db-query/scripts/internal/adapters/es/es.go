package es

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"db_query/internal/core"
)

type queryRequest struct {
	Index string         `json:"index"`
	Body  map[string]any `json:"body"`
}

type searchResponse struct {
	Hits struct {
		Hits []searchHit `json:"hits"`
	} `json:"hits"`
}

type searchHit struct {
	ID     string         `json:"_id"`
	Index  string         `json:"_index"`
	Score  any            `json:"_score"`
	Source map[string]any `json:"_source"`
	Fields map[string]any `json:"fields"`
}

func Query(ctx context.Context, cfg core.ESConnConfig, queryRaw string, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(cfg.URL) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "es url is required")
	}
	if strings.TrimSpace(queryRaw) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "es --query is required")
	}

	reqPayload := queryRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &reqPayload); err != nil {
		return nil, nil, core.WrapAppError(core.CodeInvalidQuery, "es --query must be valid json", err)
	}
	reqPayload, err := buildStructuredQuery(reqPayload)
	if err != nil {
		return nil, nil, err
	}

	bodyRaw, err := json.Marshal(reqPayload.Body)
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeInternalError, "failed to encode es query body", err)
	}

	timeout := cfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}
	client := &http.Client{Timeout: time.Duration(timeout) * time.Second}

	url := strings.TrimRight(cfg.URL, "/") + "/" + reqPayload.Index + "/_search"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyRaw))
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeInternalError, "failed to build es request", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	if strings.TrimSpace(cfg.User) != "" || strings.TrimSpace(cfg.Password) != "" {
		httpReq.SetBasicAuth(cfg.User, cfg.Password)
	}

	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeConnectionError, "failed to connect es", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "failed to read es response", err)
	}
	if resp.StatusCode >= http.StatusBadRequest {
		return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("es search failed with status %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody))))
	}

	searchResp := searchResponse{}
	if err := json.Unmarshal(respBody, &searchResp); err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "failed to decode es response", err)
	}

	rows := make([]map[string]any, 0, len(searchResp.Hits.Hits))
	for _, hit := range searchResp.Hits.Hits {
		row := make(map[string]any)
		for key, value := range hit.Source {
			row[key] = value
		}
		for key, value := range hit.Fields {
			row[key] = value
		}
		if hit.ID != "" {
			row["_id"] = hit.ID
		}
		if hit.Index != "" {
			row["_index"] = hit.Index
		}
		if hit.Score != nil {
			row["_score"] = hit.Score
		}
		rows = append(rows, row)
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}

	return collectColumns(rows), rows, nil
}

// BuildFilterFromWhereClauses 提供给 CLI builder 复用统一 where 解析逻辑。
func BuildFilterFromWhereClauses(clauses []string) ([]map[string]any, error) {
	filters := make([]map[string]any, 0, len(clauses))
	for _, clause := range clauses {
		filter, err := parseWhereClause(clause)
		if err != nil {
			return nil, err
		}
		filters = append(filters, filter)
	}
	return filters, nil
}

func buildStructuredQuery(req queryRequest) (queryRequest, error) {
	req.Index = strings.TrimSpace(req.Index)
	if req.Index == "" {
		return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "es query.index is required")
	}
	if len(req.Body) == 0 {
		return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "es query.body is required")
	}
	return req, nil
}

func collectColumns(rows []map[string]any) []string {
	if len(rows) == 0 {
		return nil
	}

	columnSet := make(map[string]struct{})
	for _, row := range rows {
		for key := range row {
			columnSet[key] = struct{}{}
		}
	}
	columns := make([]string, 0, len(columnSet))
	for key := range columnSet {
		columns = append(columns, key)
	}
	sort.Strings(columns)
	return columns
}

func parseWhereClause(clause string) (map[string]any, error) {
	parts := strings.SplitN(strings.TrimSpace(clause), ":", 3)
	if len(parts) != 3 {
		return nil, core.NewAppError(core.CodeInvalidArgument, "es --where must use field:operator:value")
	}
	field := strings.TrimSpace(parts[0])
	operator := strings.TrimSpace(parts[1])
	rawValue := strings.TrimSpace(parts[2])
	if field == "" || operator == "" {
		return nil, core.NewAppError(core.CodeInvalidArgument, "es --where must contain non-empty field and operator")
	}

	switch operator {
	case "=":
		return map[string]any{
			"term": map[string]any{
				field: parseScalarValue(rawValue),
			},
		}, nil
	case ">":
		return buildRangeFilter(field, "gt", rawValue), nil
	case ">=":
		return buildRangeFilter(field, "gte", rawValue), nil
	case "<":
		return buildRangeFilter(field, "lt", rawValue), nil
	case "<=":
		return buildRangeFilter(field, "lte", rawValue), nil
	case "in":
		return map[string]any{
			"terms": map[string]any{
				field: parseInValues(rawValue),
			},
		}, nil
	default:
		return nil, core.NewAppError(core.CodeInvalidArgument, fmt.Sprintf("es --where operator %s is not supported", operator))
	}
}

func buildRangeFilter(field, operator, rawValue string) map[string]any {
	return map[string]any{
		"range": map[string]any{
			field: map[string]any{
				operator: parseScalarValue(rawValue),
			},
		},
	}
}

func parseInValues(raw string) []any {
	parts := strings.Split(raw, ",")
	values := make([]any, 0, len(parts))
	for _, part := range parts {
		value := strings.TrimSpace(part)
		if value == "" {
			continue
		}
		values = append(values, parseScalarValue(value))
	}
	return values
}

func parseScalarValue(raw string) any {
	value := strings.TrimSpace(raw)
	switch strings.ToLower(value) {
	case "true":
		return true
	case "false":
		return false
	case "null":
		return nil
	}
	if iv, err := strconv.ParseInt(value, 10, 64); err == nil {
		return iv
	}
	if fv, err := strconv.ParseFloat(value, 64); err == nil {
		return fv
	}
	return value
}
