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
read_env_file() {
  env_file=$1 env_kind=$2
  [ -r "$env_file" ] || fail "cannot read $env_kind file: $env_file"
  env_data=$(LC_ALL=C awk -v kind="$env_kind" '
    function allowed(k) {
      if (kind == "profile") return k ~ /^(PROFILE|PROJECT_NAME|SITE_NAME|WORKSPACE_DIR|FRAPPE_REPOSITORY|FRAPPE_REF|FRAPPE_REF_KIND|FRAPPE_DOCKER_REPOSITORY|FRAPPE_DOCKER_REF|FRAPPE_DOCKER_REF_KIND|FRAPPE_MAJOR|INSTALL_APPS|CUSTOM_APPS_FILE)$/ || k ~ /^APP_[A-Z0-9_]+_REF(_KIND)?$/
      if (kind == "custom" || kind == "catalog") return (kind == "custom" && k == "CUSTOM_APP_IDS") || (kind == "catalog" && k == "APP_IDS") || k ~ /^APP_[A-Za-z0-9_]+_(DISPLAY_NAME|REPOSITORY|REF|REF_KIND|APP_NAME|REQUIRES|MAJORS)$/
      if (kind == "lock") return k ~ /^LOCK_(SCHEMA|PLAN_SHA256|PROJECT_NAME|SITE_NAME|FRAPPE_REPOSITORY|FRAPPE_REF|FRAPPE_REF_KIND|FRAPPE_COMMIT|FRAPPE_DOCKER_REPOSITORY|FRAPPE_DOCKER_REF|FRAPPE_DOCKER_REF_KIND|FRAPPE_DOCKER_COMMIT|APP_IDS)$/ || k ~ /^LOCK_APP_[A-Za-z0-9_]+_(REPOSITORY|REF|REF_KIND|APP_NAME|COMMIT)$/
      if (kind == "workspace") return k ~ /^(WORKSPACE_PLAN_SHA256|IMAGE|TAG)$/
      return 0
    }
    function bad() { exit 2 }
    {
      sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "")
      if ($0 == "" || substr($0, 1, 1) == "#") next
      pos = index($0, "="); if (!pos) bad()
      k = substr($0, 1, pos - 1); raw = substr($0, pos + 1)
      if (k !~ /^[A-Za-z_][A-Za-z0-9_]*$/ || !allowed(k) || seen[toupper(k)]++) bad()
      if (index(raw, "\t")) bad()
      sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92)
      n = length(raw); value = ""
      if (substr(raw, 1, 1) == sq) {
        if (n < 2 || substr(raw, n, 1) != sq) bad()
        inner = substr(raw, 2, n - 2)
        for (i = 1; i <= length(inner); i++) {
          ch = substr(inner, i, 1)
          if (ch == sq) {
            if (substr(inner, i, 4) != sq bs sq sq) bad()
            value = value sq; i += 3
          } else value = value ch
        }
      } else if (substr(raw, 1, 1) == dq) {
        if (n < 2 || substr(raw, n, 1) != dq) bad()
        value = substr(raw, 2, n - 2); if (index(value, dq)) bad()
      } else {
        value = raw
        if (value ~ /[[:space:]"`$;&|<>()]/ || index(value, sq)) bad()
      }
      if (k ~ /_REF_KIND$/ && value != "branch" && value != "tag" && value != "commit") bad()
      printf "%s\t%s\n", k, value
    }
  ' "$env_file") || fail "invalid, duplicate, or unsupported setting in $env_file"
  while IFS="$(printf '\t')" read -r env_key env_value; do
    [ -n "$env_key" ] || continue
    export "$env_key=$env_value"
    if [ "$env_kind" = profile ]; then PROFILE_READ_KEYS="${PROFILE_READ_KEYS:-} $env_key"; fi
  done <<EOF_ENV
$env_data
EOF_ENV
}
log_event() { mkdir -p "$LOG_DIR"; printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$LOG_DIR/cli.log"; }
