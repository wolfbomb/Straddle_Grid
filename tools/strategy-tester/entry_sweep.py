#!/usr/bin/env python3
"""
Real-tick entry-side sweep for Hydra: session windows x GridSpacingUSD.

Why this exists: MT5's native optimizer only sweeps numeric inputs, not the
string-typed Session1/Session2 windows, and the OHLC-model sweep in
docs/OPT_REPORT.md (exit tuning) already proved that a fast optimization
grid is worthless here unless every candidate is confirmed with Model=4
real ticks. This script runs one full real-tick pass per combination
(~7 min each, based on the two exit-sweep validation runs on the same
window) and parses each .htm report directly - no native optimizer
involved, so string inputs are fair game.

Base parameters come from presets/hydra_05_phase7_campaign.set (the proven
production-default preset); each combination overrides only the keys named
in its dict. Usage: python entry_sweep.py
"""

import os
import re
import subprocess
import time
import csv

HERE = os.path.dirname(os.path.abspath(__file__))
DATADIR = r"C:\Users\nimrod.resulta\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
TERMINAL = r"C:\Program Files\MetaTrader 5\terminal64.exe"
COMMON_INI = os.path.join(HERE, "configs", "common.local.ini")
FROM_DATE, TO_DATE = "2026.04.01", "2026.07.10"   # same window as run 05 / the exit sweep

BASE = {
    "AUTO_TRADING_ENABLED": "true", "MagicNumber": "20260713", "GridLevels": "9",
    "GridSpacingUSD": "0.70", "FirstLevelOffsetUSD": "0.50",
    "LotProgressionCSV": "0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05",
    "OCO_Mode": "true", "GridTTLMin": "45",
    "BasketTP_USD": "15.0", "BasketSL_USD": "10.0",
    "TrailActivate_USD": "8.0", "TrailDistance_USD": "4.0",
    "Session1": "07:00-10:00", "Session2": "12:00-15:00",
    "ATR_Min_USD": "1.5", "ATR_Max_USD": "8.0", "MaxSpreadPoints": "35",
    "MinMarginLevelPct": "500.0", "MaxDailyLossPct": "3.0",
    "WhipsawWindowSec": "300", "WhipsawCooldownMin": "60", "MaxWhipsawsPerDay": "2",
    "DashSelfTest": "false",
}

SESSIONS = {
    "ctrl":   ("07:00-10:00", "12:00-15:00"),   # current production default
    "narrow": ("07:00-08:00", "12:00-13:00"),   # just the opening hour
    "open30": ("07:00-07:30", "12:00-12:30"),   # just the first 30 min post-open
}
SPACINGS = ["0.70", "1.00", "1.40"]   # 0.70 = current; wider only (gate 3 floor ~0.60-0.65)

GRID = [
    {"label": f"entry_{sname}_sp{sp.replace('.', '')}",
     "Session1": s1, "Session2": s2, "GridSpacingUSD": sp}
    for sname, (s1, s2) in SESSIONS.items()
    for sp in SPACINGS
]


def write_set(path, params):
    with open(path, "w", encoding="utf-16") as f:
        for k, v in params.items():
            f.write(f"{k}={v}\n")


def write_ini(path, label, set_name, params):
    with open(COMMON_INI) as f:
        common = f.read()
    tester = f"""
[Tester]
Expert=Straddle\\Straddle_Grid
ExpertParameters={set_name}
Symbol=XAUUSD-VIP
Period=M1
Model=4
Optimization=0
FromDate={FROM_DATE}
ToDate={TO_DATE}
ForwardMode=0
Deposit=10000
Currency=USD
Leverage=500
Visual=0
Report={label}
ReplaceReport=1
ShutdownTerminal=1
UseLocal=1

[TesterInputs]
"""
    # Belt-and-suspenders (matches every other config in this repo): on this
    # MT5 build, ExpertParameters=.set alone was found unreliable on its own
    # (confirmed 2026-07-18 - a sweep pass silently ran on compiled defaults,
    # AUTO_TRADING_ENABLED=false, with no [TesterInputs] section present).
    tester += "\n".join(f"{k}={v}" for k, v in params.items()) + "\n"
    with open(path, "w") as f:
        f.write(common + "\n" + tester)


def terminal_running():
    # Filter by exact install path, not bare process name: other unrelated
    # MT5 installs on this machine (e.g. D:\MT5_Demo_NAS100, D:\MT5_Live_Demo)
    # also run as "terminal64.exe" and don't conflict with our data folder's
    # single-instance lock - a name-only check false-blocks on them (found
    # 2026-07-18, cost ~5.5h waiting on an unrelated stuck process).
    # @(...) forces array semantics: Where-Object returns a bare object (no
    # .Count) rather than a 1-element array when exactly one match exists -
    # without it, a single running instance silently reports as "free"
    # (found 2026-07-19 after 20 failed launch retries against a genuinely
    # running sibling instance).
    ps_cmd = ("@(Get-CimInstance Win32_Process -Filter \"Name='terminal64.exe'\" | "
              f"Where-Object {{ $_.ExecutablePath -eq '{TERMINAL}' }}).Count")
    out = subprocess.run(["powershell", "-NoProfile", "-Command", ps_cmd],
                          capture_output=True, text=True).stdout.strip()
    return out != "0" and out != ""


def parse_metric(lines, label):
    for i, ln in enumerate(lines):
        if f">{label}:<" in ln:
            m = re.search(r"<b>([^<]+)</b>", lines[i + 1])
            return m.group(1).strip() if m else None
    return None


def parse_report(htm_path):
    with open(htm_path, encoding="utf-16-le", errors="replace") as f:
        lines = f.readlines()
    return {
        "profit": parse_metric(lines, "Total Net Profit"),
        "pf": parse_metric(lines, "Profit Factor"),
        "eqdd": parse_metric(lines, "Equity Drawdown Maximal"),
        "trades": parse_metric(lines, "Total Trades"),
        "sharpe": parse_metric(lines, "Sharpe Ratio"),
        "gross_profit": parse_metric(lines, "Gross Profit"),
        "gross_loss": parse_metric(lines, "Gross Loss"),
    }


def main():
    print(f"[SWEEP] {len(GRID)} real-tick passes, ~7 min each, "
          f"~{len(GRID) * 7} min total estimate")
    presets_dir = os.path.join(DATADIR, "MQL5", "Presets")
    merged_dir = os.path.join(HERE, ".merged")
    os.makedirs(presets_dir, exist_ok=True)
    os.makedirs(merged_dir, exist_ok=True)

    results = []
    for i, combo in enumerate(GRID, 1):
        label = combo["label"]
        params = dict(BASE)
        params.update({k: v for k, v in combo.items() if k != "label"})
        set_name = f"{label}.set"
        set_path = os.path.join(presets_dir, set_name)
        ini_path = os.path.join(merged_dir, f"{label}.ini")
        write_set(set_path, params)
        write_ini(ini_path, label, set_name, params)

        if terminal_running():
            print(f"[SWEEP] ABORT before pass {i}: terminal64.exe already running")
            return 2

        print(f"[SWEEP] ({i}/{len(GRID)}) {label}: "
              f"Session1={params['Session1']} Session2={params['Session2']} "
              f"GridSpacingUSD={params['GridSpacingUSD']}")
        t0 = time.time()
        subprocess.run([TERMINAL, f"/config:{ini_path}"])
        elapsed = time.time() - t0

        htm_path = os.path.join(DATADIR, f"{label}.htm")
        if not os.path.exists(htm_path):
            print(f"[SWEEP]   no report produced ({elapsed:.0f}s) — skipping")
            continue
        metrics = parse_report(htm_path)
        metrics.update(combo)
        metrics["elapsed_s"] = round(elapsed, 1)
        results.append(metrics)
        print(f"[SWEEP]   done in {elapsed:.0f}s: profit={metrics['profit']} "
              f"pf={metrics['pf']} eqdd={metrics['eqdd']} trades={metrics['trades']}")

    out_csv = os.path.join(HERE, "..", "..", "docs", "opt", "entry_sweep_results.csv")
    os.makedirs(os.path.dirname(out_csv), exist_ok=True)
    fieldnames = ["label", "Session1", "Session2", "GridSpacingUSD",
                  "profit", "pf", "eqdd", "trades", "sharpe", "elapsed_s"]
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in results:
            w.writerow({k: r.get(k) for k in fieldnames})
    print(f"[SWEEP] wrote {len(results)} result(s) to {out_csv}")


if __name__ == "__main__":
    main()
