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

func TestParseAcceptsESDriverWithUnifiedFlags(t *testing.T) {
	opts, err := Parse([]string{
		"--driver", "es",
		"--target", "student_index",
		"--fields", "name,age",
		"--where", "status:=:active",
		"--sort", "created_at:desc",
		"--limit", "15",
	})
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	if opts.Driver != "es" {
		t.Fatalf("expected driver es, got %q", opts.Driver)
	}
	if opts.Target != "student_index" {
		t.Fatalf("expected target student_index, got %q", opts.Target)
	}
	if opts.Fields != "name,age" {
		t.Fatalf("expected fields name,age, got %q", opts.Fields)
	}
	if len(opts.WhereClauses) != 1 || opts.WhereClauses[0] != "status:=:active" {
		t.Fatalf("expected one where clause, got %#v", opts.WhereClauses)
	}
	if opts.Sort != "created_at:desc" {
		t.Fatalf("expected sort created_at:desc, got %q", opts.Sort)
	}
	if opts.Limit != 15 {
		t.Fatalf("expected limit 15, got %d", opts.Limit)
	}
}

func TestParseAcceptsMemcachedDriverWithUnifiedFlags(t *testing.T) {
	opts, err := Parse([]string{
		"--driver", "memcached",
		"--profile", "cache",
		"--command", "mget",
		"--keys", "session:1,session:2",
	})
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	if opts.Driver != "memcached" {
		t.Fatalf("expected driver memcached, got %q", opts.Driver)
	}
	if opts.Command != "mget" {
		t.Fatalf("expected command mget, got %q", opts.Command)
	}
	if opts.Keys != "session:1,session:2" {
		t.Fatalf("expected keys preserved, got %q", opts.Keys)
	}
}
