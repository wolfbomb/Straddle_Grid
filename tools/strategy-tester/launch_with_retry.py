#!/usr/bin/env python3
"""Launch one MT5 config, retrying through single-instance-lock collisions
with a rapid-firing sibling session (observed 2026-07-19: subprocess.run()
returns almost instantly with exit code 0 and NO report when our launch
loses the race to another instance already holding the lock - MT5 logs
"terminal process already started" and no-ops rather than erroring)."""
import os
import sys
import time
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_sweep as es

ini_path = sys.argv[1]
report_name = sys.argv[2]
htm_path = os.path.join(es.DATADIR, f"{report_name}.htm")
max_attempts = 20

for attempt in range(1, max_attempts + 1):
    if es.terminal_running():
        print(f"[RETRY] attempt {attempt}: terminal busy, waiting...")
        time.sleep(4)
        continue
    t0 = time.time()
    subprocess.run([es.TERMINAL, f"/config:{ini_path}"])
    elapsed = time.time() - t0
    if os.path.exists(htm_path):
        print(f"[RETRY] success on attempt {attempt} ({elapsed:.0f}s)")
        sys.exit(0)
    print(f"[RETRY] attempt {attempt}: no report after {elapsed:.0f}s (lock collision or no-history) - retrying")
    time.sleep(3)

print(f"[RETRY] FAILED after {max_attempts} attempts")
sys.exit(1)
