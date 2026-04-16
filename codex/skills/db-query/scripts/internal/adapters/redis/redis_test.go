package redis

import "testing"

func TestBuildStructuredQueryMapsTargetToKeyAndPattern(t *testing.T) {
	getReq, err := buildStructuredQuery(queryRequest{
		Command: "GET",
		Key:     "session:1",
	})
	if err != nil {
		t.Fatalf("buildStructuredQuery GET returned error: %v", err)
	}
	if getReq.Key != "session:1" {
		t.Fatalf("expected key session:1, got %#v", getReq.Key)
	}

	scanReq, err := buildStructuredQuery(queryRequest{
		Command: "SCAN",
		Pattern: "session:*",
		Count:   25,
	})
	if err != nil {
		t.Fatalf("buildStructuredQuery SCAN returned error: %v", err)
	}
	if scanReq.Pattern != "session:*" {
		t.Fatalf("expected pattern session:*, got %#v", scanReq.Pattern)
	}
	if scanReq.Count != 25 {
		t.Fatalf("expected count 25, got %d", scanReq.Count)
	}
}

func TestBuildStructuredQueryRejectsMissingCommand(t *testing.T) {
	_, err := buildStructuredQuery(queryRequest{Key: "session:1"})
	if err == nil {
		t.Fatalf("expected missing command error")
	}
}
