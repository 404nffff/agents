package memcached

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	gomemcache "github.com/bradfitz/gomemcache/memcache"

	"db_query/internal/core"
)

type queryRequest struct {
	Command string   `json:"command"`
	Key     string   `json:"key"`
	Keys    []string `json:"keys"`
}

func Query(ctx context.Context, cfg core.MemcachedConnConfig, queryRaw string, maxRows int) ([]string, []map[string]any, error) {
	if len(cfg.Addrs) == 0 {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "memcached addr is required")
	}
	if strings.TrimSpace(queryRaw) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "memcached --query is required")
	}

	req := queryRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &req); err != nil {
		return nil, nil, core.WrapAppError(core.CodeInvalidQuery, "memcached --query must be valid json", err)
	}
	req, err := buildStructuredQuery(req)
	if err != nil {
		return nil, nil, err
	}
	cmd := req.Command
	if !slices.Contains(cfg.AllowedCommands, cmd) {
		return nil, nil, core.NewAppError(
			core.CodeInvalidQuery,
			"memcached command is not allowed, only "+strings.Join(cfg.AllowedCommands, ","),
		)
	}

	client := gomemcache.New(cfg.Addrs...)
	if cfg.TimeoutSeconds > 0 {
		client.Timeout = time.Duration(cfg.TimeoutSeconds) * time.Second
	}
	switch cmd {
	case "GET":
		return runGet(ctx, client, req)
	case "MGET":
		return runMGet(ctx, client, req, maxRows)
	default:
		return nil, nil, core.NewAppError(
			core.CodeInvalidQuery,
			"memcached command is configured as allowed but not implemented: "+cmd,
		)
	}
}

func buildStructuredQuery(req queryRequest) (queryRequest, error) {
	req.Command = strings.ToUpper(strings.TrimSpace(req.Command))
	if req.Command == "" {
		return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "memcached query.command is required")
	}

	switch req.Command {
	case "GET":
		if strings.TrimSpace(req.Key) == "" {
			return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "memcached GET requires query.key")
		}
	case "MGET":
		if len(req.Keys) == 0 && strings.TrimSpace(req.Key) == "" {
			return queryRequest{}, core.NewAppError(core.CodeInvalidQuery, "memcached MGET requires query.keys or comma-separated query.key")
		}
	default:
		// 白名单仍由配置控制；这里只校验当前已实现命令的必填字段。
	}

	return req, nil
}

func runGet(ctx context.Context, client *gomemcache.Client, req queryRequest) ([]string, []map[string]any, error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "memcached GET canceled", err)
	}
	item, err := client.Get(req.Key)
	if err == gomemcache.ErrCacheMiss {
		return nil, []map[string]any{}, nil
	}
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "memcached GET failed", err)
	}
	return itemColumns(), []map[string]any{itemRow(item)}, nil
}

func runMGet(ctx context.Context, client *gomemcache.Client, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "memcached MGET canceled", err)
	}
	keys := cleanKeys(req.Keys)
	if len(keys) == 0 && strings.TrimSpace(req.Key) != "" {
		keys = cleanKeys(strings.Split(req.Key, ","))
	}
	if len(keys) == 0 {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "memcached MGET requires query.keys or comma-separated query.key")
	}

	items, err := client.GetMulti(keys)
	if err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "memcached MGET failed", err)
	}

	rows := make([]map[string]any, 0, len(items))
	for _, key := range keys {
		item, ok := items[key]
		if !ok {
			continue
		}
		rows = append(rows, itemRow(item))
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	return itemColumns(), rows, nil
}

func cleanKeys(keys []string) []string {
	out := make([]string, 0, len(keys))
	for _, key := range keys {
		key = strings.TrimSpace(key)
		if key != "" {
			out = append(out, key)
		}
	}
	return out
}

func itemColumns() []string {
	return []string{"key", "value", "flags", "cas_id"}
}

func itemRow(item *gomemcache.Item) map[string]any {
	return map[string]any{
		"key":    item.Key,
		"value":  string(item.Value),
		"flags":  item.Flags,
		"cas_id": item.CasID,
	}
}
