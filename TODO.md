# Build checklist

- [x] Replace the script-first design with a self-contained CLI foundation.
- [x] Add development and production `.env` profiles.
- [x] Add the official Frappe product-app catalog and dependency planner.
- [x] Preserve the original implementation as legacy reference.
- [x] Implement Git commit locking for all official and custom apps.
- [x] Add per-profile structured operational logs and log following.
- [x] Add Docker prerequisite diagnostics.
- [x] Generate isolated commit-locked Docker build workspaces from a lock file.
- [ ] Generate and run isolated Docker Compose projects from a workspace.
- [ ] Implement site creation and app installation inside Docker.
- [ ] Implement status, backup, restore, update, and destroy commands.
- [x] Add checksum-verified release artifacts for macOS, Linux, and Windows.
