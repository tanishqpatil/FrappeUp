package config

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Profile string

const (
	Development Profile = "development"
	Production  Profile = "production"
)

type Config struct {
	Profile                Profile
	SiteName               string
	FrappeRepository       string
	FrappeRef              string
	FrappeDockerRepository string
	FrappeDockerRef        string
	FrappeMajor            int
	InstallApps            []string
	CustomAppsFile         string
	ProjectName            string
	WorkspaceDir           string
	AllowUnpinnedRefs      bool
}

func Load(path string) (Config, error) {
	values, err := readDotEnv(path)
	if err != nil {
		return Config{}, err
	}
	return fromValues(values, filepath.Dir(path))
}

func readDotEnv(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("read environment file: %w", err)
	}
	defer f.Close()

	values := map[string]string{}
	scanner := bufio.NewScanner(f)
	for lineNumber := 1; scanner.Scan(); lineNumber++ {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(key) == "" {
			return nil, fmt.Errorf("parse environment file: line %d must use KEY=VALUE", lineNumber)
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if len(value) >= 2 && ((value[0] == '\'' && value[len(value)-1] == '\'') || (value[0] == '"' && value[len(value)-1] == '"')) {
			value = value[1 : len(value)-1]
		}
		values[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read environment file: %w", err)
	}
	return values, nil
}

func fromValues(v map[string]string, envDir string) (Config, error) {
	profile := Profile(defaultValue(v["PROFILE"], string(Development)))
	if profile != Development && profile != Production {
		return Config{}, fmt.Errorf("PROFILE must be development or production")
	}
	major, err := strconv.Atoi(defaultValue(v["FRAPPE_MAJOR"], "16"))
	if err != nil || major < 1 {
		return Config{}, fmt.Errorf("FRAPPE_MAJOR must be a positive integer")
	}
	allowUnpinned, err := strconv.ParseBool(defaultValue(v["ALLOW_UNPINNED_REFS"], "false"))
	if err != nil {
		return Config{}, fmt.Errorf("ALLOW_UNPINNED_REFS must be true or false")
	}
	customAppsFile := strings.TrimSpace(v["CUSTOM_APPS_FILE"])
	if customAppsFile != "" && !filepath.IsAbs(customAppsFile) {
		customAppsFile = filepath.Join(envDir, customAppsFile)
	}
	workspaceDir := strings.TrimSpace(v["WORKSPACE_DIR"])
	if workspaceDir == "" {
		workspaceDir = filepath.Join(envDir, ".frappe1tap", "workspaces", defaultValue(v["PROJECT_NAME"], "frappe1tap"))
	} else if !filepath.IsAbs(workspaceDir) {
		workspaceDir = filepath.Join(envDir, workspaceDir)
	}

	c := Config{
		Profile:                profile,
		SiteName:               defaultValue(v["SITE_NAME"], "site.localhost"),
		FrappeRepository:       defaultValue(v["FRAPPE_REPOSITORY"], "https://github.com/frappe/frappe"),
		FrappeRef:              defaultValue(v["FRAPPE_REF"], "version-16"),
		FrappeDockerRepository: defaultValue(v["FRAPPE_DOCKER_REPOSITORY"], "https://github.com/frappe/frappe_docker"),
		FrappeDockerRef:        defaultValue(v["FRAPPE_DOCKER_REF"], "main"),
		FrappeMajor:            major,
		InstallApps:            splitList(v["INSTALL_APPS"]),
		CustomAppsFile:         customAppsFile,
		ProjectName:            defaultValue(v["PROJECT_NAME"], "frappe1tap"),
		WorkspaceDir:           workspaceDir,
		AllowUnpinnedRefs:      allowUnpinned,
	}
	if c.SiteName == "" || c.FrappeRepository == "" || c.FrappeRef == "" || c.FrappeDockerRepository == "" || c.FrappeDockerRef == "" || c.ProjectName == "" {
		return Config{}, fmt.Errorf("SITE_NAME, FRAPPE_REPOSITORY, FRAPPE_REF, FRAPPE_DOCKER_REPOSITORY, FRAPPE_DOCKER_REF, and PROJECT_NAME cannot be blank")
	}
	return c, nil
}

func splitList(raw string) []string {
	seen := map[string]bool{}
	var values []string
	for _, value := range strings.Split(raw, ",") {
		value = strings.TrimSpace(value)
		if value != "" && !seen[value] {
			seen[value] = true
			values = append(values, value)
		}
	}
	return values
}

func defaultValue(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return strings.TrimSpace(value)
}
