package memcached

import "testing"

func TestBuildStructuredQueryAcceptsGetAndMGet(t *testing.T) {
	getReq, err := buildStructuredQuery(queryRequest{
		Command: "get",
		Key:     "session:1",
	})
	if err != nil {
		t.Fatalf("buildStructuredQuery GET returned error: %v", err)
	}
	if getReq.Command != "GET" {
		t.Fatalf("expected command GET, got %q", getReq.Command)
	}

	mgetReq, err := buildStructuredQuery(queryRequest{
		Command: "mget",
		Keys:    []string{"session:1", "session:2"},
	})
	if err != nil {
		t.Fatalf("buildStructuredQuery MGET returned error: %v", err)
	}
	if mgetReq.Command != "MGET" {
		t.Fatalf("expected command MGET, got %q", mgetReq.Command)
	}
}

func TestBuildStructuredQueryRejectsMissingMemcachedKeys(t *testing.T) {
	_, err := buildStructuredQuery(queryRequest{Command: "GET"})
	if err == nil {
		t.Fatalf("expected missing key error")
	}

	_, err = buildStructuredQuery(queryRequest{Command: "MGET"})
	if err == nil {
		t.Fatalf("expected missing keys error")
	}
}
