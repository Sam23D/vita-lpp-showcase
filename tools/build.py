#!/usr/bin/env python3
"""Package the showcase as a Vita .vpk — no VitaSDK needed.

lpp-vita ships prebuilt interpreters (eboot.bin). A VPK is just a ZIP with:
    eboot.bin                      <- the lpp-vita interpreter (safe or unsafe build)
    sce_sys/param.sfo              <- title, TITLE_ID, version (written by tools/sfo.py)
    sce_sys/icon0.png              <- 128x128 8-bit indexed PNG
    sce_sys/livearea/contents/...  <- bg.png, startup.png, template.xml
    index.lua                      <- your Lua code, run by the interpreter
    + any other files (lib/, scenes/, assets/)

Usage:
    tools/build.py                 # safe eboot  -> dist/lpp-showcase.vpk
    tools/build.py --unsafe        # unsafe eboot -> dist/lpp-showcase-unsafe.vpk
    tools/build.py --stage-only    # only build/stage_<mode>/ (used by the mock runner)

The interpreter is downloaded once from the lpp-vita "Nightly" GitHub release into
.cache/ and verified against the SHA-256 recorded below.
"""
import argparse
import hashlib
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from sfo import build_sfo, parse_sfo  # noqa: E402

TITLE = "Hello Vita (lpp showcase)"
STITLE = "lpp showcase"
TITLE_ID = "LPPS00001"  # 4 letters + 5 digits; must be unique on the console
VERSION = "01.00"

RELEASE = "https://github.com/Rinnegatamante/lpp-vita/releases/download/Nightly/"
EBOOTS = {
    # Nightly assets as of 2025-12-18 (commit "Fix: Security: entry.prefix ... oob read (#82)")
    "safe": ("eboot_safe.bin", "6ab6a6e39d32143a4e031d7072090dc34786be91e11e8f5d5edd75c098489930"),
    "unsafe": ("eboot_unsafe.bin", "07243f1b50fefe999f463104565e617517a129454197b7c82e18b3edaa3cba21"),
}


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def fetch_eboot(mode: str, allow_new: bool) -> Path:
    name, want = EBOOTS[mode]
    cache = ROOT / ".cache" / name
    cache.parent.mkdir(exist_ok=True)
    if not cache.exists():
        print(f"  downloading {name} ...")
        urllib.request.urlretrieve(RELEASE + name, cache)
    got = sha256(cache)
    if got != want:
        msg = f"{name}: sha256 {got} != pinned {want} (the Nightly release was updated)"
        if not allow_new:
            sys.exit(msg + "\n  re-run with --allow-new-eboot to accept it, then update EBOOTS in tools/build.py")
        print("  WARNING " + msg)
    return cache


def stage(mode: str, allow_new: bool) -> Path:
    if not (ROOT / "app" / "assets" / "audio" / "melody.ogg").exists():
        print("  assets missing -> running tools/make_assets.py")
        subprocess.run([sys.executable, str(ROOT / "tools" / "make_assets.py")], check=True)
    out = ROOT / "build" / f"stage_{mode}"
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(ROOT / "app", out)
    shutil.copy(fetch_eboot(mode, allow_new), out / "eboot.bin")
    title = TITLE if mode == "safe" else TITLE + " [unsafe]"
    sfo = build_sfo({
        "TITLE": ("str", title),
        "STITLE": ("str", STITLE),
        "TITLE_ID": ("str", TITLE_ID),
        "APP_VER": ("str", VERSION),
    })
    (out / "sce_sys" / "param.sfo").write_bytes(sfo)
    meta = parse_sfo(sfo)
    assert meta["TITLE_ID"] == TITLE_ID and meta["TITLE"] == title
    return out


def make_vpk(staged: Path, mode: str) -> Path:
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    vpk = dist / ("lpp-showcase.vpk" if mode == "safe" else "lpp-showcase-unsafe.vpk")
    if vpk.exists():
        vpk.unlink()
    files = sorted(p for p in staged.rglob("*") if p.is_file())
    with zipfile.ZipFile(vpk, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in files:
            rel = f.relative_to(staged).as_posix()
            # already-compressed media is stored, everything else deflated
            ctype = zipfile.ZIP_STORED if f.suffix in {".mp4", ".ogg", ".mp3", ".png", ".jpg", ".gif"} else zipfile.ZIP_DEFLATED
            z.write(f, rel, compress_type=ctype)
    # sanity: the four files VitaShell insists on
    with zipfile.ZipFile(vpk) as z:
        names = set(z.namelist())
        for req in ["eboot.bin", "sce_sys/param.sfo", "sce_sys/icon0.png", "sce_sys/livearea/contents/template.xml", "index.lua"]:
            assert req in names, f"VPK is missing {req}"
        assert z.testzip() is None
    return vpk


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--unsafe", action="store_true", help="use eboot_unsafe.bin (Registry, plugins, app install, ...)")
    ap.add_argument("--stage-only", action="store_true")
    ap.add_argument("--allow-new-eboot", action="store_true")
    a = ap.parse_args()
    mode = "unsafe" if a.unsafe else "safe"
    staged = stage(mode, a.allow_new_eboot)
    print(f"  staged  {staged.relative_to(ROOT)}  ({sum(1 for p in staged.rglob('*') if p.is_file())} files)")
    if a.stage_only:
        return
    vpk = make_vpk(staged, mode)
    print(f"  vpk     {vpk.relative_to(ROOT)}  {vpk.stat().st_size / 1024 / 1024:.1f} MiB  sha256 {sha256(vpk)[:16]}...")


if __name__ == "__main__":
    main()
