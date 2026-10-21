# Build checklist

- [x] Script-only CLI and source bootstrap for macOS/Linux.
- [x] PowerShell CLI and Batch entry points for Windows.
- [x] Official catalog and custom app definitions.
- [x] Dependency planning and commit locks.
- [x] Isolated Docker workspace and site installation.
- [x] Runtime status and Docker logs.
- [x] Frappe + ERPNext Docker verification on macOS.
- [x] Detect existing project volumes and default to preserving the site.
- [x] Guard interactive reset with exported backup and exact confirmation.
- [x] Rename CLI and documentation to FrappeUp.
- [x] Verify a disposable reset and independent restore end to end.
- [x] Add a development app install/update migration flow that retains data and verifies health; verify an additive app installation on a disposable site.
- [x] Add standalone backup, checksum verification, and explicit restore for an existing development site; verify an update checkpoint can restore the prior app inventory and data.
- [ ] Test same-major app version updates and failed migrations in disposable projects.
- [ ] Add automated recovery, off-host backups, and cross-host restore drills.
- [ ] Windows end-to-end Docker verification.
- [ ] Production installation, backup/restore, monitoring, update, and destroy.
