//+------------------------------------------------------------------+
//|                                                Straddle_Grid.mq5 |
//|                              SIGMA Suite — Hydra                 |
//|                 https://github.com/wolfbomb/Straddle_Grid        |
//+------------------------------------------------------------------+
//| Bidirectional stop-order grid (straddle) with pyramiding lot     |
//| progression. Spec: CLAUDE.md (repo root). Build plan:            |
//| PHASE_PROMPTS.md. Tests: docs/CHECKLIST.md.                      |
//|                                                                  |
//| Phase 2 — Safety Gates (on the Phase 1 skeleton).                |
//| This build compiles clean and still trades NOTHING.              |
//|                                                                  |
//| Section order (SIGMA convention, CLAUDE.md §9):                  |
//|   Inputs → Globals/State → OnInit (state recovery) →             |
//|   OnTick (state dispatch) → Gates → GridDeploy → WhipsawGuard →  |
//|   BasketManager → Dashboard → Utils                              |
//+------------------------------------------------------------------+
#property copyright "SIGMA"
#property link      "https://github.com/wolfbomb/Straddle_Grid"

//+------------------------------------------------------------------+
//| ======================== INPUTS ================================ |
//| Canonical names per CLAUDE.md §8 — do not rename.                |
//+------------------------------------------------------------------+
input group "── Master ──"
input bool    AUTO_TRADING_ENABLED = false;    // SIGMA rule: defaults false, never flip in code
input long    MagicNumber          = 20260713;

input group "── Grid ──"
input int     GridLevels           = 9;        // per side
input double  GridSpacingUSD       = 0.42;     // $ between levels
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
input double  MaxDailyLossPct     = 3.0;

input group "── Whipsaw Guard ──"
input int     WhipsawWindowSec     = 300;
input int     WhipsawCooldownMin   = 60;
input int     MaxWhipsawsPerDay    = 2;

//+------------------------------------------------------------------+
//| ===================== GLOBALS / STATE =========================== |
//+------------------------------------------------------------------+
#define HYDRA_VERSION        "v1.1"          // single source of truth — dashboard header reads this
#define HYDRA_COMMENT_PREFIX "SIGMA.Hydra"   // order comment prefix (SIGMA convention)

// Persistent global-variable keys (namespaced SIGMA.Hydra.<symbol>.<key>,
// built by GVKey()). Survive terminal restart.
#define GV_WHIPSAW_COUNT   "whipsaw_count"   // whipsaws fired today
#define GV_WHIPSAW_DAY     "whipsaw_day"     // server day-stamp the counter belongs to
#define GV_COOLDOWN_UNTIL  "cooldown_until"  // epoch time cooldown ends
#define GV_DAY_STAMP       "day_stamp"       // server day the daily anchors belong to
#define GV_DAY_BALANCE     "day_balance"     // balance snapshot at server-day start (gate 4)

enum EHydraState
  {
   STATE_IDLE     = 0,  // no grid, no positions; evaluating gates (throttled 1x/sec)
   STATE_ARMED    = 1,  // full pending grid placed, zero fills yet
   STATE_ACTIVE   = 2,  // >=1 fill, direction locked
   STATE_COOLDOWN = 3   // post-exit / post-whipsaw lockout, timer only
  };

EHydraState g_state        = STATE_IDLE;
double      g_lots[];                       // parsed LotProgressionCSV
datetime    g_lastGateEval = 0;             // 1 Hz throttle for IDLE gate checks

//--- Gates (CLAUDE.md §5): cached results for logging-on-change + dashboard (Phase 8)
#define GATE_COUNT             5
#define SPACING_BUFFER_POINTS  10           // safety buffer in gate-3 spacing validation
string g_gateNames[GATE_COUNT] = {"Session","Volatility","Spread","Exposure","MasterSwitch"};
bool   g_gatePass[GATE_COUNT];
bool   g_gateEvaluated[GATE_COUNT];         // false when short-circuited before this gate
string g_gateReason[GATE_COUNT];
string g_lastGateStatus = "";               // last logged composite status (log on change only)

int    g_atrHandle   = INVALID_HANDLE;      // ATR(14, M5) for gate 2
int    g_sess1Start = -1, g_sess1End = -1;  // session windows in minutes-of-day (GMT/server)
int    g_sess2Start = -1, g_sess2End = -1;
bool   g_sessionsValid = false;             // false = malformed input, gate 1 always fails

//+------------------------------------------------------------------+
//| ================== ONINIT (STATE RECOVERY) ====================== |
//+------------------------------------------------------------------+
int OnInit()
  {
   HydraLog(StringFormat("SIGMA Hydra %s initializing on %s (magic %I64d)",
                         HYDRA_VERSION, _Symbol, MagicNumber));

   if(GridLevels <= 0)
     {
      HydraLog(StringFormat("INIT FAIL: GridLevels must be > 0 (got %d)", GridLevels));
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(!ParseLotProgression(LotProgressionCSV, g_lots))
      return(INIT_PARAMETERS_INCORRECT);     // reason already logged

   double total = 0.0;
   for(int i = 0; i < ArraySize(g_lots); i++)
      total += g_lots[i];
   HydraLog(StringFormat("lot progression OK: %d levels/side, %.2f lots/side if fully filled",
                         ArraySize(g_lots), total));

   // Contract context (informational in Phase 1; Phase 3 validates against it)
   HydraLog(StringFormat("symbol spec: minLot=%.2f lotStep=%.2f stopsLevel=%d pts, tickSize=%.5f tickValue=%.2f",
                         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
                         (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)));

   if(!AUTO_TRADING_ENABLED)
      HydraLog("AUTO_TRADING_ENABLED is false — EA will never place orders until enabled (gate 5)");

   // Gate 1: parse session windows once (malformed input -> gate fails, EA still runs)
   g_sessionsValid = ParseSessionWindow(Session1, g_sess1Start, g_sess1End) &&
                     ParseSessionWindow(Session2, g_sess2Start, g_sess2End);
   if(!g_sessionsValid)
      HydraLog(StringFormat("WARNING: malformed session window ('%s' / '%s') — gate 1 will always fail", Session1, Session2));

   // Gate 2: ATR(14, M5) indicator handle
   g_atrHandle = iATR(_Symbol, PERIOD_M5, 14);
   if(g_atrHandle == INVALID_HANDLE)
      HydraLog("WARNING: iATR(14,M5) handle creation failed — gate 2 will fail until available");

   RecoverState();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Reconstruct state from existing orders/positions (CLAUDE.md §4). |
//| Never assume a clean slate.                                      |
//+------------------------------------------------------------------+
void RecoverState()
  {
   int      positions     = CountHydraPositions();
   int      pendings      = CountHydraOrders();
   datetime cooldownUntil = (datetime)(long)GVGet(GV_COOLDOWN_UNTIL, 0.0);

   if(positions > 0)
      SetState(STATE_ACTIVE, StringFormat("recovery: %d open position(s), %d pending(s) found", positions, pendings));
   else if(pendings > 0)
      SetState(STATE_ARMED, StringFormat("recovery: %d pending order(s) found, zero fills", pendings));
   else if(cooldownUntil > TimeCurrent())
      SetState(STATE_COOLDOWN, StringFormat("recovery: cooldown active until %s",
                                            TimeToString(cooldownUntil, TIME_DATE|TIME_SECONDS)));
   else
      SetState(STATE_IDLE, "recovery: clean slate");
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
     }
   HydraLog(StringFormat("deinit (reason %d), state=%s", reason, StateName(g_state)));
  }

//+------------------------------------------------------------------+
//| ================== ONTICK (STATE DISPATCH) ====================== |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDayAnchor();   // roll daily-loss anchor (gate 4) on server-day change

   switch(g_state)
     {
      case STATE_IDLE:
        {
         // Gate evaluation throttled to at most once per second
         if(TimeCurrent() == g_lastGateEval)
            break;
         g_lastGateEval = TimeCurrent();

         string failReason = "";
         bool   pass = EvaluateGates(failReason);
         LogGateStatusOnChange(pass, failReason);
         if(pass)
           {
            // Phase 3 will call DeployGrid() here. Phase 2: log only.
           }
         break;
        }

      case STATE_ARMED:
        {
         // Phase 3: TTL expiry + gate re-check + fill monitoring
         break;
        }

      case STATE_ACTIVE:
        {
         // MANDATORY ordering (CLAUDE.md §6): whipsaw guard runs FIRST,
         // before any other management logic. Never reorder.
         if(CheckWhipsawGuard())
            break;                            // guard fired — state already moved to COOLDOWN
         ManageBasket();                      // Phase 6
         break;
        }

      case STATE_COOLDOWN:
        {
         datetime until = (datetime)(long)GVGet(GV_COOLDOWN_UNTIL, 0.0);
         if(TimeCurrent() >= until)
            SetState(STATE_IDLE, "cooldown expired");
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| ========================= GATES ================================ |
//| Five ordered safety gates (CLAUDE.md §5), evaluated sequentially |
//| with short-circuit: a failure stops evaluation — later gates are |
//| NOT evaluated. Results cached for the dashboard (Phase 8).       |
//| Status is logged on change only (no 1 Hz spam).                  |
//+------------------------------------------------------------------+
bool EvaluateGates(string &failReason)
  {
   for(int i = 0; i < GATE_COUNT; i++)
     {
      g_gateEvaluated[i] = false;
      g_gatePass[i]      = false;
      g_gateReason[i]    = "not evaluated";
     }

   string r = "";

   // Gate 1 — Session / Killzone
   bool ok = GateSession(r);
   SetGateResult(0, ok, r);
   if(!ok) { failReason = GateFailText(0, r); return(false); }

   // Gate 2 — Volatility context
   ok = GateVolatility(r);
   SetGateResult(1, ok, r);
   if(!ok) { failReason = GateFailText(1, r); return(false); }

   // Gate 3 — Spread + spacing validity
   ok = GateSpread(r);
   SetGateResult(2, ok, r);
   if(!ok) { failReason = GateFailText(2, r); return(false); }

   // Gate 4 — Exposure / margin / daily loss
   ok = GateExposure(r);
   SetGateResult(3, ok, r);
   if(!ok) { failReason = GateFailText(3, r); return(false); }

   // Gate 5 — Master switch (SIGMA rule: never weaken or remove)
   ok = GateMasterSwitch(r);
   SetGateResult(4, ok, r);
   if(!ok) { failReason = GateFailText(4, r); return(false); }

   failReason = "";
   return(true);
  }

void SetGateResult(const int idx, const bool pass, const string reason)
  {
   g_gateEvaluated[idx] = true;
   g_gatePass[idx]      = pass;
   g_gateReason[idx]    = reason;
  }

string GateFailText(const int idx, const string reason)
  {
   return(StringFormat("gate %d (%s): %s", idx + 1, g_gateNames[idx], reason));
  }

//--- Log composite gate status only when it changes (checklist: no 1 Hz spam)
void LogGateStatusOnChange(const bool pass, const string failReason)
  {
   string status = pass ? "PASS" : failReason;
   if(status == g_lastGateStatus)
      return;
   g_lastGateStatus = status;
   if(pass)
      HydraLog("gates PASS — deployment deferred (Phase 3)");
   else
      HydraLog("gates FAIL — " + failReason);
  }

//--- Gate 1: server time inside Session1 or Session2 (windows treated as GMT per spec)
bool GateSession(string &reason)
  {
   if(!g_sessionsValid)
     {
      reason = StringFormat("malformed session input ('%s' / '%s')", Session1, Session2);
      return(false);
     }
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;
   if(nowMin >= g_sess1Start && nowMin < g_sess1End) { reason = "in " + Session1; return(true); }
   if(nowMin >= g_sess2Start && nowMin < g_sess2End) { reason = "in " + Session2; return(true); }
   reason = StringFormat("server %02d:%02d outside %s and %s", dt.hour, dt.min, Session1, Session2);
   return(false);
  }

//--- Gate 2: ATR(14, M5) within [ATR_Min_USD, ATR_Max_USD].
//    For XAUUSD the price unit is USD, so ATR in price terms IS the USD range.
bool GateVolatility(string &reason)
  {
   double atr = GetATRUSD();
   if(atr < 0.0)             { reason = "ATR(14,M5) unavailable (handle/data not ready)";                   return(false); }
   if(atr < ATR_Min_USD)     { reason = StringFormat("ATR %.2f < min %.2f (chop risk)", atr, ATR_Min_USD);  return(false); }
   if(atr > ATR_Max_USD)     { reason = StringFormat("ATR %.2f > max %.2f (move already ran)", atr, ATR_Max_USD); return(false); }
   reason = StringFormat("ATR %.2f in [%.2f, %.2f]", atr, ATR_Min_USD, ATR_Max_USD);
   return(true);
  }

//--- Last CLOSED M5 bar's ATR, in price units (USD for XAUUSD); -1.0 on failure
double GetATRUSD()
  {
   if(g_atrHandle == INVALID_HANDLE)
      return(-1.0);
   double buf[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1)
      return(-1.0);
   return(buf[0]);
  }

//--- Gate 3: spread cap + validate GridSpacingUSD against
//    SYMBOL_TRADE_STOPS_LEVEL + spread + buffer (CLAUDE.md §5 gate 3)
bool GateSpread(string &reason)
  {
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPts > MaxSpreadPoints)
     {
      reason = StringFormat("spread %d pts > max %d", (int)spreadPts, MaxSpreadPoints);
      return(false);
     }
   long   stopsLvl      = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minSpacingUSD = (stopsLvl + spreadPts + SPACING_BUFFER_POINTS) * _Point;
   if(GridSpacingUSD < minSpacingUSD)
     {
      reason = StringFormat("GridSpacingUSD %.2f < required %.2f (stops %d + spread %d + buffer %d pts)",
                            GridSpacingUSD, minSpacingUSD, (int)stopsLvl, (int)spreadPts, SPACING_BUFFER_POINTS);
      return(false);
     }
   reason = StringFormat("spread %d pts, spacing OK", (int)spreadPts);
   return(true);
  }

//--- Gate 4: no existing Hydra exposure; margin level above floor; daily loss under cap
bool GateExposure(string &reason)
  {
   int pos = CountHydraPositions();
   int ord = CountHydraOrders();
   if(pos > 0 || ord > 0)
     {
      reason = StringFormat("existing Hydra exposure (%d position(s), %d order(s))", pos, ord);
      return(false);
     }

   // Margin level is only meaningful when margin is in use
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin > 0.0)
     {
      double lvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(lvl <= MinMarginLevelPct)
        {
         reason = StringFormat("margin level %.0f%% <= min %.0f%%", lvl, MinMarginLevelPct);
         return(false);
        }
     }

   double dayStart = GVGet(GV_DAY_BALANCE, AccountInfoDouble(ACCOUNT_BALANCE));
   if(dayStart > 0.0)
     {
      double lossPct = (dayStart - AccountInfoDouble(ACCOUNT_EQUITY)) / dayStart * 100.0;
      if(lossPct >= MaxDailyLossPct)
        {
         reason = StringFormat("daily loss %.2f%% >= limit %.2f%%", lossPct, MaxDailyLossPct);
         return(false);
        }
     }

   reason = "no exposure, margin OK, daily loss OK";
   return(true);
  }

//--- Gate 5: master switch — input flag AND terminal AutoTrading AND EA trade permission
bool GateMasterSwitch(string &reason)
  {
   if(!AUTO_TRADING_ENABLED)                                { reason = "AUTO_TRADING_ENABLED=false";        return(false); }
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)     { reason = "terminal AutoTrading button OFF";   return(false); }
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)               { reason = "EA trading not allowed (program)";  return(false); }
   reason = "enabled";
   return(true);
  }

//+------------------------------------------------------------------+
//| ======================= GRID DEPLOY ============================= |
//| Phase 3: validated deployment, abort-on-partial, rollback, TTL.  |
//+------------------------------------------------------------------+
bool DeployGrid()
  {
   HydraLog("DeployGrid: not implemented (Phase 3)");
   return(false);
  }

//+------------------------------------------------------------------+
//| ====================== WHIPSAW GUARD ============================ |
//| Phase 5: MANDATORY kill switch (CLAUDE.md §6). Called at the top |
//| of OnTick in ACTIVE state, before any other management logic.    |
//| Returns true when the guard fired. Never weaken or remove.       |
//+------------------------------------------------------------------+
bool CheckWhipsawGuard()
  {
   return(false);   // Phase 5
  }

//+------------------------------------------------------------------+
//| ====================== BASKET MANAGER =========================== |
//| Phase 6: basket TP / SL / trailing, pending cleanup on trail.    |
//+------------------------------------------------------------------+
void ManageBasket()
  {
   // Phase 6
  }

//+------------------------------------------------------------------+
//| ======================== DASHBOARD ============================== |
//| Phase 8: collapsible panel per CLAUDE.md §10.1. Header sources   |
//| its version from HYDRA_VERSION — never hardcode it twice.        |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   // Phase 8
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // Phase 8: header click collapse/expand, rebuild on timeframe switch
  }

//+------------------------------------------------------------------+
//| ========================== UTILS ================================ |
//+------------------------------------------------------------------+

//--- Logging: every log line carries the [HYDRA] prefix + timestamp (SIGMA convention #8)
void HydraLog(const string msg)
  {
   Print("[HYDRA] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " ", msg);
  }

string StateName(const EHydraState s)
  {
   switch(s)
     {
      case STATE_IDLE:     return("IDLE");
      case STATE_ARMED:    return("ARMED");
      case STATE_ACTIVE:   return("ACTIVE");
      case STATE_COOLDOWN: return("COOLDOWN");
     }
   return("UNKNOWN");
  }

//--- Single choke point for state transitions: every transition is logged
void SetState(const EHydraState newState, const string reason)
  {
   HydraLog(StringFormat("state %s -> %s (%s)", StateName(g_state), StateName(newState), reason));
   g_state = newState;
  }

//--- Persistent global variables, namespaced per symbol
string GVKey(const string key)
  {
   return("SIGMA.Hydra." + _Symbol + "." + key);
  }

double GVGet(const string key, const double fallback)
  {
   string k = GVKey(key);
   if(!GlobalVariableCheck(k))
      return(fallback);
   return(GlobalVariableGet(k));
  }

void GVSet(const string key, const double value)
  {
   GlobalVariableSet(GVKey(key), value);
  }

//--- Ownership filter: Hydra manages ONLY this symbol + this magic (SIGMA convention #4)
bool IsHydraPosition()
  {
   return(PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == MagicNumber);
  }

bool IsHydraOrder()
  {
   return(OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_MAGIC) == MagicNumber);
  }

int CountHydraPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(IsHydraPosition())
         count++;
     }
   return(count);
  }

int CountHydraOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(IsHydraOrder())
         count++;
     }
   return(count);
  }

//--- Parse and validate LotProgressionCSV (CLAUDE.md §8):
//    element count must equal GridLevels; every lot >= symbol min lot
//    and aligned to the symbol lot step. Failure -> init aborts.
bool ParseLotProgression(const string csv, double &lots[])
  {
   string parts[];
   int n = StringSplit(csv, ',', parts);
   if(n != GridLevels)
     {
      HydraLog(StringFormat("INIT FAIL: LotProgressionCSV has %d entries but GridLevels=%d", n, GridLevels));
      return(false);
     }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   ArrayResize(lots, n);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      double lot = StringToDouble(s);

      if(lot < minLot || lot <= 0.0)
        {
         HydraLog(StringFormat("INIT FAIL: lot[%d]='%s' invalid (min lot %.2f)", i, s, minLot));
         return(false);
        }
      if(lotStep > 0.0 && MathAbs(MathRound(lot / lotStep) * lotStep - lot) > 0.0000001)
        {
         HydraLog(StringFormat("INIT FAIL: lot[%d]=%.4f not aligned to lot step %.4f", i, lot, lotStep));
         return(false);
        }
      lots[i] = lot;
     }
   return(true);
  }

//--- Roll the per-day anchors on server-day change: balance snapshot for
//    gate 4's daily-loss cap. Phase 5 will also reset the whipsaw counter here.
void UpdateDayAnchor()
  {
   long today = (long)(TimeCurrent() / 86400);
   if((long)GVGet(GV_DAY_STAMP, -1.0) == today)
      return;
   GVSet(GV_DAY_STAMP, (double)today);
   GVSet(GV_DAY_BALANCE, AccountInfoDouble(ACCOUNT_BALANCE));
   HydraLog(StringFormat("new server day — daily-loss balance anchor %.2f", AccountInfoDouble(ACCOUNT_BALANCE)));
  }

//--- Parse "HH:MM-HH:MM" into minutes-of-day; false on any malformation
//    (missing dash, bad numbers, start >= end)
bool ParseSessionWindow(const string window, int &startMin, int &endMin)
  {
   string parts[];
   if(StringSplit(window, '-', parts) != 2)
      return(false);
   int s = ParseHHMM(parts[0]);
   int e = ParseHHMM(parts[1]);
   if(s < 0 || e < 0 || s >= e)
      return(false);
   startMin = s;
   endMin   = e;
   return(true);
  }

//--- "HH:MM" -> minutes-of-day, or -1 if malformed
int ParseHHMM(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   string hm[];
   if(StringSplit(s, ':', hm) != 2)
      return(-1);
   long h = StringToInteger(hm[0]);
   long m = StringToInteger(hm[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return(-1);
   return((int)(h * 60 + m));
  }
//+------------------------------------------------------------------+
