# Architecture

Frappe 1-Tap is a local CLI. It does not require a service or dashboard.

The project is licensed under Apache-2.0. This license applies to Frappe 1-Tap itself; each app selected by a user retains its own license.

## Entry points

- `install.sh` installs a released binary on macOS and Linux, then runs any supplied CLI command.
- `install.ps1` does the same on Windows.
- `install.bat` forwards to PowerShell for users who start from Batch.
- `frappe1tap` owns all behaviour after bootstrap.

The released executable contains its official-app catalog. No Go, Python, Node, Bench, or Frappe installation is required before running it. Docker remains an external system requirement because its installation can require administrator approval, virtualization setup, or a reboot.

Tags beginning with `v` build checksum-verified macOS, Linux, and Windows archives through GitHub Actions. The bootstrap scripts download only these archives and verify their SHA-256 file before installation.

## Configuration model

One `.env` file describes one target. Multiple files create separate environments, for example `development.env` and `production.env`. The file contains Frappe, Frappe Docker template, version selection, and selected app IDs. `CUSTOM_APPS_FILE` points to a JSON file for repositories outside the official catalog.

The official catalog owns repository URLs, known compatible references, app names, and declared dependencies. A profile does not duplicate these values.

Each profile has an append-only JSON log at `.frappe1tap/logs/cli.jsonl`. The `logs` command reads it and can follow new records. Log events exclude raw environment values; embedded Git URL credentials and common token query parameters are redacted before error records are written.

## Lifecycle

1. `init` creates a profile file.
2. `plan` resolves official and custom apps, validates the Frappe major version, and orders dependencies before dependent apps.
3. `lock` resolves Frappe, Frappe Docker, and every app ref to a Git commit and creates an immutable production lock file.
4. `workspace` checks the lock against the current profile, snapshots those commits locally, and generates a custom Frappe Docker build context. Bench receives local Git repositories through a fixed `frappe1tap-lock` branch, so it checks out the exact locked commits rather than a moving remote branch.
5. `install` will generate an isolated Docker Compose project, create the site, fetch apps, install them, and record outcomes.
6. `status`, `backup`, `restore`, `update`, and `destroy` will operate only on that project.

The first four stages are implemented. Installation commands will not be added until Compose generation has deterministic tests.

## Production rule

Branches such as `version-16` are moving references. Development may use them. Production requires a lock that records the resolved commit for Frappe, Frappe Docker, and every app before anything is installed.
