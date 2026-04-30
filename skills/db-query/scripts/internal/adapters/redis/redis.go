package redis

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"db_query/internal/core"
)

type queryRequest struct {
	Command string   `json:"command"`
	Key     string   `json:"key"`
	Keys    []string `json:"keys"`
	Field   string   `json:"field"`
	Start   int64    `json:"start"`
	Stop    int64    `json:"stop"`
	Pattern string   `json:"pattern"`
	Count   int64    `json:"count"`
}

func Query(ctx context.Context, cfg core.RedisConnConfig, queryRaw string, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(cfg.Addr) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "redis addr is required")
	}
	if strings.TrimSpace(queryRaw) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis --query is required")
	}

	req := queryRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &req); err != nil {
		return nil, nil, core.WrapAppError(core.CodeInvalidQuery, "redis --query must be valid json", err)
	}
	req, err := buildStructuredQuery(req)
	if err != nil {
		return nil, nil, err
	}
	cmd := req.Command
	if !slices.Contains(cfg.AllowedCommands, cmd) {
		return nil, nil, core.NewAppError(
			core.CodeInvalidQuery,
			"redis command is not allowed, only "+strings.Join(cfg.AllowedCommands, ","),
		)
	}

	timeout := cfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}

	client := redis.NewClient(&redis.Options{
		Addr:         cfg.Addr,
		Username:     cfg.User,
		Password:     cfg.Password,
		DB:           cfg.DB,
		DialTimeout:  time.Duration(timeout) * time.Second,
		ReadTimeout:  time.Duration(timeout) * time.Second,
		WriteTimeout: time.Duration(timeout) * time.Second,
	})
	defer client.Close()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, nil, core.WrapAppError(core.CodeConnectionError, "failed to connect redis", err)
	}

	switch cmd {
	case "GET":
		return runGet(ctx, client, req)
	case "MGET":
		return runMGet(ctx, client, req)
	case "HGET":
		return runHGet(ctx, client, req)
	case "HGETALL":
		return runHGetAll(ctx, client, req, maxRows)
	case "SMEMBERS":
		return runSMembers(ctx, client, req, maxRows)
	case "ZRANGE":
		return runZRange(ctx, client, req, maxRows)
	case "LRANGE":
		return runLRange(ctx, client, req, maxRows)
	case "SCAN":
		return runScan(ctx, client, req, maxRows)
	default:
		return nil, nil, core.NewAppError(
			core.CodeInvalidQuery,
			"redis command is configured as allowed but not implemented: "+cmd,
		)
	}
}

func buildStructuredQuery(req queryRequest) (queryRequest, error) {
	req.Command = strings.ToUpper(strings.TrimSpace(req.Command))
	if req.Command == "" {
		return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "redis query.command is required")
	}

	switch req.Command {
	case "GET", "HGETALL", "SMEMBERS", "ZRANGE", "LRANGE":
		if strings.TrimSpace(req.Key) == "" {
			return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, fmt.Sprintf("redis %s requires query.key", req.Command))
		}
	case "MGET":
		if len(req.Keys) == 0 && strings.TrimSpace(req.Key) == "" {
			return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "redis MGET requires query.keys or comma-separated query.key")
		}
	case "HGET":
		if strings.TrimSpace(req.Key) == "" || strings.TrimSpace(req.Field) == "" {
			return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "redis HGET requires query.key and query.field")
		}
	case "SCAN":
		req.Pattern = strings.TrimSpace(req.Pattern)
		if req.Pattern == "" {
			req.Pattern = "*"
		}
		if req.Count < 0 {
			return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "redis SCAN query.count must be greater than or equal to 0")
		}
	default:
		// 其他命令的允许范围继续由配置控制，这里只做已实现命令的必填校验。
	}

	return req, nil
}

func runGet(ctx context.Context, client *redis.Client, req queryRequest) ([]string, []map[string]any, error) {
	if strings.TrimSpace(req.Key) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis GET requires query.key")
	}
	v, err := client.Get(ctx, req.Key).Result()
	if err == redis.Nil {
		return nil, []map[string]any{}, nil
	}
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis GET failed", err)
	}
	return []string{"key", "value"}, []map[string]any{{"key": req.Key, "value": v}}, nil
}

func runMGet(ctx context.Context, client *redis.Client, req queryRequest) ([]string, []map[string]any, error) {
	keys := req.Keys
	if len(keys) == 0 && strings.TrimSpace(req.Key) != "" {
		keys = strings.Split(req.Key, ",")
	}
	clean := make([]string, 0, len(keys))
	for _, k := range keys {
		kk := strings.TrimSpace(k)
		if kk != "" {
			clean = append(clean, kk)
		}
	}
	if len(clean) == 0 {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis MGET requires query.keys or comma-separated query.key")
	}

	values, err := client.MGet(ctx, clean...).Result()
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis MGET failed", err)
	}

	rows := make([]map[string]any, 0, len(values))
	for i, key := range clean {
		rows = append(rows, map[string]any{"key": key, "value": values[i]})
	}
	return []string{"key", "value"}, rows, nil
}

func runHGet(ctx context.Context, client *redis.Client, req queryRequest) ([]string, []map[string]any, error) {
	if strings.TrimSpace(req.Key) == "" || strings.TrimSpace(req.Field) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis HGET requires query.key and query.field")
	}
	v, err := client.HGet(ctx, req.Key, req.Field).Result()
	if err == redis.Nil {
		return nil, []map[string]any{}, nil
	}
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis HGET failed", err)
	}
	return []string{"key", "field", "value"}, []map[string]any{{"key": req.Key, "field": req.Field, "value": v}}, nil
}

func runHGetAll(ctx context.Context, client *redis.Client, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(req.Key) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis HGETALL requires query.key")
	}
	values, err := client.HGetAll(ctx, req.Key).Result()
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis HGETALL failed", err)
	}

	rows := make([]map[string]any, 0, len(values))
	for field, value := range values {
		rows = append(rows, map[string]any{"key": req.Key, "field": field, "value": value})
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	return []string{"key", "field", "value"}, rows, nil
}

func runSMembers(ctx context.Context, client *redis.Client, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(req.Key) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis SMEMBERS requires query.key")
	}
	values, err := client.SMembers(ctx, req.Key).Result()
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis SMEMBERS failed", err)
	}

	rows := make([]map[string]any, 0, len(values))
	for _, member := range values {
		rows = append(rows, map[string]any{"key": req.Key, "member": member})
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	return []string{"key", "member"}, rows, nil
}

func runZRange(ctx context.Context, client *redis.Client, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(req.Key) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis ZRANGE requires query.key")
	}
	stop := req.Stop
	if stop == 0 {
		stop = -1
	}
	values, err := client.ZRange(ctx, req.Key, req.Start, stop).Result()
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis ZRANGE failed", err)
	}

	rows := make([]map[string]any, 0, len(values))
	for _, member := range values {
		rows = append(rows, map[string]any{"key": req.Key, "member": member})
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	return []string{"key", "member"}, rows, nil
}

func runLRange(ctx context.Context, client *redis.Client, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(req.Key) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "redis LRANGE requires query.key")
	}
	stop := req.Stop
	if stop == 0 {
		stop = -1
	}
	values, err := client.LRange(ctx, req.Key, req.Start, stop).Result()
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis LRANGE failed", err)
	}

	rows := make([]map[string]any, 0, len(values))
	for idx, value := range values {
		rows = append(rows, map[string]any{"key": req.Key, "index": idx, "value": value})
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	return []string{"key", "index", "value"}, rows, nil
}

func runScan(ctx context.Context, client *redis.Client, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	pattern := strings.TrimSpace(req.Pattern)
	if pattern == "" {
		pattern = "*"
	}
	count := req.Count
	if count <= 0 {
		count = int64(maxRows)
	}
	keys, cursor, err := client.Scan(ctx, 0, pattern, count).Result()
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "redis SCAN failed", err)
	}

	rows := make([]map[string]any, 0, len(keys))
	for _, key := range keys {
		rows = append(rows, map[string]any{"key": key, "next_cursor": cursor})
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	return []string{"key", "next_cursor"}, rows, nil
}
