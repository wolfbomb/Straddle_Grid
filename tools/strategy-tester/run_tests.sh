#!/usr/bin/env bash
# ============================================================
#  Hydra — automated Strategy Tester runs (macOS)
#
#  The official macOS MetaTrader 5 is a Wine wrapper. This script
#  finds the wrapped terminal64.exe, copies the presets/configs into
#  the Wine "drive_c", and launches one headless test per config.
#
#  If your MT5 actually lives in a Windows VM (Parallels/VMware),
#  use run_tests.bat inside the VM instead of this script.
# ============================================================
set -u

# --- Adjust only if your install is non-standard -------------
MT5_APP="${MT5_APP:-/Applications/MetaTrader 5.app}"
WINEPREFIX_DIR="${WINEPREFIX_DIR:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
# --------------------------------------------------------------

HERE="$(cd "$(dirname "$0")" && pwd)"
DRIVE_C="$WINEPREFIX_DIR/drive_c"
MT5_DIR_C="$DRIVE_C/Program Files/MetaTrader 5"
DATA_DIR="$MT5_DIR_C"          # Mac build runs portable: data folder = install folder

fail() { echo "[ERROR] $*" >&2; exit 1; }

[ -d "$MT5_APP" ]        || fail "MetaTrader 5.app not found at: $MT5_APP  (set MT5_APP=... and rerun)"
[ -d "$DRIVE_C" ]        || fail "Wine prefix not found at: $WINEPREFIX_DIR  (set WINEPREFIX_DIR=... and rerun)"
[ -d "$DATA_DIR/MQL5" ]  || fail "MQL5 folder not found under: $DATA_DIR"

if [ ! -f "$DATA_DIR/MQL5/Experts/SIGMA/Straddle_Grid.ex5" ]; then
    echo "[WARN] Compiled EA not found at MQL5/Experts/SIGMA/Straddle_Grid.ex5"
    echo "       Compile Straddle_Grid.mq5 in MetaEditor first."
    exit 1
fi

# Locate the wine loader bundled inside the app (name/path varies by build)
WINE_BIN="$(find "$MT5_APP/Contents" -type f \( -name 'wine64' -o -name 'wine' \) -perm +111 2>/dev/null | head -1)"

echo "Copying presets and configs into the Wine prefix ..."
mkdir -p "$DATA_DIR/MQL5/Presets" "$MT5_DIR_C/hydra_configs"
# MT5 expects .set preset files in UTF-16LE (with BOM); a plain UTF-8
# file is silently ignored and the run falls back to default inputs.
for SET in "$HERE/presets/"*.set; do
    NAME="$(basename "$SET")"
    { printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE "$SET"; } > "$DATA_DIR/MQL5/Presets/$NAME"
done
cp -f "$HERE/configs/"*.ini "$MT5_DIR_C/hydra_configs/"

echo
echo "NOTE: Quit MetaTrader 5 before continuing (Cmd+Q, check the Dock)."
echo "Each run starts its own instance, tests, writes a report, and exits."
echo "First run per date range downloads tick data — be patient."
read -r -p "Press Enter to start..."

for INI in "$HERE/configs/"*.ini; do
    NAME="$(basename "$INI")"
    WIN_CFG="C:\\Program Files\\MetaTrader 5\\hydra_configs\\$NAME"
    echo "------------------------------------------------------------"
    echo "Running $NAME ..."
    # Wine prints copious harmless err:/fixme: diagnostics to stderr;
    # divert them to a log so the terminal shows only real output.
    if [ -n "$WINE_BIN" ]; then
        WINEPREFIX="$WINEPREFIX_DIR" "$WINE_BIN" \
            "C:\\Program Files\\MetaTrader 5\\terminal64.exe" "/config:$WIN_CFG" \
            2>>"$HERE/wine_noise.log"
    else
        # Fallback: launch through the app bundle and pass args through
        open -W -a "$MT5_APP" --args "/config:$WIN_CFG" 2>>"$HERE/wine_noise.log"
    fi
    echo "Finished $NAME"
done

echo "------------------------------------------------------------"
echo "All runs done."
echo "  Reports:      $DATA_DIR/Hydra_0*.htm"
echo "  Tester logs:  $DATA_DIR/Tester/*/logs/   (the [HYDRA] lines live here)"
echo "Send both back for verification."
