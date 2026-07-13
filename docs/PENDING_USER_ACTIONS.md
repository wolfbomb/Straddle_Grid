# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user, at your MT5 PC).
> Current build: `Straddle_Grid.mq5` **v1.2** (Phase 1 skeleton + Phase 2 gates + Phase 3 grid deploy/expiry).
> ⚠ From this build on, the EA CAN place orders — but only with `AUTO_TRADING_ENABLED=true`
> and all five gates passing. Test in the Strategy Tester / demo only.
> Phases 1–3 are tested together in one sitting. When these pass, report back →
> I bump to v1.3, commit "Phase 3 complete" (covering all three), and start Phase 4 (direction lock & OCO).

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

- [ ] EA initializes: `[HYDRA]` line `SIGMA Hydra v1.2 initializing on XAUUSD-VIP (magic 20260713)`.
- [ ] Lot progression line: `9 levels/side, 0.24 lots/side if fully filled`.
- [ ] Symbol spec line (minLot / lotStep / stopsLevel / tickSize / tickValue) — **note these values
      down and send them to me**; I need them to sanity-check the Phase 3 grid-spacing defaults
      for VT Markets XAUUSD-VIP.
- [ ] Warning line that AUTO_TRADING_ENABLED is false.
- [ ] State line: `state IDLE -> IDLE (recovery: clean slate)`.
- [ ] Gate status lines (`gates FAIL — gate N (…): …`) appear **only when the status changes**
      (e.g. at session open/close, ATR band crossings) — no once-per-second log spam.
- [ ] With everything else passing, the final blocker is
      `gates FAIL — gate 5 (MasterSwitch): AUTO_TRADING_ENABLED=false`.
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

## 5. Phase 2 — gate behavior tests

Full list in `docs/CHECKLIST.md` §Phase 2. The quick version (tester, one recent week, real ticks):

- [ ] **Session gate:** run with default sessions → `gates FAIL — gate 1` outside 07:00–10:00 /
      12:00–15:00 server time; status flips at window boundaries. Set `Session1 = "banana"` →
      init warning + gate 1 always fails with "malformed session input".
- [ ] **Volatility gate:** set `ATR_Max_USD = 0.01` → gate 2 fails "> max"; set
      `ATR_Min_USD = 999` → gate 2 fails "< min". Restore defaults after.
- [ ] **Spread gate:** in tester settings force spread = 100 (> `MaxSpreadPoints` 35) →
      gate 3 fails. Set `GridSpacingUSD = 0.01` → gate 3 fails with the computed required
      minimum in the log.
- [ ] **Exposure gate:** hard to force in Phase 2 (needs Hydra orders) — the "existing
      exposure" branch gets exercised naturally from Phase 3 on. Skip for now.
- [ ] **Master switch:** with gates 1–4 passing (pick a time inside a session window),
      confirm the chain stops at gate 5 while `AUTO_TRADING_ENABLED=false`; flip it to `true`
      in the tester → log shows `gates PASS — deployment deferred (Phase 3)` and still
      **zero orders**.
- [ ] **Short-circuit:** while gate 1 is failing, no gate 2–5 reasons appear in any log line
      (later gates are never evaluated).

## 6. Phase 3 — grid deploy & expiry tests

Full list in `docs/CHECKLIST.md` §Phase 3. Tester, real ticks, `AUTO_TRADING_ENABLED=true`,
pick a date/time inside a session window so gates can pass:

- [ ] **Deployment:** on gates PASS, exactly 9 buy stops above and 9 sell stops below the anchor
      appear at once; journal shows `grid deployed: 9+9 stops around <anchor>`. Spot-check 2–3
      prices against the formula `anchor ± (0.50 + i × 0.42)` and lots against the progression;
      comments read `SIGMA.Hydra.B0…B8 / S0…S8`.
- [ ] **Stops-level abort:** set `FirstLevelOffsetUSD = 0.0` (and if your stops level is 0, also
      `GridSpacingUSD` tiny) → journal shows `deployment ABORTED — … violates min distance`,
      zero orders ever placed, state stays IDLE. Restore defaults after.
- [ ] **TTL expiry:** set `GridTTLMin = 2`, deploy in a quiet period (or widen
      `FirstLevelOffsetUSD` so nothing fills) → after 2 min all 18 pendings deleted,
      log `grid TTL 2 min expired with zero fills`, state back to IDLE, then a fresh grid
      may deploy while gates still pass.
- [ ] **Gate re-check while ARMED:** deploy near the end of a session window → at window close,
      log `grid cancelled — gate failed while ARMED`, all pendings deleted.
- [ ] **No partial grids:** at every moment the Hydra pending count is 0 or 18, never in between
      (scan the tester journal / orders tab).
- [ ] **ARMED restart recovery (demo chart, optional but valuable):** let a grid deploy on demo,
      remove and re-attach the EA → log `recovery: 18 pending order(s) found … TTL anchor …`,
      no duplicate grid placed.
- [ ] If price reaches a stop during these runs, the EA logs a transition to ACTIVE via the
      polling fallback — that's expected; full fill handling is Phase 4. Whipsaw Guard does not
      exist yet, so don't leave it running unattended with auto-trading on.

## 7. Report back

Send me:

1. Compile result (0/0 or the exact messages).
2. The symbol-spec log line values (item 2, third bullet).
3. Pass/fail on items 2–6 (screenshots or pasted log lines are perfect).

Then I will: bump `HYDRA_VERSION` → `v1.3`, commit `Phase 3 complete — … (v1.3)` to main
(covering Phases 1–3), and immediately proceed to **Phase 4 — direction lock & OCO**.

---

## Upcoming user tasks (not yet actionable — for awareness)

| When | Task |
|---|---|
| Phase 4 done | Fill/OCO tests: first fill locks direction, opposite side cancelled; restart mid-ACTIVE recovery |
| Phase 5 done | Whipsaw candle test on a violent news bar — must pass before Phase 6 code is accepted |
| Phase 7 | 3-month real-tick backtest incl. one NFP + one FOMC day; download tick history beforehand |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED = true` (see final checklist in `docs/CHECKLIST.md`) |
