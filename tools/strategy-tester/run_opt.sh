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

if tasklist //FI "IMAGENAME eq terminal64.exe" 2>/dev/null | grep -q terminal64; then
    echo "[ERROR] terminal64.exe already running — close it first" >&2
    exit 1
fi

echo "Launching optimization: $NAME (this can run a long time)"
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    "$TERMINAL" "/config:$(cygpath -w "$MERGED")"
echo "Optimization run finished: $NAME"
echo "Report: $DATADIR/$(grep -oP '^Report=\K.*' "$INI" | tr -d '\r').htm (plus .xml opt results if produced)"
