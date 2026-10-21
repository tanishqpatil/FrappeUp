# Existing Frappe installation and operations tools

Checked against project documentation on 21 October 2026. FrappeUp is one option among mature official tools; it does not replace them.

| Tool | Existing scope | Relation to FrappeUp |
|---|---|---|
| [Frappe Docker](https://github.com/frappe/frappe_docker) | Official images, Compose definitions, development workflow, and production deployment guidance. Its [deployment guide](https://github.com/frappe/frappe_docker/blob/main/docs/01-getting-started/01-choosing-a-deployment-method.md) distinguishes demo, devcontainer, Easy Install, and manual production. | FrappeUp builds on its pinned Compose source. |
| [Bench Easy Install](https://github.com/frappe/bench) | Official Python script that installs prerequisites and deploys Frappe through Docker for development or production. | More deployment-complete today; FrappeUp targets a shell-only host CLI and explicit commit locks. |
| [Bench](https://github.com/frappe/bench) | The core site/app lifecycle CLI, including app install, migrate, backup, and restore. | FrappeUp invokes Bench inside Docker; it must respect Bench's site and migration semantics. |
| [Bench Manager](https://github.com/frappe/bench_manager) | A Frappe GUI for app/site management, backups, and restores after Bench is running. | Different interface and installation stage. |
| [frappectl](https://github.com/frappe/frappectl) | CLI for interacting with an existing Frappe site over its API. | Complementary; it does not provision Docker stacks. |

The strongest useful gap for FrappeUp is a cross-platform host CLI that needs only scripts, Git, and Docker; records exact source commits; and treats existing site data as protected. The most important unfinished work is a safe app-update path with restore testing. Until then, users needing production deployment or existing-site migrations should use the official tools and their documented procedures.
