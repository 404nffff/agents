package cli

import "testing"

func TestParseSupportsUnifiedQueryFlags(t *testing.T) {
	opts, err := Parse([]string{
		"--driver", "mongo",
		"--target", "users",
		"--fields", "name,email",
		"--sort", "{\"_id\":-1}",
		"--where", "status:=:active",
		"--where", "age:>=:18",
		"--command", "scan",
		"--pipeline", "[{\"$match\":{\"status\":\"active\"}}]",
	})
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	if opts.Target != "users" {
		t.Fatalf("expected target users, got %q", opts.Target)
	}
	if opts.Fields != "name,email" {
		t.Fatalf("expected fields name,email, got %q", opts.Fields)
	}
	if opts.Sort != "{\"_id\":-1}" {
		t.Fatalf("expected sort json, got %q", opts.Sort)
	}
	if len(opts.WhereClauses) != 2 {
		t.Fatalf("expected 2 where clauses, got %d", len(opts.WhereClauses))
	}
	if opts.Command != "scan" {
		t.Fatalf("expected command scan, got %q", opts.Command)
	}
	if opts.Pipeline != "[{\"$match\":{\"status\":\"active\"}}]" {
		t.Fatalf("expected pipeline preserved, got %q", opts.Pipeline)
	}
}

func TestParseKeepsLegacySQLFlags(t *testing.T) {
	opts, err := Parse([]string{
		"--driver", "mysql",
		"--table", "users",
		"--columns", "id,name",
		"--order-by", "id desc",
	})
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	if opts.Table != "users" {
		t.Fatalf("expected table users, got %q", opts.Table)
	}
	if opts.Columns != "id,name" {
		t.Fatalf("expected columns id,name, got %q", opts.Columns)
	}
	if opts.OrderBy != "id desc" {
		t.Fatalf("expected order by id desc, got %q", opts.OrderBy)
	}
}
