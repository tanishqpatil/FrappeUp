#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
"$ROOT/frappeup" init --profile development --env-file "$TEMP/test.env" >/dev/null
"$ROOT/frappeup" logs --env-file "$TEMP/test.env" --lines 3 >/dev/null
mkdir -p "$TEMP/.frappeup/workspaces/frappeup-dev"
printf 'ADMIN_PASSWORD=test-secret\nDB_PASSWORD=private-db-secret\n' > "$TEMP/.frappeup/workspaces/frappeup-dev/credentials.env"
"$ROOT/frappeup" credentials --env-file "$TEMP/test.env" > "$TEMP/credentials.out"
grep -q '^Login: Administrator$' "$TEMP/credentials.out"
grep -q '^Initial password: test-secret$' "$TEMP/credentials.out"
if grep -q 'private-db-secret' "$TEMP/credentials.out"; then echo 'database secret was exposed' >&2; exit 1; fi
printf '\nINSTALL_APPS=hrms\nFRAPPE_REF=%040d\nFRAPPE_REF_KIND=commit\nFRAPPE_DOCKER_REF=%040d\nFRAPPE_DOCKER_REF_KIND=commit\nAPP_ERPNEXT_REF=%040d\nAPP_ERPNEXT_REF_KIND=commit\nAPP_HRMS_REF=%040d\nAPP_HRMS_REF_KIND=commit\n' 1 2 3 4 >> "$TEMP/test.env"
plan=$("$ROOT/frappeup" plan --env-file "$TEMP/test.env")
printf '%s\n' "$plan" | grep -q 'erpnext \[commit\]'
printf '%s\n' "$plan" | grep -q 'hrms \[commit\]'
"$ROOT/frappeup" lock --env-file "$TEMP/test.env" >/dev/null
[ -s "$TEMP/test.env.lock.env" ]
printf '\nSITE_NAME=changed.localhost\n' >> "$TEMP/test.env"
if "$ROOT/frappeup" workspace --env-file "$TEMP/test.env" >"$TEMP/install.out" 2>&1; then
  echo 'stale lock was accepted' >&2; exit 1
fi
grep -q 'lock file does not match profile' "$TEMP/install.out"
FRAPPEUP_INSTALL_DIR="$TEMP/bin" "$ROOT/install.sh" version > "$TEMP/bootstrap.out"
grep -q '0.4.0' "$TEMP/bootstrap.out"
"$TEMP/bin/frappeup" catalog list > "$TEMP/catalog.out"
grep -q 'ERPNext' "$TEMP/catalog.out"

# Simulate stopped containers and persistent volumes. Even a stale profile must
# be protected before lock validation, image build, or site creation.
cat > "$TEMP/bin/docker" <<'DOCKER'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
case "$1 $2" in
  'version --format'|'compose version'|'buildx version') printf 'mock\n' ;;
  'ps -aq') printf 'existing-container\n' ;;
  'volume ls')
    case " $* " in *' -q '*) printf 'existing-volume\n';; *) printf '  volume: existing-volume\n';; esac ;;
  'ps -a') printf '  container: existing-backend (Exited)\n' ;;
  *) case " $* " in *' ps '*|*' logs '*) printf 'mock\n';; *) printf 'unexpected Docker operation: %s\n' "$*" >&2; exit 90;; esac ;;
esac
DOCKER
chmod +x "$TEMP/bin/docker"
MOCK_DOCKER_LOG="$TEMP/docker.log" PATH="$TEMP/bin:$PATH" "$ROOT/frappeup" install --env-file "$TEMP/test.env" --existing keep > "$TEMP/keep.out"
grep -q 'Keeping existing data' "$TEMP/keep.out"
if grep -E 'buildx build|compose .* (up|down|exec)|new-site|backup' "$TEMP/docker.log" >/dev/null; then echo 'keep modified an existing project' >&2; exit 1; fi
MOCK_DOCKER_LOG="$TEMP/docker-read.log" PATH="$TEMP/bin:$PATH" "$ROOT/frappeup" status --env-file "$TEMP/test.env" >/dev/null
MOCK_DOCKER_LOG="$TEMP/docker-read.log" PATH="$TEMP/bin:$PATH" "$ROOT/frappeup" logs --env-file "$TEMP/test.env" --docker --lines 1 >/dev/null
grep -E 'compose .* -f .*compose.yaml .* ps$' "$TEMP/docker-read.log" >/dev/null
grep -E 'compose .* -f .*compose.yaml .* logs --tail 1$' "$TEMP/docker-read.log" >/dev/null

PREP="$TEMP/prepare"
mkdir -p "$PREP/current/runtime/sources/apps/erpnext"
for repository in "$PREP/current/runtime" "$PREP/current/runtime/sources/frappe" "$PREP/current/runtime/sources/apps/erpnext"; do
  mkdir -p "$repository"
  git -C "$repository" init -q
  git -C "$repository" -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm initial
done
cat > "$PREP/current.env" <<'PROFILE'
PROFILE=development
PROJECT_NAME=prepare-test
SITE_NAME=site.localhost
WORKSPACE_DIR=current
FRAPPE_MAJOR=16
INSTALL_APPS=erpnext
PROFILE
"$ROOT/frappeup" app prepare --current-env-file "$PREP/current.env" --env-file "$PREP/next.env" > "$PREP/prepare.out"
[ -s "$PREP/next.env" ]
grep -q "^FRAPPE_REF_KIND='commit'$" "$PREP/next.env"
grep -q "^FRAPPE_DOCKER_REF_KIND='commit'$" "$PREP/next.env"
grep -q "^APP_ERPNEXT_REF_KIND='commit'$" "$PREP/next.env"
grep -q "^INSTALL_APPS='erpnext'$" "$PREP/next.env"
if "$ROOT/frappeup" app prepare --current-env-file "$PREP/current.env" --env-file "$PREP/next.env" > "$PREP/repeat.out" 2>&1; then
  echo 'app prepare overwrote an existing target profile' >&2; exit 1
fi
BACKUP="$TEMP/backup-fixture"
mkdir -p "$BACKUP"
printf 'SELECT 1;\n' | gzip -c > "$BACKUP/test-database.sql.gz"
printf 'public\n' > "$TEMP/public-marker"
printf 'private\n' > "$TEMP/private-marker"
tar -czf "$BACKUP/test-files.tgz" -C "$TEMP" public-marker
tar -czf "$BACKUP/test-private-files.tgz" -C "$TEMP" private-marker
printf '{}\n' > "$BACKUP/test-site_config_backup.json"
printf "BACKUP_PROJECT='other-project'\nBACKUP_SITE='site.localhost'\nBACKUP_IMAGE='test:tag'\n" > "$BACKUP/manifest.env"
. "$ROOT/lib/common.sh"
for artifact in test-database.sql.gz test-files.tgz test-private-files.tgz test-site_config_backup.json; do
  printf '%s  %s\n' "$(sha256 < "$BACKUP/$artifact")" "$artifact" >> "$BACKUP/SHA256SUMS"
done
"$ROOT/frappeup" backup verify --backup-dir "$BACKUP" > "$TEMP/backup-ok.out"
grep -q '^PASS backup checksums and archive integrity:' "$TEMP/backup-ok.out"
if "$ROOT/frappeup" restore --env-file "$PREP/current.env" --backup-dir "$BACKUP" --yes > "$TEMP/restore-wrong.out" 2>&1; then
  echo 'restore accepted an unrelated backup before Docker checks' >&2; exit 1
fi
grep -q 'backup belongs to a different project or site' "$TEMP/restore-wrong.out"
printf 'corruption\n' >> "$BACKUP/test-site_config_backup.json"
if "$ROOT/frappeup" backup verify --backup-dir "$BACKUP" > "$TEMP/backup-bad.out" 2>&1; then
  echo 'backup verification accepted a corrupted file' >&2; exit 1
fi
grep -q 'backup checksum mismatch' "$TEMP/backup-bad.out"
echo 'PASS script CLI smoke tests'
