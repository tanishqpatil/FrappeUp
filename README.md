# Frappe 1-Tap Install

A local, Docker-based CLI for creating reproducible Frappe environments. Users need no server, dashboard, Go, Python, Node, Bench, or Frappe installation before using a released binary.

## Current foundation

The CLI can create separate development and production profile files, list supported official Frappe product apps, produce a dependency-aware plan, lock every source commit, and materialize a deterministic Docker build workspace. Running Frappe containers and site creation are the next implementation stage.

After the first release, macOS and Linux users will run the shell launcher:

```sh
curl -fsSL https://raw.githubusercontent.com/SwayAlgo/Frappe1TapInstall/main/install.sh | sh
frappe1tap init --profile development --env-file development.env
frappe1tap plan --env-file development.env
```

The launcher downloads a checksum-verified native binary. Passing command arguments to `install.sh`, `install.ps1`, or `install.bat` installs the binary and then runs that command. A source checkout uses Go to build locally because release artifacts are not stored in Git.

## Profiles and apps

Start from [development.env.example](profiles/development.env.example) or [production.env.example](profiles/production.env.example). Set `INSTALL_APPS` to official catalog IDs. Dependency apps are resolved automatically and appear before apps that require them.

For a third-party app, set `CUSTOM_APPS_FILE` and use [custom-apps.json.example](profiles/custom-apps.json.example). The custom definition supplies its Git URL, tag/branch/commit, Frappe app name, and any known dependencies.

Production plans identify moving refs and will require a commit lock before installation. See [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Locked workspace

Create a lock, then materialize it. The workspace contains the locked Frappe Docker runtime context, Frappe and app sources, a generated custom Containerfile, and private generated administrator credentials. It does not start any Docker containers.

```sh
frappe1tap lock --env-file production.env --force
frappe1tap workspace --env-file production.env
```

`workspace` refuses a stale lock and refuses to replace an existing workspace unless `--force` is supplied. It uses `FRAPPE_DOCKER_REPOSITORY` and `FRAPPE_DOCKER_REF` from the profile, defaulting to the official `frappe/frappe_docker` repository and `main`.

## Logs

Each profile writes append-only JSON logs to `.frappe1tap/logs/cli.jsonl` beside its `.env` file. Logs record command events and errors without writing profile values; embedded Git URL credentials and common token query parameters are redacted before errors are written.

```sh
frappe1tap logs --env-file production.env
frappe1tap logs --env-file production.env --follow
```

## Docker readiness

Run this before creating an environment. It checks the Docker CLI, Docker Compose, Buildx, and Docker daemon, then explains how to fix any failed prerequisite.

```sh
frappe1tap doctor --env-file production.env
```

## Legacy files

The original DIY Docker scripts are preserved in [legacy](legacy/README.md). They are no longer part of the active implementation.

## License

Apache License 2.0. See [LICENSE](LICENSE).
