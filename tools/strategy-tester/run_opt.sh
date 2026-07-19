#!/usr/bin/env bash
# Launch one Hydra OPTIMIZATION config (configs/opt/*.ini) headlessly.
# Same merge/convert plumbing as run_tests.sh but for the opt configs,
# which are deliberately excluded from the numbered pass/fail suite.
# Usage: ./run_opt.sh hydra_opt_01_exits
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
COMMON_INI="$HERE/configs/common.local.ini"
ENV_LOCAL="$HERE/.env.local"
# shellcheck disable=SC1090
[ -f "$ENV_LOCAL" ] && . "$ENV_LOCAL"
[ -f "$COMMON_INI" ] || { echo "[ERROR] missing $COMMON_INI" >&2; exit 1; }

NAME="${1:?usage: run_opt.sh <config name without .ini>}"
INI="$HERE/configs/opt/$NAME.ini"
[ -f "$INI" ] || { echo "[ERROR] $INI not found" >&2; exit 1; }

DATADIR="${DATADIR:?set DATADIR in .env.local}"
TERMINAL="${TERMINAL:-/c/Program Files/MetaTrader 5/terminal64.exe}"
[ -f "$TERMINAL" ] || { echo "[ERROR] terminal64.exe not found at $TERMINAL" >&2; exit 1; }

# Preset referenced by ExpertParameters= must exist in MQL5\Presets — the
# main runner already converts all presets/ on every run; do the same here.
mkdir -p "$DATADIR/MQL5/Presets"
for SET in "$HERE/presets/"*.set; do
    powershell -NoProfile -Command \
        "Get-Content -Path '$(cygpath -w "$SET")' | Set-Content -Encoding Unicode -Path '$(cygpath -w "$DATADIR/MQL5/Presets/$(basename "$SET")")'"
done

MERGED="$HERE/.merged/$NAME.ini"
mkdir -p "$HERE/.merged"
{ cat "$COMMON_INI"; echo; cat "$INI"; } > "$MERGED"

# Filter by exact install path, not bare process name: other unrelated MT5
# installs on this machine (e.g. D:\MT5_Live_Demo, D:\MT5_NAS100_v2) also run
# as "terminal64.exe" and don't hold our data folder's single-instance lock -
# a name-only check false-blocks on them (same bug class entry_sweep.py's
# terminal_running() was already fixed for; cost ~5.5h once before that fix).
TERMINAL_WIN="$(cygpath -w "$TERMINAL")"
RUNNING_COUNT="$(powershell -NoProfile -Command \
    "(Get-CimInstance Win32_Process -Filter \"Name='terminal64.exe'\" | Where-Object { \$_.ExecutablePath -eq '$TERMINAL_WIN' }).Count" \
    2>/dev/null | tr -d '\r')"
if [ -n "$RUNNING_COUNT" ] && [ "$RUNNING_COUNT" != "0" ]; then
    echo "[ERROR] our terminal64.exe ($TERMINAL_WIN) already running — close it first" >&2
    exit 1
fi

echo "Launching optimization: $NAME (this can run a long time)"
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    "$TERMINAL" "/config:$(cygpath -w "$MERGED")"
echo "Optimization run finished: $NAME"
echo "Report: $DATADIR/$(sed -n 's/^Report=//p' "$INI" | tr -d '\r').htm (plus .xml opt results if produced)"
