#!/usr/bin/env bash
# Waits until OUR specific MT5 install/data-folder is free (checked via
# ExecutablePath, not bare process name - other unrelated MT5 installs on
# this machine also run as terminal64.exe and don't actually conflict),
# then runs entry_sweep.py. See entry_sweep.py's terminal_running() for
# the same check reused between sweep passes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

is_free() {
    python -c "import entry_sweep as es; import sys; sys.exit(0 if not es.terminal_running() else 1)"
}

until is_free; do
    sleep 5
done
echo "[SWEEP] our install is free, starting sweep"
python entry_sweep.py
