#!/usr/bin/env bash
# ============================================================
#  Hydra — automated Strategy Tester runs (cross-platform)
#
#  * Windows Git Bash / MINGW64: drives the native terminal64.exe
#    directly. Auto-detects the repo-as-data-folder layout
#    (terminal64.exe + MQL5\ in the repo root, e.g. D:\Straddle_Grid).
#    Override with:  TERMINAL=/d/path/terminal64.exe DATADIR=/d/path ./run_tests.sh
#
#  * macOS: the official MT5 is a Wine wrapper. The script finds the
#    wrapped terminal64.exe, copies presets/configs into "drive_c",
#    and launches one headless test per config.
#
#  If MT5 lives in a Parallels/VMware Windows VM, use run_tests.bat
#  inside the VM instead.
# ============================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

fail() { echo "[ERROR] $*" >&2; exit 1; }

convert_set_utf16() {   # $1 = src.set  $2 = dest.set
    # MT5 expects .set preset files in UTF-16LE (with BOM); a plain
    # UTF-8 file is silently ignored and the run falls back to defaults.
    { printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE "$1"; } > "$2"
}

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
    Darwin)               PLATFORM=mac ;;
    *) fail "Unsupported OS: $(uname -s). Use run_tests.bat on plain Windows." ;;
esac

# ============================================================
#  Windows (Git Bash) — native terminal64.exe
# ============================================================
if [ "$PLATFORM" = windows ]; then
    # Data folder: the repo root itself when MT5 runs portable from it
    # (MQL5\ lives next to terminal64.exe), else set DATADIR=... manually.
    DATADIR="${DATADIR:-}"
    if [ -z "$DATADIR" ] && [ -d "$REPO_ROOT/MQL5/Experts/SIGMA" ]; then
        DATADIR="$REPO_ROOT"
    fi
    [ -n "$DATADIR" ] && [ -d "$DATADIR/MQL5" ] \
        || fail "MT5 data folder not found. Set DATADIR=/d/your/data/folder and rerun.
        (MT5: File -> Open Data Folder shows the path.)"

    # Terminal: portable copy in the data folder first, then default install.
    TERMINAL="${TERMINAL:-}"
    if [ -z "$TERMINAL" ]; then
        for CAND in "$DATADIR/terminal64.exe" \
                    "/c/Program Files/MetaTrader 5/terminal64.exe"; do
            [ -f "$CAND" ] && TERMINAL="$CAND" && break
        done
    fi
    [ -n "$TERMINAL" ] && [ -f "$TERMINAL" ] \
        || fail "terminal64.exe not found. Set TERMINAL=/d/path/to/terminal64.exe and rerun."

    [ -f "$DATADIR/MQL5/Experts/SIGMA/Straddle_Grid.ex5" ] \
        || fail "Compiled EA not found at MQL5/Experts/SIGMA/Straddle_Grid.ex5 — compile in MetaEditor first."

    # /portable keeps the tester writing into DATADIR when the terminal
    # lives inside it (repo-as-data-folder layout).
    PORTABLE=""
    case "$TERMINAL" in
        "$DATADIR"/*) PORTABLE="/portable" ;;
    esac

    echo "Terminal:    $TERMINAL ${PORTABLE:+(portable mode)}"
    echo "Data folder: $DATADIR"
    echo
    echo "Copying presets (UTF-16 conversion) into MQL5/Presets ..."
    mkdir -p "$DATADIR/MQL5/Presets"
    for SET in "$HERE/presets/"*.set; do
        convert_set_utf16 "$SET" "$DATADIR/MQL5/Presets/$(basename "$SET")"
    done

    echo
    echo "NOTE: Close MetaTrader 5 before continuing — a running terminal"
    echo "blocks the headless instances. Each run tests, writes a report, exits."
    echo "First run per date range downloads tick data — be patient."
    read -r -p "Press Enter to start..."

    for INI in "$HERE/configs/"*.ini; do
        NAME="$(basename "$INI")"
        WIN_INI="$(cygpath -w "$INI")"
        echo "------------------------------------------------------------"
        echo "Running $NAME ..."
        # MSYS mangles /flag:path arguments into POSIX paths; suppress that.
        MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
            "$TERMINAL" $PORTABLE "/config:$WIN_INI"
        echo "Finished $NAME"
    done

    echo "------------------------------------------------------------"
    echo "All runs done."
    echo "  Reports:      $DATADIR/Hydra_0*.htm"
    echo "  Tester logs:  $DATADIR/Tester/*/logs/   (the [HYDRA] lines live here)"
    echo "Send both back for verification."
    exit 0
fi

# ============================================================
#  macOS — official MT5 (Wine wrapper)
# ============================================================
# --- Adjust only if your install is non-standard -------------
MT5_APP="${MT5_APP:-/Applications/MetaTrader 5.app}"
WINEPREFIX_DIR="${WINEPREFIX_DIR:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
# --------------------------------------------------------------

DRIVE_C="$WINEPREFIX_DIR/drive_c"
MT5_DIR_C="$DRIVE_C/Program Files/MetaTrader 5"
DATA_DIR="$MT5_DIR_C"          # Mac build runs portable: data folder = install folder

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
for SET in "$HERE/presets/"*.set; do
    convert_set_utf16 "$SET" "$DATA_DIR/MQL5/Presets/$(basename "$SET")"
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
