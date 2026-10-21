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
grep -q '0.3.1' "$TEMP/bootstrap.out"
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
echo 'PASS script CLI smoke tests'
