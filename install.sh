#!/bin/sh
set -eu
REPOSITORY=${FRAPPEUP_REPOSITORY:-tanishqpatil/FrappeUp}
VERSION=${FRAPPEUP_VERSION:-latest}
if [ -n "${FRAPPEUP_INSTALL_DIR:-}" ]; then INSTALL_DIR=$FRAPPEUP_INSTALL_DIR
elif [ -d "$HOME/.frappe1tap/bin" ]; then INSTALL_DIR="$HOME/.frappe1tap/bin"
else INSTALL_DIR="$HOME/.frappeup/bin"; fi
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
download() {
  if command -v curl >/dev/null 2>&1; then curl --fail --location --silent --show-error "$1" --output "$2"
  elif command -v wget >/dev/null 2>&1; then wget --quiet --output-document="$2" "$1"
  else echo 'curl or wget is required' >&2; exit 1; fi
}
if [ -f "$SCRIPT_DIR/frappeup" ] && [ -f "$SCRIPT_DIR/lib/common.sh" ] && [ -f "$SCRIPT_DIR/catalog/official-apps.env" ]; then
  BUNDLE_DIR=$SCRIPT_DIR
else
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
  if [ "$VERSION" = latest ]; then BASE_URL="https://github.com/$REPOSITORY/releases/latest/download"
  else BASE_URL="https://github.com/$REPOSITORY/releases/download/$VERSION"; fi
  ASSET=frappeup_unix.tar.gz
  download "$BASE_URL/$ASSET" "$TEMP_DIR/$ASSET"
  download "$BASE_URL/$ASSET.sha256" "$TEMP_DIR/$ASSET.sha256"
  if command -v shasum >/dev/null 2>&1; then (cd "$TEMP_DIR" && shasum -a 256 -c "$ASSET.sha256")
  elif command -v sha256sum >/dev/null 2>&1; then (cd "$TEMP_DIR" && sha256sum -c "$ASSET.sha256")
  else echo 'shasum or sha256sum is required' >&2; exit 1; fi
  tar -xzf "$TEMP_DIR/$ASSET" -C "$TEMP_DIR"
  BUNDLE_DIR=$TEMP_DIR
fi
ROOT_DIR=$(dirname -- "$INSTALL_DIR")
mkdir -p "$INSTALL_DIR" "$ROOT_DIR/lib" "$ROOT_DIR/catalog"
install -m 0755 "$BUNDLE_DIR/frappeup" "$INSTALL_DIR/frappeup"
install -m 0644 "$BUNDLE_DIR/lib/common.sh" "$ROOT_DIR/lib/common.sh"
install -m 0644 "$BUNDLE_DIR/catalog/official-apps.env" "$ROOT_DIR/catalog/official-apps.env"
printf 'Installed %s/frappeup\n' "$INSTALL_DIR"
case ":$PATH:" in *":$INSTALL_DIR:"*) ;; *) printf 'Add to PATH: %s\n' "$INSTALL_DIR";; esac
[ "$#" -eq 0 ] || exec "$INSTALL_DIR/frappeup" "$@"
