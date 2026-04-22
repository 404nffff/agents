package es

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"db_query/internal/core"
)

func TestQueryReadsSearchHitsIntoRows(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST method, got %s", r.Method)
		}
		if r.URL.Path != "/student_index/_search" {
			t.Fatalf("expected _search path, got %s", r.URL.Path)
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("failed to read request body: %v", err)
		}
		if !strings.Contains(string(body), `"size":2`) {
			t.Fatalf("expected search body to contain size, got %s", string(body))
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"hits": {
				"hits": [
					{
						"_id": "1",
						"_index": "student_index",
						"_score": 1.0,
						"_source": {"name":"alice","age":18}
					}
				]
			}
		}`))
	}))
	defer server.Close()

	columns, rows, err := Query(context.Background(), core.ESConnConfig{
		URL:            server.URL,
		TimeoutSeconds: 5,
	}, `{"index":"student_index","body":{"size":2}}`, 10)
	if err != nil {
		t.Fatalf("Query returned error: %v", err)
	}
	if len(columns) == 0 {
		t.Fatalf("expected flattened columns, got %#v", columns)
	}
	if len(rows) != 1 {
		t.Fatalf("expected one row, got %d", len(rows))
	}
	if rows[0]["_id"] != "1" {
		t.Fatalf("expected _id 1, got %#v", rows[0]["_id"])
	}
	if rows[0]["name"] != "alice" {
		t.Fatalf("expected name alice, got %#v", rows[0]["name"])
	}
	if rows[0]["age"] != float64(18) {
		t.Fatalf("expected age 18, got %#v", rows[0]["age"])
	}
}

func TestQueryRejectsMissingIndex(t *testing.T) {
	_, _, err := Query(context.Background(), core.ESConnConfig{
		URL:            "http://127.0.0.1:9200",
		TimeoutSeconds: 5,
	}, `{"body":{"size":2}}`, 10)
	if err == nil {
		t.Fatalf("expected missing index error")
	}
}
