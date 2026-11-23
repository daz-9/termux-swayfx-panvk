#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO="${SWAYFX_PANVK_REPO:-daz-9/termux-swayfx-panvk}"
LOCAL_PREFIX="${HOME}/.local"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
ASSET_NAME="swayfx-panvk-termux-aarch64.tar.gz"
TAG=""

for arg in "$@"; do
  case "$arg" in
    --tag=*) TAG="${arg#--tag=}" ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--tag=<release-tag>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

for cmd in curl sha256sum tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[-] Required command not found: $cmd" >&2
    exit 1
  fi
done

if [ -n "$TAG" ]; then
  BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"
else
  BASE_URL="https://github.com/${REPO}/releases/latest/download"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[*] Downloading ${ASSET_NAME} from ${REPO}..."
curl -fL --retry 3 "${BASE_URL}/${ASSET_NAME}" -o "$TMP_DIR/${ASSET_NAME}"
curl -fL --retry 3 "${BASE_URL}/SHA256SUMS" -o "$TMP_DIR/SHA256SUMS"

expected_sha="$(awk -v name="$ASSET_NAME" '$2 == name { print $1; exit }' "$TMP_DIR/SHA256SUMS")"
if [ -z "$expected_sha" ]; then
  echo "[-] Could not find checksum for ${ASSET_NAME} in SHA256SUMS" >&2
  exit 1
fi

actual_sha="$(sha256sum "$TMP_DIR/${ASSET_NAME}" | awk '{ print $1 }')"
if [ "$expected_sha" != "$actual_sha" ]; then
  echo "[-] SHA-256 mismatch for ${ASSET_NAME}: expected ${expected_sha}, got ${actual_sha}" >&2
  exit 1
fi

mkdir -p "$LOCAL_PREFIX"
tar -xzf "$TMP_DIR/${ASSET_NAME}" -C "$LOCAL_PREFIX"
chmod 0755 "$LOCAL_PREFIX/bin/swayfx" "$LOCAL_PREFIX/bin/gpu"

if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath "$LOCAL_PREFIX/lib:$PREFIX_DIR/lib" "$LOCAL_PREFIX/lib/libscenefx-0.5.so" 2>/dev/null || true
  patchelf --set-rpath "$LOCAL_PREFIX/lib:$PREFIX_DIR/lib" "$LOCAL_PREFIX/bin/swayfx" 2>/dev/null || true
fi

echo "[+] Installed SwayFX + SceneFX + patched wlroots into $LOCAL_PREFIX"
