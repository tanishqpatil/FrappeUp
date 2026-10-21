package plan

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"

	"github.com/SwayAlgo/Frappe1TapInstall/internal/catalog"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/config"
)

type CustomAppFile struct {
	Apps []CustomApp `json:"apps"`
}

type CustomApp struct {
	ID         string   `json:"id"`
	Name       string   `json:"name"`
	Repository string   `json:"repository"`
	Ref        string   `json:"ref"`
	RefKind    string   `json:"ref_kind"`
	AppName    string   `json:"app_name"`
	Requires   []string `json:"requires"`
}

type App struct {
	ID         string   `json:"id"`
	Name       string   `json:"name"`
	Repository string   `json:"repository"`
	Ref        string   `json:"ref"`
	RefKind    string   `json:"ref_kind"`
	AppName    string   `json:"app_name"`
	Requires   []string `json:"requires"`
	Source     string   `json:"source"`
}

type Source struct {
	Repository string `json:"repository"`
	Ref        string `json:"ref"`
	RefKind    string `json:"ref_kind"`
}

type Plan struct {
	SchemaVersion int            `json:"schema_version"`
	Profile       config.Profile `json:"profile"`
	ProjectName   string         `json:"project_name"`
	SiteName      string         `json:"site_name"`
	Frappe        Source         `json:"frappe"`
	FrappeDocker  Source         `json:"frappe_docker"`
	Apps          []App          `json:"apps"`
	Warnings      []string       `json:"warnings,omitempty"`
	LockRequired  bool           `json:"lock_required"`
}

func LoadCustomApps(path string) ([]CustomApp, error) {
	if path == "" {
		return nil, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read custom apps file: %w", err)
	}
	var file CustomAppFile
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, fmt.Errorf("parse custom apps file: %w", err)
	}
	for _, app := range file.Apps {
		if app.ID == "" || app.Repository == "" || app.Ref == "" {
			return nil, fmt.Errorf("custom app %q requires id, repository, and ref", app.ID)
		}
		if app.RefKind == "" {
			app.RefKind = "branch"
		}
	}
	return file.Apps, nil
}

func Build(c catalog.Catalog, cfg config.Config, customApps []CustomApp) (Plan, error) {
	apps := c.ByID()
	for _, custom := range customApps {
		if _, found := apps[custom.ID]; found {
			return Plan{}, fmt.Errorf("custom app %q conflicts with an official catalog id", custom.ID)
		}
		name := custom.Name
		if name == "" {
			name = custom.ID
		}
		apps[custom.ID] = catalog.App{
			ID: custom.ID, DisplayName: name, Publisher: "custom", Repository: custom.Repository,
			Ref: custom.Ref, RefKind: defaultRefKind(custom.RefKind), AppName: custom.AppName,
			SupportedFrappeMajors: []int{cfg.FrappeMajor}, Requires: custom.Requires,
		}
	}

	ordered, err := resolve(cfg.InstallApps, apps, cfg.FrappeMajor)
	if err != nil {
		return Plan{}, err
	}
	result := Plan{
		SchemaVersion: 1, Profile: cfg.Profile, ProjectName: cfg.ProjectName, SiteName: cfg.SiteName,
		Frappe:       Source{Repository: cfg.FrappeRepository, Ref: cfg.FrappeRef, RefKind: refKind(cfg.FrappeRef)},
		FrappeDocker: Source{Repository: cfg.FrappeDockerRepository, Ref: cfg.FrappeDockerRef, RefKind: refKind(cfg.FrappeDockerRef)},
	}
	for _, app := range ordered {
		result.Apps = append(result.Apps, App{
			ID: app.ID, Name: app.DisplayName, Repository: app.Repository, Ref: app.Ref,
			RefKind: app.RefKind, AppName: app.AppName, Requires: app.Requires, Source: app.Publisher,
		})
		if app.Publisher == "custom" && app.AppName == "" {
			result.Warnings = append(result.Warnings, fmt.Sprintf("custom app %q has no app_name; discover and confirm it before installation", app.ID))
		}
	}

	if cfg.Profile == config.Production && !cfg.AllowUnpinnedRefs && hasMovingRef(result) {
		result.LockRequired = true
		result.Warnings = append(result.Warnings, "production uses moving refs; create and use a commit lock before installation")
	}
	return result, nil
}

func resolve(selected []string, apps map[string]catalog.App, frappeMajor int) ([]catalog.App, error) {
	state := map[string]int{}
	var ordered []catalog.App
	var visit func(string, []string) error
	visit = func(id string, trail []string) error {
		app, found := apps[id]
		if !found {
			return fmt.Errorf("app %q is not in the official catalog or custom apps file", id)
		}
		switch state[id] {
		case 1:
			return fmt.Errorf("dependency cycle: %s -> %s", strings.Join(trail, " -> "), id)
		case 2:
			return nil
		}
		if !supports(app.SupportedFrappeMajors, frappeMajor) {
			return fmt.Errorf("app %q does not support Frappe %d", id, frappeMajor)
		}
		state[id] = 1
		deps := append([]string(nil), app.Requires...)
		sort.Strings(deps)
		for _, dep := range deps {
			if err := visit(dep, append(trail, id)); err != nil {
				return err
			}
		}
		state[id] = 2
		ordered = append(ordered, app)
		return nil
	}
	for _, id := range selected {
		if err := visit(id, nil); err != nil {
			return nil, err
		}
	}
	return ordered, nil
}

func supports(versions []int, major int) bool {
	for _, version := range versions {
		if version == major {
			return true
		}
	}
	return false
}

func defaultRefKind(kind string) string {
	if kind == "" {
		return "branch"
	}
	return kind
}

var commitRef = regexp.MustCompile(`^[0-9a-fA-F]{7,64}$`)

func refKind(ref string) string {
	if commitRef.MatchString(ref) {
		return "commit"
	}
	return "branch"
}

func hasMovingRef(p Plan) bool {
	if p.Frappe.RefKind != "commit" {
		return true
	}
	if p.FrappeDocker.RefKind != "commit" {
		return true
	}
	for _, app := range p.Apps {
		if app.RefKind != "commit" {
			return true
		}
	}
	return false
}
