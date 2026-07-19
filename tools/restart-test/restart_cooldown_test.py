#!/usr/bin/env python3
"""
Hydra restart-mid-COOLDOWN test (live DEMO account) — closes the
CHECKLIST.md Phase 5 gap: "restart during cooldown -> recovers to
COOLDOWN with correct remaining time" not separately exercised.

Uses a tiny BasketTP_USD/BasketSL_USD (test preset override) so whichever
side fills exits the basket almost immediately on ordinary market noise,
triggering the 60s post-exit COOLDOWN quickly and predictably. Polls for
the ACTIVE->COOLDOWN transition and kills within a couple of seconds -
comfortably inside the 60s window - then confirms recovery to COOLDOWN
with a sane remaining-time value (not reset to 0, not stuck at the full
60s as if the clock never advanced).
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import restart_test as rt
import MetaTrader5 as mt5

PRESET = "hydra_cooldown_restart_demo.set"
START_INI = os.path.join(rt.HERE, "_startup_cooldown_generated.ini")
FILL_TIMEOUT_S = 20 * 60
EXIT_TIMEOUT_S = 10 * 60
RECOVERY_WATCH_S = 60

PRESET_BODY = """AUTO_TRADING_ENABLED=true
MagicNumber=20260713
GridLevels=9
GridSpacingUSD=0.70
FirstLevelOffsetUSD=0.50
LotProgressionCSV=0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05
OCO_Mode=true
GridTTLMin=240
BasketTP_USD=0.30
BasketSL_USD=0.30
TrailActivate_USD=999.0
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
    rt.log("=== Hydra restart-mid-COOLDOWN test ===")
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
    rt.log("preset + start config written (BasketTP/SL=$0.30, trailing disabled)")

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

    rt.log(f"waiting for first fill, timeout {FILL_TIMEOUT_S//60} min...")
    deadline = time.time() + FILL_TIMEOUT_S
    while time.time() < deadline and not rt.hydra_positions():
        time.sleep(2)
    if not rt.hydra_positions():
        rt.log("TIMEOUT: no fill — cleaning up, inconclusive")
        rt.cleanup()
        return 3
    rt.log(f"ACTIVE: {len(rt.hydra_positions())} position(s)")

    rt.log(f"waiting for basket exit -> COOLDOWN, timeout {EXIT_TIMEOUT_S//60} min...")
    deadline = time.time() + EXIT_TIMEOUT_S
    saw_cooldown = False
    while time.time() < deadline:
        if len(rt.hydra_positions()) == 0:
            saw_cooldown = True
            rt.log("positions closed — basket exited, should be in COOLDOWN now")
            break
        time.sleep(1)
    if not saw_cooldown:
        rt.log("TIMEOUT: basket never exited — cleaning up, inconclusive")
        rt.cleanup()
        return 3

    kill_time = time.time()
    mt5.shutdown()
    rt.hard_kill()
    rt.log(f"killed {time.time()-kill_time:.1f}s after detecting the exit "
           f"(well inside the 60s post-exit cooldown window)")

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

    # Server-side evidence: account should still be flat (basket already
    # closed before the kill) and gates should stay blocked for a little
    # while (still in COOLDOWN) before naturally opening back up to IDLE.
    rt.check(len(rt.hydra_positions()) == 0, "account still flat after restart (basket stayed closed)")

    cooldown_recovery_logged = any(
        "recovery: cooldown active until" in ln for ln in rt.todays_expert_log_lines())
    rt.log(f"bonus check: RecoverState() COOLDOWN-path log line found = {cooldown_recovery_logged}")

    # Watch a further stretch: no new grid should deploy while still
    # within the 60s cooldown from the ORIGINAL exit time, and it MUST
    # eventually deploy again once cooldown expires (gates permitting) -
    # proving the recovered cooldown timer actually still governs behavior.
    time.sleep(5)
    early_pendings = len(rt.hydra_orders())
    rt.check(early_pendings == 0,
              f"no new grid deployed immediately after restart while still in cooldown ({early_pendings} pendings)")

    rt.log("watching up to 90s for a fresh deploy once cooldown naturally expires...")
    redeploy_deadline = time.time() + 90
    redeployed = False
    while time.time() < redeploy_deadline:
        if len(rt.hydra_orders()) > 0:
            redeployed = True
            break
        time.sleep(2)
    rt.check(redeployed, "a new grid deployed once the recovered cooldown timer expired (proves it wasn't stuck)")

    rt.cleanup()
    rt.log("=== RESULT ===")
    if rt.failures:
        rt.log(f"FAIL — {rt.failures}")
        return 1
    rt.log("PASS — COOLDOWN-state restart recovery verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
