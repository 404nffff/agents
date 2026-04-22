package main

import (
	"encoding/json"
	"strings"
	"testing"

	"db_query/internal/cli"
)

func TestResolveSQLQuerySupportsUnifiedAliases(t *testing.T) {
	query, err := resolveSQLQuery(cli.Options{
		Target: "users",
		Fields: "id,name",
		Where:  "status = 'active'",
		Sort:   "id desc",
		Limit:  20,
	})
	if err != nil {
		t.Fatalf("resolveSQLQuery returned error: %v", err)
	}
	want := "SELECT `id`, `name` FROM `users` WHERE status = 'active' ORDER BY id desc LIMIT 20"
	if query != want {
		t.Fatalf("expected %q, got %q", want, query)
	}
}

func TestValidateStructuredQueryConflictRejectsQueryAndTarget(t *testing.T) {
	err := validateStructuredQueryConflict("mongo", cli.Options{
		Query:  "{\"collection\":\"users\"}",
		Target: "users",
	})
	if err == nil {
		t.Fatalf("expected conflict error")
	}
	if !strings.Contains(err.Error(), "--query cannot be used with") {
		t.Fatalf("expected query conflict message, got %v", err)
	}
}

func TestBuildRedisQueryUsesTargetForScanPattern(t *testing.T) {
	query, err := buildRedisQuery(cli.Options{
		Command: "scan",
		Target:  "session:*",
		Limit:   25,
	})
	if err != nil {
		t.Fatalf("buildRedisQuery returned error: %v", err)
	}
	if !strings.Contains(query, "\"pattern\":\"session:*\"") {
		t.Fatalf("expected redis pattern in query, got %s", query)
	}
	if !strings.Contains(query, "\"count\":25") {
		t.Fatalf("expected redis count in query, got %s", query)
	}
}

func TestBuildMongoQueryRejectsJSONSortSyntax(t *testing.T) {
	_, err := buildMongoQuery(cli.Options{
		Target: "users",
		Sort:   "{\"created_at\":-1}",
		Limit:  20,
	})
	if err == nil {
		t.Fatalf("expected mongo json sort syntax to be rejected")
	}
	if !strings.Contains(err.Error(), "mongo --sort must use field:asc or field:desc") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestBuildMongoRawSQLUsesMongoShellSyntax(t *testing.T) {
	rawSQL, err := buildMongoRawSQL("app_db", `{"collection":"t_student","filter":{},"limit":3,"operation":"find"}`)
	if err != nil {
		t.Fatalf("buildMongoRawSQL returned error: %v", err)
	}
	want := `db.getSiblingDB("app_db").getCollection("t_student").find({}).limit(3)`
	if rawSQL != want {
		t.Fatalf("expected %q, got %q", want, rawSQL)
	}
}

func TestBuildRedisRawSQLUsesCommandSyntax(t *testing.T) {
	rawSQL, err := buildRedisRawSQL(`{"command":"SCAN","pattern":"session:*","count":50}`)
	if err != nil {
		t.Fatalf("buildRedisRawSQL returned error: %v", err)
	}
	want := "SCAN 0 MATCH session:* COUNT 50"
	if rawSQL != want {
		t.Fatalf("expected %q, got %q", want, rawSQL)
	}
}

func TestBuildESQueryUsesUnifiedFlags(t *testing.T) {
	query, err := buildESQuery(cli.Options{
		Target:       "student_index",
		Fields:       "name,age",
		WhereClauses: []string{"status:=:active", "age:>=:18"},
		Sort:         "created_at:desc",
		Limit:        20,
	})
	if err != nil {
		t.Fatalf("buildESQuery returned error: %v", err)
	}

	var payload map[string]any
	if err := json.Unmarshal([]byte(query), &payload); err != nil {
		t.Fatalf("query must be valid json: %v", err)
	}

	if payload["index"] != "student_index" {
		t.Fatalf("expected index student_index, got %#v", payload["index"])
	}

	body, ok := payload["body"].(map[string]any)
	if !ok {
		t.Fatalf("expected body object, got %#v", payload["body"])
	}
	if body["size"] != float64(20) {
		t.Fatalf("expected size 20, got %#v", body["size"])
	}

	source, ok := body["_source"].([]any)
	if !ok || len(source) != 2 || source[0] != "name" || source[1] != "age" {
		t.Fatalf("expected _source [name age], got %#v", body["_source"])
	}

	queryExpr, ok := body["query"].(map[string]any)
	if !ok {
		t.Fatalf("expected query object, got %#v", body["query"])
	}
	boolExpr, ok := queryExpr["bool"].(map[string]any)
	if !ok {
		t.Fatalf("expected bool query, got %#v", queryExpr["bool"])
	}
	filters, ok := boolExpr["filter"].([]any)
	if !ok || len(filters) != 2 {
		t.Fatalf("expected 2 filters, got %#v", boolExpr["filter"])
	}

	sortExpr, ok := body["sort"].([]any)
	if !ok || len(sortExpr) != 1 {
		t.Fatalf("expected one sort expression, got %#v", body["sort"])
	}
}

func TestBuildESRawSQLUsesCurlSyntax(t *testing.T) {
	rawSQL, err := buildESRawSQL("http://127.0.0.1:9200", `{"index":"student_index","body":{"size":3}}`)
	if err != nil {
		t.Fatalf("buildESRawSQL returned error: %v", err)
	}
	if !strings.Contains(rawSQL, "curl -X POST 'http://127.0.0.1:9200/student_index/_search'") {
		t.Fatalf("expected curl search command, got %q", rawSQL)
	}
	if !strings.Contains(rawSQL, `-d '{"size":3}'`) {
		t.Fatalf("expected curl body payload, got %q", rawSQL)
	}
}
