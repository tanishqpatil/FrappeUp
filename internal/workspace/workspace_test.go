package workspace

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/SwayAlgo/Frappe1TapInstall/internal/catalog"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/config"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/lock"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/plan"
)

func TestPrepareCreatesCommitLockedBuildContext(t *testing.T) {
	root := t.TempDir()
	runtimeRepo, runtimeCommit := repository(t, root, "runtime", map[string]string{
		"images/custom/Containerfile": "FROM base AS builder\n\nRUN setup\n\nUSER frappe\n\nARG FRAPPE_BRANCH=version-16\nARG FRAPPE_PATH=https://github.com/frappe/frappe\nRUN bench init\n",
	})
	frappeRepo, frappeCommit := repository(t, root, "frappe", map[string]string{"frappe.txt": "frappe"})
	appRepo, appCommit := repository(t, root, "erpnext", map[string]string{"app.txt": "erpnext"})

	p, err := plan.Build(catalog.Catalog{SchemaVersion: 1, Apps: []catalog.App{{
		ID: "erpnext", DisplayName: "ERPNext", Repository: appRepo, Ref: appCommit, RefKind: "commit", AppName: "erpnext", SupportedFrappeMajors: []int{16},
	}}}, config.Config{
		Profile: config.Production, ProjectName: "test-project", SiteName: "site.localhost", FrappeRepository: frappeRepo, FrappeRef: frappeCommit,
		FrappeDockerRepository: runtimeRepo, FrappeDockerRef: runtimeCommit, FrappeMajor: 16, InstallApps: []string{"erpnext"},
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	checksum, err := lock.Checksum(p)
	if err != nil {
		t.Fatal(err)
	}
	file := lock.File{
		SchemaVersion: 2, CreatedAt: time.Now(), PlanSHA256: checksum, ProjectName: p.ProjectName, SiteName: p.SiteName,
		Frappe:       lock.Source{Repository: frappeRepo, Ref: frappeCommit, Commit: frappeCommit},
		FrappeDocker: lock.Source{Repository: runtimeRepo, Ref: runtimeCommit, Commit: runtimeCommit},
		Apps:         []lock.App{{ID: "erpnext", AppName: "erpnext", Source: lock.Source{Repository: appRepo, Ref: appCommit, Commit: appCommit}}},
	}
	result, err := Prepare(context.Background(), filepath.Join(root, "workspace"), p, file, false)
	if err != nil {
		t.Fatal(err)
	}
	build, err := os.ReadFile(result.BuildFile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(build), "COPY --chown=frappe:0 sources /opt/frappe/sources") {
		t.Fatalf("build file does not copy locked sources:\n%s", build)
	}
	if !strings.Contains(string(build), "ARG FRAPPE_BRANCH="+lockBranch) || !strings.Contains(string(build), "ARG FRAPPE_PATH=file:///opt/frappe/sources/frappe") {
		t.Fatalf("build file does not use locked Frappe source:\n%s", build)
	}
	apps, err := os.ReadFile(result.AppsFile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(apps), "file:///opt/frappe/sources/apps/erpnext") || !strings.Contains(string(apps), lockBranch) {
		t.Fatalf("unexpected apps file: %s", apps)
	}
	branch := git(t, filepath.Join(result.BuildContext, "sources", "frappe"), "rev-parse", "refs/heads/"+lockBranch)
	if strings.TrimSpace(branch) != frappeCommit {
		t.Fatalf("workspace branch = %s, want %s", branch, frappeCommit)
	}
	info, err := os.Stat(result.CredentialsFile)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("credentials mode = %o, want 600", info.Mode().Perm())
	}
}

func TestPrepareRejectsMismatchedLock(t *testing.T) {
	p := plan.Plan{ProjectName: "test", SiteName: "site"}
	file := lock.File{SchemaVersion: 2, PlanSHA256: "different", ProjectName: "test", SiteName: "site"}
	if _, err := Prepare(context.Background(), filepath.Join(t.TempDir(), "workspace"), p, file, false); err == nil {
		t.Fatal("expected lock validation failure")
	}
}

func repository(t *testing.T, root, name string, files map[string]string) (string, string) {
	t.Helper()
	path := filepath.Join(root, name)
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
	for relative, contents := range files {
		filename := filepath.Join(path, relative)
		if err := os.MkdirAll(filepath.Dir(filename), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	git(t, path, "init")
	git(t, path, "add", ".")
	git(t, path, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "initial")
	return path, strings.TrimSpace(git(t, path, "rev-parse", "HEAD"))
}

func git(t *testing.T, directory string, args ...string) string {
	t.Helper()
	command := exec.Command("git", args...)
	command.Dir = directory
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("git %s: %v: %s", strings.Join(args, " "), err, output)
	}
	return string(output)
}
