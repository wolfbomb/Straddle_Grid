# CLAUDE.md — Straddle_Grid (codename: Hydra)

> **Project context file for Claude Code sessions.**
> Read this file fully before writing or modifying any code in this repository.
> This EA is part of the **SIGMA suite** and follows all SIGMA conventions established in `CRT_Breakout`.

---

## 1. Project Identity

| Field | Value |
|---|---|
| EA Name | `Straddle_Grid` |
| Codename | Hydra |
| Suite | SIGMA |
| Magic Number | `20260713` |
| Target Symbols | XAUUSD-VIP (primary), BTCUSD (secondary) |
| Timeframe | M1 (execution), M5 (context filter) |
| Broker Profile | VT Markets (Pty) Ltd, MT5, hedging account |
| Deployment | Per-chart, one instance per symbol (SIGMA convention) |
| Language | MQL5 only — no DLLs, no external dependencies |
| Repository | https://github.com/wolfbomb/Straddle_Grid.git |
| Version | v1.0 — increment last digit on every change (v1.1, v1.2, …); shown in dashboard header |

---

## 2. Strategy Concept

**Bidirectional stop-order grid (straddle) with pyramiding lot progression.**

At deployment, Hydra places a symmetric grid of pending stop orders around an anchor price:

- **N Buy Stops** above the anchor, ascending lot sizes
- **N Sell Stops** below the anchor, ascending lot sizes

Whichever direction price breaks, orders trigger sequentially and the position compounds *into* the momentum. The grid is designed to capture displacement moves (news spikes, session-open expansion, liquidity runs) where XAUUSD travels $15–30 in minutes.

**Default lot progression (9 levels per side):**
`0.01, 0.01, 0.02, 0.02, 0.02, 0.03, 0.04, 0.04, 0.05` — total 0.24 lots per side if fully filled.

**Known weakness (must be engineered against):** whipsaw/chop. A wick through both sides fills opposing positions and stacks losses. The Whipsaw Guard (Section 6) is *mandatory* and must never be disabled by refactoring.

---

## 3. SIGMA Conventions (Non-Negotiable)

These apply to all SIGMA EAs and must be preserved in every code change:

1. `AUTO_TRADING_ENABLED` input **defaults to `false`**. The EA must never place a live order unless the user explicitly flips it to `true`.
2. Order filling mode: `ORDER_FILLING_IOC`.
3. All orders tagged with the magic number `20260713` and comment prefix `"SIGMA.Hydra"`.
4. Per-chart deployment: the EA manages **only its own symbol + magic number**. It must never touch positions/orders belonging to other EAs or manual trades.
5. Five ordered safety gates evaluated **sequentially** before any deployment (Section 5). A gate failure short-circuits — later gates are not evaluated.
6. Collapsible dashboard panel on chart per the spec in Section 10.1 (header `SIGMA Hydra vX.Y`).
7. Version constant `HYDRA_VERSION` bumped (last digit +1) on **every** code change; dashboard header reflects it.
8. All state transitions logged via `Print()` with a `[HYDRA]` prefix and timestamp.
9. Spec-first workflow: any behavioral change must be reflected in this file **before** implementation.

---

## 4. State Machine

```
IDLE ──gates pass──▶ ARMED ──first fill──▶ ACTIVE ──basket exit──▶ COOLDOWN ──timer──▶ IDLE
  ▲                    │                      │
  │                    └──expiry/gate fail────┤
  └────────────────────◀── whipsaw kill ──────┘
```

| State | Meaning | Allowed actions |
|---|---|---|
| `IDLE` | No grid, no positions. Evaluating gates each tick (throttled to 1x/sec). | Deploy grid → ARMED |
| `ARMED` | Full pending grid placed, zero fills yet. | Monitor fills; cancel on expiry or gate failure → IDLE |
| `ACTIVE` | ≥1 order filled. Direction locked. | OCO cancel (if enabled), basket management, trailing |
| `COOLDOWN` | Post-exit or post-whipsaw lockout. | Nothing. Timer only. |

**State must be recoverable after terminal restart**: on `OnInit`, reconstruct state from existing orders/positions matching magic number. Never assume a clean slate.

---

## 5. Safety Gates (Ordered, Sequential)

Evaluated in `IDLE` before grid deployment. All five must pass.

| # | Gate | Rule | Default |
|---|---|---|---|
| 1 | **Session / Killzone** | Current server time inside an allowed window (London open, NY open — configurable). | LO 07:00–10:00, NY 12:00–15:00 GMT |
| 2 | **Volatility Context** | ATR(14, M5) within `[ATR_Min, ATR_Max]`. Too low = chop risk; too high = grid already missed the move. | ATR_Min 1.5, ATR_Max 8.0 (USD) |
| 3 | **Spread** | Current spread ≤ `MaxSpreadPoints`. Also validates `GridSpacing ≥ SYMBOL_TRADE_STOPS_LEVEL + spread + buffer`. | 35 points |
| 4 | **Exposure** | No existing Hydra positions/orders; account margin level > `MinMarginLevel`; daily loss limit not breached. | Margin 500%, DailyLoss 3% |
| 5 | **Master Switch** | `AUTO_TRADING_ENABLED == true` AND terminal AutoTrading button enabled. | `false` |

---

## 6. Whipsaw Guard (Kill Switch) — MANDATORY

- If **both a buy-side and sell-side order fill within `WhipsawWindowSec`** (default 300s):
  1. Immediately close all Hydra positions at market.
  2. Delete all remaining pending Hydra orders.
  3. Enter `COOLDOWN` for `WhipsawCooldownMin` (default 60 min).
  4. Increment persistent whipsaw counter (global variable, survives restart).
- If whipsaw counter ≥ `MaxWhipsawsPerDay` (default 2), remain in `COOLDOWN` until next trading day.
- This logic must live in its own function `CheckWhipsawGuard()` called at the top of `OnTick` in `ACTIVE` state, before any other management logic.

**Design note (2026-07-13, user decision):** a "slow whipsaw" — opposite-side fills more than
`WhipsawWindowSec` apart with `OCO_Mode=false` (observed in tester: reversal 10.5 min after the
first side filled) — deliberately does **not** trigger the guard. The 300 s window stands.
Rationale: with the default `OCO_Mode=true` the opposite side is cancelled seconds after the
first fill, so the hole barely exists; OCO-off is the discouraged reversal-hedge mode where
opposing positions are intentional, and the Basket Manager (§7) governs the net exposure there.
Do not "fix" this by widening the window or triggering on coexisting opposing positions.

---

## 7. Grid Mechanics

**Deployment (IDLE → ARMED):**
- Anchor = current mid price at deploy time.
- Buy Stop `i` at `anchor + FirstLevelOffset + i * GridSpacing`, lot = `LotProgression[i]`.
- Sell Stop `i` at `anchor − FirstLevelOffset − i * GridSpacing`, lot = `LotProgression[i]`.
- All levels validated against stops level before sending; if any level is invalid, **abort the entire deployment** (no partial grids).
- Grid expiry: pending orders auto-cancel after `GridTTLMin` (default 45 min) with no fill → back to IDLE.

**Direction lock (ARMED → ACTIVE):**
- On first fill, record direction.
- If `OCO_Mode == true` (default): delete all opposite-side pendings immediately.
- If `OCO_Mode == false`: opposite side remains as reversal hedge (Reel-style — allowed but discouraged; Whipsaw Guard still applies).

**Basket management (ACTIVE):**
- Aggregate P/L across all filled Hydra positions on this symbol.
- **Basket TP:** close all at `BasketTP_USD` (default $15 per 0.01 base — scaled by filled volume).
- **Basket SL:** close all at `BasketSL_USD` (default −$10 scaled).
- **Basket trailing:** once basket P/L ≥ `TrailActivate_USD`, trail a locked floor at `BasketP/L − TrailDistance_USD`; close all if floor is hit.
- Unfilled same-direction pendings are deleted once basket trailing activates (stop adding into an extended move).
- **Scaling (implemented v1.9):** effective TP / SL / activate / distance = input USD × (total filled volume ÷ 0.01). Floating P/L includes swap; commission lives on deals and is not counted.
- **Post-exit cooldown (v1.9):** every basket exit (TP, SL, trail floor) transitions to `COOLDOWN` for **60 s** before returning to IDLE — distinct from the whipsaw cooldown — so any re-entry must re-pass all five gates. Trail floor persists in a global variable and survives restart; it resets only on return to IDLE.

---

## 8. Inputs Block (Canonical Names)

```mql5
input group "── Master ──"
input bool    AUTO_TRADING_ENABLED = false;
input long    MagicNumber          = 20260713;

input group "── Grid ──"
input int     GridLevels           = 9;        // per side
input double  GridSpacingUSD       = 0.70;     // $ between levels (raised from 0.42 — see field note below)
input double  FirstLevelOffsetUSD  = 0.50;     // $ from anchor to level 1
input string  LotProgressionCSV    = "0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05";
input bool    OCO_Mode             = true;
input int     GridTTLMin           = 45;

input group "── Basket Exit ──"
input double  BasketTP_USD         = 15.0;
input double  BasketSL_USD         = 10.0;
input double  TrailActivate_USD    = 8.0;
input double  TrailDistance_USD    = 4.0;

input group "── Gates ──"
input string  Session1             = "07:00-10:00";  // GMT
input string  Session2             = "12:00-15:00";
input double  ATR_Min_USD          = 1.5;
input double  ATR_Max_USD          = 8.0;
input int     MaxSpreadPoints      = 35;
input double  MinMarginLevelPct    = 500.0;
input double  MaxDailyLossPct      = 3.0;

input group "── Whipsaw Guard ──"
input int     WhipsawWindowSec     = 300;
input int     WhipsawCooldownMin   = 60;
input int     MaxWhipsawsPerDay    = 2;

input group "── Self-Test (tester only) ──"
input bool    DashSelfTest         = false;   // synthetic dashboard battery + visual-mode screenshots;
                                              // hard-gated on MQLInfoInteger(MQL_TESTER) — inert on a live chart
```

**Field note (2026-07-13, live VT Markets XAUUSD-VIP):** `SYMBOL_TRADE_STOPS_LEVEL` = 20 pts,
typical live spread 29–30 pts, tick size 0.01, tick value $1.00/lot, min lot 0.01.
Gate 3 requires `GridSpacingUSD ≥ stops + spread + 10-pt buffer` ≈ $0.60 (up to $0.65 at the
`MaxSpreadPoints=35` cap), so the original 0.42 default could never deploy on this broker.
Default raised to **0.70** — clears the worst allowed spread with margin. Full grid depth is now
`0.50 + 8 × 0.70 = $6.10` per side (was $3.86).

---

## 9. File / Repo Structure

```
Straddle_Grid/
├── CLAUDE.md                  ← this file
├── PHASE_PROMPTS.md           ← phased build prompts for Claude Code
├── .gitignore                 ← MQL5 pattern (ex5, logs, tester artifacts)
├── MQL5/
│   └── Experts/Straddle/
│       └── Straddle_Grid.mq5  ← single-file EA (per-EA folder; renamed from the shared
│                                  `SIGMA/` folder 2026-07-18 to avoid collisions with
│                                  sibling SIGMA-suite EAs in the same MT5 terminal)
└── docs/
    └── CHECKLIST.md           ← pre-deploy verification checklist
```

Single `.mq5` file, organized into clearly commented sections:
`Inputs → Globals/State → OnInit (state recovery) → OnTick (state dispatch) → Gates → GridDeploy → WhipsawGuard → BasketManager → Dashboard → Utils`.

---

## 10. Build Phases (for PHASE_PROMPTS.md)

1. **Phase 1 — Skeleton & State Machine:** inputs, enums, state recovery in OnInit, logging. Compiles clean, trades nothing.
2. **Phase 2 — Gates:** all five gates + gate status logging.
3. **Phase 3 — Grid Deploy & Expiry:** validated deployment, TTL cancel, abort-on-partial. Verify VT Markets' `SYMBOL_TRADE_STOPS_LEVEL`, tick value, and contract spec for XAUUSD-VIP; adjust default spacing if needed.
4. **Phase 4 — Direction Lock & OCO:** fill detection via OnTradeTransaction, opposite-side cancel.
5. **Phase 5 — Whipsaw Guard:** kill switch + persistent counter. *Test before Phase 6.*
6. **Phase 6 — Basket Manager:** TP/SL/trailing, pending cleanup on trail activation.
7. **Phase 7 — Strategy Tester validation:** M1 XAUUSD-VIP, real ticks, spread stress;
verify no partial grids, no orphaned orders after restart mid-ACTIVE.
8. **Phase 8 — Dashboard Panel:** full spec in Section 10.1 below.

**Per-phase workflow (mandatory):**
- Every phase ends with its own test suite (compile check + phase-specific Strategy Tester or log-verification tests defined in `docs/CHECKLIST.md`).
- A phase is complete only when **all its tests pass with zero compile warnings**.
- On full pass: bump the version (v1.0 → v1.1 → v1.2 …) in the `HYDRA_VERSION` constant and dashboard header, then **automatically commit, merge to `main`, and push** to `https://github.com/wolfbomb/Straddle_Grid.git` with message format: `Phase N complete — <summary> (vX.Y)`. Merging to `main` on phase completion is automatic — no per-phase approval needed (user directive, 2026-07-13).
- Never commit a failing or warning build.

### 10.1 Dashboard Panel Spec (Phase 8)

**Header:** `SIGMA Hydra v1.0` — version string sourced from the single `HYDRA_VERSION` constant (never hardcoded twice).

**Behavior:**
- Collapsible panel, anchored top-left of chart.
- **Default state: expanded.** Clicking the header toggles collapse.
- Collapsed state shows the **title bar only** (header text + a small ▲/▼ indicator).
- Collapse state persists across timeframe switches (chart object based, rebuilt in `OnChartEvent`).

**Visual style (modern):**
- Dark translucent background (`clrBlack`-based rectangle label with subtle alpha look), rounded feel via padding, accent color per state: gray = IDLE, blue = ARMED, green = ACTIVE (profit), red = ACTIVE (drawdown), orange = COOLDOWN.
- Monospace-aligned rows, section separators, no overlapping chart data window.

**Expanded body — the essential information, top to bottom:**
| Row | Content |
|---|---|
| State | `IDLE / ARMED / ACTIVE ▲ / ACTIVE ▼ / COOLDOWN` with accent color |
| Auto Trading | ON / OFF (red warning when OFF) |
| Gates | 5 compact pass/fail dots (● green / ● red) with gate name on fail |
| Session | Current session window + server time |
| Spread / ATR | Live spread (points) vs max; ATR(M5) vs min/max band |
| Grid | Levels armed (e.g. `9+9 pending`), direction after lock, fills `3/9` |
| Basket P/L | Floating P/L in USD, color-coded |
| Targets | Basket TP / SL / trail floor (shows `—` until trailing active) |
| Whipsaw | Counter today `n / MaxWhipsawsPerDay`; cooldown countdown when active |
| Expiry | Grid TTL countdown while ARMED |

Keep the panel read-only — no trade buttons (SIGMA safety convention: the only master switch is the input + terminal AutoTrading button).

**Self-verification (2026-07-16/17, see `docs/superpowers/specs/2026-07-16-dashboard-selftest-design.md`):**
1. *Passive read-back guard* — every dashboard property write is read back and compared;
   mismatches log `[DASH-FAIL]` lines that `run_tests.sh` counts (UTF-16-aware) into a
   PASS/FAIL summary per run. Always on, live and tester; silent when correct.
2. *Synthetic event battery + screenshots* (`DashSelfTest=true`, tester-only): synthesizes
   the header click and `CHARTEVENT_CHART_CHANGE` through `OnChartEvent()` and asserts
   collapse/expand geometry, row visibility, arrow glyph, and collapse persistence; in
   visual mode also captures `ChartScreenShot()` PNGs of every display state for review.
   The only check code cannot make is MT5's own mouse-pixel → `CHARTEVENT_OBJECT_CLICK`
   hit-testing (platform behavior).

---

## 11. Testing Requirements

- Backtest on **every tick based on real ticks**, XAUUSD-VIP M1, minimum 3 months including at least one NFP and one FOMC day.
- Explicit test cases:
  - Whipsaw candle piercing both sides in one bar → guard fires, flat, cooldown.
  - Terminal restart during ACTIVE → state fully recovered, no duplicate grid.
  - Stops-level rejection at deploy → clean abort, zero orders left behind.
  - Trailing floor hit during a retrace → all positions closed, all pendings deleted.
- Never report a phase complete if the compile has warnings.

## 12. Hard Rules for Claude Code

- Never remove or weaken the Whipsaw Guard or Gate 5 (master switch).
- Never introduce martingale beyond the fixed `LotProgressionCSV` array.
- Never widen `BasketSL_USD` at runtime.
- Deliver **complete files**, not diffs (user preference).
- Bump `HYDRA_VERSION` on every change; commit + push to the repo only after all phase tests pass with zero warnings.
- Update this CLAUDE.md whenever behavior changes.
