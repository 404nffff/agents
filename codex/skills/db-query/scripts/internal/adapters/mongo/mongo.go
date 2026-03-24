package mongo

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"db_query/internal/core"
)

type queryRequest struct {
	Operation  string                 `json:"operation"`
	Collection string                 `json:"collection"`
	Filter     map[string]interface{} `json:"filter"`
	Projection map[string]interface{} `json:"projection"`
	Sort       map[string]interface{} `json:"sort"`
	Limit      int                    `json:"limit"`
	Pipeline   []map[string]any       `json:"pipeline"`
}

func Query(ctx context.Context, cfg core.MongoConnConfig, queryRaw string, maxRows int) ([]string, []map[string]any, error) {
	if strings.TrimSpace(cfg.URI) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "mongo uri is required")
	}
	if strings.TrimSpace(cfg.Database) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidConfig, "mongo database is required")
	}
	if strings.TrimSpace(queryRaw) == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "mongo --query is required")
	}

	req := queryRequest{}
	if err := json.Unmarshal([]byte(queryRaw), &req); err != nil {
		return nil, nil, core.WrapAppError(core.CodeInvalidQuery, "mongo --query must be valid json", err)
	}
	req.Operation = strings.ToLower(strings.TrimSpace(req.Operation))
	if req.Operation == "" {
		req.Operation = "find"
	}
	if !slices.Contains(cfg.AllowedOperations, req.Operation) {
		return nil, nil, core.NewAppError(
			core.CodeInvalidQuery,
			"mongo operation is not allowed, only "+strings.Join(cfg.AllowedOperations, ","),
		)
	}
	if req.Collection == "" {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "mongo query.collection is required")
	}
	if req.Limit <= 0 {
		req.Limit = maxRows
	}
	if req.Limit > maxRows {
		req.Limit = maxRows
	}

	timeout := cfg.TimeoutSeconds
	if timeout <= 0 {
		timeout = core.DefaultTimeout
	}
	connCtx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	client, err := mongo.Connect(connCtx, options.Client().ApplyURI(cfg.URI))
	if err != nil {
		return nil, nil, wrapMongoError(core.CodeConnectionError, "failed to connect mongo", err)
	}
	defer func() { _ = client.Disconnect(context.Background()) }()

	coll := client.Database(cfg.Database).Collection(req.Collection)

	switch req.Operation {
	case "find":
		return runFind(connCtx, coll, req, maxRows)
	case "aggregate":
		return runAggregate(connCtx, coll, req, maxRows, cfg.ForbiddenAggStages)
	default:
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "mongo operation must be find or aggregate")
	}
}

func runFind(ctx context.Context, coll *mongo.Collection, req queryRequest, maxRows int) ([]string, []map[string]any, error) {
	opts := options.Find().SetLimit(int64(req.Limit))
	if len(req.Projection) > 0 {
		opts.SetProjection(req.Projection)
	}
	if len(req.Sort) > 0 {
		opts.SetSort(req.Sort)
	}

	cursor, err := coll.Find(ctx, req.Filter, opts)
	if err != nil {
		return nil, nil, wrapMongoError(core.CodeExecutionError, "mongo find failed", err)
	}
	defer cursor.Close(ctx)

	rows := make([]map[string]any, 0)
	for cursor.Next(ctx) {
		doc := make(map[string]any)
		if err := cursor.Decode(&doc); err != nil {
			return nil, nil, core.WrapAppError(core.CodeExecutionError, "failed to decode mongo document", err)
		}
		rows = append(rows, doc)
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	if err := cursor.Err(); err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "mongo cursor iteration failed", err)
	}

	return nil, rows, nil
}

func runAggregate(ctx context.Context, coll *mongo.Collection, req queryRequest, maxRows int, forbiddenStages []string) ([]string, []map[string]any, error) {
	if len(req.Pipeline) == 0 {
		return nil, nil, core.NewAppError(core.CodeInvalidQuery, "mongo aggregate requires query.pipeline")
	}

	pipeline := make([]bson.M, 0, len(req.Pipeline))
	for _, stage := range req.Pipeline {
		for key := range stage {
			lowerKey := strings.ToLower(strings.TrimSpace(key))
			if !strings.HasPrefix(lowerKey, "$") {
				lowerKey = "$" + lowerKey
			}
			if slices.Contains(forbiddenStages, lowerKey) {
				return nil, nil, core.NewAppError(core.CodeInvalidQuery, "mongo aggregate contains forbidden write stage: "+lowerKey)
			}
		}
		pipeline = append(pipeline, stage)
	}

	cursor, err := coll.Aggregate(ctx, pipeline, options.Aggregate().SetMaxTime(30*time.Second))
	if err != nil {
		return nil, nil, wrapMongoError(core.CodeExecutionError, "mongo aggregate failed", err)
	}
	defer cursor.Close(ctx)

	rows := make([]map[string]any, 0)
	for cursor.Next(ctx) {
		doc := make(map[string]any)
		if err := cursor.Decode(&doc); err != nil {
			return nil, nil, core.WrapAppError(core.CodeExecutionError, "failed to decode mongo aggregate document", err)
		}
		rows = append(rows, doc)
		if len(rows) > maxRows {
			return nil, nil, core.NewAppError(core.CodeExecutionError, fmt.Sprintf("query returned %d rows, exceeding --max-rows=%d", len(rows), maxRows))
		}
	}
	if err := cursor.Err(); err != nil {
		return nil, nil, core.WrapAppError(core.CodeExecutionError, "mongo aggregate cursor failed", err)
	}

	return nil, rows, nil
}

func wrapMongoError(code, message string, err error) error {
	if err == nil {
		return nil
	}

	errText := strings.ToLower(err.Error())
	switch {
	case strings.Contains(errText, "unsupported mechanism scram-sha-256"):
		return core.WrapAppError(
			code,
			message+"; mongo server does not support SCRAM-SHA-256, try authMechanism=SCRAM-SHA-1 or remove authMechanism",
			err,
		)
	case strings.Contains(errText, "unable to authenticate using mechanism \"scram-sha-1\""):
		return core.WrapAppError(
			code,
			message+"; SCRAM-SHA-1 authentication failed, check username/password/authSource or try SCRAM-SHA-256",
			err,
		)
	case strings.Contains(errText, "unable to authenticate using mechanism \"scram-sha-256\""):
		return core.WrapAppError(
			code,
			message+"; SCRAM-SHA-256 authentication failed, check username/password/authSource",
			err,
		)
	case strings.Contains(errText, "authenticationfailed"):
		return core.WrapAppError(
			code,
			message+"; authentication failed, check username/password/authSource",
			err,
		)
	default:
		return core.WrapAppError(code, message, err)
	}
}
