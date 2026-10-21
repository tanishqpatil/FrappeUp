package plan_test

import (
	"testing"

	"github.com/SwayAlgo/Frappe1TapInstall/internal/catalog"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/config"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/plan"
)

func TestBuildIncludesDependenciesInOrder(t *testing.T) {
	c := catalog.Catalog{SchemaVersion: 1, Apps: []catalog.App{
		{ID: "erpnext", DisplayName: "ERPNext", Repository: "repo/erpnext", Ref: "version-16", RefKind: "branch", AppName: "erpnext", SupportedFrappeMajors: []int{16}},
		{ID: "payments", DisplayName: "Payments", Repository: "repo/payments", Ref: "version-16", RefKind: "branch", AppName: "payments", SupportedFrappeMajors: []int{16}},
		{ID: "webshop", DisplayName: "Webshop", Repository: "repo/webshop", Ref: "v1", RefKind: "tag", AppName: "webshop", SupportedFrappeMajors: []int{16}, Requires: []string{"payments", "erpnext"}},
	}}
	p, err := plan.Build(c, config.Config{Profile: config.Development, ProjectName: "test", SiteName: "site.localhost", FrappeRepository: "repo/frappe", FrappeRef: "version-16", FrappeMajor: 16, InstallApps: []string{"webshop"}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(p.Apps), 3; got != want {
		t.Fatalf("app count = %d, want %d", got, want)
	}
	if got, want := p.Apps[0].ID+","+p.Apps[1].ID+","+p.Apps[2].ID, "erpnext,payments,webshop"; got != want {
		t.Fatalf("order = %s, want %s", got, want)
	}
}

func TestBuildRejectsUnsupportedFrappeVersion(t *testing.T) {
	c := catalog.Catalog{SchemaVersion: 1, Apps: []catalog.App{{ID: "v16", DisplayName: "v16", Repository: "repo", Ref: "v16", RefKind: "tag", AppName: "v16", SupportedFrappeMajors: []int{16}}}}
	_, err := plan.Build(c, config.Config{Profile: config.Development, ProjectName: "test", SiteName: "site", FrappeRepository: "repo", FrappeRef: "version-15", FrappeMajor: 15, InstallApps: []string{"v16"}}, nil)
	if err == nil {
		t.Fatal("expected compatibility error")
	}
}

func TestProductionPlanRequiresLockForBranch(t *testing.T) {
	c := catalog.Catalog{SchemaVersion: 1}
	p, err := plan.Build(c, config.Config{Profile: config.Production, ProjectName: "test", SiteName: "site", FrappeRepository: "repo", FrappeRef: "version-16", FrappeMajor: 16}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !p.LockRequired {
		t.Fatal("expected production branch to require a lock")
	}
}

func TestBuildIncludesCustomAppDependency(t *testing.T) {
	c := catalog.Catalog{SchemaVersion: 1, Apps: []catalog.App{
		{ID: "erpnext", DisplayName: "ERPNext", Repository: "repo/erpnext", Ref: "version-16", RefKind: "branch", AppName: "erpnext", SupportedFrappeMajors: []int{16}},
	}}
	p, err := plan.Build(c, config.Config{Profile: config.Development, ProjectName: "test", SiteName: "site", FrappeRepository: "repo/frappe", FrappeRef: "version-16", FrappeMajor: 16, InstallApps: []string{"custom_app"}}, []plan.CustomApp{{
		ID: "custom_app", Repository: "https://example.invalid/custom-app", Ref: "main", AppName: "custom_app", Requires: []string{"erpnext"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := p.Apps[0].ID+","+p.Apps[1].ID, "erpnext,custom_app"; got != want {
		t.Fatalf("order = %s, want %s", got, want)
	}
}
