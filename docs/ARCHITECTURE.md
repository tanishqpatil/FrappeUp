# Architecture

FrappeUp has no compiled host component. `frappeup` is POSIX shell; `frappeup.ps1` is PowerShell; `frappeup.bat` is a Windows launcher. Docker runs Frappe, MariaDB, Redis, and apps. Git resolves and snapshots sources. No host Go, Python, Node, or Bench is required.

```text
trusted profile + catalog → dependency plan → commit lock → immutable workspace
                                                        ↓
                                     build image → Compose project → Frappe site
                                                        ↓
                                        Docker volumes: database + site files
```

A `.env` profile identifies one Compose project and Frappe site. The catalog holds repositories, default refs, declared major compatibility, and dependencies. `CUSTOM_APPS_FILE` adds user-provided repositories. These files are trusted shell-compatible configuration. `plan` orders dependencies. `lock` resolves refs to commits and records a plan checksum. `workspace` verifies the lock, snapshots sources, and creates an app build context and private credentials. `install` builds the image and creates a new development site. `status`, `logs`, and `credentials` inspect the result.

A Compose project label is the ownership boundary. Before touching a project, `install` asks Docker for **all** matching containers (including stopped ones) and volumes. Any match means prior state exists. The default is to keep that state and exit without a build, `new-site`, or migration. A changed profile cannot bypass this check. Existing legacy `.frappe1tap` workspaces are located by their original project name; their data remains in the same Docker volumes.

Reset needs a running backend and site. It stages a Frappe backup outside the site's `private/backups` directory, exports it outside Docker, checks all four artifacts and archive integrity, and asks for an exact typed project confirmation before Compose removes volumes. It then creates a fresh site from the locked workspace. The exported backup path is `.frappeup/backups/<project>/` beside the profile and is ignored by Git. Operators should still perform restore drills for their own data and environment.

Development app updates use two profiles for the same project and site. `app prepare` makes a target profile with the current Frappe, Docker, and app commits pinned and a new workspace path. `app plan` compares the target lock with the live app inventory and source commits, verifies Compose ownership and the running image, and refuses app removal or core/Docker changes. `app apply` builds the target image, verifies and exports a complete site backup with a manifest and checksums, stops application services but preserves database/site volumes, runs `install-app` for additions and `bench migrate`, then starts the new services and checks inventory and HTTP. The operation is intentionally not zero downtime. A failed migration can change the database, so switching back to the old image is not an automatic rollback. `restore` checks the backup identity and archive integrity, requires an explicit confirmation, runs Bench restore with the matching image, and verifies the site. Recovery still needs operator assessment and may lose writes after the backup.

The development profile publishes the frontend on `http://localhost:8080`. Production installation is gated until TLS, external backup/restore, monitoring, deployment, and rollback controls exist. Each app retains its own license.
