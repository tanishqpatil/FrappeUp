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
cat > "$TEMP/test.env" <<'PROFILE'
PROFILE=development
PROJECT_NAME=frappeup-dev
SITE_NAME=site.localhost
INSTALL_APPS=hrms
FRAPPE_REF=0000000000000000000000000000000000000001
FRAPPE_REF_KIND=commit
FRAPPE_DOCKER_REF=0000000000000000000000000000000000000002
FRAPPE_DOCKER_REF_KIND=commit
APP_ERPNEXT_REF=0000000000000000000000000000000000000003
APP_ERPNEXT_REF_KIND=commit
APP_HRMS_REF=0000000000000000000000000000000000000004
APP_HRMS_REF_KIND=commit
PROFILE
plan=$("$ROOT/frappeup" plan --env-file "$TEMP/test.env")
printf '%s\n' "$plan" | grep -q 'erpnext \[commit\]'
printf '%s\n' "$plan" | grep -q 'hrms \[commit\]'
"$ROOT/frappeup" lock --env-file "$TEMP/test.env" >/dev/null
[ -s "$TEMP/test.env.lock.env" ]
cp "$TEMP/test.env.lock.env" "$TEMP/good.lock.env"
printf 'LOCK_SCHEMA=2\n' >> "$TEMP/test.env.lock.env"
if "$ROOT/frappeup" workspace --env-file "$TEMP/test.env" > /dev/null 2>&1; then echo 'duplicate lock key was accepted' >&2; exit 1; fi
mv "$TEMP/good.lock.env" "$TEMP/test.env.lock.env"
sed 's/^SITE_NAME=.*/SITE_NAME=changed.localhost/' "$TEMP/test.env" > "$TEMP/changed.env"
mv "$TEMP/changed.env" "$TEMP/test.env"
if "$ROOT/frappeup" workspace --env-file "$TEMP/test.env" >"$TEMP/install.out" 2>&1; then
  echo 'stale lock was accepted' >&2; exit 1
fi
grep -q 'lock file does not match profile' "$TEMP/install.out"
printf 'PROFILE=development\nPROFILE=production\n' > "$TEMP/duplicate.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/duplicate.env" > /dev/null 2>&1; then echo 'duplicate profile key was accepted' >&2; exit 1; fi
printf 'PROFILE=development\nPATH=/tmp\n' > "$TEMP/unknown.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/unknown.env" > /dev/null 2>&1; then echo 'unknown profile key was accepted' >&2; exit 1; fi
printf 'PROFILE=development\nAPP_MISSING_REF=main\n' > "$TEMP/unknown.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/unknown.env" > /dev/null 2>&1; then echo 'unknown app override was accepted' >&2; exit 1; fi
printf 'PROFILE=development\nFRAPPE_REF_KIND=invalid\n' > "$TEMP/unknown.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/unknown.env" > /dev/null 2>&1; then echo 'invalid ref kind was accepted' >&2; exit 1; fi
printf 'PROFILE=development\nPROJECT_NAME=$(touch %s)\n' "$TEMP/executed" > "$TEMP/injection.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/injection.env" > /dev/null 2>&1; then echo 'executable profile syntax was accepted' >&2; exit 1; fi
[ ! -e "$TEMP/executed" ] || { echo 'profile executed a command' >&2; exit 1; }
printf 'PROFILE=development\ntouch %s\n' "$TEMP/executed" > "$TEMP/injection.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/injection.env" > /dev/null 2>&1; then echo 'profile command was accepted' >&2; exit 1; fi
[ ! -e "$TEMP/executed" ] || { echo 'profile executed a command' >&2; exit 1; }
printf "PROFILE=development\nFRAPPE_REPOSITORY='\$(touch %s)'\n" "$TEMP/quoted-executed" > "$TEMP/quoted.env"
"$ROOT/frappeup" plan --env-file "$TEMP/quoted.env" > "$TEMP/quoted.out"
[ ! -e "$TEMP/quoted-executed" ] || { echo 'quoted profile value executed a command' >&2; exit 1; }
grep -F '$(touch ' "$TEMP/quoted.out" >/dev/null
printf 'PROFILE=development\nINSTALL_APPS=erpnext\n' > "$TEMP/defaults.env"
APP_ERPNEXT_REF=unexpected "$ROOT/frappeup" plan --env-file "$TEMP/defaults.env" > "$TEMP/defaults.out"
grep -F 'erpnext [branch] @ version-16' "$TEMP/defaults.out" >/dev/null
printf 'PROFILE=development\nCUSTOM_APPS_FILE=unsafe-custom.env\n' > "$TEMP/custom-profile.env"
printf 'CUSTOM_APP_IDS=example\nPATH=/tmp\n' > "$TEMP/unsafe-custom.env"
if "$ROOT/frappeup" plan --env-file "$TEMP/custom-profile.env" > /dev/null 2>&1; then echo 'unsafe custom app key was accepted' >&2; exit 1; fi
printf 'PROFILE=development\nCUSTOM_APPS_FILE=custom.env\nINSTALL_APPS=example\n' > "$TEMP/custom-profile.env"
cat > "$TEMP/custom.env" <<'CUSTOM'
CUSTOM_APP_IDS=example
APP_example_REPOSITORY=https://example.invalid/repository
APP_example_REF='$(touch /tmp/frappeup-custom-must-not-execute)'
APP_example_REF_KIND=branch
APP_example_APP_NAME=example
APP_example_REQUIRES=''
APP_example_MAJORS=16
CUSTOM
"$ROOT/frappeup" plan --env-file "$TEMP/custom-profile.env" > "$TEMP/custom.out"
grep -F '$(touch /tmp/frappeup-custom-must-not-execute)' "$TEMP/custom.out" >/dev/null
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
mkdir -p "$PREP/space and apostrophe's"
"$ROOT/frappeup" app prepare --current-env-file "$PREP/current.env" --env-file "$PREP/space and apostrophe's/next.env" >/dev/null
"$ROOT/frappeup" plan --env-file "$PREP/space and apostrophe's/next.env" >/dev/null
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
printf 'WORKSPACE_PLAN_SHA256=test\n$(touch %s)\n' "$TEMP/executed" > "$TEMP/unsafe-workspace.env"
if (read_env_file "$TEMP/unsafe-workspace.env" workspace) > /dev/null 2>&1; then echo 'executable workspace metadata was accepted' >&2; exit 1; fi
[ ! -e "$TEMP/executed" ] || { echo 'workspace metadata executed a command' >&2; exit 1; }
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
