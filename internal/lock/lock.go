package lock

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/SwayAlgo/Frappe1TapInstall/internal/plan"
)

type Source struct {
	Repository string `json:"repository"`
	Ref        string `json:"ref"`
	Commit     string `json:"commit"`
}

type App struct {
	ID      string `json:"id"`
	AppName string `json:"app_name"`
	Source  Source `json:"source"`
}

type File struct {
	SchemaVersion int       `json:"schema_version"`
	CreatedAt     time.Time `json:"created_at"`
	PlanSHA256    string    `json:"plan_sha256"`
	ProjectName   string    `json:"project_name"`
	SiteName      string    `json:"site_name"`
	Frappe        Source    `json:"frappe"`
	FrappeDocker  Source    `json:"frappe_docker"`
	Apps          []App     `json:"apps"`
}

type Resolver interface {
	Resolve(ctx context.Context, repository, ref, refKind string) (string, error)
}

type GitResolver struct{}

func (GitResolver) Resolve(ctx context.Context, repository, ref, refKind string) (string, error) {
	if refKind == "commit" {
		return ref, nil
	}
	if _, err := exec.LookPath("git"); err != nil {
		return "", fmt.Errorf("Git is required to lock refs: %w", err)
	}
	refs := []string{ref}
	switch refKind {
	case "branch":
		refs = append(refs, "refs/heads/"+ref)
	case "tag":
		refs = append(refs, "refs/tags/"+ref, "refs/tags/"+ref+"^{}")
	}
	command := exec.CommandContext(ctx, "git", append([]string{"ls-remote", repository}, refs...)...)
	output, err := command.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("resolve %s @ %s: %w: %s", repository, ref, err, strings.TrimSpace(string(output)))
	}
	commit := pickCommit(string(output), ref, refKind)
	if commit == "" {
		return "", fmt.Errorf("ref %q was not found in %s", ref, repository)
	}
	return commit, nil
}

func Create(ctx context.Context, p plan.Plan, resolver Resolver, now time.Time) (File, error) {
	planSHA, err := Checksum(p)
	if err != nil {
		return File{}, err
	}
	frappeCommit, err := resolver.Resolve(ctx, p.Frappe.Repository, p.Frappe.Ref, p.Frappe.RefKind)
	if err != nil {
		return File{}, err
	}
	frappeDockerCommit, err := resolver.Resolve(ctx, p.FrappeDocker.Repository, p.FrappeDocker.Ref, p.FrappeDocker.RefKind)
	if err != nil {
		return File{}, err
	}
	result := File{
		SchemaVersion: 2, CreatedAt: now.UTC(), PlanSHA256: planSHA, ProjectName: p.ProjectName, SiteName: p.SiteName,
		Frappe:       Source{Repository: p.Frappe.Repository, Ref: p.Frappe.Ref, Commit: frappeCommit},
		FrappeDocker: Source{Repository: p.FrappeDocker.Repository, Ref: p.FrappeDocker.Ref, Commit: frappeDockerCommit},
	}
	for _, app := range p.Apps {
		commit, err := resolver.Resolve(ctx, app.Repository, app.Ref, app.RefKind)
		if err != nil {
			return File{}, err
		}
		result.Apps = append(result.Apps, App{
			ID: app.ID, AppName: app.AppName,
			Source: Source{Repository: app.Repository, Ref: app.Ref, Commit: commit},
		})
	}
	return result, nil
}

func Write(path string, file File) error {
	data, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return fmt.Errorf("encode lock file: %w", err)
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create lock directory: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".frappe1tap-lock-*")
	if err != nil {
		return fmt.Errorf("create lock file: %w", err)
	}
	temporaryName := temporary.Name()
	defer os.Remove(temporaryName)
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return fmt.Errorf("write lock file: %w", err)
	}
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("set lock permissions: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close lock file: %w", err)
	}
	if err := os.Rename(temporaryName, path); err != nil {
		return fmt.Errorf("save lock file: %w", err)
	}
	return nil
}

func Read(path string) (File, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return File{}, fmt.Errorf("read lock file: %w", err)
	}
	var file File
	if err := json.Unmarshal(data, &file); err != nil {
		return File{}, fmt.Errorf("parse lock file: %w", err)
	}
	if err := file.Validate(); err != nil {
		return File{}, err
	}
	return file, nil
}

func (f File) Validate() error {
	if f.SchemaVersion != 2 {
		return fmt.Errorf("lock schema %d is unsupported; recreate the lock file with this version of frappe1tap", f.SchemaVersion)
	}
	if f.ProjectName == "" || f.SiteName == "" || f.PlanSHA256 == "" {
		return fmt.Errorf("lock file is missing project_name, site_name, or plan_sha256")
	}
	if err := validateSource("frappe", f.Frappe); err != nil {
		return err
	}
	if err := validateSource("frappe_docker", f.FrappeDocker); err != nil {
		return err
	}
	for _, app := range f.Apps {
		if app.ID == "" || app.AppName == "" {
			return fmt.Errorf("lock file contains an app without id or app_name")
		}
		if err := validateSource("app "+app.ID, app.Source); err != nil {
			return err
		}
	}
	return nil
}

func validateSource(name string, source Source) error {
	if source.Repository == "" || source.Ref == "" || !isCommit(source.Commit) {
		return fmt.Errorf("lock file contains an invalid %s source", name)
	}
	return nil
}

func isCommit(value string) bool {
	if len(value) < 7 || len(value) > 64 {
		return false
	}
	for _, char := range value {
		if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f') || (char >= 'A' && char <= 'F')) {
			return false
		}
	}
	return true
}

func Checksum(p plan.Plan) (string, error) {
	data, err := json.Marshal(p)
	if err != nil {
		return "", fmt.Errorf("encode plan for checksum: %w", err)
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}

func pickCommit(output, ref, refKind string) string {
	var exact, dereferenced string
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		parts := strings.Fields(line)
		if len(parts) != 2 {
			continue
		}
		commit, remoteRef := parts[0], parts[1]
		if remoteRef == "refs/tags/"+ref+"^{}" {
			dereferenced = commit
		}
		if remoteRef == ref || remoteRef == "refs/heads/"+ref || remoteRef == "refs/tags/"+ref {
			exact = commit
		}
	}
	if refKind == "tag" && dereferenced != "" {
		return dereferenced
	}
	return exact
}
