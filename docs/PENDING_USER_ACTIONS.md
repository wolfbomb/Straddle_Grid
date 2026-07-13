# PENDING_USER_ACTIONS.md — Your Test Queue

> 🚀 **Shortcut:** most tester scenarios below are automated in `tools/strategy-tester/` —
> edit two paths in `run_tests.bat`, double-click, send back the reports + tester logs.
> See `tools/strategy-tester/README.md`. Manual steps below remain valid as the reference.

> Everything currently waiting on you (the user, at your MT5 PC).
> Current build: `Straddle_Grid.mq5` **v1.6** (Phases 1–5: skeleton, gates, grid deploy/expiry,
> direction lock & OCO, Whipsaw Guard; v1.6 = GridSpacingUSD default 0.70 for VT Markets + gate
> log de-spam, from your 2026-07-13 live-chart log).
> ⚠ The EA CAN place orders — but only with `AUTO_TRADING_ENABLED=true` and all five gates
> passing. Test in the Strategy Tester / demo only.
> Phases 1–5 are tested together in one sitting. **Phase 5 tests are the gate for Phase 6** —
> per CLAUDE.md the Basket Manager may not be built until the Whipsaw Guard tests pass.
> On pass, report back → I bump to v1.7, commit "Phase 5 complete", and start Phase 6.

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

- [ ] EA initializes: `[HYDRA]` line `SIGMA Hydra v1.6 initializing on XAUUSD-VIP (magic 20260713)`.
      (Re-pull the repo and recompile first — v1.6 fixes the gate-3 spacing block you hit.)
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
      prices against the formula `anchor ± (0.50 + i × 0.70)` and lots against the progression;
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
- [ ] If price reaches a stop during these runs, the EA transitions to ACTIVE with a
      direction-lock log line — see the Phase 4 tests below. Whipsaw Guard does not exist yet,
      so don't leave it running unattended with auto-trading on.

## 7. Phase 4 — direction lock & OCO tests

Full list in `docs/CHECKLIST.md` §Phase 4. Tester, real ticks, `AUTO_TRADING_ENABLED=true`;
pick a trending day (e.g. a session open with displacement) so stops actually fill:

- [ ] **Direction lock:** when price hits the first stop, journal shows
      `fill 1/9: BUY … @ …` (or SELL) then
      `state ARMED -> ACTIVE (first fill — direction locked BUY, OCO cancel issued)`.
- [ ] **OCO cancel (`OCO_Mode=true`, default):** within the same second, all 9 opposite-side
      pendings are deleted (`OCO: opposite side clear`); the 8 remaining same-side stops stay.
- [ ] **Sequential fills:** as the move extends, `fill 2/9`, `fill 3/9`… appear with correct
      sides, lots, and prices.
- [ ] **`OCO_Mode=false`:** repeat one run — after the first fill, all 9 opposite-side pendings
      remain in place (reversal-hedge mode), log says `reversal hedge kept (OCO off)`.
- [ ] **Restart mid-ACTIVE (demo chart):** while holding fills, remove and re-attach the EA →
      log shows `recovery: N open position(s) … direction BUY, N fill(s)`, no duplicate grid,
      no re-locked wrong direction. (§11 explicit case)
- [ ] Note: with no basket exits yet (Phase 6), positions ride until you close them manually,
      the Whipsaw Guard fires, or the tester run ends — expected at this phase.

## 8. Phase 5 — Whipsaw Guard tests  ⚠ must pass before Phase 6 is built

Full list in `docs/CHECKLIST.md` §Phase 5. Tester, real ticks, `AUTO_TRADING_ENABLED=true`.
The easiest way to force a whipsaw: `OCO_Mode=false`, pick a violent news day
(NFP/FOMC/CPI release), and shrink `FirstLevelOffsetUSD`/`GridSpacingUSD` a little so one
big two-sided candle can reach both sides.

- [ ] **Guard fires:** when a buy fill and a sell fill land within `WhipsawWindowSec` (300 s),
      journal shows `WHIPSAW DETECTED — buy fill … / sell fill …, gap N s`, then every position
      is closed at market, every pending deleted, and
      `state ACTIVE -> COOLDOWN (whipsaw guard fired (1/2 today), cooldown until …)`.
      Account is completely flat afterwards (Trade tab empty). (§11 explicit case)
- [ ] **Cooldown holds:** for the next 60 min nothing deploys — no gate logs, no orders;
      then `state COOLDOWN -> IDLE (cooldown expired)`.
- [ ] **Daily cap:** force a second whipsaw the same day → log shows `(2/2 today) — locked out
      until next trading day`; EA stays in COOLDOWN past the 60-minute mark until the next
      server day, then resets (`whipsaw counter reset for the new trading day`).
- [ ] **Counter survives restart (demo):** after one whipsaw, check F3 Global Variables —
      `SIGMA.Hydra.XAUUSD-VIP.whipsaw_count = 1` — re-attach the EA → recovery goes straight
      to COOLDOWN with the correct remaining time.
- [ ] **Ordering:** the whipsaw log lines appear BEFORE any other ACTIVE-state management
      lines in the same tick (guard runs first — will matter more once Phase 6 adds exits).
- [ ] **No false fires:** on a clean trending run (OCO on), the guard never triggers —
      one-sided fills only.

## 9. Report back

Send me:

1. Compile result (0/0 or the exact messages).
2. The symbol-spec log line values (item 2, third bullet).
3. Pass/fail on items 2–8 (screenshots or pasted log lines are perfect).

Then I will: bump `HYDRA_VERSION` → `v1.7`, commit `Phase 5 complete — … (v1.7)` to main
(covering Phases 1–5), and immediately proceed to **Phase 6 — Basket Manager**
(which per CLAUDE.md is only allowed to start once the Phase 5 tests pass).

---

## Upcoming user tasks (not yet actionable — for awareness)

| When | Task |
|---|---|
| Phase 6 done | Basket TP/SL/trailing tests; trail-floor retrace test |
| Phase 7 | 3-month real-tick backtest incl. one NFP + one FOMC day; download tick history beforehand |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED = true` (see final checklist in `docs/CHECKLIST.md`) |
