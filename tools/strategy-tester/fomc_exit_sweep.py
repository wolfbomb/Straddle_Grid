#!/usr/bin/env python3
"""
FOMC-only exit sweep: does tuning BasketTP/SL specifically for FOMC-day
volatility find an edge, given every exit sweep so far (docs/OPT_REPORT.md
Sweep 01) assumed the always-on session trigger and found nothing?

Unlike Sweep 01 (which used the fast OHLC model and needed real-tick
re-validation of the winners), every probe here already runs Model=4 real
ticks - there is no shortcut-model risk to re-validate afterward.

Method: for each (BasketTP_USD, BasketSL_USD) combination, run one short
real-tick probe per FOMC day (reusing the same 15-day FOMC sample from
news_day_probe_multiyear.py, 2024.03-2025.12 - the only real-tick history
this account has), then aggregate: net profit sums directly across days,
and profit factor is recomputed properly from summed Gross Profit / summed
|Gross Loss| across all 15 days for that combination - NOT an average of
per-day ratios, which would be statistically wrong for a ratio metric.

TrailActivate_USD/TrailDistance_USD held at production defaults (8.0/4.0)
to keep the grid size (and runtime: 16 combos x 15 days x ~13s ~= 52 min)
manageable - a 4D grid here would take hours for probes this short.
"""

import os
import sys
import csv
import time
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_sweep as es
import news_day_probe_multiyear as mp

TP_GRID = [10.0, 15.0, 20.0, 25.0]
SL_GRID = [6.0, 8.0, 10.0, 12.0]

FOMC_DAYS = [d for d, kind in mp.build_day_list() if kind == "FOMC"]


def to_float(s):
    try:
        return float(str(s).replace(" ", "").split("(")[0])
    except (TypeError, ValueError):
        return None


def run_one_day(tp, sl, date_str, presets_dir, merged_dir):
    label = f"fomcexit_tp{int(tp)}sl{int(sl)}_{date_str.replace('.', '')}"
    params = dict(es.BASE)
    params["BasketTP_USD"] = tp
    params["BasketSL_USD"] = sl
    set_name = f"{label}.set"
    set_path = os.path.join(presets_dir, set_name)
    ini_path = os.path.join(merged_dir, f"{label}.ini")
    es.write_set(set_path, params)
    es.FROM_DATE, es.TO_DATE = mp.day_before(date_str), mp.day_after(date_str)
    es.write_ini(ini_path, label, set_name, params)

    if es.terminal_running():
        return None

    subprocess.run([es.TERMINAL, f"/config:{ini_path}"])
    htm_path = os.path.join(es.DATADIR, f"{label}.htm")
    result = es.parse_report(htm_path) if os.path.exists(htm_path) else None

    for p in (set_path, ini_path, htm_path):
        if os.path.exists(p):
            os.remove(p)
    return result


def main():
    print(f"[FOMCEXIT] {len(TP_GRID)}x{len(SL_GRID)}={len(TP_GRID)*len(SL_GRID)} combos "
          f"x {len(FOMC_DAYS)} FOMC days, real ticks throughout")
    presets_dir = os.path.join(es.DATADIR, "MQL5", "Presets")
    merged_dir = os.path.join(es.HERE, ".merged")
    os.makedirs(presets_dir, exist_ok=True)
    os.makedirs(merged_dir, exist_ok=True)

    combo_results = []
    for tp in TP_GRID:
        for sl in SL_GRID:
            t0 = time.time()
            total_profit = 0.0
            total_gp = 0.0
            total_gl = 0.0
            total_trades = 0
            days_ok = 0
            for date_str in FOMC_DAYS:
                r = run_one_day(tp, sl, date_str, presets_dir, merged_dir)
                if r is None:
                    print(f"[FOMCEXIT] ABORT mid-combo TP={tp} SL={sl} at {date_str} "
                          f"(terminal busy or no report)")
                    break
                p, gp, gl, tr = (to_float(r["profit"]), to_float(r["gross_profit"]),
                                  to_float(r["gross_loss"]), to_float(r["trades"]))
                if p is not None:
                    total_profit += p
                    total_gp += (gp or 0.0)
                    total_gl += (gl or 0.0)
                    total_trades += int(tr or 0)
                    days_ok += 1
            elapsed = time.time() - t0
            combined_pf = (total_gp / abs(total_gl)) if total_gl else None
            combo_results.append({
                "TP": tp, "SL": sl, "total_profit": round(total_profit, 2),
                "combined_pf": round(combined_pf, 3) if combined_pf is not None else None,
                "total_trades": total_trades, "days_ok": days_ok, "elapsed_s": round(elapsed, 1),
            })
            print(f"[FOMCEXIT] TP={tp} SL={sl}: profit={total_profit:.2f} "
                  f"pf={combined_pf} trades={total_trades} ({days_ok}/{len(FOMC_DAYS)} days, {elapsed:.0f}s)")

    combo_results.sort(key=lambda r: r["total_profit"], reverse=True)
    out_csv = os.path.join(es.HERE, "..", "..", "docs", "opt", "fomc_exit_sweep_results.csv")
    fieldnames = ["TP", "SL", "total_profit", "combined_pf", "total_trades", "days_ok", "elapsed_s"]
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in combo_results:
            w.writerow(r)
    print(f"[FOMCEXIT] wrote {len(combo_results)} combo(s) to {out_csv}")
    print("[FOMCEXIT] === top 5 ===")
    for r in combo_results[:5]:
        print(f"  TP={r['TP']} SL={r['SL']}: profit={r['total_profit']} pf={r['combined_pf']}")


if __name__ == "__main__":
    main()
