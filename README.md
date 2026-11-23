# termux-swayfx-panvk

Patched **wlroots `0.20.2`**, **SceneFX `0.5.0`**, and **SwayFX `0.6.1`** for **Termux (Android ARM64)** with hardware-accelerated **Zink / PanVK GLES2** support on Mali GPUs (tested on Mali-G68 MC5), plus PanVK ICD/WSI installer and `gpu` launcher.

## Why these patches exist

1. **No DRI3 DRM render node on Termux:** Stock `wlroots` / `scenefx` GLES2 renderers only advertise `WLR_BUFFER_CAP_DMABUF`, causing `Failed to create allocator` on Termux X11 (`WLR_BUFFER_CAP_SHM`) and headless outputs.
2. **PanVK + Zink DMA-BUF export crash:** On Mesa Zink + `panvk-kbase`, importing AHB DMA-BUFs into FBOs crashes in `libgallium` (`zink_batch.c`) due to missing `SYNC_FD` semaphore export.
3. **Solution (`WLR_BUFFER_CAP_DATA_PTR` + `WLR_GLES2_NO_DMABUF=1`):**
   - Renders into regular GPU `GL_TEXTURE_2D` FBOs on PanVK/Zink and reads back to the output buffer via `glReadPixels(GL_BGRA_EXT)` / `GL_RGBA` on `submit()`.
   - Keeps SceneFX's internal `fx_offscreen_buffers` (blur/effects/saved pixels) purely on GPU (`skip_readback` + `fx_framebuffer_try_get` fast-path) with zero CPU round-trips.
   - Installs cleanly into `~/.local` without overwriting `dpkg`-managed `$PREFIX` packages.

## Quick Install (Prebuilt Release)

Install runtime packages in Termux:

```sh
pkg install x11-repo tur-repo -y
pkg install sway swaybg xwayland mesa mesa-demos vulkan-loader-generic vulkan-tools patchelf curl -y
```

Install PanVK ICD + X11 WSI symlinks:

```sh
curl -fsSL https://raw.githubusercontent.com/daz-9/termux-swayfx-panvk/main/scripts/install-panvk.sh | bash
```

Install prebuilt SwayFX + SceneFX + patched wlroots into `~/.local`:

```sh
curl -fsSL https://raw.githubusercontent.com/daz-9/termux-swayfx-panvk/main/scripts/install-release.sh | bash
```

## Build Locally on Termux

```sh
git clone https://github.com/daz-9/termux-swayfx-panvk
cd termux-swayfx-panvk
./scripts/build-local.sh
```

## Usage

```sh
# Check Vulkan (PanVK) + OpenGL (Zink)
gpu --check

# Run SwayFX on Termux:X11 with Zink/PanVK GLES2
WLR_BACKENDS=x11 WLR_RENDERER=gles2 WLR_GLES2_NO_DMABUF=1 \
  GALLIUM_DRIVER=zink \
  VK_DRIVER_FILES="$PREFIX/share/vulkan/icd.d/panfrost_icd.aarch64.json" \
  ~/.local/bin/swayfx -c ~/.config/swayfx/config
```

## Layout

```text
termux-swayfx-panvk/
├── bin/gpu                            # PanVK + Zink launcher (--check, --virgl)
├── scripts/
│   ├── install-panvk.sh               # PanVK ICD + panvk-wsi symlinks + patchelf
│   ├── install-release.sh             # Downloads verified GitHub Release tarball -> ~/.local
│   ├── build-local.sh                 # On-device Termux source build
│   └── ci/fetch-termux-sysroot.py     # Termux aarch64 sysroot fetcher for GitHub Actions
├── patches/
│   ├── wlroots/                       # Termux 0001..0005 + termuxgui-src + 0007-gles2-data-ptr-zink.patch
│   ├── scenefx/                       # 0001-fx-renderer-data-ptr-zink.patch
│   └── swayfx/                        # 0001-termux-compat.patch
└── .github/workflows/build-release.yml
```
