#!/usr/bin/env python3
"""
Hydra restart-mid-ARMED test (live DEMO account) — closes the CHECKLIST.md
Phase 1 gap: "ARMED-specific restart recovery not separately exercised"
(only ACTIVE and IDLE were proven by restart_test.py / run 09).

Uses a widened FirstLevelOffsetUSD (test preset override, same technique
as hydra_13_armed_session_end) so the grid deploys and sits ARMED with a
comfortable no-fill window, giving a reliable kill target: pendings > 0,
zero fills. Reuses restart_test.py's proven helpers (attach/kill/relaunch/
journal parsing) rather than duplicating them.
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import restart_test as rt
import MetaTrader5 as mt5

PRESET = "hydra_armed_restart_demo.set"
START_INI = os.path.join(rt.HERE, "_startup_armed_generated.ini")
ARM_TIMEOUT_S = 15 * 60
RECOVERY_WATCH_S = 60

PRESET_BODY = """AUTO_TRADING_ENABLED=true
MagicNumber=20260713
GridLevels=9
GridSpacingUSD=0.70
FirstLevelOffsetUSD=5.0
LotProgressionCSV=0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05
OCO_Mode=true
GridTTLMin=45
BasketTP_USD=15.0
BasketSL_USD=10.0
TrailActivate_USD=8.0
TrailDistance_USD=4.0
Session1=00:00-23:59
Session2=00:00-23:59
ATR_Min_USD=0.01
ATR_Max_USD=999.0
MaxSpreadPoints=300
MinMarginLevelPct=100.0
MaxDailyLossPct=90.0
WhipsawWindowSec=300
WhipsawCooldownMin=60
MaxWhipsawsPerDay=2
DashSelfTest=false
"""


def main():
    rt.log("=== Hydra restart-mid-ARMED test ===")
    if rt.terminal_pids():
        rt.log("ABORT: terminal64.exe already running")
        return 2

    os.makedirs(os.path.join(rt.DATADIR, "MQL5", "Presets"), exist_ok=True)
    with open(os.path.join(rt.DATADIR, "MQL5", "Presets", PRESET), "w", encoding="utf-16") as f:
        f.write(PRESET_BODY)
    with open(START_INI, "w", encoding="ascii") as f:
        f.write(
            "[Experts]\nEnabled=1\nAllowLiveTrading=1\nAllowDllImport=0\n\n"
            f"[StartUp]\nExpert=Straddle\\Straddle_Grid\nExpertParameters={PRESET}\n"
            f"Symbol={rt.SYMBOL}\nPeriod=M1\n")
    rt.log("preset + start config written (FirstLevelOffsetUSD=5.0, gates loosened)")

    rt.launch_terminal(START_INI)
    acct = rt.attach()
    if not acct:
        rt.log("ABORT: could not attach")
        return 2
    rt.check(acct.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO, "account is DEMO")
    if acct.trade_mode != mt5.ACCOUNT_TRADE_MODE_DEMO:
        rt.graceful_close()
        return 2
    rt.log(f"attached: {acct.login} equity={acct.equity}")

    rt.log(f"waiting for ARMED (pendings > 0, zero fills), timeout {ARM_TIMEOUT_S//60} min...")
    deadline = time.time() + ARM_TIMEOUT_S
    while time.time() < deadline:
        n_ord, n_pos = len(rt.hydra_orders()), len(rt.hydra_positions())
        if n_pos > 0:
            rt.log("a fill already happened before we could catch pure-ARMED — "
                   "offset wasn't wide enough this time. Cleaning up, inconclusive.")
            rt.cleanup()
            return 3
        if n_ord > 0:
            rt.log(f"ARMED: {n_ord} pendings, 0 fills — killing now")
            break
        time.sleep(2)
    else:
        rt.log("TIMEOUT: never reached ARMED — cleaning up, inconclusive")
        rt.cleanup()
        return 3

    pre_ord = {o.ticket: (o.price_open, o.type) for o in rt.hydra_orders()}
    rt.log(f"pre-kill: {len(pre_ord)} pending(s) {sorted(pre_ord)}")
    mt5.shutdown()
    rt.hard_kill()

    journal_mark = len(rt.terminal_journal_lines())
    rt.launch_terminal(START_INI)
    acct = rt.attach()
    if not acct:
        rt.log("ABORT: could not re-attach after restart")
        return 2
    time.sleep(10)

    deadline = time.time() + RECOVERY_WATCH_S
    ea_loaded = False
    while time.time() < deadline and not ea_loaded:
        new_journal = rt.terminal_journal_lines()[journal_mark:]
        ea_loaded = any("Straddle_Grid" in ln and "loaded successfully" in ln for ln in new_journal)
        time.sleep(3)
    rt.check(ea_loaded, "EA re-attached after restart")

    # Soft observation only, not a hard assertion: [HYDRA] Print() lines land
    # in the expert log (MQL5\Logs), which this build flushes unreliably
    # around a hard kill (same platform quirk restart_test.py's own design
    # note documents) - server-side position/order state below is the
    # reliable evidence, this is just a bonus confirmation if it survived.
    armed_recovery_logged = any(
        "recovery:" in ln and "pending order(s) found, zero fills" in ln
        for ln in rt.todays_expert_log_lines()
    )
    rt.log(f"bonus check: RecoverState() ARMED-path log line found = {armed_recovery_logged}")

    post_ord = {o.ticket: (o.price_open, o.type) for o in rt.hydra_orders()}
    rt.check(len(rt.hydra_positions()) == 0, "still zero fills after restart (recovery target was ARMED, not ACTIVE)")
    rt.check(set(pre_ord) == set(post_ord),
             f"pending tickets preserved exactly (pre={sorted(pre_ord)}, post={sorted(post_ord)})")
    rt.check(len(post_ord) == 18, f"still a full 9+9 grid, no partial loss ({len(post_ord)}/18)")

    rt.cleanup()
    rt.log("=== RESULT ===")
    if rt.failures:
        rt.log(f"FAIL — {rt.failures}")
        return 1
    rt.log("PASS — ARMED-state restart recovery verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
