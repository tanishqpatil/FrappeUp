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

App updates on an existing site are **not implemented**. Frappe apps live in the custom image while state persists in database and site volumes. A future migration command must build a replacement image, verify app/dependency compatibility, make a restorable backup, perform `install-app` and `bench migrate`, and check health. A single Compose backend may be unavailable during schema migration; this architecture does not promise zero downtime.

The development profile publishes the frontend on `http://localhost:8080`. Production installation is gated until TLS, external backup/restore, monitoring, deployment, and rollback controls exist. Each app retains its own license.
