// Package workspace materializes an immutable Docker build context from a lock file.
package workspace

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/SwayAlgo/Frappe1TapInstall/internal/lock"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/logging"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/plan"
)

const lockBranch = "frappe1tap-lock"

type Result struct {
	Path            string
	BuildContext    string
	BuildFile       string
	AppsFile        string
	CredentialsFile string
	Image           string
	Tag             string
}

type metadata struct {
	SchemaVersion int       `json:"schema_version"`
	Lock          lock.File `json:"lock"`
	Image         string    `json:"image"`
	Tag           string    `json:"tag"`
}

// Prepare checks that the current profile matches the lock, then creates a
// complete local Docker build context. Existing workspaces are preserved unless
// force is explicitly set.
func Prepare(ctx context.Context, destination string, p plan.Plan, file lock.File, force bool) (Result, error) {
	if err := verifyPlan(p, file); err != nil {
		return Result{}, err
	}
	if destination == "" {
		return Result{}, errors.New("workspace destination cannot be blank")
	}
	destination, err := filepath.Abs(destination)
	if err != nil {
		return Result{}, fmt.Errorf("resolve workspace path: %w", err)
	}
	if _, err := os.Stat(destination); err == nil {
		if !force {
			return Result{}, fmt.Errorf("workspace %s already exists; use --force to replace it", destination)
		}
		if err := os.RemoveAll(destination); err != nil {
			return Result{}, fmt.Errorf("replace workspace: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return Result{}, fmt.Errorf("inspect workspace: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return Result{}, fmt.Errorf("create workspace parent: %w", err)
	}
	temporary, err := os.MkdirTemp(filepath.Dir(destination), ".frappe1tap-workspace-*")
	if err != nil {
		return Result{}, fmt.Errorf("create workspace: %w", err)
	}
	defer os.RemoveAll(temporary)

	if err := snapshot(ctx, file.FrappeDocker, filepath.Join(temporary, "runtime")); err != nil {
		return Result{}, fmt.Errorf("snapshot Frappe Docker: %w", err)
	}
	if err := snapshot(ctx, file.Frappe, filepath.Join(temporary, "runtime", "sources", "frappe")); err != nil {
		return Result{}, fmt.Errorf("snapshot Frappe: %w", err)
	}
	for _, app := range file.Apps {
		if err := snapshot(ctx, app.Source, filepath.Join(temporary, "runtime", "sources", "apps", app.ID)); err != nil {
			return Result{}, fmt.Errorf("snapshot app %s: %w", app.ID, err)
		}
	}

	image := "frappe1tap/" + p.ProjectName
	tag := file.PlanSHA256[:12]
	buildContext := filepath.Join(temporary, "runtime")
	buildFile := filepath.Join(buildContext, "images", "custom", "Containerfile")
	if err := writeBuildFile(buildFile, buildFile); err != nil {
		return Result{}, err
	}
	appsFile := filepath.Join(buildContext, "apps.json")
	if err := writeApps(appsFile, file.Apps); err != nil {
		return Result{}, err
	}
	_, err = createCredentials(filepath.Join(temporary, "credentials.env"))
	if err != nil {
		return Result{}, err
	}
	if err := writeMetadata(filepath.Join(temporary, "workspace.json"), metadata{SchemaVersion: 1, Lock: file, Image: image, Tag: tag}); err != nil {
		return Result{}, err
	}
	if err := os.Rename(temporary, destination); err != nil {
		return Result{}, fmt.Errorf("save workspace: %w", err)
	}
	return Result{
		Path: destination, BuildContext: filepath.Join(destination, "runtime"), BuildFile: filepath.Join(destination, "runtime", "images", "custom", "Containerfile"), AppsFile: filepath.Join(destination, "runtime", "apps.json"),
		CredentialsFile: filepath.Join(destination, "credentials.env"), Image: image, Tag: tag,
	}, nil
}

func verifyPlan(p plan.Plan, file lock.File) error {
	if err := file.Validate(); err != nil {
		return err
	}
	checksum, err := lock.Checksum(p)
	if err != nil {
		return fmt.Errorf("checksum current plan: %w", err)
	}
	if file.PlanSHA256 != checksum {
		return errors.New("lock file does not match the current profile; run frappe1tap lock again")
	}
	return nil
}

func snapshot(ctx context.Context, source lock.Source, destination string) error {
	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("Git is required to create a workspace: %w", err)
	}
	if err := runGit(ctx, "clone", "--no-checkout", "--filter=blob:none", source.Repository, destination); err != nil {
		return err
	}
	if err := runGitAt(ctx, destination, "fetch", "--filter=blob:none", "origin", source.Commit); err != nil {
		return err
	}
	if err := runGitAt(ctx, destination, "checkout", "--detach", source.Commit); err != nil {
		return err
	}
	return runGitAt(ctx, destination, "branch", "-f", lockBranch, source.Commit)
}

func runGit(ctx context.Context, args ...string) error {
	return run(ctx, "git", "", args...)
}

func runGitAt(ctx context.Context, directory string, args ...string) error {
	return run(ctx, "git", directory, args...)
}

func run(ctx context.Context, command, directory string, args ...string) error {
	cmd := exec.CommandContext(ctx, command, args...)
	cmd.Dir = directory
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w: %s", command, strings.Join(args, " "), err, logging.Redact(strings.TrimSpace(string(output))))
	}
	return nil
}

func writeBuildFile(source, destination string) error {
	contents, err := os.ReadFile(source)
	if err != nil {
		return fmt.Errorf("read Frappe Docker Containerfile: %w", err)
	}
	const marker = "USER frappe\n\nARG FRAPPE_BRANCH="
	const insertion = "USER frappe\n\n# Commit-locked sources generated by frappe1tap.\nCOPY --chown=frappe:0 sources /opt/frappe/sources\n\nARG FRAPPE_BRANCH="
	count := strings.Count(string(contents), marker)
	if count != 1 {
		return fmt.Errorf("unsupported Frappe Docker Containerfile: expected one builder stage marker, found %d", count)
	}
	patched := strings.Replace(string(contents), marker, insertion, 1)
	patched, err = replaceBuildArg(patched, "FRAPPE_BRANCH", lockBranch)
	if err != nil {
		return err
	}
	patched, err = replaceBuildArg(patched, "FRAPPE_PATH", "file:///opt/frappe/sources/frappe")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return fmt.Errorf("create Docker file directory: %w", err)
	}
	if err := os.WriteFile(destination, []byte(patched), 0o644); err != nil {
		return fmt.Errorf("write Docker Containerfile: %w", err)
	}
	return nil
}

func replaceBuildArg(contents, name, value string) (string, error) {
	prefix := "ARG " + name + "="
	lines := strings.Split(contents, "\n")
	count := 0
	for index, line := range lines {
		if strings.HasPrefix(line, prefix) {
			lines[index] = prefix + value
			count++
		}
	}
	if count != 1 {
		return "", fmt.Errorf("unsupported Frappe Docker Containerfile: expected one %s declaration, found %d", name, count)
	}
	return strings.Join(lines, "\n"), nil
}

func writeApps(path string, apps []lock.App) error {
	type appSource struct {
		URL    string `json:"url"`
		Branch string `json:"branch"`
	}
	output := make([]appSource, 0, len(apps))
	for _, app := range apps {
		output = append(output, appSource{URL: "file:///opt/frappe/sources/apps/" + app.ID, Branch: lockBranch})
	}
	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return fmt.Errorf("encode apps file: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write apps file: %w", err)
	}
	return nil
}

func createCredentials(path string) (string, error) {
	password, err := randomSecret()
	if err != nil {
		return "", err
	}
	contents := "# Keep this file private. It is required by the install command.\nADMIN_PASSWORD=" + password + "\n"
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		return "", fmt.Errorf("write generated credentials: %w", err)
	}
	return password, nil
}

func randomSecret() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate credentials: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func writeMetadata(path string, value metadata) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("encode workspace metadata: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write workspace metadata: %w", err)
	}
	return nil
}
