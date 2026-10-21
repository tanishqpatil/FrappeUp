# FrappeUp data lifecycle

## Invariants

- The Compose `db-data` and `sites` volumes hold user data. Images, source snapshots, and generated Compose files are rebuildable. No routine install or app change may remove those volumes.
- A project is treated as existing when Docker reports any container or volume carrying its Compose project label, including stopped containers and orphaned volumes. A partial or unknown state is protected as existing.
- An existing project is never passed through `bench new-site` again. The current app image and database remain untouched when the user chooses **Keep**.
- A reset is a separate destructive operation. It requires a running backend, a successful `bench backup --with-files`, verified copies of the backup archives and `site_config.json` outside Docker volumes, and a typed project-name confirmation before `compose down --volumes`.
- If any prerequisite or verification fails, stop before altering the deployment. Non-interactive runs keep data unless the caller explicitly requests another supported action.

## Initial lifecycle phase

1. Rename the public-facing CLI to **FrappeUp** (`frappeup`) while preserving the legacy project and workspace identity for existing profiles.
2. Inspect Docker by project label before any build or site creation. If resources exist, show the evidence and ask whether to keep data or reset. `keep` exits without changing containers or volumes. A changed lock or app set is not applied until a dedicated migration flow exists.
3. For an explicitly chosen reset, make and export a complete site backup, verify it, require typed confirmation, then remove only that Compose project's volumes. The next install creates a fresh site.
4. Keep `plan`, `lock`, and `workspace` available without touching a live site. Do not overwrite an active workspace; future versioned workspaces will enable side-by-side builds.

## Current development update phase

`app prepare` creates a separate, commit-pinned target workspace. `app plan` verifies project/site identity, Frappe core and Docker commits, the running image, and the installed app set. `app apply` builds first, pauses web and workers, takes and verifies a full backup while the backend is still available, then stops the backend and migrates with the target image. It checks services, inventory, and HTTP before reporting success. `backup verify` checks exported archives and SHA-256 hashes; `restore` uses the matching old image and requires explicit confirmation. App apply and restore share a per-project lock in the CLI installation directory.

## Later phases

- App changes across Frappe core versions, production topology, and automated recovery remain future work. A failed database migration requires a deliberate restore from a matching checkpoint; switching the image alone is unsafe.
- Production: TLS, external backups and restore drills, monitoring, resource limits, and a deployment topology that can actually support low-downtime updates. A single Compose backend cannot guarantee zero downtime during schema migration.

## Verification

- Existing running and stopped projects are detected before `new-site` or build. Keep leaves volumes and containers unchanged.
- Reset cannot proceed without an exported backup and exact typed confirmation.
- A fresh project still installs Frappe and ERPNext, and the legacy profile still finds its existing site.

## Verified on an isolated project

On 2026-10-22, `frappeup-reset-test` installed Frappe 16.52.0 and ERPNext 16.51.2 on port 8081. A database ToDo and private file were added. Cancelling after backup preserved all volumes. A confirmed reset exported intact database and file archives, removed only that project's volumes, and created a fresh site without either test marker. Restoring the exported backup into that fresh site recovered both markers; Frappe and ERPNext loaded and HTTP returned 200. The pre-existing `frappe1tap-dev` site was checked separately and remained available.

The drill exposed a Frappe backup constraint: a directory inside `sites/<site>/private/backups` causes a later `bench backup` to fail. Reset backups now stage under `sites/.frappeup-backups` before export. This drill does not validate production recovery, encrypted backups, or every Frappe version.

## Development app update and restore drill

On 2026-10-22, a separate `frappeup-p0-test` project on port 8082 started with Frappe 16.52.0 and ERPNext 16.52.0. A ToDo record and private file were added. `app plan` identified Payments as a new app; `app apply` built the locked image, exported a backup, installed Payments, migrated the site, and returned HTTP 200. The record and private file remained. A controlled restore of the pre-update checkpoint returned the site to Frappe + ERPNext without Payments; the record, private file, and HTTP 200 remained. A later standalone backup generated a manifest and four checksums, and `backup verify` passed. A further run exposed that the target workspace had lost the original custom HTTP port. The failed run completed migration but could not start its frontend; restoring the port restarted the site. The CLI now carries over the current endpoint settings, and a full restore-and-update rerun passed with Payments, the ToDo record, private file, verified backup, and HTTP 200. The pre-existing `frappe1tap-dev` site also returned HTTP 200.

This was one disposable Docker project on macOS. It does not establish Windows end-to-end behavior, production availability, cross-host recovery, encrypted backup restoration, or a failed-patch recovery path. During the initial build, the pre-existing `frappe1tap-dev` project's containers stopped for an undetermined reason; they were restarted from preserved volumes and its Frappe + ERPNext inventory and HTTP 200 were verified. The test project was stopped after validation, with its volumes retained.
