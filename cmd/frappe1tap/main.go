package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/SwayAlgo/Frappe1TapInstall/internal/catalog"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/config"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/doctor"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/lock"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/logging"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/plan"
	"github.com/SwayAlgo/Frappe1TapInstall/internal/workspace"
)

const version = "0.1.0-dev"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		printUsage()
		return nil
	}
	switch args[0] {
	case "help", "--help", "-h":
		printUsage()
		return nil
	case "version", "--version":
		fmt.Println(version)
		return nil
	case "init":
		return initCommand(args[1:])
	case "plan":
		return planCommand(args[1:])
	case "lock":
		return lockCommand(args[1:])
	case "workspace":
		return workspaceCommand(args[1:])
	case "logs":
		return logsCommand(args[1:])
	case "doctor":
		return doctorCommand(args[1:])
	case "catalog":
		return catalogCommand(args[1:])
	default:
		return fmt.Errorf("unknown command %q; run frappe1tap help", args[0])
	}
}

func initCommand(args []string) error {
	fs := flag.NewFlagSet("init", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	profile := fs.String("profile", "development", "development or production")
	path := fs.String("env-file", "", "destination environment file")
	force := fs.Bool("force", false, "replace an existing file")
	logFile := fs.String("log-file", "", "optional log file path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	selectedProfile := config.Profile(*profile)
	contents, err := config.Template(selectedProfile)
	if err != nil {
		return err
	}
	if *path == "" {
		*path = fmt.Sprintf("frappe1tap.%s.env", selectedProfile)
	}
	logger, err := openLogger(*path, *logFile)
	if err != nil {
		return err
	}
	defer logger.Close()
	_ = logger.Info("init.started", "creating profile", map[string]any{"profile": selectedProfile})
	if _, err := os.Stat(*path); err == nil && !*force {
		return loggedError(logger, "init.failed", fmt.Errorf("%s already exists; use --force to replace it", *path))
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return loggedError(logger, "init.failed", fmt.Errorf("inspect %s: %w", *path, err))
	}
	if err := os.MkdirAll(filepath.Dir(*path), 0o755); err != nil {
		return loggedError(logger, "init.failed", fmt.Errorf("create environment directory: %w", err))
	}
	if err := os.WriteFile(*path, []byte(contents), 0o600); err != nil {
		return loggedError(logger, "init.failed", fmt.Errorf("write environment file: %w", err))
	}
	_ = logger.Info("init.completed", "profile created", nil)
	fmt.Printf("Created %s\n", *path)
	return nil
}

func planCommand(args []string) error {
	fs := flag.NewFlagSet("plan", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	envFile := fs.String("env-file", "", "profile environment file")
	catalogPath := fs.String("catalog", "", "optional replacement catalog JSON file")
	jsonOutput := fs.Bool("json", false, "write JSON")
	logFile := fs.String("log-file", "", "optional log file path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *envFile == "" {
		return fmt.Errorf("--env-file is required")
	}
	logger, err := openLogger(*envFile, *logFile)
	if err != nil {
		return err
	}
	defer logger.Close()
	_ = logger.Info("plan.started", "resolving installation plan", nil)
	p, err := buildPlan(*envFile, *catalogPath)
	if err != nil {
		return loggedError(logger, "plan.failed", err)
	}
	if *jsonOutput {
		data, err := json.MarshalIndent(p, "", "  ")
		if err != nil {
			return loggedError(logger, "plan.failed", fmt.Errorf("encode plan: %w", err))
		}
		_ = logger.Info("plan.completed", "installation plan resolved", map[string]any{"app_count": len(p.Apps)})
		fmt.Println(string(data))
		return nil
	}
	_ = logger.Info("plan.completed", "installation plan resolved", map[string]any{"app_count": len(p.Apps)})
	fmt.Print(plan.RenderText(p))
	return nil
}

func lockCommand(args []string) error {
	fs := flag.NewFlagSet("lock", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	envFile := fs.String("env-file", "", "profile environment file")
	catalogPath := fs.String("catalog", "", "optional replacement catalog JSON file")
	output := fs.String("output", "", "destination lock file")
	force := fs.Bool("force", false, "replace an existing lock file")
	logFile := fs.String("log-file", "", "optional log file path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *envFile == "" {
		return fmt.Errorf("--env-file is required")
	}
	logger, err := openLogger(*envFile, *logFile)
	if err != nil {
		return err
	}
	defer logger.Close()
	_ = logger.Info("lock.started", "resolving Git refs", nil)
	p, err := buildPlan(*envFile, *catalogPath)
	if err != nil {
		return loggedError(logger, "lock.failed", err)
	}
	if *output == "" {
		*output = *envFile + ".lock.json"
	}
	if _, err := os.Stat(*output); err == nil && !*force {
		return loggedError(logger, "lock.failed", fmt.Errorf("%s already exists; use --force to replace it", *output))
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return loggedError(logger, "lock.failed", fmt.Errorf("inspect %s: %w", *output, err))
	}
	file, err := lock.Create(context.Background(), p, lock.GitResolver{}, time.Now())
	if err != nil {
		return loggedError(logger, "lock.failed", err)
	}
	if err := lock.Write(*output, file); err != nil {
		return loggedError(logger, "lock.failed", err)
	}
	_ = logger.Info("lock.completed", "lock file created", map[string]any{"app_count": len(file.Apps)})
	fmt.Printf("Created %s\n", *output)
	return nil
}

func workspaceCommand(args []string) error {
	fs := flag.NewFlagSet("workspace", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	envFile := fs.String("env-file", "", "profile environment file")
	lockFile := fs.String("lock-file", "", "commit lock file")
	path := fs.String("path", "", "workspace destination")
	catalogPath := fs.String("catalog", "", "optional replacement catalog JSON file")
	force := fs.Bool("force", false, "replace an existing workspace")
	logFile := fs.String("log-file", "", "optional log file path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *envFile == "" {
		return fmt.Errorf("--env-file is required")
	}
	logger, err := openLogger(*envFile, *logFile)
	if err != nil {
		return err
	}
	defer logger.Close()
	_ = logger.Info("workspace.started", "materializing locked Docker build context", nil)
	p, err := buildPlan(*envFile, *catalogPath)
	if err != nil {
		return loggedError(logger, "workspace.failed", err)
	}
	if *lockFile == "" {
		*lockFile = *envFile + ".lock.json"
	}
	file, err := lock.Read(*lockFile)
	if err != nil {
		return loggedError(logger, "workspace.failed", err)
	}
	if *path == "" {
		cfg, err := config.Load(*envFile)
		if err != nil {
			return loggedError(logger, "workspace.failed", err)
		}
		*path = cfg.WorkspaceDir
	}
	result, err := workspace.Prepare(context.Background(), *path, p, file, *force)
	if err != nil {
		return loggedError(logger, "workspace.failed", err)
	}
	_ = logger.Info("workspace.completed", "locked Docker build context created", map[string]any{"path": result.Path, "app_count": len(file.Apps)})
	fmt.Printf("Created workspace %s\nBuild context: %s\nBuild file: %s\nApps file: %s\nCredentials: %s\nImage: %s:%s\n", result.Path, result.BuildContext, result.BuildFile, result.AppsFile, result.CredentialsFile, result.Image, result.Tag)
	return nil
}

func logsCommand(args []string) error {
	fs := flag.NewFlagSet("logs", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	envFile := fs.String("env-file", "", "profile environment file")
	logFile := fs.String("log-file", "", "optional log file path")
	lines := fs.Int("lines", 100, "number of records to show")
	follow := fs.Bool("follow", false, "watch new records until interrupted")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *envFile == "" && *logFile == "" {
		return fmt.Errorf("--env-file or --log-file is required")
	}
	path := *logFile
	if path == "" {
		path = logging.DefaultPath(*envFile)
	}
	output, err := logging.Tail(path, *lines)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read logs: %w", err)
	}
	if output != "" {
		fmt.Print(output)
	}
	if !*follow {
		return nil
	}
	fmt.Printf("Watching %s; press Ctrl+C to stop.\n", path)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	return logging.Follow(ctx, path, os.Stdout)
}

func doctorCommand(args []string) error {
	fs := flag.NewFlagSet("doctor", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	envFile := fs.String("env-file", "", "optional profile environment file for project logs")
	logFile := fs.String("log-file", "", "optional log file path")
	jsonOutput := fs.Bool("json", false, "write JSON")
	if err := fs.Parse(args); err != nil {
		return err
	}
	path, err := doctorLogPath(*envFile, *logFile)
	if err != nil {
		return err
	}
	logger, err := logging.Open(path)
	if err != nil {
		return err
	}
	defer logger.Close()
	_ = logger.Info("doctor.started", "checking installation prerequisites", nil)
	report := doctor.Run(context.Background(), doctor.CommandRunner{})
	if *jsonOutput {
		data, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			return loggedError(logger, "doctor.failed", fmt.Errorf("encode doctor report: %w", err))
		}
		fmt.Println(string(data))
	} else {
		for _, check := range report.Checks {
			state := "PASS"
			if !check.Passed {
				state = "FAIL"
			}
			fmt.Printf("%s  %s: %s\n", state, check.Name, check.Detail)
			if check.Fix != "" {
				fmt.Printf("      Fix: %s\n", check.Fix)
			}
		}
	}
	if err := report.Error(); err != nil {
		return loggedError(logger, "doctor.failed", err)
	}
	_ = logger.Info("doctor.completed", "installation prerequisites are ready", nil)
	return nil
}

func doctorLogPath(envFile, configuredPath string) (string, error) {
	if configuredPath != "" {
		return configuredPath, nil
	}
	if envFile != "" {
		return logging.DefaultPath(envFile), nil
	}
	return logging.GlobalPath()
}

func openLogger(envFile, configuredPath string) (*logging.Logger, error) {
	if configuredPath == "" {
		configuredPath = logging.DefaultPath(envFile)
	}
	return logging.Open(configuredPath)
}

func loggedError(logger *logging.Logger, event string, err error) error {
	_ = logger.Error(event, err)
	return err
}

func buildPlan(envFile, catalogPath string) (plan.Plan, error) {
	cfg, err := config.Load(envFile)
	if err != nil {
		return plan.Plan{}, err
	}
	c, err := loadCatalog(catalogPath)
	if err != nil {
		return plan.Plan{}, err
	}
	custom, err := plan.LoadCustomApps(cfg.CustomAppsFile)
	if err != nil {
		return plan.Plan{}, err
	}
	return plan.Build(c, cfg, custom)
}

func catalogCommand(args []string) error {
	if len(args) != 1 || args[0] != "list" {
		return fmt.Errorf("usage: frappe1tap catalog list")
	}
	c, err := catalog.LoadBuiltin()
	if err != nil {
		return err
	}
	for _, app := range c.Apps {
		fmt.Printf("%-24s %-28s %s @ %s\n", app.ID, app.DisplayName, app.RefKind, app.Ref)
	}
	return nil
}

func loadCatalog(path string) (catalog.Catalog, error) {
	if path == "" {
		return catalog.LoadBuiltin()
	}
	return catalog.Load(path)
}

func printUsage() {
	fmt.Print(`Frappe 1-Tap CLI

Usage:
  frappe1tap init --profile development|production [--env-file PATH]
  frappe1tap plan --env-file PATH [--catalog PATH] [--json]
  frappe1tap lock --env-file PATH [--catalog PATH] [--output PATH]
  frappe1tap workspace --env-file PATH [--lock-file PATH] [--path PATH] [--force]
  frappe1tap logs --env-file PATH [--lines N] [--follow]
  frappe1tap doctor [--env-file PATH] [--json]
  frappe1tap catalog list
  frappe1tap version

The CLI plans an installation before it changes Docker or a Frappe site.
`)
}
