# FrappeUp

**Install Frappe and ERPNext from a terminal. Keep your site data when you return.**

[![Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Script CLI](https://img.shields.io/badge/host_CLI-shell_%2B_PowerShell-2ea44f)](docs/ARCHITECTURE.md) [![Checks](https://github.com/tanishqpatil/FrappeUp/actions/workflows/check.yml/badge.svg)](https://github.com/tanishqpatil/FrappeUp/actions/workflows/check.yml)

FrappeUp is an open-source, script-only CLI for a local Docker-based Frappe development site. The host needs a shell, Git, Docker with Compose and Buildx; it does **not** need Go, Python, Node, or Bench installed. Docker images contain Frappe's runtimes.

| Available now | Planned |
|---|---|
| Lock official or user-defined apps to commits | Production deployment workflows |
| Build a Frappe image and create a development site | Production backups and restore |
| Show logs, status, and initial credentials | Health checks and low-downtime operations |
| Detect existing data and default to keeping it | Low-downtime deployments |
| Add or update apps on a development site with a backup checkpoint | Automated recovery after a failed migration |
| Back up, verify, and explicitly restore a development site | Cross-host disaster recovery |

## Start with Frappe + ERPNext

On macOS or Linux, from this checkout:

```sh
./install.sh
frappeup init --profile development --env-file erpnext.env
frappeup doctor --env-file erpnext.env
frappeup plan --env-file erpnext.env
frappeup lock --env-file erpnext.env
frappeup workspace --env-file erpnext.env
frappeup install --env-file erpnext.env
frappeup status --env-file erpnext.env
```

Init selects ERPNext. Open **http://localhost:8080**, sign in as **Administrator**, and get the generated initial password with `frappeup credentials --env-file erpnext.env`. Frappe opens its setup wizard after login while setup is incomplete. A password later changed in Frappe is not reflected in the CLI. To run from the checkout without installing a command, use `./frappeup`.

On Windows, run `install.bat` or `install.ps1` from the checkout, then use `frappeup.bat` or `frappeup.ps1` in PowerShell. Docker Desktop and Git are required.

## Existing site: keep or reset

A repeat install detects Docker containers **and volumes** for the project before validating a lock or building an image. An interactive terminal offers **Keep** (default) or **Reset**. Keep exits without changing the deployment or database. In scripts, `--existing keep` is explicit; without a terminal, keep is the default.

Reset requires a running site, exports database, public/private files, and site configuration outside Docker, checks archive integrity, and then requires `RESET <project-name>` before removing that project's Compose volumes. A disposable reset and restore drill is recorded in the [data lifecycle notes](docs/DATA_LIFECYCLE_PLAN.md). Verify recovery with your own data before relying on reset. Do not use reset to update apps.

Changing `INSTALL_APPS` or a ref in the original profile does not change a running site through `install`. Use the separate app update workflow below. This development setup does not promise zero downtime.

```sh
frappeup install --env-file erpnext.env --existing keep
frappeup logs --env-file erpnext.env --docker --lines 100
```

Existing `frappe1tap-dev` profiles and `.frappe1tap` workspaces remain discoverable. Run `./install.sh` from this checkout to put the new command in your existing CLI directory, then use the same profile and project name. Do not rename `PROJECT_NAME` to access an existing site.

## Add or update an app on an existing development site

Create a separate target profile. `prepare` pins the current Frappe, Frappe Docker, and installed app commits and gives the target its own workspace. Edit only the desired app selection or app refs in the new profile; keep the project and site names unchanged.

```sh
frappeup app prepare --current-env-file erpnext.env --env-file erpnext-next.env
# Edit erpnext-next.env, for example: INSTALL_APPS=erpnext,payments
frappeup lock --env-file erpnext-next.env
frappeup workspace --env-file erpnext-next.env
frappeup app plan --current-env-file erpnext.env --env-file erpnext-next.env
frappeup app apply --current-env-file erpnext.env --env-file erpnext-next.env
```

`plan` only inspects the running site and compares locked commits. `apply` requires `APPLY <project-name>` in a terminal; automation may pass `--yes`. It builds the target image, pauses web and workers, exports and checks a database/files/config backup, stops the backend, installs new apps, runs `bench migrate`, then checks app inventory, services, and HTTP. Database and site volumes are preserved. If the backup fails, it attempts to restart the original services. After success, use the target profile as the current profile for later changes.

Create a separate backup at any time with `frappeup backup --env-file erpnext.env`. The command prints its directory; run `frappeup backup verify --backup-dir PATH` to recheck checksums and archive integrity. This does not replace a restore drill.

To recover from a failed update, use the **profile and image that created the backup**, then run `frappeup restore --env-file erpnext.env --backup-dir PATH`. The command checks project, site, image and archive integrity, asks for `RESTORE <project-name>`, stops app services, restores the database and public/private files, then checks the restored site. `--yes` is available for controlled automation. Restore overwrites current site data and may lose writes made after the checkpoint; it currently supports only an existing development project on the same Docker host.

This path currently supports development only, and it refuses Frappe core or Frappe Docker changes, app removal, non-forward app commits, changed target sources, mismatched project/site identities, or an unverified running image. Web requests and writes pause during migration. If a migration fails, FrappeUp stops and reports the backup path; it does **not** automatically roll back a database migration. Restore the matching backup with a version-matched image after assessing the failed site. Test recovery before using this on important data.

## Apps and versions

The [official app catalog](catalog/official-apps.env) supplies repositories, default refs, declared Frappe majors, and dependencies. `INSTALL_APPS=erpnext,hrms` selects apps; `APP_ERPNEXT_REF=version-16` overrides a ref. Use `*_REF_KIND=branch`, `tag`, or `commit`. A lock records resolved commits; a workspace snapshots sources before build.

For apps outside the catalog, use [custom app definitions](profiles/custom-apps.env.example) through `CUSTOM_APPS_FILE`. Treat profile and custom app files as trusted local scripts. The catalog is a starting point, not a compatibility guarantee for every version combination.

The only implemented install profile is **development**. Production may be planned and locked but cannot yet be installed. See the [architecture](docs/ARCHITECTURE.md), [data lifecycle](docs/DATA_LIFECYCLE_PLAN.md), [existing tools](docs/ECOSYSTEM.md), [roadmap](TODO.md), and [contributing guide](CONTRIBUTING.md).

## Releases

The [latest release](https://github.com/tanishqpatil/FrappeUp/releases/latest) contains checksum-verified shell and PowerShell bundles. On macOS or Linux, install without cloning:

```sh
curl -fsSL https://raw.githubusercontent.com/tanishqpatil/FrappeUp/master/install.sh | sh
```

The installer prints the command directory to add to `PATH` if needed. For Windows, download the release ZIP or run `install.ps1` from a checkout. The source checkout also works immediately without a release.

Licensed under [Apache-2.0](LICENSE).
