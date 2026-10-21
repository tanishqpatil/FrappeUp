# FrappeUp

**Install Frappe and ERPNext from a terminal. Keep your site data when you return.**

[![Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Script CLI](https://img.shields.io/badge/host_CLI-shell_%2B_PowerShell-2ea44f)](docs/ARCHITECTURE.md) [![Checks](https://github.com/tanishqpatil/FrappeUp/actions/workflows/check.yml/badge.svg)](https://github.com/tanishqpatil/FrappeUp/actions/workflows/check.yml)

FrappeUp is an open-source, script-only CLI for a local Docker-based Frappe development site. The host needs a shell, Git, Docker with Compose and Buildx; it does **not** need Go, Python, Node, or Bench installed. Docker images contain Frappe's runtimes.

| Available now | Planned |
|---|---|
| Lock official or user-defined apps to commits | Safely add or upgrade apps on an existing site |
| Build a Frappe image and create a development site | Production deployment and restore workflows |
| Show logs, status, and initial credentials | Health checks and low-downtime operations |
| Detect existing data and default to keeping it | Automated migrations with rollback checks |

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

Reset requires a running site, exports database, public/private files, and site configuration outside Docker, checks the files, and then requires `RESET <project-name>` before removing that project's Compose volumes. Verify a backup by restoring it independently before relying on it. Do not use reset to update apps.

Changing `INSTALL_APPS` or a ref does **not yet** migrate an existing site. FrappeUp keeps it unchanged; migration is a separate future command. This development setup does not promise zero downtime.

```sh
frappeup install --env-file erpnext.env --existing keep
frappeup logs --env-file erpnext.env --docker --lines 100
```

Existing `frappe1tap-dev` profiles and `.frappe1tap` workspaces remain discoverable. Run `./install.sh` from this checkout to put the new command in your existing CLI directory, then use the same profile and project name. Do not rename `PROJECT_NAME` to access an existing site.

## Apps and versions

The [official app catalog](catalog/official-apps.env) supplies repositories, default refs, declared Frappe majors, and dependencies. `INSTALL_APPS=erpnext,hrms` selects apps; `APP_ERPNEXT_REF=version-16` overrides a ref. Use `*_REF_KIND=branch`, `tag`, or `commit`. A lock records resolved commits; a workspace snapshots sources before build.

For apps outside the catalog, use [custom app definitions](profiles/custom-apps.env.example) through `CUSTOM_APPS_FILE`. Treat profile and custom app files as trusted local scripts. The catalog is a starting point, not a compatibility guarantee for every version combination.

The only implemented install profile is **development**. Production may be planned and locked but cannot yet be installed. See the [architecture](docs/ARCHITECTURE.md), [data lifecycle](docs/DATA_LIFECYCLE_PLAN.md), [existing tools](docs/ECOSYSTEM.md), [roadmap](TODO.md), and [contributing guide](CONTRIBUTING.md).

## Releases

After a tagged release is published, `install.sh` and `install.ps1` can download checksum-verified script bundles. This source checkout works immediately without a release. Releases and source: [github.com/tanishqpatil/FrappeUp](https://github.com/tanishqpatil/FrappeUp).

Licensed under [Apache-2.0](LICENSE).
