#!/usr/bin/env bash
# Install the showcase into Vita3K's virtual filesystem and boot it.
#   tools/emu.sh                  safe build, you drive it
#   tools/emu.sh --unsafe         unsafe build
#   tools/emu.sh --autotest       the app drives itself through every scene, logs each
#                                 step ("AUTOTEST ...") and exits; full log in build/emu.log
# Vita3K (Qt build) ignores a .vpk on the command line, so we extract the VPK into
# vita_fs/ux0/app/<TITLE_ID>/ ourselves and start it with -r <TITLE_ID>.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=safe; AUTOTEST=0
for a in "$@"; do
  case "$a" in
    --unsafe) MODE=unsafe ;;
    --autotest) AUTOTEST=1 ;;
  esac
done
VPK=dist/lpp-showcase.vpk; [[ $MODE == unsafe ]] && VPK=dist/lpp-showcase-unsafe.vpk
TITLE_ID=LPPS00001
V3K="${VITA3K:-$HOME/.local/opt/vita3k/Vita3K-x86_64.AppImage}"
FS="${VITA3K_FS:-$HOME/.local/share/Vita3K/Vita3K}"

if [[ ! -x "$V3K" ]]; then
  echo "Vita3K not found at $V3K"
  echo "  mkdir -p ~/.local/opt/vita3k && cd ~/.local/opt/vita3k && \\"
  echo "  gh release download continuous -R Vita3K/Vita3K -p 'Vita3K-x86_64.AppImage' && chmod +x Vita3K-x86_64.AppImage"
  exit 1
fi

python3 tools/build.py $([[ $MODE == unsafe ]] && echo --unsafe)
rm -rf "$FS/ux0/app/$TITLE_ID"
mkdir -p "$FS/ux0/app/$TITLE_ID" "$FS/ux0/data/lpp-showcase"
unzip -o -q "$VPK" -d "$FS/ux0/app/$TITLE_ID"
echo "  installed $VPK -> $FS/ux0/app/$TITLE_ID"

rm -f "$FS/ux0/data/lpp-showcase/autotest" "$FS/ux0/data/lpp-showcase/autotest_done"
if [[ $AUTOTEST == 1 ]]; then
  touch "$FS/ux0/data/lpp-showcase/autotest"
  echo "  autotest on: screenshots -> $FS/ux0/data/lpp-showcase/shots/"
fi

# Qt's Wayland plugin is not bundled in the AppImage; XWayland works everywhere.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
mkdir -p build
set +e
"$V3K" -r "$TITLE_ID" > build/emu.log 2>&1 &
pid=$!
tail -n +1 -f build/emu.log --pid=$pid | grep --line-buffered -E "AUTOTEST|\[lpp-showcase\]|\|C\|"
wait $pid; rc=$?
rm -f "$FS/ux0/data/lpp-showcase/autotest"
if [[ $AUTOTEST == 1 ]]; then
  if [[ -f "$FS/ux0/data/lpp-showcase/autotest_done" ]]; then
    echo "AUTOTEST: completed"
  else
    echo "AUTOTEST: did NOT complete (Vita3K exit $rc). Last steps:"
    grep AUTOTEST build/emu.log | tail -5
  fi
fi
exit $rc
