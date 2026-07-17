#!/usr/bin/env python3
"""Resume the restart test from a live, already-trading session (used when
restart_test.py aborts after the EA is on the board). Performs: attach ->
snapshot -> kill -> config relaunch -> recovery assertions -> cleanup."""

import time
import sys
import restart_test as rt
import MetaTrader5 as mt5


def wait_journal(pred, timeout, mark):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if any(pred(ln) for ln in rt.terminal_journal_lines()[mark:]):
            return True
        time.sleep(2)
    return False


def main():
    rt.log("=== RESUME: taking over live session ===")
    if not rt.terminal_pids():
        rt.log("ABORT: no terminal running — use restart_test.py instead")
        return 2
    if not mt5.initialize(path=rt.TERMINAL):
        rt.log(f"ABORT: initialize failed: {mt5.last_error()}")
        return 2
    acct = mt5.account_info()
    if not acct or acct.trade_mode != mt5.ACCOUNT_TRADE_MODE_DEMO:
        rt.log("ABORT: not attached to the demo account")
        return 2
    rt.log(f"attached: {acct.login} equity={acct.equity}")

    fo = rt.foreign_orders()
    if not fo:
        rt.log("no foreign order (aborted run placed none?) — placing one now")
        tick = mt5.symbol_info_tick(rt.SYMBOL)
        req = {"action": mt5.TRADE_ACTION_PENDING, "symbol": rt.SYMBOL, "volume": 0.01,
               "type": mt5.ORDER_TYPE_BUY_LIMIT, "price": round(tick.bid - 30.0, 2),
               "type_time": mt5.ORDER_TIME_GTC, "type_filling": mt5.ORDER_FILLING_RETURN,
               "magic": rt.FOREIGN_MAGIC, "comment": "FOREIGN.TEST"}
        res = mt5.order_send(req)
        if res is None or res.retcode != mt5.TRADE_RETCODE_DONE:
            rt.log(f"ABORT: foreign order rejected: {getattr(res, 'retcode', None)}")
            rt.cleanup()
            return 2
        time.sleep(2)
        fo = rt.foreign_orders()
    f0 = fo[0]
    rt.log(f"foreign order: ticket={f0.ticket} @ {f0.price_open}")

    if not rt.hydra_positions():
        rt.log("INCONCLUSIVE: no Hydra position open right now — cleaning up")
        rt.cleanup()
        return 3
    rt.capture("ACTIVE")

    pre_pos = {p.ticket for p in rt.hydra_positions()}
    pre_ord = {o.ticket for o in rt.hydra_orders()}
    rt.log(f"pre-kill: positions={sorted(pre_pos)}, pendings={len(pre_ord)}")
    mark = len(rt.terminal_journal_lines())
    mt5.shutdown()
    rt.hard_kill()

    rt.launch_terminal(rt.START_INI)
    if not wait_journal(lambda ln: "authorized on" in ln, 90, mark):
        rt.log("ABORT: relaunched terminal never authorized")
        return 2
    ea_loaded = wait_journal(
        lambda ln: "Straddle_Grid" in ln and "loaded successfully" in ln, 60, mark)
    rt.check(ea_loaded, "EA re-attached after restart (journal 'loaded successfully')")
    if not mt5.initialize(path=rt.TERMINAL):
        rt.log("ABORT: could not re-attach python after restart")
        return 2
    time.sleep(15)
    rt.capture("RECOVERED")

    post_pos = {p.ticket for p in rt.hydra_positions()}
    post_ord = {o.ticket for o in rt.hydra_orders()}
    if not post_pos:
        rt.log("INCONCLUSIVE: basket exited during restart gap — cleaning up")
        rt.cleanup()
        return 3
    rt.check(pre_pos <= post_pos, f"pre-kill positions preserved ({sorted(pre_pos)} -> {sorted(post_pos)})")
    rt.check(len(post_ord) <= len(pre_ord) and post_ord <= pre_ord,
             f"no duplicate grid after restart (pendings {len(pre_ord)} -> {len(post_ord)}, no new tickets)")
    fo2 = rt.foreign_orders()
    rt.check(len(fo2) == 1 and fo2[0].ticket == f0.ticket
             and fo2[0].price_open == f0.price_open,
             "foreign order untouched across restart")

    rt.cleanup()
    rt.log("=== RESULT ===")
    if rt.failures:
        rt.log(f"FAIL — {rt.failures}")
        return 1
    rt.log("PASS — restart recovery + foreign-order isolation verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
