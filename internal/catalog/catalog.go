package catalog

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
)

//go:embed official-apps.json
var builtinCatalog []byte

// Catalog is the maintained inventory of supported first-party Frappe apps.
// It intentionally lists product apps, not every repository in the frappe org.
type Catalog struct {
	SchemaVersion int    `json:"schema_version"`
	GeneratedAt   string `json:"generated_at"`
	Apps          []App  `json:"apps"`
}

type App struct {
	ID                    string   `json:"id"`
	DisplayName           string   `json:"display_name"`
	Publisher             string   `json:"publisher"`
	Repository            string   `json:"repository"`
	Ref                   string   `json:"ref"`
	RefKind               string   `json:"ref_kind"`
	AppName               string   `json:"app_name"`
	SupportedFrappeMajors []int    `json:"supported_frappe_majors"`
	Requires              []string `json:"requires"`
	Notes                 string   `json:"notes,omitempty"`
}

func Load(path string) (Catalog, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Catalog{}, fmt.Errorf("read catalog: %w", err)
	}
	return parse(data)
}

func LoadBuiltin() (Catalog, error) {
	return parse(builtinCatalog)
}

func parse(data []byte) (Catalog, error) {
	var c Catalog
	if err := json.Unmarshal(data, &c); err != nil {
		return Catalog{}, fmt.Errorf("parse catalog: %w", err)
	}
	if c.SchemaVersion != 1 {
		return Catalog{}, fmt.Errorf("unsupported catalog schema version %d", c.SchemaVersion)
	}
	seen := make(map[string]bool, len(c.Apps))
	for _, app := range c.Apps {
		if app.ID == "" || app.Repository == "" || app.Ref == "" || app.AppName == "" {
			return Catalog{}, fmt.Errorf("catalog app has missing required fields: %q", app.ID)
		}
		if seen[app.ID] {
			return Catalog{}, fmt.Errorf("catalog contains duplicate app id %q", app.ID)
		}
		seen[app.ID] = true
	}
	return c, nil
}

func (c Catalog) ByID() map[string]App {
	result := make(map[string]App, len(c.Apps))
	for _, app := range c.Apps {
		result[app.ID] = app
	}
	return result
}
