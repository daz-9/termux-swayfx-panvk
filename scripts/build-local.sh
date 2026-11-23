#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
LOCAL_PREFIX="${HOME}/.local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_ROOT="$REPO_ROOT/patches"
BUILD_ROOT="${SWAYFX_BUILD_DIR:-$HOME/src/swayfx-panvk}"

WLROOTS_VER="0.20.2"
WLROOTS_URL="https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/${WLROOTS_VER}/wlroots-${WLROOTS_VER}.tar.bz2"
WLROOTS_SHA256="20c37b521dc3054b6e9627b79bdd45fc716db9ebc58bdf97e57e84d04b04610f"
SCENEFX_COMMIT="6a7c568bd7dbdac4b2b92d6b9fa73881c603d665"
SWAYFX_TAG="0.6.1"

export PATH="$LOCAL_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:$PREFIX_DIR/lib/pkgconfig"

for cmd in curl git ninja patch patchelf pkg-config sha256sum tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[-] Required build tool not found: $cmd" >&2
    exit 1
  fi
done

if ! command -v meson >/dev/null 2>&1; then
  echo "[*] meson not found; installing via pip --user..."
  python3 -m pip install --user meson
fi

mkdir -p "$BUILD_ROOT" "$LOCAL_PREFIX/bin" "$LOCAL_PREFIX/lib"

echo "=== [1/3] Building patched wlroots ${WLROOTS_VER} ==="
WLROOTS_TAR="$BUILD_ROOT/wlroots-${WLROOTS_VER}.tar.bz2"
if [ ! -f "$WLROOTS_TAR" ]; then
  curl -fL --retry 3 "$WLROOTS_URL" -o "$WLROOTS_TAR"
fi
actual_sha="$(sha256sum "$WLROOTS_TAR" | awk '{ print $1 }')"
if [ "$actual_sha" != "$WLROOTS_SHA256" ]; then
  echo "[-] wlroots tarball SHA-256 mismatch: expected $WLROOTS_SHA256, got $actual_sha" >&2
  exit 1
fi

WLROOTS_SRC="$BUILD_ROOT/wlroots-${WLROOTS_VER}"
rm -rf "$WLROOTS_SRC"
tar -xjf "$WLROOTS_TAR" -C "$BUILD_ROOT"
cp -r "$PATCH_ROOT/wlroots/termuxgui-src/"* "$WLROOTS_SRC/"
for p in "$PATCH_ROOT/wlroots/"*.patch; do
  echo "[*] Applying $(basename "$p")..."
  patch -d "$WLROOTS_SRC" -p1 < "$p"
done

meson setup "$WLROOTS_SRC/build" "$WLROOTS_SRC" \
  --prefix="$LOCAL_PREFIX" \
  --libdir="lib" \
  -Dbuildtype=release \
  -Dexamples=false \
  -Dxwayland=enabled \
  -Dsession=disabled \
  -Dbackends=x11,termuxgui \
  -Drenderers=gles2 \
  -Dc_args="-Wno-alloca -Wno-strict-prototypes" \
  -Dc_link_args="-Wl,-rpath,$LOCAL_PREFIX/lib -Wl,-rpath,$PREFIX_DIR/lib"
ninja -C "$WLROOTS_SRC/build"
ninja -C "$WLROOTS_SRC/build" install

echo "=== [2/3] Building patched scenefx (${SCENEFX_COMMIT:0:7}) ==="
SCENEFX_SRC="$BUILD_ROOT/scenefx"
rm -rf "$SCENEFX_SRC"
git clone https://github.com/wlrfx/scenefx.git "$SCENEFX_SRC"
git -C "$SCENEFX_SRC" checkout "$SCENEFX_COMMIT"
for p in "$PATCH_ROOT/scenefx/"*.patch; do
  echo "[*] Applying $(basename "$p")..."
  patch -d "$SCENEFX_SRC" -p1 < "$p"
done

meson setup "$SCENEFX_SRC/build" "$SCENEFX_SRC" \
  --prefix="$LOCAL_PREFIX" \
  --libdir="lib" \
  -Dbuildtype=release \
  -Dexamples=false \
  -Drenderers=gles2 \
  -Dc_args="-Wno-alloca -Wno-strict-prototypes -Wno-unused-function" \
  -Dc_link_args="-Wl,-rpath,$LOCAL_PREFIX/lib -Wl,-rpath,$PREFIX_DIR/lib"
ninja -C "$SCENEFX_SRC/build"
ninja -C "$SCENEFX_SRC/build" install
patchelf --set-rpath "$LOCAL_PREFIX/lib:$PREFIX_DIR/lib" "$LOCAL_PREFIX/lib/libscenefx-0.5.so"

echo "=== [3/3] Building patched swayfx ${SWAYFX_TAG} ==="
SWAYFX_SRC="$BUILD_ROOT/swayfx"
rm -rf "$SWAYFX_SRC"
git clone --depth 1 --branch "$SWAYFX_TAG" https://github.com/WillPower3309/swayfx.git "$SWAYFX_SRC"
for p in "$PATCH_ROOT/swayfx/"*.patch; do
  echo "[*] Applying $(basename "$p")..."
  patch -d "$SWAYFX_SRC" -p1 < "$p"
done

meson setup "$SWAYFX_SRC/build" "$SWAYFX_SRC" \
  --prefix="$LOCAL_PREFIX" \
  --libdir="lib" \
  --sysconfdir="$PREFIX_DIR/etc" \
  -Dbuildtype=release \
  -Dman-pages=disabled \
  -Dtray=disabled \
  -Ddefault-wallpaper=false \
  -Dc_args="-Wno-alloca -Wno-deprecated-declarations -Wno-unused-function" \
  -Dc_link_args="-landroid-wordexp -Wl,-rpath,$LOCAL_PREFIX/lib -Wl,-rpath,$PREFIX_DIR/lib"
ninja -C "$SWAYFX_SRC/build" sway/sway
install -m 0755 "$SWAYFX_SRC/build/sway/sway" "$LOCAL_PREFIX/bin/swayfx"
install -m 0755 "$REPO_ROOT/bin/gpu" "$LOCAL_PREFIX/bin/gpu"
patchelf --set-rpath "$LOCAL_PREFIX/lib:$PREFIX_DIR/lib" "$LOCAL_PREFIX/bin/swayfx"

echo "[+] Installed patched libwlroots-0.20.so, libscenefx-0.5.so, $LOCAL_PREFIX/bin/swayfx, and $LOCAL_PREFIX/bin/gpu"
