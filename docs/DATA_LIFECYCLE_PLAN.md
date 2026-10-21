# FrappeUp data lifecycle

## Invariants

- The Compose `db-data` and `sites` volumes hold user data. Images, source snapshots, and generated Compose files are rebuildable. No routine install or app change may remove those volumes.
- A project is treated as existing when Docker reports any container or volume carrying its Compose project label, including stopped containers and orphaned volumes. A partial or unknown state is protected as existing.
- An existing project is never passed through `bench new-site` again. The current app image and database remain untouched when the user chooses **Keep**.
- A reset is a separate destructive operation. It requires a running backend, a successful `bench backup --with-files`, verified copies of the backup archives and `site_config.json` outside Docker volumes, and a typed project-name confirmation before `compose down --volumes`.
- If any prerequisite or verification fails, stop before altering the deployment. Non-interactive runs keep data unless the caller explicitly requests another supported action.

## This phase

1. Rename the public-facing CLI to **FrappeUp** (`frappeup`) while preserving the legacy project and workspace identity for existing profiles.
2. Inspect Docker by project label before any build or site creation. If resources exist, show the evidence and ask whether to keep data or reset. `keep` exits without changing containers or volumes. A changed lock or app set is not applied until a dedicated migration flow exists.
3. For an explicitly chosen reset, make and export a complete site backup, verify it, require typed confirmation, then remove only that Compose project's volumes. The next install creates a fresh site.
4. Keep `plan`, `lock`, and `workspace` available without touching a live site. Do not overwrite an active workspace; future versioned workspaces will enable side-by-side builds.

## Later phases

- App changes: build a new immutable image, verify app compatibility, back up the site, run `install-app` or `migrate` against the preserved volumes, and verify health before accepting the deployment. These operations need their own rollback plan.
- Production: TLS, external backups and restore drills, monitoring, resource limits, and a deployment topology that can actually support low-downtime updates. A single Compose backend cannot guarantee zero downtime during schema migration.

## Verification

- Existing running and stopped projects are detected before `new-site` or build. Keep leaves volumes and containers unchanged.
- Reset cannot proceed without an exported backup and exact typed confirmation.
- A fresh project still installs Frappe and ERPNext, and the legacy profile still finds its existing site.
