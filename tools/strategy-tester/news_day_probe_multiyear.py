#!/usr/bin/env python3
"""
Multi-year extension of news_day_probe.py: the n=4 NFP-only probe
(docs/OPT_REPORT.md, 2026-07-18) found 2 of 4 profitable days - too small a
sample to trust in either direction. This runs the same cheap method (short
independent real-tick backtests bracketing one event day, no EA code
change) across a much bigger sample: NFP days for all of 2024+2025 (computed
by pure calendar rule - first Friday of each month) plus FOMC decision days
for 2024+2025 (the second day of each 2-day meeting, when the rate decision
and press conference actually move markets).

FOMC dates below are recalled from published Federal Reserve meeting
schedules (public record for these past years) - NOT independently
re-verified against an official source in this session. Flagged in the
report; if this probe's results end up mattering for a real decision,
cross-check these dates against federalreserve.gov before trusting them.

2026 NFP days (Apr/May/Jun/Jul) were already covered by news_day_probe.py -
not repeated here; results are merged when reporting.
"""

import os
import sys
import csv
import time
import datetime
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_sweep as es

NFP_YEARS = [2024, 2025]

# Confirmed 2026-07-18 via a direct MT5 history-availability check: real tick
# data for XAUUSD-VIP on this account begins 2024.02.20. Anything before
# that returns "no history data" and aborts the test - filter dates out
# rather than waste a probe (and a stray idle terminal) on each one.
HISTORY_START = datetime.date(2024, 2, 20)

# FOMC decision days (2nd day of each 2-day meeting) - recalled, not
# independently re-verified this session; see module docstring.
FOMC_DATES = {
    2024: ["2024.01.31", "2024.03.20", "2024.05.01", "2024.06.12",
           "2024.07.31", "2024.09.18", "2024.11.07", "2024.12.18"],
    2025: ["2025.01.29", "2025.03.19", "2025.05.07", "2025.06.18",
           "2025.07.30", "2025.09.17", "2025.10.29", "2025.12.10"],
}


def nfp_fridays(year):
    out = []
    for month in range(1, 13):
        d = datetime.date(year, month, 1)
        days_ahead = (4 - d.weekday()) % 7   # Friday = 4 (Mon=0)
        out.append((d + datetime.timedelta(days=days_ahead)).strftime("%Y.%m.%d"))
    return out


def build_day_list():
    days = []
    for year in NFP_YEARS:
        for d in nfp_fridays(year):
            days.append((d, "NFP"))
        for d in FOMC_DATES.get(year, []):
            days.append((d, "FOMC"))
    # Filter anything whose "day before" (the actual FromDate requested)
    # predates confirmed history availability.
    kept = []
    for date_str, kind in days:
        y, m, dd = (int(x) for x in date_str.split("."))
        if datetime.date(y, m, dd) - datetime.timedelta(days=1) >= HISTORY_START:
            kept.append((date_str, kind))
    skipped = len(days) - len(kept)
    if skipped:
        print(f"[MYPROBE] skipped {skipped} date(s) before history start ({HISTORY_START})")
    return kept


def day_before(d):
    y, m, dd = (int(x) for x in d.split("."))
    return (datetime.date(y, m, dd) - datetime.timedelta(days=1)).strftime("%Y.%m.%d")


def day_after(d):
    y, m, dd = (int(x) for x in d.split("."))
    return (datetime.date(y, m, dd) + datetime.timedelta(days=1)).strftime("%Y.%m.%d")


def main():
    day_list = build_day_list()
    print(f"[MYPROBE] {len(day_list)} probes ({sum(1 for _, k in day_list if k=='NFP')} NFP, "
          f"{sum(1 for _, k in day_list if k=='FOMC')} FOMC), production defaults, real ticks")

    presets_dir = os.path.join(es.DATADIR, "MQL5", "Presets")
    merged_dir = os.path.join(es.HERE, ".merged")
    os.makedirs(presets_dir, exist_ok=True)
    os.makedirs(merged_dir, exist_ok=True)

    results = []
    for i, (date_str, kind) in enumerate(day_list, 1):
        label = f"myprobe_{kind.lower()}_{date_str.replace('.', '')}"
        from_date, to_date = day_before(date_str), day_after(date_str)
        params = dict(es.BASE)
        set_name = f"{label}.set"
        set_path = os.path.join(presets_dir, set_name)
        ini_path = os.path.join(merged_dir, f"{label}.ini")
        es.write_set(set_path, params)
        es.FROM_DATE, es.TO_DATE = from_date, to_date
        es.write_ini(ini_path, label, set_name, params)

        if es.terminal_running():
            print(f"[MYPROBE] ABORT before probe {i}: our terminal already running")
            break

        print(f"[MYPROBE] ({i}/{len(day_list)}) {kind} {date_str}: window {from_date}-{to_date}")
        t0 = time.time()
        subprocess.run([es.TERMINAL, f"/config:{ini_path}"])
        elapsed = time.time() - t0

        htm_path = os.path.join(es.DATADIR, f"{label}.htm")
        if not os.path.exists(htm_path):
            print(f"[MYPROBE]   no report produced ({elapsed:.0f}s) - skipping "
                  f"(likely no history for this date)")
            continue
        metrics = es.parse_report(htm_path)
        metrics.update({"date": date_str, "kind": kind, "elapsed_s": round(elapsed, 1)})
        results.append(metrics)
        print(f"[MYPROBE]   done in {elapsed:.0f}s: profit={metrics['profit']} "
              f"pf={metrics['pf']} trades={metrics['trades']}")

        # Clean up as we go - 40 presets/htms left behind would be clutter
        os.remove(set_path)
        os.remove(htm_path)
        os.remove(ini_path)

    out_csv = os.path.join(es.HERE, "..", "..", "docs", "opt", "news_day_probe_multiyear_results.csv")
    fieldnames = ["date", "kind", "profit", "pf", "eqdd", "trades", "sharpe", "elapsed_s"]
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in results:
            w.writerow({k: r.get(k) for k in fieldnames})
    print(f"[MYPROBE] wrote {len(results)}/{len(day_list)} result(s) to {out_csv}")

    def to_float(s):
        try:
            return float(str(s).replace(" ", "").split("(")[0])
        except (TypeError, ValueError):
            return None

    for kind in ("NFP", "FOMC"):
        sub = [r for r in results if r["kind"] == kind]
        profits = [to_float(r["profit"]) for r in sub if to_float(r["profit"]) is not None]
        wins = sum(1 for p in profits if p > 0)
        if profits:
            print(f"[MYPROBE] {kind}: n={len(profits)}, wins={wins} ({100*wins/len(profits):.0f}%), "
                  f"total={sum(profits):.2f}, mean={sum(profits)/len(profits):.2f}")


if __name__ == "__main__":
    main()
