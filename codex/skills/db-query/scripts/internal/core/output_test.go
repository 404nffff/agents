package core

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestEncodeJSON_PrettyAndNoHTMLEscape(t *testing.T) {
	payload := map[string]any{
		"html": "<b>\u6d4b\u8bd5</b>",
		"text": "\u4e2d\u6587",
	}

	data, err := encodeJSON(payload)
	if err != nil {
		t.Fatalf("encodeJSON failed: %v", err)
	}

	if !utf8.Valid(data) {
		t.Fatalf("encodeJSON should return valid utf-8 bytes")
	}

	got := string(data)
	if !strings.Contains(got, "<b>\u6d4b\u8bd5</b>") {
		t.Fatalf("expected html not escaped, got: %s", got)
	}
	if !strings.HasPrefix(got, "{\n  ") {
		t.Fatalf("expected pretty json with indentation, got: %s", got)
	}
	if !strings.HasSuffix(got, "\n") {
		t.Fatalf("expected trailing newline")
	}
}

func TestEncodeJSON_InvalidValue(t *testing.T) {
	_, err := encodeJSON(map[string]any{
		"bad": make(chan int),
	})
	if err == nil {
		t.Fatalf("expected encodeJSON to fail on unsupported value")
	}

	var unsupported *json.UnsupportedTypeError
	if !errors.As(err, &unsupported) && !strings.Contains(err.Error(), "unsupported type") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestEncodeJSON_SuccessPayloadIncludesRawSQL(t *testing.T) {
	payload := SuccessPayload{
		Driver:   "mysql",
		Profile:  "main",
		Query:    "SELECT id FROM users LIMIT 1",
		RawSQL:   "SELECT id FROM users LIMIT 1",
		RowCount: 1,
		Rows: []map[string]any{
			{"id": 1},
		},
	}

	data, err := encodeJSON(payload)
	if err != nil {
		t.Fatalf("encodeJSON failed: %v", err)
	}

	got := string(data)
	if !strings.Contains(got, "\"raw_sql\": \"SELECT id FROM users LIMIT 1\"") {
		t.Fatalf("expected raw_sql in payload, got: %s", got)
	}
}
