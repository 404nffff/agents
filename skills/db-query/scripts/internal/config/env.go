package config

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var profileNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

type DriverProfileSummary struct {
	Driver                  string   `json:"driver"`
	Profiles                []string `json:"profiles"`
	DriverDefaultProfile    string   `json:"driver_default_profile,omitempty"`
	EffectiveDefaultProfile string   `json:"effective_default_profile,omitempty"`
}

type profileDriverSpec struct {
	driver        string
	profileKey    string
	valuePrefixes []string
}

var profileDriverSpecs = []profileDriverSpec{
	{
		driver:     "mysql",
		profileKey: "MYSQL_PROFILE",
		valuePrefixes: []string{
			"MYSQL_HOST_", "MYSQL_PORT_", "MYSQL_USER_", "MYSQL_PASSWORD_", "MYSQL_DATABASE_", "MYSQL_SOCKET_", "MYSQL_TIMEOUT_",
		},
	},
	{
		driver:     "pgsql",
		profileKey: "PGSQL_PROFILE",
		valuePrefixes: []string{
			"PGSQL_HOST_", "PGSQL_PORT_", "PGSQL_USER_", "PGSQL_PASSWORD_", "PGSQL_DATABASE_", "PGSQL_SSLMODE_", "PGSQL_TIMEOUT_",
		},
	},
	{
		driver:     "mongo",
		profileKey: "MONGO_PROFILE",
		valuePrefixes: []string{
			"MONGO_URI_", "MONGO_DATABASE_", "MONGO_TIMEOUT_", "MONGO_ALLOWED_OPERATIONS_", "MONGO_FORBIDDEN_AGG_STAGES_",
		},
	},
	{
		driver:     "redis",
		profileKey: "REDIS_PROFILE",
		valuePrefixes: []string{
			"REDIS_ADDR_", "REDIS_USER_", "REDIS_PASSWORD_", "REDIS_DB_", "REDIS_TIMEOUT_", "REDIS_ALLOWED_COMMANDS_",
		},
	},
	{
		driver:     "memcached",
		profileKey: "MEMCACHED_PROFILE",
		valuePrefixes: []string{
			"MEMCACHED_ADDR_", "MEMCACHED_TIMEOUT_", "MEMCACHED_ALLOWED_COMMANDS_",
		},
	},
	{
		driver:     "es",
		profileKey: "ES_PROFILE",
		valuePrefixes: []string{
			"ES_URL_", "ES_USERNAME_", "ES_PASSWORD_", "ES_INDEX_", "ES_TIMEOUT_",
		},
	},
}

func IsProfileName(name string) bool {
	return profileNamePattern.MatchString(name)
}

func ResolveConfigPath(explicitPath string) (string, error) {
	if strings.TrimSpace(explicitPath) != "" {
		if _, err := os.Stat(explicitPath); err != nil {
			return "", fmt.Errorf("config file not found: %s", explicitPath)
		}
		return explicitPath, nil
	}

	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		if filepath.Base(exeDir) == "bin" {
			candidate := filepath.Join(filepath.Dir(exeDir), "config.env")
			if _, err := os.Stat(candidate); err == nil {
				return candidate, nil
			}
		}
	}

	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("failed to resolve working directory: %w", err)
	}
	candidate := filepath.Join(cwd, "config.env")
	if _, err := os.Stat(candidate); err == nil {
		return candidate, nil
	}

	return "", fmt.Errorf("config file not found: expected --config or config.env in executable skill root/current directory")
}

func LoadEnvFile(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open config file: %w", err)
	}
	defer f.Close()

	out := make(map[string]string)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "export ") {
			line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		}
		idx := strings.Index(line, "=")
		if idx <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		if key == "" {
			continue
		}
		if strings.HasPrefix(val, "\"") && strings.HasSuffix(val, "\"") && len(val) >= 2 {
			val = val[1 : len(val)-1]
		} else if strings.HasPrefix(val, "'") && strings.HasSuffix(val, "'") && len(val) >= 2 {
			val = val[1 : len(val)-1]
		} else if hash := strings.Index(val, " #"); hash >= 0 {
			val = strings.TrimSpace(val[:hash])
		}
		out[key] = expandEnvRefs(val, out)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}
	return out, nil
}

func GetProfileValue(env map[string]string, key, profile string) string {
	if profile == "" {
		return ""
	}
	return strings.TrimSpace(env[key+"_"+profile])
}

func ResolveProfile(driver, explicit string, env map[string]string) (string, error) {
	if explicit != "" {
		if !IsProfileName(explicit) {
			return "", fmt.Errorf("invalid --profile name: %s", explicit)
		}
		return explicit, nil
	}

	if v := strings.TrimSpace(env["DB_PROFILE"]); v != "" {
		if !IsProfileName(v) {
			return "", fmt.Errorf("invalid DB_PROFILE: %s", v)
		}
		return v, nil
	}

	driverKey := strings.ToUpper(strings.TrimSpace(driver)) + "_PROFILE"
	if v := strings.TrimSpace(env[driverKey]); v != "" {
		if !IsProfileName(v) {
			return "", fmt.Errorf("invalid %s: %s", driverKey, v)
		}
		return v, nil
	}

	return "", fmt.Errorf("profile is required: pass --profile or set DB_PROFILE/%s", driverKey)
}

func ListConfiguredProfiles(env map[string]string, driverFilter string) ([]DriverProfileSummary, error) {
	driverFilter = strings.ToLower(strings.TrimSpace(driverFilter))
	if driverFilter != "" && !isKnownDriver(driverFilter) {
		return nil, fmt.Errorf("unsupported driver: %s", driverFilter)
	}

	globalDefault := strings.TrimSpace(env["DB_PROFILE"])
	out := make([]DriverProfileSummary, 0, len(profileDriverSpecs))
	for _, spec := range profileDriverSpecs {
		if driverFilter != "" && spec.driver != driverFilter {
			continue
		}

		profileSet := make(map[string]struct{})
		for key := range env {
			for _, prefix := range spec.valuePrefixes {
				if !strings.HasPrefix(key, prefix) {
					continue
				}
				name := strings.TrimSpace(strings.TrimPrefix(key, prefix))
				if name != "" && IsProfileName(name) {
					profileSet[name] = struct{}{}
				}
			}
		}

		driverDefault := strings.TrimSpace(env[spec.profileKey])

		profiles := make([]string, 0, len(profileSet))
		for name := range profileSet {
			profiles = append(profiles, name)
		}
		sort.Strings(profiles)

		effectiveDefault := driverDefault
		if globalDefault != "" {
			effectiveDefault = globalDefault
		}

		out = append(out, DriverProfileSummary{
			Driver:                  spec.driver,
			Profiles:                profiles,
			DriverDefaultProfile:    driverDefault,
			EffectiveDefaultProfile: effectiveDefault,
		})
	}

	return out, nil
}

func isKnownDriver(driver string) bool {
	for _, spec := range profileDriverSpecs {
		if spec.driver == driver {
			return true
		}
	}
	return false
}

func ParseCSV(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	seen := make(map[string]struct{})
	for _, p := range parts {
		v := strings.TrimSpace(p)
		if v == "" {
			continue
		}
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

func expandEnvRefs(value string, vars map[string]string) string {
	reBraced := regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)\}`)
	reSimple := regexp.MustCompile(`\$([A-Za-z_][A-Za-z0-9_]*)`)

	expanded := reBraced.ReplaceAllStringFunc(value, func(match string) string {
		sub := reBraced.FindStringSubmatch(match)
		if len(sub) != 2 {
			return match
		}
		name := sub[1]
		if v, ok := vars[name]; ok {
			return v
		}
		return os.Getenv(name)
	})

	expanded = reSimple.ReplaceAllStringFunc(expanded, func(match string) string {
		sub := reSimple.FindStringSubmatch(match)
		if len(sub) != 2 {
			return match
		}
		name := sub[1]
		if v, ok := vars[name]; ok {
			return v
		}
		return os.Getenv(name)
	})

	return expanded
}
