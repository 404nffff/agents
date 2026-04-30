package mongo

import "testing"

func TestParseWhereClausesBuildsMongoFilter(t *testing.T) {
	filter, err := parseWhereClauses([]string{
		"status:=:active",
		"age:>=:18",
		"age:<:60",
		"tag:in:vip,gold,new",
		"enabled:=:true",
	})
	if err != nil {
		t.Fatalf("parseWhereClauses returned error: %v", err)
	}

	if filter["status"] != "active" {
		t.Fatalf("expected status active, got %#v", filter["status"])
	}
	age, ok := filter["age"].(map[string]any)
	if !ok {
		t.Fatalf("expected age to be operator map, got %#v", filter["age"])
	}
	if age["$gte"] != int64(18) {
		t.Fatalf("expected $gte 18, got %#v", age["$gte"])
	}
	if age["$lt"] != int64(60) {
		t.Fatalf("expected $lt 60, got %#v", age["$lt"])
	}
	tag, ok := filter["tag"].(map[string]any)
	if !ok {
		t.Fatalf("expected tag to be operator map, got %#v", filter["tag"])
	}
	values, ok := tag["$in"].([]any)
	if !ok || len(values) != 3 {
		t.Fatalf("expected $in with 3 values, got %#v", tag["$in"])
	}
	if filter["enabled"] != true {
		t.Fatalf("expected enabled true, got %#v", filter["enabled"])
	}
}

func TestParseWhereClausesRejectsUnsupportedOperator(t *testing.T) {
	_, err := parseWhereClauses([]string{"age:between:18,60"})
	if err == nil {
		t.Fatalf("expected unsupported operator error")
	}
}
