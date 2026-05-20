package config

import "testing"

func TestListConfiguredProfilesOnlyExposesProfileNames(t *testing.T) {
	profiles, err := ListConfiguredProfiles(map[string]string{
		"DB_PROFILE":                   "main",
		"MYSQL_PROFILE":                "report",
		"MYSQL_HOST_main":              "127.0.0.1",
		"MYSQL_PASSWORD_main":          "secret",
		"MYSQL_DATABASE_report":        "report_db",
		"MYSQL_SQL_ALLOWED_START":      "select,show",
		"REDIS_PROFILE":                "cache",
		"REDIS_ADDR_cache":             "127.0.0.1:6379",
		"REDIS_ALLOWED_COMMANDS_cache": "GET",
	}, "mysql")
	if err != nil {
		t.Fatalf("ListConfiguredProfiles returned error: %v", err)
	}
	if len(profiles) != 1 {
		t.Fatalf("expected one driver summary, got %d", len(profiles))
	}
	got := profiles[0]
	if got.Driver != "mysql" {
		t.Fatalf("expected mysql driver, got %q", got.Driver)
	}
	if got.DriverDefaultProfile != "report" {
		t.Fatalf("expected driver default report, got %q", got.DriverDefaultProfile)
	}
	if got.EffectiveDefaultProfile != "main" {
		t.Fatalf("expected effective default main, got %q", got.EffectiveDefaultProfile)
	}
	wantProfiles := []string{"main", "report"}
	if len(got.Profiles) != len(wantProfiles) {
		t.Fatalf("expected profiles %#v, got %#v", wantProfiles, got.Profiles)
	}
	for i, want := range wantProfiles {
		if got.Profiles[i] != want {
			t.Fatalf("expected profile %q at index %d, got %q", want, i, got.Profiles[i])
		}
	}
}

func TestListConfiguredProfilesRejectsUnknownDriver(t *testing.T) {
	_, err := ListConfiguredProfiles(map[string]string{}, "sqlite")
	if err == nil {
		t.Fatalf("expected unsupported driver error")
	}
}
