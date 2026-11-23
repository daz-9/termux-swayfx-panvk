#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
RELEASE_TAG="${PANVK_RELEASE_TAG:-panvk-kbase-v26.3.1}"
BASE_URL="https://github.com/zenithblue-oss/panvk-kbase-android/releases/download/${RELEASE_TAG}"
ASSET_NAME="libvulkan_panfrost-android-aarch64.so"
ICD_PATH="$PREFIX_DIR/share/vulkan/icd.d/panfrost_icd.aarch64.json"
LIB_PATH="$PREFIX_DIR/lib/libvulkan_panfrost.so"
WSI_DIR="$PREFIX_DIR/lib/panvk-wsi"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--force]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

for cmd in curl patchelf sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[-] Required command not found: $cmd" >&2
    exit 1
  fi
done

mkdir -p "$PREFIX_DIR/lib" "$WSI_DIR" "$(dirname "$ICD_PATH")"

if [ "$FORCE" -eq 1 ] || [ ! -f "$LIB_PATH" ]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  echo "[*] Downloading PanVK (${RELEASE_TAG})..."
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

  install -m 0755 "$TMP_DIR/${ASSET_NAME}" "$LIB_PATH"
  echo "[+] Verified and installed $LIB_PATH"
else
  echo "[+] $LIB_PATH already present (pass --force to re-download)"
fi

# Create versioned X11/XCB soname symlinks expected by Android PanVK X11 WSI dlopen
wsi_links=(
  "libX11-xcb.so.1:libX11-xcb.so"
  "libxcb.so.1:libxcb.so"
  "libxcb-dri3.so.0:libxcb-dri3.so"
  "libxcb-present.so.0:libxcb-present.so"
  "libxcb-randr.so.0:libxcb-randr.so"
  "libxcb-shm.so.0:libxcb-shm.so"
  "libxcb-sync.so.1:libxcb-sync.so"
  "libxcb-xfixes.so.0:libxcb-xfixes.so"
  "libxshmfence.so.1:libxshmfence.so"
)
for entry in "${wsi_links[@]}"; do
  link_name="${entry%%:*}"
  target_name="${entry##*:}"
  if [ -e "$PREFIX_DIR/lib/$target_name" ]; then
    ln -sf "../$target_name" "$WSI_DIR/$link_name"
  fi
done

patchelf --set-rpath "$WSI_DIR:$PREFIX_DIR/lib" "$LIB_PATH"

cat > "$ICD_PATH" <<EOF
{
    "ICD": {
        "api_version": "1.4.363",
        "library_arch": "64",
        "library_path": "${LIB_PATH}"
    },
    "file_format_version": "1.0.1"
}
EOF

echo "[+] Configured PanVK WSI symlinks ($WSI_DIR) and ICD ($ICD_PATH)"
