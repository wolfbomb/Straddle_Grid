# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user, at your MT5 PC).
> Current build: `Straddle_Grid.mq5` **v1.0** (Phase 1 — skeleton & state machine, trades nothing).
> When these pass, report back → I bump to v1.1, commit "Phase 1 complete", and start Phase 2 (gates).

---

## 1. Compile check (required — blocks everything)

1. Copy `MQL5/Experts/SIGMA/Straddle_Grid.mq5` into your terminal's data folder under
   `MQL5/Experts/SIGMA/` (or pull the repo straight into the data folder).
2. Open it in MetaEditor and compile (**F7**).
3. **Pass criteria: 0 errors, 0 warnings.**
4. If there are any errors or warnings, paste them back to me verbatim — do not fix by hand;
   I'll ship a corrected complete file (SIGMA rule: complete files, not diffs).

## 2. Strategy Tester smoke run

Config: XAUUSD-VIP, M1, model **"Every tick based on real ticks"**, any recent week,
default inputs (leave `AUTO_TRADING_ENABLED = false`).

Check the Journal/Experts log for:

- [ ] EA initializes: `[HYDRA]` line `SIGMA Hydra v1.0 initializing on XAUUSD-VIP (magic 20260713)`.
- [ ] Lot progression line: `9 levels/side, 0.24 lots/side if fully filled`.
- [ ] Symbol spec line (minLot / lotStep / stopsLevel / tickSize / tickValue) — **note these values
      down and send them to me**; I need them to sanity-check the Phase 3 grid-spacing defaults
      for VT Markets XAUUSD-VIP.
- [ ] Warning line that AUTO_TRADING_ENABLED is false.
- [ ] State line: `state IDLE -> IDLE (recovery: clean slate)`.
- [ ] Gate stub lines appear **at most once per second** (compare consecutive log timestamps).
- [ ] **Zero orders placed** across the whole run (Trade/History tabs empty).
- [ ] No errors in the journal.

## 3. Input validation checks (quick)

- [ ] Set `LotProgressionCSV = "0.01,0.02"` (wrong count) → EA refuses to start,
      logs `INIT FAIL: LotProgressionCSV has 2 entries but GridLevels=9`.
- [ ] Set `LotProgressionCSV = "0.001,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05"` (below min lot)
      → EA refuses to start with a clear `INIT FAIL` lot message.
- [ ] Restore the default CSV afterwards.

## 4. State recovery — COOLDOWN path

1. Attach the EA to a live/demo XAUUSD-VIP chart (auto-trading can stay off — it trades nothing).
2. In the terminal press **F3** (Global Variables), add:
   `SIGMA.Hydra.XAUUSD-VIP.cooldown_until` = a future Unix epoch time
   (e.g. current epoch + 3600; https://www.epochconverter.com).
3. Remove and re-attach the EA (or recompile) → log must show
   `state IDLE -> COOLDOWN (recovery: cooldown active until ...)`.
4. Set the variable to a past epoch → next tick logs `state COOLDOWN -> IDLE (cooldown expired)`.
5. Delete the global variable when done.

## 5. State recovery — ARMED / ACTIVE paths (deferrable)

These need orders/positions tagged with magic `20260713`, which nothing can create yet
(the EA places no orders in Phase 1, and manual trades carry magic 0).

- **Option A (recommended):** defer to Phase 3/4 — the moment the EA can place its own grid,
  restart-recovery becomes directly testable and is on the Phase 3/4 checklists anyway.
- **Option B:** ask me for a tiny throwaway helper script that places one magic-tagged
  pending order on demo so you can verify ARMED recovery now.

## 6. Report back

Send me:

1. Compile result (0/0 or the exact messages).
2. The symbol-spec log line values (item 2, third bullet).
3. Pass/fail on items 2–4 (screenshots or pasted log lines are perfect).

Then I will: bump `HYDRA_VERSION` → `v1.1`, commit `Phase 1 complete — … (v1.1)` to main,
and immediately proceed to **Phase 2 — the five safety gates**.

---

## Upcoming user tasks (not yet actionable — for awareness)

| When | Task |
|---|---|
| Phase 2 done | Re-run tester; force each gate to fail (inputs listed in `docs/CHECKLIST.md` §Phase 2) |
| Phase 3 done | Verify grid levels vs. hand-computed prices; stops-level abort test; TTL expiry test |
| Phase 5 done | Whipsaw candle test on a violent news bar — must pass before Phase 6 code is accepted |
| Phase 7 | 3-month real-tick backtest incl. one NFP + one FOMC day; download tick history beforehand |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED = true` (see final checklist in `docs/CHECKLIST.md`) |
