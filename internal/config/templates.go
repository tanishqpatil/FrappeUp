package config

import "fmt"

func Template(profile Profile) (string, error) {
	switch profile {
	case Development:
		return `# Frappe 1-Tap development profile
PROFILE=development
PROJECT_NAME=frappe1tap-dev
SITE_NAME=site.localhost

# The planner uses this to validate selected app compatibility.
FRAPPE_REPOSITORY=https://github.com/frappe/frappe
FRAPPE_REF=version-16
FRAPPE_DOCKER_REPOSITORY=https://github.com/frappe/frappe_docker
FRAPPE_DOCKER_REF=main
FRAPPE_MAJOR=16

# Comma-separated official catalog IDs. Dependencies are added automatically.
INSTALL_APPS=erpnext,hrms

# Optional path, relative to this file, containing custom app definitions.
# CUSTOM_APPS_FILE=custom-apps.json

# Development may use branches. Production must create a lock file first.
ALLOW_UNPINNED_REFS=true

# Optional workspace path, relative to this file.
# WORKSPACE_DIR=.frappe1tap/workspaces/frappe1tap-dev
`, nil
	case Production:
		return `# Frappe 1-Tap production profile
PROFILE=production
PROJECT_NAME=frappe1tap-prod
SITE_NAME=site.example.com

FRAPPE_REPOSITORY=https://github.com/frappe/frappe
FRAPPE_REF=version-16
FRAPPE_DOCKER_REPOSITORY=https://github.com/frappe/frappe_docker
FRAPPE_DOCKER_REF=main
FRAPPE_MAJOR=16

INSTALL_APPS=erpnext,hrms
# CUSTOM_APPS_FILE=custom-apps.json

# Production requires a commit lock before installation.
ALLOW_UNPINNED_REFS=false
# WORKSPACE_DIR=.frappe1tap/workspaces/frappe1tap-prod
`, nil
	default:
		return "", fmt.Errorf("profile must be development or production")
	}
}
