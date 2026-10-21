# Phase 2: Runtime installation plan

This records the initial installation phase. For current existing-site behavior, see [Data lifecycle](DATA_LIFECYCLE_PLAN.md).

## Goal

Turn an existing commit-locked workspace into one running, isolated Frappe environment. The first acceptance case is `site.localhost` with Frappe and ERPNext on a development profile.

## Scope

1. Generate a Compose project from the pinned `frappe_docker` source using its base Compose file, MariaDB, Redis, and no-proxy overrides.
2. Generate a one-shot `create-site` service that waits for configuration, creates the requested site, and installs every resolved app in lock order.
3. Generate private runtime secrets once per workspace. They are not profile settings and are never printed or written to CLI logs.
4. Add `install`, `status`, and Docker-log support to the CLI.
5. Build the exact workspace image with BuildKit's `apps.json` secret, start the project, wait for successful site creation, and report the local URL.
6. Validate generated Compose configuration, command behavior with unit tests, and the Frappe/ERPNext development path against Docker when upstream image downloads permit it.

## Constraints

- Installation only accepts a current lock file and workspace metadata that match the profile plan.
- Each project uses its `PROJECT_NAME` as the Compose project name and has isolated containers, networks, and volumes.
- The initial runtime target is a local development environment on its default local HTTP port. Production TLS, custom port selection, backups, restore, update, and destroy remain later phases.
- Existing workspaces and sites are never replaced implicitly. Interactive reset now requires an exported backup and typed confirmation; app migration remains a future command.

## Completion criteria

`frappeup install --env-file erpnext.env` creates the locked image, starts the Frappe services, creates `site.localhost`, installs ERPNext, and makes its container logs available through `frappeup logs --docker`.
