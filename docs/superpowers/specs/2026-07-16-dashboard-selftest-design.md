# Dashboard self-verification — design

**Date:** 2026-07-16
**Status:** Approved for planning
**Scope:** Reduce the Phase 8 dashboard manual-check checklist (`docs/CHECKLIST.md` §Phase 8,
`docs/PENDING_USER_ACTIONS.md`) by asserting content/color correctness in code instead of by eye.

## Problem

The Phase 8 dashboard checklist has 12 manual items. Nearly all of them reduce to "does this
chart object's text/color match what the EA's current state should produce" — a comparison that
can be made in code, not just by a human looking at a chart. Only a few items are genuinely
visual (does a real mouse click fire the collapse handler, does the panel overlap the chart's
native OHLC label on a given monitor/skin) and can't be automated away.

Today `tools/strategy-tester/run_tests.sh` ends every run by telling the user to "send both
[report and logs] back for verification" — there is no automatic pass/fail signal.

## Design

### 1. Passive read-back guard (in `Straddle_Grid.mq5`)

Add a read-back check directly into the three places that write dashboard chart objects:

- `SetRow(rowKey, text, clr)` — after `ObjectSetString`/`ObjectSetInteger`, read the property
  back immediately and compare to what was just written.
- The gate-dot loop in `UpdateDashboard()` (5 dots + fail name).
- The header/accent update in `UpdateDashboard()`.

On mismatch, log:

```
[HYDRA][DASH-FAIL] row=<key> field=<text|color> expected=<x> actual=<y>
```

On match: silent. No per-tick log spam — a passing dashboard produces zero new log lines.

`RemoveDashboard()` gets the same treatment: after `ObjectsDeleteAll(0, DASH_PREFIX)`, loop and
confirm zero objects with `DASH_PREFIX` remain; log `DASH-FAIL` if any survive.

**Safety:** this is a passive read-back, not a synthetic/injected test. No new input, no
`MQL_TESTER` gating needed, no behavior change live or in tester. Correct code never emits a
`DASH-FAIL` line under any conditions (live, demo, or tester).

### 2. Tooling: `run_tests.sh` fails loud on `DASH-FAIL`

After each headless config run, grep the produced Tester log
(`$DATADIR/Tester/*/logs/*.log` or platform equivalent) for `DASH-FAIL` and print a per-config
`PASS`/`FAIL` line, replacing the current "send both back for verification" close-out. A
`DASH-FAIL` hit should make the run's result visibly fail rather than requiring a human to read
the log.

### 3. Manual checklist shrinks

Update `docs/CHECKLIST.md` §Phase 8 and `docs/PENDING_USER_ACTIONS.md` to reflect the new,
shorter list. What remains manual (things a screen is required for):

- A real header click actually collapses/expands the panel (event wiring itself, not the
  geometry math behind it).
- The panel doesn't visually overlap the chart's native top-left OHLC/price label.
- One general "does it look right" eyeball pass (fonts, spacing, readability).

Everything else currently in the 12-item list (header version text, all 5 accent colors, gate
dot colors + fail-name, every row's content including scaled TP/SL/trail-floor targets and the
whipsaw/TTL countdowns, leftover-object cleanup on removal) becomes an automatic pass/fail on
every future headless `run_tests.sh` run — not just a one-time check for this phase.

### 4. Version bump

Hold `HYDRA_VERSION` at v2.0 until both:
- an automated headless run across the known state-cycling window (`hydra_02` config /
  `hydra_dash_visual` window) shows zero `DASH-FAIL` lines, **and**
- the user confirms the 3-item visual micro-checklist above.

This follows the existing "bump once confirmed working" pattern already used for Phase 6 and
Phase 8's initial implementation — just with a smaller manual confirmation step now.

## Addendum (2026-07-17): Approach B re-scoped IN by user request

The user asked to automate the remaining eyes-on items ("can you automate these 3 items",
2026-07-17), which supersedes the earlier decision to decline Approach B. Added:

1. **Synthetic event battery** (`RunDashSyntheticBattery()`, tester-gated behind a new
   test-only input `DashSelfTest=false` + `MQLInfoInteger(MQL_TESTER)`): calls
   `OnChartEvent()` directly with `CHARTEVENT_OBJECT_CLICK` on the header and
   `CHARTEVENT_CHART_CHANGE`, asserting via read-back after each step: collapse state
   toggles, BG height switches between header-only and full, body rows hide/show
   (`OBJPROP_TIMEFRAMES`), header arrow flips ▲/▼, and collapse state survives the
   rebuild. Failures reuse the `[DASH-FAIL]` format (counted by `run_tests.sh`); a
   positive `[DASH-SELFTEST] ... N checks, M failures` line proves the battery ran.
   Residual risk not covered: MT5's own pixel hit-testing that turns a physical mouse
   click into `CHARTEVENT_OBJECT_CLICK` (platform code, not ours).
2. **Screenshot capture** (visual mode only): first occurrence of each display state
   (IDLE / ARMED / ACTIVE-profit / ACTIVE-drawdown / COOLDOWN) plus the collapsed and
   re-expanded panel during the battery is saved via `ChartScreenShot()`; Claude reviews
   the PNGs for the overlap + "looks right" checks in place of a human eyeball pass.
3. New config: `hydra_08_dash_selftest` (headless battery, part of the numbered suite).
   A `hydra_dash_visual_auto` config (Visual=1 + ShutdownTerminal=1 + `ChartScreenShot`)
   was tried and **removed**: on this MT5 build (5836) a config-launched Visual=1 run
   keeps its journal only in the UI and never executed the screenshot path — same class
   of silently-ignored config behavior as the `[Tester] Spread=` override found in
   Phase 7. Pixel evidence comes instead from `tools/restart-test/` window captures
   (PrintWindow) of the panel on a **real** demo chart during the restart test —
   strictly better than tester rendering for the overlap/"looks right" review.

## Out of scope

- ~~Synthesizing a real `CHARTEVENT_OBJECT_CLICK` or otherwise testing the collapse/expand
  geometry logic without a real click (considered as "Approach B" and declined — smaller,
  safer change was preferred; the click handler is ~6 lines and low regression risk).~~
  **Re-scoped in 2026-07-17 — see Addendum above.**
- Any change to trading logic, gates, whipsaw guard, or basket management — this work touches
  only the dashboard rendering/verification path.
- General-purpose self-test scaffolding for future phases (state machine, gates, basket math) —
  scoped explicitly to the Phase 8 dashboard checklist per user decision (2026-07-16).

## Testing

- Compile check: 0 errors / 0 warnings (existing requirement, unchanged).
- Run `./run_tests.sh hydra_dash_visual` (or a headless equivalent of the same window) and
  confirm the new PASS/FAIL summary reports zero `DASH-FAIL` lines across a window that cycles
  IDLE → ARMED → ACTIVE (TP win) → COOLDOWN → ... → ACTIVE (SL loss), matching the existing
  known-good 4-day window already used for the visual check.
- Manually confirm the 3-item shrunk checklist once (header click, OHLC overlap, general look).
