#!/usr/bin/env python3
"""
Generates the shared preset + [StartUp] config used by both attach_fomc.ps1
and detach_fomc.ps1's attach step, for the FOMC-only forward-tracking
deployment (CLAUDE.md §5.1, docs/OPT_REPORT.md's FOMC-only exit sweep).

Run once to (re)write the files into the live MT5 data folder. The scheduled
tasks launch terminal64.exe with this exact [StartUp] config at each
attach window - no EA code recompilation happens here; if Straddle_Grid.mq5
changes before the next scheduled date, recompile the DATADIR copy manually
and rerun this script if the preset itself needs to change.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "strategy-tester"))
import entry_sweep as es

LABEL = "fomc_live_tracking"

PARAMS = dict(es.BASE)
PARAMS.update({
    "AUTO_TRADING_ENABLED": "true",   # demo account only - see CLAUDE.md Master Switch convention
    "BasketTP_USD": "20.0",           # tested combination, docs/OPT_REPORT.md FOMC-only exit sweep
    "BasketSL_USD": "10.0",
    "FOMCOnlyMode": "true",
    "FOMCDatesCSV": "2026.01.28,2026.03.18,2026.04.29,2026.06.17,2026.07.29,2026.09.16,2026.10.28,2026.12.09",
    "FOMCWindowDays": "1",
})


def main():
    presets_dir = os.path.join(es.DATADIR, "MQL5", "Presets")
    os.makedirs(presets_dir, exist_ok=True)
    set_path = os.path.join(presets_dir, f"{LABEL}.set")
    es.write_set(set_path, PARAMS)
    print(f"wrote preset: {set_path}")

    startup_ini = os.path.join(os.path.dirname(os.path.abspath(__file__)), "startup_fomc_live.ini")
    with open(startup_ini, "w", encoding="ascii") as f:
        f.write(
            "[Experts]\nEnabled=1\nAllowLiveTrading=1\nAllowDllImport=0\n\n"
            f"[StartUp]\nExpert=Straddle\\Straddle_Grid\nExpertParameters={LABEL}.set\n"
            "Symbol=XAUUSD-VIP\nPeriod=M1\n")
    print(f"wrote startup config: {startup_ini}")


if __name__ == "__main__":
    main()
