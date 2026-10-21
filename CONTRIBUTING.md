# Contributing

FrappeUp aims to make Frappe maintenance easier without risking existing site data.

Before changing install behavior, read [the architecture](docs/ARCHITECTURE.md) and [data lifecycle](docs/DATA_LIFECYCLE_PLAN.md). Keep the macOS/Linux and Windows commands behaviorally aligned. Host CLI features must run with shell or PowerShell, Git, and Docker; do not add a host programming-language runtime requirement.

Run `sh -n frappeup install.sh lib/common.sh` and `./tests/smoke.sh` for local script changes. Windows changes also need the PowerShell smoke test in `.github/workflows/check.yml`. Exercise destructive or migration logic on a disposable Compose project; never test a reset on a user's live volumes. Document limitations and only claim Docker end-to-end validation when it has run.

Open an issue describing the problem and expected behavior, or submit a focused pull request with validation results. Do not include `.env` profiles, workspaces, backups, credentials, or site data in commits. The project is licensed under Apache-2.0; contributions are made under that license.
