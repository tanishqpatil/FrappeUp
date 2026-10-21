#!/usr/bin/env sh
set -eu

REPOSITORY="SwayAlgo/Frappe1TapInstall"
VERSION="${FRAPPE1TAP_VERSION:-latest}"
INSTALL_DIR="${FRAPPE1TAP_INSTALL_DIR:-$HOME/.frappe1tap/bin}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  *) echo "Frappe 1-Tap supports macOS and Linux through this installer." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac

ASSET="frappe1tap_${OS}_${ARCH}.tar.gz"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

download() {
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error "$1" --output "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="$2" "$1"
  else
    echo "curl or wget is required to download Frappe 1-Tap." >&2
    exit 1
  fi
}

if [ -f "$SCRIPT_DIR/go.mod" ]; then
  if ! command -v go >/dev/null 2>&1; then
    echo "This is a source checkout and no released binary exists here. Install Go to build it, or use a published release." >&2
    exit 1
  fi
  echo "Building Frappe 1-Tap from this source checkout..."
  (cd "$SCRIPT_DIR" && go build -trimpath -o "$TMP_DIR/frappe1tap" ./cmd/frappe1tap)
else
  if [ "$VERSION" = "latest" ]; then
    BASE_URL="https://github.com/$REPOSITORY/releases/latest/download"
  else
    BASE_URL="https://github.com/$REPOSITORY/releases/download/$VERSION"
  fi
  download "$BASE_URL/$ASSET" "$TMP_DIR/$ASSET"
  download "$BASE_URL/$ASSET.sha256" "$TMP_DIR/$ASSET.sha256"

  if command -v shasum >/dev/null 2>&1; then
    (cd "$TMP_DIR" && shasum -a 256 -c "$ASSET.sha256")
  elif command -v sha256sum >/dev/null 2>&1; then
    (cd "$TMP_DIR" && sha256sum -c "$ASSET.sha256")
  else
    echo "shasum or sha256sum is required to verify the download." >&2
    exit 1
  fi
  tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR"
fi

mkdir -p "$INSTALL_DIR"
install -m 0755 "$TMP_DIR/frappe1tap" "$INSTALL_DIR/frappe1tap"

echo "Installed Frappe 1-Tap to $INSTALL_DIR/frappe1tap"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Add this directory to PATH: $INSTALL_DIR" ;;
esac

if [ "$#" -gt 0 ]; then
  exec "$INSTALL_DIR/frappe1tap" "$@"
fi
