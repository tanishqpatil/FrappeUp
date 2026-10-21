#!/bin/sh
set -eu

fail() { printf '%s\n' "error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "$1 is required"; }
valid_identifier() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; *) return 0;; esac; }
valid_app_id() { case "$1" in ''|*[!A-Za-z0-9_]*) return 1;; *) return 0;; esac; }
valid_site() { case "$1" in ''|*[!A-Za-z0-9.-]*) return 1;; *) return 0;; esac; }
upper() { printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'; }
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else fail 'shasum or sha256sum is required'; fi; }
quote_env() { printf "%s" "$1" | sed "s/'/'\\\\''/g"; }
log_event() { mkdir -p "$LOG_DIR"; printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$LOG_DIR/cli.log"; }
