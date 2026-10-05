#!/usr/bin/env bash
# Minimal lpp-vita repro app (TITLE_ID LPPT00001) for isolating Vita3K crashes.
#   tools/repro.sh path/to/index.lua [seconds]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$1"; SECS="${2:-60}"
FS="${VITA3K_FS:-$HOME/.local/share/Vita3K/Vita3K}"
V3K="${VITA3K:-$HOME/.local/opt/vita3k/Vita3K-x86_64.AppImage}"
T="$FS/ux0/app/LPPT00001"
mkdir -p "$T/sce_sys/livearea/contents" "$T/assets"
cp "$ROOT/build/stage_safe/eboot.bin" "$T/eboot.bin"
cp -r "$ROOT/app/sce_sys/." "$T/sce_sys/"
cp -r "$ROOT/app/assets/fonts" "$ROOT/app/assets/img" "$T/assets/"
python3 - "$T" "$ROOT" <<'EOF'
import sys; sys.path.insert(0, sys.argv[2] + "/tools")
from sfo import build_sfo
open(sys.argv[1] + "/sce_sys/param.sfo", "wb").write(build_sfo({"TITLE": ("str", "lpp repro"), "STITLE": ("str", "lpp repro"), "TITLE_ID": ("str", "LPPT00001"), "APP_VER": ("str", "01.00")}))
EOF
cp "$SRC" "$T/index.lua"; [ -n "${VARIANT:-}" ] && echo "$VARIANT" > "$T/variant.txt"
mkdir -p "$ROOT/build"
QT_QPA_PLATFORM=xcb timeout "$SECS" "$V3K" -r LPPT00001 > "$ROOT/build/repro.log" 2>&1 || true
grep -E "REPRO|\|C\|" "$ROOT/build/repro.log" | sed 's/^\[[0-9:.]*\] |.| \[[a-z_A-Z]*\]: //' | head -40
