#!/usr/bin/env python3
"""
Real-tick entry-side sweep for Hydra on BTCUSD: session windows x
GridSpacingUSD. BTC-specific sibling of entry_sweep.py (see that file's
docstring for why this exists: MT5's native optimizer can't sweep the
string-typed Session1/Session2 inputs, and docs/OPT_REPORT.md's whole
campaign established that only real-tick (Model=4) results are trustworthy
for this EA - no OHLC-model shortcuts).

BASE["BasketTP_USD"]/["BasketSL_USD"] = 6.0/2.0, the Sweep-1
(hydra_opt_04_btcusd_exits) candidate that survived out-of-sample validation
(hydra_opt_06_btcusd_validate_B: +$379.80/PF 1.046 training -> +$26.46/PF 1.01
held-out - weak, but held its sign). The raw sweep argmax (TP=3/SL=8,
+$487.67 training) was REJECTED: it flipped to -$48.56 out-of-sample,
confirming it was an isolated-spike noise artifact, not a real effect -
exactly the trap docs/OPT_REPORT.md's Sweep 01 fell into with the OHLC model,
here caught instead by held-out data with no model-risk excuse available.

Includes an "always" session variant (00:00-23:59 both windows) alongside the
gold sweep's three variants: BTC trades 24/7 with no natural session open the
way FX/gold has, so "no session restriction at all" is a hypothesis worth its
own real-tick data point here specifically (gold's sweep had no reason to
test it).

Training window matches Sweep 1 (hydra_opt_04_btcusd_exits.ini):
2026.02.01-2026.06.01, leaving 2026.06.01-2026.07.18 held out for validation.

Usage: python entry_sweep_btc.py
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
FROM_DATE, TO_DATE = "2026.02.01", "2026.06.01"   # same training window as Sweep 1

BASE = {
    "AUTO_TRADING_ENABLED": "true", "MagicNumber": "20260713", "GridLevels": "9",
    "GridSpacingUSD": "45.0", "FirstLevelOffsetUSD": "35.0",
    "LotProgressionCSV": "0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05",
    "OCO_Mode": "true", "GridTTLMin": "45",
    # Sweep 1 validated candidate (see module docstring):
    "BasketTP_USD": "6.0", "BasketSL_USD": "2.0",
    "TrailActivate_USD": "3.0", "TrailDistance_USD": "1.5",
    "Session1": "07:00-10:00", "Session2": "12:00-15:00",
    "ATR_Min_USD": "40.0", "ATR_Max_USD": "250.0", "MaxSpreadPoints": "3000",
    "MinMarginLevelPct": "500.0", "MaxDailyLossPct": "3.0",
    "WhipsawWindowSec": "300", "WhipsawCooldownMin": "60", "MaxWhipsawsPerDay": "2",
    "DashSelfTest": "false",
}

SESSIONS = {
    "ctrl":   ("07:00-10:00", "12:00-15:00"),   # London/NY opens (gold's default windows)
    "narrow": ("07:00-08:00", "12:00-13:00"),   # just the opening hour
    "open30": ("07:00-07:30", "12:00-12:30"),   # just the first 30 min post-open
    "always": ("00:00-23:59", "00:00-23:59"),   # no session restriction - BTC-specific hypothesis
}
SPACINGS = ["40.0", "45.0", "60.0"]   # 45 = first-pass; 40 near gate-3's theoretical floor

GRID = [
    {"label": f"btc_entry_{sname}_sp{sp.replace('.', '')}",
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
Symbol=BTCUSD
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
    tester += "\n".join(f"{k}={v}" for k, v in params.items()) + "\n"
    with open(path, "w") as f:
        f.write(common + "\n" + tester)


def terminal_running():
    # Filter by exact install path - see run_opt.sh / capture_window.ps1
    # comments: a name-only check false-blocks on unrelated sibling-project
    # MT5 installs (D:\MT5_Live_Demo, D:\MT5_NAS100_v2) also named terminal64.exe.
    ps_cmd = ("(Get-CimInstance Win32_Process -Filter \"Name='terminal64.exe'\" | "
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
    print(f"[SWEEP] {len(GRID)} real-tick passes on BTCUSD, window {FROM_DATE}-{TO_DATE}")
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

    out_csv = os.path.join(HERE, "..", "..", "docs", "opt", "btc_entry_sweep_results.csv")
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
