package core

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
)

var (
	sqlCommentBlockPattern = regexp.MustCompile(`/\*.*?\*/`)
	sqlCommentDashPattern  = regexp.MustCompile(`--[^\n]*`)
	sqlCommentHashPattern  = regexp.MustCompile(`#[^\n]*`)
	sqlSpacePattern        = regexp.MustCompile(`\s+`)
)

func BuildSQLRulesFromEnv(env map[string]string, prefix string) SQLRules {
	allowed := parseKeywordCSV(env[prefix+"_SQL_ALLOWED_START"])
	if len(allowed) == 0 {
		allowed = slices.Clone(DefaultSQLAllowedStart)
	}

	forbiddenKeywords := parseKeywordCSV(env[prefix+"_SQL_FORBIDDEN_KEYWORDS"])
	if len(forbiddenKeywords) == 0 {
		forbiddenKeywords = slices.Clone(DefaultSQLForbiddenKeywords)
	}

	forbiddenPhrases := parsePhraseCSV(env[prefix+"_SQL_FORBIDDEN_PHRASES"])
	if len(forbiddenPhrases) == 0 {
		forbiddenPhrases = slices.Clone(DefaultSQLForbiddenPhrases)
	}

	return SQLRules{
		AllowedStart:      allowed,
		ForbiddenKeywords: forbiddenKeywords,
		ForbiddenPhrases:  forbiddenPhrases,
	}
}

func NormalizeSQL(sql string) string {
	noBlock := sqlCommentBlockPattern.ReplaceAllString(sql, " ")
	noDash := sqlCommentDashPattern.ReplaceAllString(noBlock, " ")
	noHash := sqlCommentHashPattern.ReplaceAllString(noDash, " ")
	trimmed := strings.TrimSpace(noHash)
	trimmed = strings.TrimSuffix(trimmed, ";")
	return strings.TrimSpace(trimmed)
}

func ValidateSQL(sql string, rules SQLRules) (SQLValidationResult, error) {
	normalized := NormalizeSQL(sql)
	if normalized == "" {
		return SQLValidationResult{}, NewAppError(CodeInvalidQuery, "query is empty after normalization")
	}

	if strings.Contains(normalized, ";") {
		return SQLValidationResult{}, NewAppError(CodeInvalidQuery, "multiple SQL statements are not allowed")
	}

	lower := strings.ToLower(normalized)
	lowerCompact := normalizeSpacesLower(lower)
	parts := strings.Fields(lowerCompact)
	if len(parts) == 0 {
		return SQLValidationResult{}, NewAppError(CodeInvalidQuery, "query is empty after normalization")
	}

	if fileKind, action, ok := detectSQLFileRule(lowerCompact); ok {
		return SQLValidationResult{
			NormalizedSQL:      normalized,
			ShouldGenerateFile: true,
			FileKind:           fileKind,
			Action:             action,
		}, nil
	}

	first := parts[0]
	if !slices.Contains(rules.AllowedStart, first) {
		return SQLValidationResult{}, NewAppError(
			CodeInvalidQuery,
			fmt.Sprintf("only read-only SQL is allowed (allowed starts: %s)", strings.ToUpper(strings.Join(rules.AllowedStart, "/"))),
		)
	}

	allowShowCreate := regexp.MustCompile(`^show\s+create\b`).MatchString(lowerCompact)
	for _, keyword := range rules.ForbiddenKeywords {
		if keyword == "create" && allowShowCreate {
			continue
		}
		if regexp.MustCompile(`\b` + regexp.QuoteMeta(keyword) + `\b`).MatchString(lower) {
			return SQLValidationResult{}, NewAppError(CodeInvalidQuery, fmt.Sprintf("forbidden SQL keyword detected: %s", keyword))
		}
	}

	for _, phrase := range rules.ForbiddenPhrases {
		if phrase != "" && strings.Contains(lowerCompact, phrase) {
			return SQLValidationResult{}, NewAppError(CodeInvalidQuery, fmt.Sprintf("forbidden SQL pattern detected: %s", strings.ToUpper(phrase)))
		}
	}

	return SQLValidationResult{NormalizedSQL: normalized}, nil
}

func detectSQLFileRule(lowerCompact string) (string, string, bool) {
	if regexp.MustCompile(`\binsert\b`).MatchString(lowerCompact) {
		return "dml_insert", "INSERT", true
	}
	if regexp.MustCompile(`\balter\s+table\b`).MatchString(lowerCompact) {
		return "ddl_alter_table", "ALTER TABLE", true
	}
	if regexp.MustCompile(`\bcreate\s+table\b`).MatchString(lowerCompact) {
		return "ddl_create_table", "CREATE TABLE", true
	}
	if regexp.MustCompile(`\bcreate\s+index\b`).MatchString(lowerCompact) {
		return "ddl_create_index", "CREATE INDEX", true
	}
	return "", "", false
}

func normalizeSpacesLower(s string) string {
	return strings.TrimSpace(sqlSpacePattern.ReplaceAllString(strings.ToLower(strings.TrimSpace(s)), " "))
}

func parseKeywordCSV(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}

	seen := make(map[string]struct{})
	out := make([]string, 0)
	for _, item := range strings.Split(raw, ",") {
		n := normalizeSpacesLower(item)
		if n == "" {
			continue
		}
		if !regexp.MustCompile(`^[a-z_][a-z0-9_]*$`).MatchString(n) {
			continue
		}
		if _, ok := seen[n]; ok {
			continue
		}
		seen[n] = struct{}{}
		out = append(out, n)
	}
	return out
}

func parsePhraseCSV(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	seen := make(map[string]struct{})
	out := make([]string, 0)
	for _, item := range strings.Split(raw, ",") {
		n := strings.ReplaceAll(item, "_", " ")
		n = normalizeSpacesLower(n)
		if n == "" {
			continue
		}
		if _, ok := seen[n]; ok {
			continue
		}
		seen[n] = struct{}{}
		out = append(out, n)
	}
	return out
}
