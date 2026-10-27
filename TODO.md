# Build checklist

FrappeUp is a terminal-only Frappe lifecycle manager. Host entry points remain POSIX shell, PowerShell, and Batch; Frappe runtimes and developer tools run inside Docker. No web dashboard or host Go, Python, Node, or Bench installation is required.

Unchecked items are planned capabilities, not claims of current support. Work proceeds in the order below, with a plan and relevant verification before each implementation is marked complete.

## Completed foundation

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
- [x] Test a same-major Payments commit update on a disposable site with retained data.
- [x] Exercise an actual failing Bench migration patch and restore on a disposable project; retain a database record and private file.
- [x] Exercise an actual failing patch through `app apply` and restore its checkpoint on a disposable macOS Docker project.

## 1. Shared safeguards and release identity

- [ ] **Parse configuration as data:** replace executable shell profile loading with strict, equivalent shell and PowerShell parsers; validate settings without executing their contents and document migration for existing profiles.
- [ ] **Lock every mutating operation:** prevent overlapping install, update, restore, reset, and lifecycle changes on the same project; record operation ownership and explain recovery after interruption.
- [ ] **Verify exact release images:** record the image identity, app commits, target platform, and build provenance; detect replaced tags and preserve the matching previous image for recovery.
- [ ] **Reuse verified artifacts:** deploy or restore the same retained image without rebuilding or resolving branches again. Keep deployment repeatability distinct from reproducible source builds.
- [ ] **Lock build inputs:** pin and verify runtime base images, toolchains, downloaded artifacts, and dependency inputs; identify unsupported or unresolved inputs and test clean rebuilds before claiming reproducibility.

## 2. Terminal navigation and everyday lifecycle

- [ ] **Select an environment:** list known projects and sites, select a target, and show its identity before changes. Saved selection must not prevent an explicit target in automation.
- [ ] **Start, stop, and restart:** control an existing installation without repeating site creation or deleting database and file volumes.
- [ ] **Provide a terminal menu:** guide users through installation, lifecycle controls, app changes, logs, backups, and recovery using the same operation logic as direct commands.
- [ ] **Guide installation:** choose a profile, official or custom apps, and refs in the terminal; preview dependencies and the installation plan, then generate configuration without requiring manual file edits.
- [ ] **Expand diagnostics:** check Docker readiness, architecture, memory, disk capacity, port conflicts, and workspace ownership before changes; inspect web, worker, scheduler, database, Redis, and backup health afterward.
- [ ] **Show operation history:** list completed, interrupted, and failed operations with phase logs, image identities, backup checkpoints, and applicable recovery instructions; redact secrets from diagnostic output.
- [ ] **Support unattended use:** provide explicit targets, documented exit codes, machine-readable results, and clear confirmation behavior so CI and scripts can use the same features as the menu.

## 3. App discovery and developer workflows

- [ ] **Discover apps and versions:** show official app metadata and available refs, accept custom repository URLs and refs, resolve exact commits, and distinguish declared, verified, conflicting, and unknown compatibility.
- [ ] **Inspect installations for adoption:** read an existing installation's apps, versions, site identity, and storage ownership; produce an adoption plan before taking control or modifying it.
- [ ] **Open containerized developer tools:** provide terminal access to the container shell, Bench console, app commands, and tests without installing language toolchains on the host.
- [ ] **Provide an editable development workspace:** support source editing, asset watching, and development dependencies separately from immutable deployment images.
- [ ] **Isolate app tests:** create disposable test sites and run app tests without using a site's persistent user data.

## 4. Backup and recovery

- [ ] **Manage backup inventory:** list checkpoints, their site and image identities, age, verification status, and storage use; apply explicit retention rules without deleting the only usable recovery checkpoint.
- [ ] **Store encrypted off-host backups:** support a documented external destination, encryption and key recovery, transfer verification, and configurable retention.
- [ ] **Restore on another host:** recover database, public/private files, site configuration, required keys, and the matching image into an explicitly selected destination; verify the restored site.
- [ ] **Guide recovery:** use recorded operation phases and checkpoints to explain and execute a confirmed recovery procedure. Add automatic recovery only for failure states whose behavior has been tested.
- [ ] **Schedule backup and restore checks:** offer opt-in scheduled jobs through documented host or container scheduling, with logs and backup freshness checks; keep normal CLI operation independent of an always-running dashboard.

## 5. UAT, production, and release promotion

- [ ] **Define profile capabilities:** give development, UAT, and production distinct source, runtime, configuration, secret, and maintenance behavior; gate unsupported capabilities.
- [ ] **Clone safely into UAT:** restore into isolated storage, sanitize sensitive data, rotate relevant credentials, and disable outbound email, webhooks, and other integrations before enabling access.
- [ ] **Deploy production environments:** provide tested hostname/TLS configuration, durable storage, restart policies, resource checks, and restricted database/Redis exposure using supported Frappe Docker components.
- [ ] **Promote tested releases:** move the same verified image from UAT to production by digest, with deployment checks, an explicit operator decision, and recorded release history.
- [ ] **Monitor from the terminal:** report service health, queue and scheduler state, resource usage, certificate validity, backup freshness, and logs; provide actionable failures and redacted support exports.
- [ ] **Provide controlled production maintenance:** support tested update, backup, restore, and explicit teardown procedures; keep destructive data removal separate and confirmed.
- [ ] **Classify deployment availability:** distinguish code-only changes, compatible migrations, and breaking or unknown patches; show whether reads or writes must pause.
- [ ] **Test low-downtime deployments:** rehearse traffic draining, backend switching, worker coordination, and Frappe read-only maintenance where supported; measure disruption before making an availability claim.

## 6. Remote operation and support verification

- [ ] **Operate through SSH:** target a remote host explicitly and reuse the same project/site lifecycle contract, ownership checks, logs, and recovery controls.
- [ ] **Validate native Windows Docker workflows:** test installation, paths with spaces, file permissions, lifecycle operations, app updates, and recovery using PowerShell/Batch with Docker Desktop.
- [ ] **Validate Linux Docker workflows:** test the same lifecycle and retained-data behavior on a Linux Docker host; include an actual failing-patch recovery drill.
- [ ] **Extend automated integration coverage:** run disposable Docker drills for successful updates, failed patches, backup failures, interrupted operations, missing images, and configuration errors on supported platforms.
- [ ] **Publish an evidence-based support matrix:** document tested OS, architecture, Docker, Frappe, and app combinations and keep unverified combinations explicitly identified.
