package doctor

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type Check struct {
	Name     string `json:"name"`
	Required bool   `json:"required"`
	Passed   bool   `json:"passed"`
	Detail   string `json:"detail"`
	Fix      string `json:"fix,omitempty"`
}

type Report struct {
	Ready  bool    `json:"ready"`
	Checks []Check `json:"checks"`
}

type Runner interface {
	Run(context.Context, string, ...string) (string, error)
}

type CommandRunner struct{}

func (CommandRunner) Run(ctx context.Context, name string, args ...string) (string, error) {
	output, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	return strings.TrimSpace(string(output)), err
}

func Run(ctx context.Context, runner Runner) Report {
	checks := []Check{
		check(ctx, runner, "Docker CLI", "docker", []string{"--version"}, "Install Docker Desktop or Docker Engine."),
		check(ctx, runner, "Docker Compose", "docker", []string{"compose", "version"}, "Install Docker Compose v2."),
		check(ctx, runner, "Docker Buildx", "docker", []string{"buildx", "version"}, "Install a Docker Buildx plugin."),
		check(ctx, runner, "Docker daemon", "docker", []string{"info", "--format", "{{.ServerVersion}}"}, "Start Docker Desktop or the Docker daemon."),
	}
	report := Report{Ready: true, Checks: checks}
	for _, check := range checks {
		if check.Required && !check.Passed {
			report.Ready = false
		}
	}
	return report
}

func check(parent context.Context, runner Runner, label, command string, args []string, fix string) Check {
	ctx, cancel := context.WithTimeout(parent, 10*time.Second)
	defer cancel()
	output, err := runner.Run(ctx, command, args...)
	if err != nil {
		detail := strings.TrimSpace(output)
		if detail == "" {
			detail = err.Error()
		}
		return Check{Name: label, Required: true, Passed: false, Detail: detail, Fix: fix}
	}
	if output == "" {
		output = "available"
	}
	return Check{Name: label, Required: true, Passed: true, Detail: output}
}

func (r Report) Error() error {
	if r.Ready {
		return nil
	}
	var failed []string
	for _, check := range r.Checks {
		if check.Required && !check.Passed {
			failed = append(failed, check.Name)
		}
	}
	return fmt.Errorf("installation prerequisites are not ready: %s", strings.Join(failed, ", "))
}
