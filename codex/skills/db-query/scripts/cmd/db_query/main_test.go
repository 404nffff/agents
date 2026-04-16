package main

import (
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
