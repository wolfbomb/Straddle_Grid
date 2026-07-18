#!/usr/bin/env python3
"""
Cheap proof-of-concept: does Hydra actually have edge on known high-impact
news days, as the original displacement thesis (CLAUDE.md Section 2) claims -
independent of the always-on session-window trigger that 18 configurations
(exit sweep + entry sweep) already failed to make profitable?

Session1/Session2 are time-of-day windows only - the EA has no calendar-date
concept, so isolating specific days means running short, separate backtests
whose FromDate/ToDate bracket just one event day (no EA code change).

Scope: NFP (first Friday of the month) only - these are the one category of
"known high-impact day" computable by pure calendar rule for this fictional
2026 window. Real FOMC meeting dates for 2026 aren't independently
verifiable and are NOT included (same caveat as docs/TEST_REPORT_P7.md's
Run 05 note on NFP/FOMC inclusion).

Each probe: FromDate = day before the NFP Friday, ToDate = day after
(3-day window, production defaults unchanged), so the EA sees clean
lookback for its indicators and the full NFP day itself. Independent single
passes - no state carries between them.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_sweep as es  # reuse write_set/write_ini/terminal_running/parse_report

NFP_FRIDAYS_2026 = ["2026.04.03", "2026.05.01", "2026.06.05", "2026.07.03"]


def day_before(d):
    y, m, dd = (int(x) for x in d.split("."))
    import datetime
    dt = datetime.date(y, m, dd) - datetime.timedelta(days=1)
    return dt.strftime("%Y.%m.%d")


def day_after(d):
    y, m, dd = (int(x) for x in d.split("."))
    import datetime
    dt = datetime.date(y, m, dd) + datetime.timedelta(days=1)
    return dt.strftime("%Y.%m.%d")


def main():
    print(f"[NEWSPROBE] {len(NFP_FRIDAYS_2026)} NFP-day probes, production defaults, real ticks")
    presets_dir = os.path.join(es.DATADIR, "MQL5", "Presets")
    merged_dir = os.path.join(es.HERE, ".merged")
    os.makedirs(presets_dir, exist_ok=True)
    os.makedirs(merged_dir, exist_ok=True)

    results = []
    for i, nfp in enumerate(NFP_FRIDAYS_2026, 1):
        label = f"newsprobe_{nfp.replace('.', '')}"
        from_date, to_date = day_before(nfp), day_after(nfp)
        params = dict(es.BASE)   # production defaults, untouched
        set_name = f"{label}.set"
        set_path = os.path.join(presets_dir, set_name)
        ini_path = os.path.join(merged_dir, f"{label}.ini")
        es.write_set(set_path, params)

        # write_ini hardcodes es.FROM_DATE/es.TO_DATE - override per-probe
        es.FROM_DATE, es.TO_DATE = from_date, to_date
        es.write_ini(ini_path, label, set_name, params)

        if es.terminal_running():
            print(f"[NEWSPROBE] ABORT before probe {i}: our terminal already running")
            return 2

        print(f"[NEWSPROBE] ({i}/{len(NFP_FRIDAYS_2026)}) NFP {nfp}: window {from_date}-{to_date}")
        import subprocess, time
        t0 = time.time()
        subprocess.run([es.TERMINAL, f"/config:{ini_path}"])
        elapsed = time.time() - t0

        htm_path = os.path.join(es.DATADIR, f"{label}.htm")
        if not os.path.exists(htm_path):
            print(f"[NEWSPROBE]   no report produced ({elapsed:.0f}s) - skipping")
            continue
        metrics = es.parse_report(htm_path)
        metrics["nfp_date"] = nfp
        metrics["elapsed_s"] = round(elapsed, 1)
        results.append(metrics)
        print(f"[NEWSPROBE]   done in {elapsed:.0f}s: profit={metrics['profit']} "
              f"pf={metrics['pf']} trades={metrics['trades']}")

    print("[NEWSPROBE] === summary ===")
    for r in results:
        print(f"  {r['nfp_date']}: profit={r['profit']} pf={r['pf']} "
              f"eqdd={r['eqdd']} trades={r['trades']}")

    out_csv = os.path.join(es.HERE, "..", "..", "docs", "opt", "news_day_probe_results.csv")
    import csv
    fieldnames = ["nfp_date", "profit", "pf", "eqdd", "trades", "sharpe", "elapsed_s"]
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in results:
            w.writerow({k: r.get(k) for k in fieldnames})
    print(f"[NEWSPROBE] wrote {len(results)} result(s) to {out_csv}")


if __name__ == "__main__":
    main()
