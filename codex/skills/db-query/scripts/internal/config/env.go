package config

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var profileNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

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
