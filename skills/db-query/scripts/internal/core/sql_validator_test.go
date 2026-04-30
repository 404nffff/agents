package core

import (
	"path/filepath"
	"testing"
	"time"
)

func TestValidateSQLAllowsSelect(t *testing.T) {
	rules := SQLRules{
		AllowedStart:      DefaultSQLAllowedStart,
		ForbiddenKeywords: DefaultSQLForbiddenKeywords,
		ForbiddenPhrases:  DefaultSQLForbiddenPhrases,
	}
	result, err := ValidateSQL("SELECT id, name FROM users LIMIT 1", rules)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if result.ShouldGenerateFile {
		t.Fatalf("expected no SQL file generation")
	}
	if result.NormalizedSQL == "" {
		t.Fatalf("expected normalized sql")
	}
}

func TestValidateSQLInsertGeneratesFile(t *testing.T) {
	rules := SQLRules{
		AllowedStart:      DefaultSQLAllowedStart,
		ForbiddenKeywords: DefaultSQLForbiddenKeywords,
		ForbiddenPhrases:  DefaultSQLForbiddenPhrases,
	}
	result, err := ValidateSQL("INSERT INTO users(id, name) VALUES (1, 'a')", rules)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if !result.ShouldGenerateFile {
		t.Fatalf("expected SQL file generation")
	}
	if result.FileKind != "dml_insert" {
		t.Fatalf("unexpected file kind: %s", result.FileKind)
	}
}

func TestValidateSQLRejectsMultiStatement(t *testing.T) {
	rules := SQLRules{
		AllowedStart:      DefaultSQLAllowedStart,
		ForbiddenKeywords: DefaultSQLForbiddenKeywords,
		ForbiddenPhrases:  DefaultSQLForbiddenPhrases,
	}
	_, err := ValidateSQL("SELECT 1; SELECT 2", rules)
	if err == nil {
		t.Fatalf("expected error for multi statement")
	}
}

func TestGenerateSQLFileAt(t *testing.T) {
	dir := t.TempDir()
	path, err := GenerateSQLFileAt("INSERT INTO users VALUES (1)", "dml_insert", time.Date(2026, 3, 20, 10, 0, 0, 0, time.UTC), dir)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	expected := filepath.Join(dir, "dml_insert_20260320_100000.sql")
	if path != expected {
		t.Fatalf("expected %s, got %s", expected, path)
	}
}
