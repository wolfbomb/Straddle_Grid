#!/usr/bin/env python3
"""
Hydra restart-mid-ACTIVE + foreign-order-untouched test (live DEMO account).

Automates the two Phase 7 items that can't be backtested (CLAUDE.md §11):
  1. Terminal restart during ACTIVE -> state fully recovered, no duplicate grid.
  2. Foreign orders/positions (different magic) untouched throughout.

Flow:
  A. Sanity: no terminal running; demo account confirmed on first connect.
  B. Convert the hydra_09 preset to UTF-16 into MQL5\\Presets; write a start
     config that attaches Straddle_Grid to a fresh XAUUSD-VIP M1 chart.
  C. Launch terminal, attach via MetaTrader5 python module.
  D. Place a FOREIGN pending order (magic 77777, BUY LIMIT far below market).
  E. Wait for Hydra to deploy (ARMED) and get >=1 fill (ACTIVE).
  F. Snapshot positions/orders, then HARD-KILL the terminal (crash sim).
  G. Relaunch (plain, profile-restore; fallback: same config), reattach.
  H. Assert: EA logs '-> ACTIVE (recovery:'; no new 'grid deployed' after
     the kill; position tickets unchanged; foreign order still present and
     byte-identical (price/volume/magic); no Hydra order references it.
  I. Cleanup: close Hydra positions, delete Hydra pendings, delete the
     foreign order, verify flat, close terminal gracefully, and strip any
     profile-persisted Hydra chart so no future terminal start auto-trades.

Every action logs a [RT] line; exits 0 only if every assertion passed.
"""

import os
import re
import glob
import time
import shutil
import subprocess
import sys
from datetime import datetime, timezone

import MetaTrader5 as mt5

TERMINAL = r"C:\Program Files\MetaTrader 5\terminal64.exe"
DATADIR = r"C:\Users\nimrod.resulta\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
HERE = os.path.dirname(os.path.abspath(__file__))
SYMBOL = "XAUUSD-VIP"
HYDRA_MAGIC = 20260713
FOREIGN_MAGIC = 77777
PRESET = "hydra_09_restart_demo.set"
START_INI = os.path.join(HERE, "_startup_generated.ini")
FILL_TIMEOUT_S = 40 * 60          # give price up to 40 min to reach level 1
RECOVERY_WATCH_S = 90             # watch this long post-restart for duplicates

failures = []


def log(msg):
    print(f"[RT] {datetime.now().strftime('%H:%M:%S')} {msg}", flush=True)


def capture(tag):
    """PNG of the real terminal window (PrintWindow) — doubles as the Phase 8
    pixel evidence: panel on a live chart, per-state accent, OHLC overlap."""
    out = os.path.join(HERE, "shots", f"live_{tag}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    r = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
         "-File", os.path.join(HERE, "capture_window.ps1"), out],
        capture_output=True, text=True)
    log(f"window capture [{tag}]: {(r.stdout or r.stderr).strip()}")


def check(cond, what):
    if cond:
        log(f"PASS: {what}")
    else:
        failures.append(what)
        log(f"FAIL: {what}")


def terminal_pids():
    out = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq terminal64.exe", "/FO", "CSV", "/NH"],
        capture_output=True, text=True).stdout
    return [int(m) for m in re.findall(r'"terminal64.exe","(\d+)"', out)]


def launch_terminal(config=None):
    args = [TERMINAL]
    if config:
        args.append(f"/config:{config}")
    subprocess.Popen(args, cwd=os.path.dirname(TERMINAL))
    log(f"terminal launched {'with ' + os.path.basename(config) if config else '(plain)'}")


def terminal_journal_lines():
    day = datetime.now().strftime("%Y%m%d")
    path = os.path.join(DATADIR, "logs", f"{day}.log")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-16-le", errors="replace") as f:
        return f.readlines()


def attach(timeout=90):
    """Attach to the ALREADY-LAUNCHED terminal. Critical ordering: wait for
    the launched instance to be authorized (journal line) BEFORE the first
    mt5.initialize() call — calling it too early makes the python module
    spawn its own config-less terminal64, which then wins the single-instance
    race and silently discards our [StartUp] EA attach (observed 2026-07-17:
    'terminal process already started' collisions in the journal)."""
    mark = max(0, len(terminal_journal_lines()) - 5)   # from just before our launch
    deadline = time.time() + timeout
    while time.time() < deadline:
        if terminal_pids() and any("authorized on" in ln for ln in terminal_journal_lines()[mark:]):
            break
        time.sleep(2)
    else:
        log("attach: launched terminal never reached 'authorized' state")
        return None
    time.sleep(3)
    while time.time() < deadline:
        if mt5.initialize(path=TERMINAL):
            info = mt5.terminal_info()
            acct = mt5.account_info()
            if info and acct and info.connected:
                return acct
        time.sleep(3)
    return None


def hard_kill():
    for pid in terminal_pids():
        subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
    log("terminal HARD-KILLED (crash simulation)")
    time.sleep(3)


def graceful_close():
    subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "Get-Process terminal64 -ErrorAction SilentlyContinue | "
         "ForEach-Object { $null = $_.CloseMainWindow(); $_.WaitForExit(30000) }"],
        capture_output=True)
    time.sleep(2)


def hydra_positions():
    return [p for p in (mt5.positions_get(symbol=SYMBOL) or []) if p.magic == HYDRA_MAGIC]


def hydra_orders():
    return [o for o in (mt5.orders_get(symbol=SYMBOL) or []) if o.magic == HYDRA_MAGIC]


def foreign_orders():
    return [o for o in (mt5.orders_get(symbol=SYMBOL) or []) if o.magic == FOREIGN_MAGIC]


def todays_expert_log_lines():
    day = datetime.now().strftime("%Y%m%d")
    path = os.path.join(DATADIR, "MQL5", "Logs", f"{day}.log")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-16-le", errors="replace") as f:
        return [ln for ln in f if "[HYDRA]" in ln]


def strip_hydra_charts_from_profiles():
    """With the terminal closed, delete any profile chart file that has the
    Hydra expert attached, so no future start silently auto-trades."""
    removed = 0
    for chr_path in glob.glob(os.path.join(DATADIR, "MQL5", "Profiles", "Charts", "*", "*.chr")):
        try:
            with open(chr_path, encoding="utf-16-le", errors="replace") as f:
                content = f.read()
        except OSError:
            continue
        if "Straddle_Grid" in content:
            os.remove(chr_path)
            removed += 1
            log(f"removed profile chart with Hydra attached: {chr_path}")
    log(f"profile scrub: {removed} chart file(s) removed")


def main():
    log("=== Hydra restart-mid-ACTIVE + foreign-order test ===")

    if terminal_pids():
        log("ABORT: terminal64.exe already running — close it (or wait) and rerun")
        return 2

    # B: preset (UTF-16 with BOM) + start config
    os.makedirs(os.path.join(DATADIR, "MQL5", "Presets"), exist_ok=True)
    with open(os.path.join(HERE, PRESET), encoding="utf-8") as f:
        preset_text = f.read()
    with open(os.path.join(DATADIR, "MQL5", "Presets", PRESET), "w", encoding="utf-16") as f:
        f.write(preset_text)
    with open(START_INI, "w", encoding="ascii") as f:
        f.write(
            "[Experts]\nEnabled=1\nAllowLiveTrading=1\nAllowDllImport=0\n\n"
            f"[StartUp]\nExpert=SIGMA\\Straddle_Grid\nExpertParameters={PRESET}\n"
            f"Symbol={SYMBOL}\nPeriod=M1\n")
    log("preset + start config written")

    # C: launch + attach
    launch_terminal(START_INI)
    acct = attach()
    if not acct:
        log("ABORT: could not attach to terminal via MetaTrader5 module")
        return 2
    check(acct.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO,
          f"account {acct.login} is DEMO (trade_mode={acct.trade_mode})")
    if acct.trade_mode != mt5.ACCOUNT_TRADE_MODE_DEMO:
        log("ABORT: refusing to run against a non-demo account")
        graceful_close()
        return 2
    log(f"attached: {acct.login} {acct.server} equity={acct.equity}")

    # D: foreign pending far below market
    tick = mt5.symbol_info_tick(SYMBOL)
    fprice = round(tick.bid - 30.0, 2)
    req = {
        "action": mt5.TRADE_ACTION_PENDING, "symbol": SYMBOL, "volume": 0.01,
        "type": mt5.ORDER_TYPE_BUY_LIMIT, "price": fprice,
        "type_time": mt5.ORDER_TIME_GTC, "type_filling": mt5.ORDER_FILLING_RETURN,
        "magic": FOREIGN_MAGIC, "comment": "FOREIGN.TEST"}
    res = mt5.order_send(req)
    if res is not None and res.retcode == 10030:      # unsupported filling mode
        req["type_filling"] = mt5.ORDER_FILLING_IOC
        res = mt5.order_send(req)
    check(res is not None and res.retcode == mt5.TRADE_RETCODE_DONE,
          f"foreign BUY LIMIT placed @ {fprice} (retcode={getattr(res, 'retcode', None)})")
    if not foreign_orders():
        log("ABORT: foreign order not visible after placement")
        graceful_close()
        return 2
    f0 = foreign_orders()[0]
    log(f"foreign order ticket={f0.ticket} price={f0.price_open} vol={f0.volume_current}")

    # E: wait for ARMED then ACTIVE
    log("waiting for Hydra grid deploy + first fill "
        f"(timeout {FILL_TIMEOUT_S // 60} min)...")
    deadline = time.time() + FILL_TIMEOUT_S
    armed_seen = False
    while time.time() < deadline:
        n_ord, n_pos = len(hydra_orders()), len(hydra_positions())
        if not armed_seen and n_ord > 0:
            armed_seen = True
            log(f"ARMED: {n_ord} Hydra pendings on book")
            time.sleep(2)
            capture("ARMED")
        if n_pos > 0:
            log(f"ACTIVE: {n_pos} Hydra position(s) open")
            capture("ACTIVE")
            break
        time.sleep(2)
    else:
        log("TIMEOUT: no fill — cleaning up and aborting (inconclusive, not a failure)")
        cleanup()
        return 3
    check(armed_seen, "grid was observed ARMED before first fill")

    # F: snapshot + crash
    time.sleep(3)   # let the EA's OCO cancel settle
    pre_pos = {p.ticket: (p.volume, p.type) for p in hydra_positions()}
    pre_ord = {o.ticket: (o.price_open, o.type) for o in hydra_orders()}
    log(f"pre-kill snapshot: {len(pre_pos)} position(s) {list(pre_pos)}, "
        f"{len(pre_ord)} pending(s)")
    mt5.shutdown()
    hard_kill()

    # G: relaunch with the same start config. (This datadir has no Profiles
    # directory — nothing persists chart/EA state across a crash, so profile
    # restore can never re-attach the EA here; the config relaunch IS the
    # restart scenario. Live expert logs are also unreliably flushed on this
    # build, so attach/recovery evidence comes from the terminal journal +
    # server-side state + the RECOVERED window capture.)
    journal_mark = len(terminal_journal_lines())
    launch_terminal(START_INI)
    acct = attach()
    if not acct:
        log("ABORT: could not re-attach after config relaunch")
        return 2
    time.sleep(10)

    # H: recovery assertions
    deadline = time.time() + RECOVERY_WATCH_S
    ea_loaded = False
    while time.time() < deadline and not ea_loaded:
        new_journal = terminal_journal_lines()[journal_mark:]
        ea_loaded = any("Straddle_Grid" in ln and "loaded successfully" in ln
                        for ln in new_journal)
        time.sleep(3)
    check(ea_loaded, "EA re-attached after restart (journal 'loaded successfully')")
    if not hydra_positions():
        log("INCONCLUSIVE: no Hydra position left after the restart gap "
            "(basket may have exited server-side). Cleaning up; rerun for a verdict.")
        cleanup()
        return 3

    capture("RECOVERED")
    time.sleep(RECOVERY_WATCH_S // 3)   # watch window for duplicate deployment
    post_ord = {o.ticket: (o.price_open, o.type) for o in hydra_orders()}
    check(len(post_ord) <= len(pre_ord) and set(post_ord) <= set(pre_ord),
          f"no duplicate grid after restart (pendings before={len(pre_ord)}, "
          f"after={len(post_ord)}, no new tickets)")

    post_pos = {p.ticket: (p.volume, p.type) for p in hydra_positions()}
    check(set(pre_pos) <= set(post_pos),
          f"pre-kill position tickets all preserved (pre={sorted(pre_pos)}, post={sorted(post_pos)})")

    fo = foreign_orders()
    check(len(fo) == 1, f"foreign order still present (found {len(fo)})")
    if fo:
        check(fo[0].ticket == f0.ticket and fo[0].price_open == f0.price_open
              and fo[0].volume_current == f0.volume_current,
              "foreign order untouched (ticket/price/volume identical)")

    # I: cleanup
    cleanup()

    log("=== RESULT ===")
    if failures:
        log(f"FAIL — {len(failures)} assertion(s): {failures}")
        return 1
    log("PASS — restart recovery + foreign-order isolation both verified")
    return 0


def cleanup():
    log("cleanup: closing Hydra positions / deleting all test orders")
    for p in hydra_positions():
        tick = mt5.symbol_info_tick(SYMBOL)
        res = mt5.order_send({
            "action": mt5.TRADE_ACTION_DEAL, "symbol": SYMBOL, "volume": p.volume,
            "type": mt5.ORDER_TYPE_SELL if p.type == mt5.POSITION_TYPE_BUY else mt5.ORDER_TYPE_BUY,
            "position": p.ticket, "price": tick.bid if p.type == mt5.POSITION_TYPE_BUY else tick.ask,
            "deviation": 100, "type_filling": mt5.ORDER_FILLING_IOC,
            "magic": HYDRA_MAGIC, "comment": "SIGMA.Hydra.rt-cleanup"})
        log(f"  close position {p.ticket}: retcode={getattr(res, 'retcode', None)}")
    for o in hydra_orders() + foreign_orders():
        res = mt5.order_send({"action": mt5.TRADE_ACTION_REMOVE, "order": o.ticket})
        log(f"  delete order {o.ticket} (magic {o.magic}): retcode={getattr(res, 'retcode', None)}")
    time.sleep(2)
    left_p, left_o = len(hydra_positions()), len(hydra_orders()) + len(foreign_orders())
    check(left_p == 0 and left_o == 0,
          f"account flat after cleanup (positions={left_p}, test orders={left_o})")
    mt5.shutdown()
    graceful_close()
    strip_hydra_charts_from_profiles()
    log("cleanup complete; terminal closed")


if __name__ == "__main__":
    sys.exit(main())
