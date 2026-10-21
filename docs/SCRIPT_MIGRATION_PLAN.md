# Script-only CLI migration

This records the earlier migration plan. Current behavior and limits are in [Architecture](ARCHITECTURE.md) and [Data lifecycle](DATA_LIFECYCLE_PLAN.md).

## Objective

Run the same Frappe installation lifecycle without requiring a Go, Python, Node, or Bench installation on the host. Docker supplies the application runtime; Git supplies source snapshots. macOS and Linux use POSIX `sh`; Windows uses PowerShell, with Batch launchers.

## Architecture

1. A small launcher installs a versioned bundle of scripts and the official app catalog. Local source checkouts run directly. Release archives contain the same scripts, with a SHA-256 sidecar checked by the launcher.
2. Each `.env` profile names its Compose project, site, Frappe sources and refs, and app IDs. The official catalog declares app Git URLs, default refs, compatibility, and dependencies. An optional custom catalog adds third-party apps without CLI edits.
3. `plan` validates identifiers and resolves dependency order. `lock` resolves every ref to a commit and records a checksum of the plan. `workspace` checks that checksum, checks out those commits, and prepares a pinned Frappe Docker build context and private runtime credentials.
4. For a new project, `install` validates the workspace, builds the pinned image, starts an isolated Compose project, creates the site, and installs apps in dependency order. `status` and `logs --docker` inspect that project. A repeated install detects project containers or volumes and defaults to keeping them unchanged.
5. Production installation remains unavailable until TLS and production operational controls exist. The production profile can be planned and locked now.

## Implementation sequence

1. Finish and harden the POSIX shell CLI and app catalog; keep profile and custom app syntax consistent.
2. Implement equivalent PowerShell commands and Batch entry points, sharing the catalog data and profile fields.
3. Replace Go release packaging and bootstrap with script archives and checksum verification.
4. Remove the approved Go implementation and stale Go instructions; retain the legacy Docker scripts as historical reference.
5. Validate shell syntax and command behavior; verify Frappe and ERPNext in Docker on this Mac. Check Windows script syntax and behavior where a PowerShell runtime is available; record any platform that cannot be run locally.

## Acceptance

`frappeup init`, `plan`, `lock`, `workspace`, and `install` work without host Go. `status` shows running containers, `bench --site site.localhost list-apps` shows `frappe` and `erpnext`, and the HTTP ping returns `pong`.
