package core

const (
	MaxLimit       = 1000
	DefaultLimit   = 100
	DefaultMaxRows = 2000
	DefaultTimeout = 10
)

var DefaultSQLAllowedStart = []string{"select", "show", "desc", "describe", "explain", "with"}

var DefaultSQLForbiddenKeywords = []string{
	"delete", "insert", "update", "replace", "truncate", "drop", "alter", "create",
	"grant", "revoke", "rename", "merge", "call",
}

var DefaultSQLForbiddenPhrases = []string{
	"into outfile", "into dumpfile", "load data", "lock tables", "unlock tables",
}
