#!/usr/bin/env python3
"""Download and extract Termux aarch64/all .deb packages into / as a cross-compile sysroot."""

import concurrent.futures
import gzip
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

MIRRORS = [
    "https://packages-cf.termux.dev/apt",
    "https://mirror.bouwhuis.network/termux",
]

REPO_SPECS = [
    ("termux-main", "dists/stable/main/binary-aarch64/Packages"),
    ("termux-main", "dists/stable/main/binary-all/Packages"),
    ("termux-x11", "dists/x11/main/binary-aarch64/Packages"),
    ("termux-x11", "dists/x11/main/binary-all/Packages"),
]

ROOT_PACKAGES = [
    "gdk-pixbuf",
    "json-c",
    "libandroid-wordexp",
    "libcairo",
    "libdrm",
    "libevdev",
    "libglvnd",
    "libglvnd-dev",
    "libpixman",
    "libwayland",
    "libwayland-protocols",
    "libxcb",
    "libxkbcommon",
    "littlecms",
    "mesa",
    "mesa-dev",
    "pango",
    "pcre2",
    "termux-gui-c",
    "xcb-util-renderutil",
    "xcb-util-wm",
    "xwayland",
]

# Huge or runtime-only packages unnecessary for C/Meson header & shared-lib linking
SKIP_PACKAGES = {
    "bash",
    "busybox",
    "coreutils",
    "dash",
    "debianutils",
    "diffutils",
    "findutils",
    "gawk",
    "grep",
    "gzip",
    "ncurses",
    "python",
    "perl",
    "sed",
    "tar",
    "termux-tools",
    "xkeyboard-config",
}


def fetch_bytes(rel_path: str) -> bytes:
    last_err: Exception | None = None
    for base in MIRRORS:
        url = f"{base}/{rel_path}"
        req = urllib.request.Request(url, headers={"User-Agent": "termux-swayfx-panvk-ci/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                return resp.read()
        except Exception as e:
            last_err = e
    raise RuntimeError(f"Failed to fetch {rel_path}: {last_err}")


def parse_packages(text: str, repo_name: str, index: dict[str, dict[str, str]]) -> None:
    cur: dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip():
            if "Package" in cur and "Filename" in cur:
                cur["_repo"] = repo_name
                index[cur["Package"]] = cur
            cur = {}
            continue
        if line[0].isspace():
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            cur[k.strip()] = v.strip()
    if "Package" in cur and "Filename" in cur:
        cur["_repo"] = repo_name
        index[cur["Package"]] = cur


def parse_depends(dep_str: str) -> list[str]:
    result: list[str] = []
    if not dep_str:
        return result
    for group in dep_str.split(","):
        first_alt = group.split("|")[0].strip()
        name = re.split(r"[\s(]", first_alt, maxsplit=1)[0].strip()
        if name:
            result.append(name)
    return result


def resolve_closure(index: dict[str, dict[str, str]], roots: list[str]) -> list[dict[str, str]]:
    visited: set[str] = set()
    queue = list(roots)
    resolved: list[dict[str, str]] = []
    while queue:
        pkg = queue.pop(0)
        if pkg in visited or pkg in SKIP_PACKAGES:
            continue
        visited.add(pkg)
        meta = index.get(pkg)
        if meta is None:
            print(f"[!] Package not in index (skipping): {pkg}", file=sys.stderr)
            continue
        resolved.append(meta)
        for dep in parse_depends(meta.get("Depends", "")):
            if dep not in visited and dep not in SKIP_PACKAGES:
                queue.append(dep)
    return resolved


def download_and_verify(meta: dict[str, str], out_dir: str) -> str:
    rel = f"{meta['_repo']}/{meta['Filename']}"
    data = fetch_bytes(rel)
    expected = meta.get("SHA256", "").lower()
    if expected:
        actual = hashlib.sha256(data).hexdigest().lower()
        if actual != expected:
            raise RuntimeError(f"SHA256 mismatch for {meta['Package']}: {actual} != {expected}")
    dest = os.path.join(out_dir, f"{meta['Package']}.deb")
    with open(dest, "wb") as f:
        f.write(data)
    return dest


def main() -> int:
    target_root = sys.argv[1] if len(sys.argv) > 1 else "/"
    index: dict[str, dict[str, str]] = {}

    print("[*] Fetching Termux package indexes...")
    for repo_name, idx_path in REPO_SPECS:
        try:
            raw = fetch_bytes(f"{repo_name}/{idx_path}.gz")
            text = gzip.decompress(raw).decode("utf-8", errors="replace")
        except Exception:
            text = fetch_bytes(f"{repo_name}/{idx_path}").decode("utf-8", errors="replace")
        parse_packages(text, repo_name, index)

    print(f"[+] Indexed {len(index)} packages")
    pkgs = resolve_closure(index, ROOT_PACKAGES)
    print(f"[*] Downloading & extracting {len(pkgs)} Termux sysroot packages into {target_root}...")

    with tempfile.TemporaryDirectory() as tmp:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            debs = list(pool.map(lambda m: download_and_verify(m, tmp), pkgs))
        for deb in sorted(debs):
            subprocess.run(["dpkg-deb", "-x", deb, target_root], check=True)

    print(f"[+] Termux sysroot ready ({len(pkgs)} packages extracted)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
