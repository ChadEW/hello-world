//+------------------------------------------------------------------+
//|                                     ICC_TradesBySci_EA_v1_0.mq5   |
//|   EXPERT ADVISOR port of the ICC_TradesBySci_v3.1 INDICATOR       |
//|                                                                  |
//|   Converts the v3.1 chart-marking indicator into a real trading  |
//|   EA. Keeps the full v3.1 brain:                                 |
//|     - D1 -> H4 -> H1 -> M15 four-TF cascade bias                 |
//|     - Sci-style blue/red swing rays (visual)                     |
//|     - Body-close Support/Resistance engine                       |
//|     - Broken-level handling (Gray Out) + retest state            |
//|     - Retest-confirmation entries (broken-S/R-becomes-opposite)  |
//|     - Flashing entry/exit dialog boxes (live + visual mode)      |
//|                                                                  |
//|   NEW vs the indicator: TWO real order paths via CTrade          |
//|     1) CASCADE CONTINUATION  (M15 close beyond H1 swing)         |
//|     2) RETEST CONFIRMATION   (armed broken level rejects)        |
//|   with symbol-aware Smart SL, risk-% sizing, broker-stop floor,  |
//|   trailing stop and break-even (borrowed from ICC EA v4.0).      |
//|                                                                  |
//|   Built for Chad Woodyard, July 2026.                            |
//+------------------------------------------------------------------+
#property copyright   "Chad Woodyard"
#property version     "1.00"
#property description "ICC TradesBySci EA v1.0 - cascade + retest-confirmation entries with Smart SL"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//============================= ENUMS =================================
enum ENUM_SR_DUR      { SR_DAYS = 0, SR_SESSIONS = 1 };
enum ENUM_BRK_MODE    { BRK_GRAY = 0, BRK_DELETE = 1 };
enum ENUM_ASSET_CLASS { ASSET_FOREX=0, ASSET_METAL=1, ASSET_INDEX=2, ASSET_CRYPTO=3, ASSET_OTHER=4 };
enum ENUM_SL_METHOD
  {
   SL_STRUCTURAL = 0, // Structural anchor only
   SL_ATR        = 1, // ATR x multiplier
   SL_SMART      = 2  // MAX(structural, ATR, broker min) - recommended
  };

//============================= INPUTS ================================
input group "=== Entry Paths (turn either on/off) ==="
input bool   UseCascadeEntries = true;          // Cascade continuation entries
input bool   UseRetestEntries  = true;          // Retest-confirmation entries
input bool   CloseOnOpposite   = true;          // Close open trade on opposite signal

input group "=== Timeframe Cascade (Sci D1->H4->H1->M15) ==="
input ENUM_TIMEFRAMES BiasTF   = PERIOD_D1;     // Top bias TF
input ENUM_TIMEFRAMES MidTF    = PERIOD_H4;     // Mid TF
input ENUM_TIMEFRAMES WorkTF   = PERIOD_H1;     // Working TF (swing anchor)
input ENUM_TIMEFRAMES TrigTF   = PERIOD_M15;    // Trigger TF (entry timing)
input bool   StrictAlign       = true;          // Require all 4 TFs to agree
input int    CascadeSwingLen   = 5;             // Pivot length per-TF for cascade

input group "=== Stop Loss / Sizing ==="
input ENUM_SL_METHOD SL_Method = SL_SMART;      // SL method
input double ATR_Multiplier    = 1.5;           // ATR multiplier
input int    ATR_Period        = 14;            // ATR period
input double BrokerStopCushion = 1.2;           // Safety multiple over broker min
input bool   AutoScaleByAsset  = true;          // Scale buffers for metal/index/crypto
input int    SL_Buffer_Points  = 50;            // Extra structural buffer (points)
input double RR_Ratio          = 2.0;           // TP reward : risk
input double RiskPercent       = 0.5;           // % balance risked per trade
input double FixedLots         = 0.0;           // >0 overrides risk-% sizing
input int    MaxOpenTrades     = 1;             // Max concurrent trades (this EA/symbol)
input bool   ShowDiagnostics   = true;          // Print broker diagnostics on init

input group "=== Trailing Stop ==="
input bool   UseTrailingStop   = true;
input int    TrailingStart_Pts = 200;
input int    TrailingStep_Pts  = 100;

input group "=== Break Even ==="
input bool   UseBreakEven      = true;
input int    BreakEvenAt_Pts   = 150;
input int    BreakEvenProfit   = 10;

input group "=== Session Filter ==="
input bool   UseSessionFilter  = false;
input int    SessionStartHour  = 13;            // 09:30 NY ~ 13:30 UTC
input int    SessionEndHour    = 20;            // 16:00 NY ~ 20:00 UTC

input group "=== Support / Resistance (body-close levels) ==="
input bool         SR_Show      = true;         // Run body-close S/R engine
input int          SR_MinTouch  = 3;            // Min body closes to confirm a level
input double       SR_TolPips   = 10.0;         // Zone tolerance (pips)
input ENUM_SR_DUR  SR_DurMode   = SR_DAYS;      // Level duration unit
input int          SR_DurN      = 3;            // Level duration (days or sessions)
input color        SR_ColRes    = clrOrange;    // Resistance color
input color        SR_ColSup    = clrTeal;      // Support color
input bool         SR_UseZone   = true;         // Draw as shaded zone vs line
input bool         SR_ShowCnt   = true;         // Show touch-count label
input int          SR_RefLen    = 20;           // Reference SMA length (S/R classifier)

input group "=== Broken-Level Behavior ==="
input ENUM_BRK_MODE BrkMode     = BRK_GRAY;     // Gray Out (needed for retests) or Delete
input double        BrkBufPips   = 2.0;         // Break buffer beyond level (pips)
input color         BrkColor     = clrDimGray;  // Grayed-out color

input group "=== Retest-Confirmation Entry ==="
input double RetestConfBufPips  = 1.0;          // Rejection confirmation buffer (pips)
input int    RetestArmBars      = 5;            // Arm window (bars) after a retest
input bool   RetestSepBar       = true;         // Require a separate confirmation bar
input double RetestSLbufPips    = 3.0;          // Retest SL buffer beyond level (pips)

input group "=== Visuals: Swings + Dashboard ==="
input bool   ShowSwings         = true;         // Draw swing high/low rays
input int    SwingLen           = 5;            // Swing pivot length (bars L/R)
input int    MaxSwings          = 6;            // Max recent swing lines kept
input color  ColHigh            = clrDodgerBlue;// Swing High (sellers' line)
input color  ColLow             = clrCrimson;   // Swing Low (buyers' line)
input bool   ShowDashboard      = true;         // Show cascade dashboard (Comment)

input group "=== Entry / Exit Flashing Dialog ==="
input bool   FlashOn            = true;         // Show flashing entry/exit dialog box
input int    FlashSeconds       = 6;            // How long the box flashes (seconds)
input int    FlashMs            = 400;          // Flash toggle interval (ms)
input ENUM_BASE_CORNER FlashCorner = CORNER_LEFT_UPPER;
input int    FlashX             = 220;          // X offset (px)
input int    FlashY             = 30;           // Y offset (px)
input bool   ShowFlashPrices    = true;         // Show Entry / SL / TP in the box
input color  ColBuy             = clrLime;      // BUY box color
input color  ColSell            = clrRed;       // SELL box color
input color  ColExit            = clrOrange;    // EXIT box color
input color  ColRBuy            = clrLime;      // RETEST BUY box color
input color  ColRSell           = clrRed;       // RETEST SELL box color

input group "=== Alerts ==="
input bool   AlertPopup         = true;         // Terminal pop-up (live only)
input bool   AlertPush          = false;        // Push to phone (live only)
input bool   AlertEmail         = false;        // Email (live only)
input bool   AlertSound         = false;        // Sound (live only)
input string AlertSoundFile     = "alert.wav";

input group "=== EA Settings ==="
input ulong  MagicNumber        = 20260714;
input int    Slippage           = 30;
input string TradeComment       = "ICC-Sci-EA";
input bool   DebugLog           = false;

//============================ GLOBALS ================================
CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;

double g_pip=0, g_tol=0, g_brkBuf=0, g_confBuf=0, g_slBuf=0;
int    g_sessCount=0, g_lastDayKey=-1;
int    g_barCount=0;                 // running closed-bar counter (arm window)
int    atrHandle=INVALID_HANDLE;
int    g_maHandle=INVALID_HANDLE;
int    g_uid=0;
ENUM_ASSET_CLASS AssetClass=ASSET_FOREX;
string AssetClassLabel="FOREX";
int    SLBufPts_Runtime=0;           // asset-scaled copy of SL_Buffer_Points
int    TrailStart_Runtime=0, TrailStep_Runtime=0, BEat_Runtime=0, BEprofit_Runtime=0;

string PFX    = "ICCsciEA_";
string SR_PFX = "ICCsciEA_SR_";
string SW_PFX = "ICCsciEA_SW_";

// ---- swing ray names ----
string g_swingNames[];

// ---- cascade bias ----
struct SwingCache { double lastHi, prevHi, lastLo, prevLo; };
SwingCache cD1, cH4, cH1, cM15;
int  biasD1=0, biasH4=0, biasH1=0, biasM15=0;
bool alignBull=false, alignBear=false;
double wkLastHi=0, wkLastLo=0;

// ---- cascade continuation edge detection ----
bool prevBuyCont=false, prevSellCont=false;

// ---- S/R cluster storage (parallel arrays) ----
double   sr_price[];    int      sr_count[];
datetime sr_birthTime[]; int     sr_birthSes[];
datetime sr_birthBar[];  bool    sr_isRes[];
bool     sr_drawn[];     bool    sr_broken[];
bool     sr_retested[];  bool    sr_armed[];
int      sr_armBar[];    string  sr_name[];

// ---- retest-confirmation signal outputs (set each bar by SR_CheckConfirm) ----
bool   retestBuySig=false, retestSellSig=false;
double retestSigLevel=0;
bool   srRetestThisBar=false, srRetestIsRes=false;

// ---- alerts ----
datetime lastAlertTime=0;

// ---- flashing dialog state ----
string FLASH_NAME="ICCsciEA_FLASH";
bool   g_flashActive=false;
int    g_flashTicks=0;
bool   g_flashPhase=false;
string g_flashMsg="";
color  g_flashBase=clrLime;
bool   g_flashHasPx=false;
double g_flashEntry=0, g_flashSL=0, g_flashTP=0;

//+==================================================================+
//|                 ASSET CLASS + SCALING                            |
//+==================================================================+
ENUM_ASSET_CLASS DetectAssetClass()
  {
   string sym=_Symbol; StringToUpper(sym);
   if(StringFind(sym,"XAU")>=0||StringFind(sym,"GOLD")>=0||StringFind(sym,"XAG")>=0||
      StringFind(sym,"SILVER")>=0||StringFind(sym,"XPT")>=0||StringFind(sym,"XPD")>=0)
     { AssetClassLabel="METAL"; return ASSET_METAL; }
   if(StringFind(sym,"BTC")>=0||StringFind(sym,"ETH")>=0||StringFind(sym,"XRP")>=0||
      StringFind(sym,"LTC")>=0||StringFind(sym,"BCH")>=0||StringFind(sym,"SOL")>=0||
      StringFind(sym,"DOGE")>=0||StringFind(sym,"ADA")>=0)
     { AssetClassLabel="CRYPTO"; return ASSET_CRYPTO; }
   if(StringFind(sym,"US30")>=0||StringFind(sym,"US500")>=0||StringFind(sym,"NAS")>=0||
      StringFind(sym,"SPX")>=0||StringFind(sym,"DJ")>=0||StringFind(sym,"DAX")>=0||
      StringFind(sym,"FTSE")>=0||StringFind(sym,"NIK")>=0||StringFind(sym,"HK50")>=0||
      StringFind(sym,"AUS200")>=0||StringFind(sym,"GER")>=0||StringFind(sym,"UK100")>=0)
     { AssetClassLabel="INDEX"; return ASSET_INDEX; }
   if(StringLen(sym)>=6){ AssetClassLabel="FOREX"; return ASSET_FOREX; }
   AssetClassLabel="OTHER"; return ASSET_OTHER;
  }

void ApplyAssetClassScaling()
  {
   SLBufPts_Runtime  = SL_Buffer_Points;
   TrailStart_Runtime= TrailingStart_Pts;
   TrailStep_Runtime = TrailingStep_Pts;
   BEat_Runtime      = BreakEvenAt_Pts;
   BEprofit_Runtime  = BreakEvenProfit;
   if(!AutoScaleByAsset) return;
   int mult=1;
   switch(AssetClass)
     {
      case ASSET_METAL:  mult=30;  break;
      case ASSET_INDEX:  mult=20;  break;
      case ASSET_CRYPTO: mult=300; break;
      default: return;
     }
   SLBufPts_Runtime  *= mult;
   TrailStart_Runtime*= mult;
   TrailStep_Runtime *= mult;
   BEat_Runtime      *= mult;
   BEprofit_Runtime  *= mult;
   PrintFormat("ASSET SCALING [%s]: SL_Buffer %d -> %d | Trail %d/%d",
               AssetClassLabel, SL_Buffer_Points, SLBufPts_Runtime,
               TrailStart_Runtime, TrailStep_Runtime);
  }

//+==================================================================+
//|                 SMART STOP CALCULATIONS                          |
//+==================================================================+
double GetMinStopDistance()
  {
   long stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread  = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)*point;
   double minDist = MathMax((double)stopsLvl,(double)freezeLvl)*point;
   minDist = MathMax(minDist, spread*3.0);
   minDist = MathMax(minDist, point*10.0);
   return minDist;
  }

double GetATRStopDistance()
  {
   if(atrHandle==INVALID_HANDLE) return GetMinStopDistance()*2;
   double atr[]; ArraySetAsSeries(atr,true);
   if(CopyBuffer(atrHandle,0,1,1,atr)<1) return GetMinStopDistance()*2;
   if(atr[0]<=0) return GetMinStopDistance()*2;
   return atr[0]*ATR_Multiplier;
  }

double CalculateSLDistance(double structuralDist)
  {
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bufStop = SLBufPts_Runtime*point + structuralDist;
   double minStop = GetMinStopDistance();
   double atrStop = GetATRStopDistance();
   double finalDist;
   switch(SL_Method)
     {
      case SL_STRUCTURAL: finalDist=bufStop; break;
      case SL_ATR:        finalDist=atrStop; break;
      case SL_SMART:
      default:            finalDist=MathMax(MathMax(bufStop,atrStop), minStop*BrokerStopCushion); break;
     }
   finalDist = MathMax(finalDist, minStop*BrokerStopCushion);
   return finalDist;
  }

void PrintBrokerDiagnostics()
  {
   if(!ShowDiagnostics) return;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("==============================================================");
   Print("        ICC TradesBySci EA v1.0 - BROKER DIAGNOSTICS          ");
   Print("==============================================================");
   Print(" Symbol:       ", _Symbol, "  Asset: ", AssetClassLabel);
   Print(" Chart TF:     ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print(" Cascade:      ", EnumToString(BiasTF), " -> ", EnumToString(MidTF),
                            " -> ", EnumToString(WorkTF), " -> ", EnumToString(TrigTF));
   Print(" Entry paths:  Cascade=", (UseCascadeEntries?"ON":"OFF"),
                       "  Retest=", (UseRetestEntries?"ON":"OFF"));
   Print(" Stops Level:  ", stopsLvl, " pts   Spread: ", spread, " pts");
   Print(" SL Method:    ", EnumToString(SL_Method), "   RR: ", DoubleToString(RR_Ratio,1));
   Print(" Min SafeStop: ", DoubleToString(GetMinStopDistance(),(int)digits),
         " | x Cushion: ", DoubleToString(GetMinStopDistance()*BrokerStopCushion,(int)digits));
   Print("==============================================================");
  }

//+==================================================================+
//|                 CASCADE BIAS ENGINE                              |
//+==================================================================+
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid=iHigh(_Symbol,tf,shift);
   if(mid==0) return false;
   for(int i=1;i<=L;i++)
     {
      if(iHigh(_Symbol,tf,shift-i)>=mid) return false;
      if(iHigh(_Symbol,tf,shift+i)> mid) return false;
     }
   return true;
  }
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid=iLow(_Symbol,tf,shift);
   if(mid==0) return false;
   for(int i=1;i<=L;i++)
     {
      if(iLow(_Symbol,tf,shift-i)<=mid) return false;
      if(iLow(_Symbol,tf,shift+i)< mid) return false;
     }
   return true;
  }
void RefreshSwingsTF(ENUM_TIMEFRAMES tf, SwingCache &c)
  {
   c.lastHi=c.prevHi=c.lastLo=c.prevLo=0;
   int bars=Bars(_Symbol,tf);
   int fh=0,fl=0;
   for(int shift=CascadeSwingLen+1; shift<bars-CascadeSwingLen-1 && (fh<2||fl<2); shift++)
     {
      if(fh<2 && IsPivotHighTF(tf,shift,CascadeSwingLen))
        { double px=iHigh(_Symbol,tf,shift); if(fh==0) c.lastHi=px; else c.prevHi=px; fh++; }
      if(fl<2 && IsPivotLowTF(tf,shift,CascadeSwingLen))
        { double px=iLow(_Symbol,tf,shift);  if(fl==0) c.lastLo=px; else c.prevLo=px; fl++; }
     }
  }
int BiasOf(const SwingCache &c)
  {
   if(c.lastHi==0||c.prevHi==0||c.lastLo==0||c.prevLo==0) return 0;
   if(c.lastHi>c.prevHi && c.lastLo>c.prevLo) return  1;
   if(c.lastHi<c.prevHi && c.lastLo<c.prevLo) return -1;
   return 0;
  }
void EvaluateCascade()
  {
   RefreshSwingsTF(BiasTF,cD1);
   RefreshSwingsTF(MidTF, cH4);
   RefreshSwingsTF(WorkTF,cH1);
   RefreshSwingsTF(TrigTF,cM15);
   biasD1=BiasOf(cD1); biasH4=BiasOf(cH4); biasH1=BiasOf(cH1); biasM15=BiasOf(cM15);
   wkLastHi=cH1.lastHi; wkLastLo=cH1.lastLo;
   if(StrictAlign)
     {
      alignBull=(biasD1==1 && biasH4==1 && biasH1==1 && biasM15==1);
      alignBear=(biasD1==-1&& biasH4==-1&& biasH1==-1&& biasM15==-1);
     }
   else
     {
      alignBull=(biasH1==1 && biasM15==1);
      alignBear=(biasH1==-1&& biasM15==-1);
     }
  }

//+==================================================================+
//|                 SCI SWING RAYS (visual)                          |
//+==================================================================+
void MakeSwing(datetime t, double px, color col)
  {
   string nm=SW_PFX+IntegerToString(g_uid++);
   ObjectCreate(0,nm,OBJ_TREND,0,t,px,TimeCurrent(),px);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,true);
   int n=ArraySize(g_swingNames); ArrayResize(g_swingNames,n+1); g_swingNames[n]=nm;
   while(ArraySize(g_swingNames)>MaxSwings*2)
     {
      ObjectDelete(0,g_swingNames[0]);
      for(int i=0;i<ArraySize(g_swingNames)-1;i++) g_swingNames[i]=g_swingNames[i+1];
      ArrayResize(g_swingNames,ArraySize(g_swingNames)-1);
     }
  }
void ProcessSwing()
  {
   if(!ShowSwings) return;
   int need=SwingLen*2+2;
   double hi[],lo[]; datetime tm[];
   ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true); ArraySetAsSeries(tm,true);
   if(CopyHigh(_Symbol,_Period,0,need,hi)<need) return;
   if(CopyLow (_Symbol,_Period,0,need,lo)<need) return;
   if(CopyTime(_Symbol,_Period,0,need,tm)<need) return;
   int c=SwingLen;
   bool isHigh=true,isLow=true;
   for(int k=1;k<=SwingLen;k++)
     {
      if(hi[c]<=hi[c+k]||hi[c]<=hi[c-k]) isHigh=false;
      if(lo[c]>=lo[c+k]||lo[c]>=lo[c-k]) isLow =false;
     }
   if(isHigh) MakeSwing(tm[c],hi[c],ColHigh);
   if(isLow)  MakeSwing(tm[c],lo[c],ColLow);
  }

//+==================================================================+
//|                 BODY-CLOSE S/R ENGINE                            |
//+==================================================================+
double RefSMA()
  {
   if(g_maHandle==INVALID_HANDLE) return SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_maHandle,0,1,1,buf)==1) return buf[0];
   return SymbolInfoDouble(_Symbol,SYMBOL_BID);
  }

void SR_CheckBroken(double c)
  {
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      if(!sr_drawn[i]||sr_broken[i]) continue;
      double lvl=sr_price[i];
      bool brokeUp  =( sr_isRes[i] && c>lvl+g_brkBuf);
      bool brokeDown=(!sr_isRes[i] && c<lvl-g_brkBuf);
      if(brokeUp||brokeDown)
        {
         if(BrkMode==BRK_DELETE){ DeleteLevelObjects(i); RemoveAt(i); }
         else                   { sr_broken[i]=true; GrayOutLevel(i); }
        }
     }
  }
void SR_CheckRetest(double barHigh, double barLow, double barClose)
  {
   srRetestThisBar=false;
   if(BrkMode!=BRK_GRAY) return;
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      if(!sr_broken[i]||sr_retested[i]) continue;
      double lvl=sr_price[i];
      bool retRes=( sr_isRes[i] && barLow <=lvl+g_brkBuf && barClose>=lvl-g_brkBuf);
      bool retSup=(!sr_isRes[i] && barHigh>=lvl-g_brkBuf && barClose<=lvl+g_brkBuf);
      if(retRes||retSup)
        {
         sr_retested[i]=true;
         sr_armed[i]=true;
         sr_armBar[i]=g_barCount;
         srRetestThisBar=true;
         srRetestIsRes=sr_isRes[i];
        }
     }
  }
void SR_CheckConfirm(double c)
  {
   retestBuySig=false; retestSellSig=false; retestSigLevel=0;
   if(!UseRetestEntries) return;
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      if(!sr_armed[i]) continue;
      double lvl=sr_price[i];
      int    age=g_barCount-sr_armBar[i];
      if(age>RetestArmBars){ sr_armed[i]=false; continue; }
      bool canCheck = RetestSepBar ? (age>=1) : (age>=0);
      if(!canCheck) continue;
      bool confBuy =( sr_isRes[i] && c>lvl+g_confBuf);   // broken R now S -> BUY
      bool confSell=(!sr_isRes[i] && c<lvl-g_confBuf);   // broken S now R -> SELL
      if(confBuy)  { sr_armed[i]=false; retestBuySig=true;  retestSigLevel=lvl; }
      else if(confSell){ sr_armed[i]=false; retestSellSig=true; retestSigLevel=lvl; }
     }
  }
void GrayOutLevel(int i)
  {
   string nm=sr_name[i];
   if(SR_UseZone && ObjectFind(0,nm+"_box")>=0)
     { ObjectSetInteger(0,nm+"_box",OBJPROP_COLOR,BrkColor); ObjectSetInteger(0,nm+"_box",OBJPROP_STYLE,STYLE_DOT); }
   if(!SR_UseZone && ObjectFind(0,nm+"_ln")>=0)
     { ObjectSetInteger(0,nm+"_ln",OBJPROP_COLOR,BrkColor); ObjectSetInteger(0,nm+"_ln",OBJPROP_STYLE,STYLE_DASH); }
   if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0)
     { ObjectSetInteger(0,nm+"_lb",OBJPROP_COLOR,BrkColor);
       ObjectSetString(0,nm+"_lb",OBJPROP_TEXT,"x "+(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i])); }
  }
void ProcessBar(double c, datetime t)
  {
   MqlDateTime mt; TimeToStruct(t,mt);
   int dayKey=mt.year*10000+mt.mon*100+mt.day;
   if(dayKey!=g_lastDayKey){ g_sessCount++; g_lastDayKey=dayKey; }
   bool matched=false;
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(sr_broken[i]) continue;
      if(MathAbs(c-sr_price[i])<=g_tol)
        {
         int nc=sr_count[i]+1;
         sr_price[i]=(sr_price[i]*sr_count[i]+c)/nc;
         sr_count[i]=nc; matched=true;
         if(nc==SR_MinTouch && !sr_drawn[i]){ sr_drawn[i]=true; sr_isRes[i]=(sr_price[i]>=RefSMA()); DrawLevel(i); }
         else if(nc>SR_MinTouch && SR_ShowCnt && sr_drawn[i]) UpdateLabel(i);
         break;
        }
     }
   if(!matched)
     {
      int n=ArraySize(sr_price);
      ArrayResize(sr_price,n+1);     ArrayResize(sr_count,n+1);
      ArrayResize(sr_birthTime,n+1); ArrayResize(sr_birthSes,n+1);
      ArrayResize(sr_birthBar,n+1);  ArrayResize(sr_isRes,n+1);
      ArrayResize(sr_drawn,n+1);     ArrayResize(sr_broken,n+1);
      ArrayResize(sr_retested,n+1);  ArrayResize(sr_armed,n+1);
      ArrayResize(sr_armBar,n+1);    ArrayResize(sr_name,n+1);
      sr_price[n]=c; sr_count[n]=1; sr_birthTime[n]=t; sr_birthSes[n]=g_sessCount;
      sr_birthBar[n]=t; sr_isRes[n]=false; sr_drawn[n]=false; sr_broken[n]=false;
      sr_retested[n]=false; sr_armed[n]=false; sr_armBar[n]=0;
      sr_name[n]=SR_PFX+IntegerToString(g_uid++);
      if(ArraySize(sr_price)>60) RemoveAt(0);
     }
  }
void ExpireLevels(datetime now)
  {
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      bool expired=false;
      if(SR_DurMode==SR_DAYS) expired=((now-sr_birthTime[i])>=(long)SR_DurN*86400);
      else                    expired=((g_sessCount-sr_birthSes[i])>=SR_DurN);
      if(expired){ DeleteLevelObjects(i); RemoveAt(i); }
     }
  }
void UpdateActiveLevels(datetime now)
  {
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(!sr_drawn[i]||sr_broken[i]) continue;
      string nm=sr_name[i];
      if(SR_UseZone){ if(ObjectFind(0,nm+"_box")>=0) ObjectSetInteger(0,nm+"_box",OBJPROP_TIME,1,now); }
      else          { if(ObjectFind(0,nm+"_ln")>=0)  ObjectSetInteger(0,nm+"_ln",OBJPROP_TIME,1,now); }
      if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0) ObjectSetInteger(0,nm+"_lb",OBJPROP_TIME,now);
     }
  }
void DrawLevel(int i)
  {
   string nm=sr_name[i]; color col=sr_isRes[i]?SR_ColRes:SR_ColSup;
   double p=sr_price[i]; datetime t1=sr_birthBar[i]; datetime t2=TimeCurrent();
   if(SR_UseZone)
     {
      string on=nm+"_box";
      ObjectCreate(0,on,OBJ_RECTANGLE,0,t1,p+g_tol/2.0,t2,p-g_tol/2.0);
      ObjectSetInteger(0,on,OBJPROP_COLOR,col);
      ObjectSetInteger(0,on,OBJPROP_FILL,true);
      ObjectSetInteger(0,on,OBJPROP_BACK,true);
     }
   else
     {
      string on=nm+"_ln";
      ObjectCreate(0,on,OBJ_TREND,0,t1,p,t2,p);
      ObjectSetInteger(0,on,OBJPROP_COLOR,col);
      ObjectSetInteger(0,on,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,on,OBJPROP_RAY_RIGHT,false);
     }
   if(SR_ShowCnt)
     {
      string lb=nm+"_lb";
      ObjectCreate(0,lb,OBJ_TEXT,0,t2,p);
      ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
      ObjectSetInteger(0,lb,OBJPROP_COLOR,col);
      ObjectSetInteger(0,lb,OBJPROP_ANCHOR,sr_isRes[i]?ANCHOR_LOWER:ANCHOR_UPPER);
      ObjectSetInteger(0,lb,OBJPROP_FONTSIZE,8);
     }
  }
void UpdateLabel(int i)
  {
   string lb=sr_name[i]+"_lb";
   if(ObjectFind(0,lb)>=0) ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
  }
void DeleteLevelObjects(int i)
  { string nm=sr_name[i]; ObjectDelete(0,nm+"_box"); ObjectDelete(0,nm+"_ln"); ObjectDelete(0,nm+"_lb"); }
void RemoveAt(int idx)
  {
   int n=ArraySize(sr_price); if(idx<0||idx>=n) return;
   for(int i=idx;i<n-1;i++)
     {
      sr_price[i]=sr_price[i+1];         sr_count[i]=sr_count[i+1];
      sr_birthTime[i]=sr_birthTime[i+1]; sr_birthSes[i]=sr_birthSes[i+1];
      sr_birthBar[i]=sr_birthBar[i+1];   sr_isRes[i]=sr_isRes[i+1];
      sr_drawn[i]=sr_drawn[i+1];         sr_broken[i]=sr_broken[i+1];
      sr_retested[i]=sr_retested[i+1];   sr_armed[i]=sr_armed[i+1];
      sr_armBar[i]=sr_armBar[i+1];       sr_name[i]=sr_name[i+1];
     }
   ArrayResize(sr_price,n-1);     ArrayResize(sr_count,n-1);
   ArrayResize(sr_birthTime,n-1); ArrayResize(sr_birthSes,n-1);
   ArrayResize(sr_birthBar,n-1);  ArrayResize(sr_isRes,n-1);
   ArrayResize(sr_drawn,n-1);     ArrayResize(sr_broken,n-1);
   ArrayResize(sr_retested,n-1);  ArrayResize(sr_armed,n-1);
   ArrayResize(sr_armBar,n-1);    ArrayResize(sr_name,n-1);
  }
int ActiveSRCount()
  { int cnt=0; for(int i=0;i<ArraySize(sr_drawn);i++) if(sr_drawn[i]&&!sr_broken[i]) cnt++; return cnt; }
int ArmedCount()
  { int cnt=0; for(int i=0;i<ArraySize(sr_armed);i++) if(sr_armed[i]) cnt++; return cnt; }

//+==================================================================+
//|                 FLASHING DIALOG BOX                              |
//+==================================================================+
void SetLabel(string nm,int corner,int x,int y,string txt,color col,int fsize,string font)
  {
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,nm,OBJPROP_TEXT,txt);
   ObjectSetString (0,nm,OBJPROP_FONT,font);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fsize);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
  }
void DrawFlashBox(bool on)
  {
   int boxH=g_flashHasPx?92:40;
   string bg=FLASH_NAME+"_bg";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,FlashCorner);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,FlashX);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,FlashY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,180);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,boxH);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,on?g_flashBase:clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,g_flashBase);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   SetLabel(FLASH_NAME,FlashCorner,FlashX+12,FlashY+11,g_flashMsg,on?clrWhite:g_flashBase,12,"Arial Black");
   if(g_flashHasPx)
     {
      SetLabel(FLASH_NAME+"_e", FlashCorner,FlashX+12,FlashY+34,"E:  "+DoubleToString(g_flashEntry,_Digits),clrWhite,9,"Consolas");
      SetLabel(FLASH_NAME+"_sl",FlashCorner,FlashX+12,FlashY+53,"SL: "+DoubleToString(g_flashSL,_Digits),clrTomato,9,"Consolas");
      SetLabel(FLASH_NAME+"_tp",FlashCorner,FlashX+12,FlashY+72,"TP: "+DoubleToString(g_flashTP,_Digits),clrLime,9,"Consolas");
     }
   else
     { ObjectDelete(0,FLASH_NAME+"_e"); ObjectDelete(0,FLASH_NAME+"_sl"); ObjectDelete(0,FLASH_NAME+"_tp"); }
  }
void ClearFlashBox()
  {
   ObjectDelete(0,FLASH_NAME);      ObjectDelete(0,FLASH_NAME+"_bg");
   ObjectDelete(0,FLASH_NAME+"_e"); ObjectDelete(0,FLASH_NAME+"_sl");
   ObjectDelete(0,FLASH_NAME+"_tp");
  }
void TriggerFlash(string msg,color base,bool hasPx,double e,double sl,double tp)
  {
   if(!FlashOn) return;
   g_flashActive=true; g_flashMsg=msg; g_flashBase=base; g_flashPhase=true;
   g_flashHasPx=(hasPx && ShowFlashPrices);
   g_flashEntry=e; g_flashSL=sl; g_flashTP=tp;
   g_flashTicks=(int)MathMax(2,(FlashSeconds*1000)/MathMax(50,FlashMs));
   DrawFlashBox(true);
   ChartRedraw();
  }

//+==================================================================+
//|                 ALERTS                                           |
//+==================================================================+
void DispatchAlert(string m)
  {
   Print("ICC-Sci-EA: ",m);
   if(AlertPopup) Alert(m);
   if(AlertPush)  SendNotification(m);
   if(AlertEmail) SendMail("ICC TradesBySci EA - "+_Symbol,m);
   if(AlertSound) PlaySound(AlertSoundFile);
   lastAlertTime=TimeCurrent();
  }

//+==================================================================+
//|                 POSITION / RISK MANAGEMENT                       |
//+==================================================================+
double NormalizeLots(double l)
  {
   double mn=symInfo.LotsMin(), mx=symInfo.LotsMax(), st=symInfo.LotsStep();
   l=MathMax(l,mn); l=MathMin(l,mx); l=MathFloor(l/st)*st;
   return NormalizeDouble(l,2);
  }
double CalculateLotSize(double sd)
  {
   if(FixedLots>0) return NormalizeLots(FixedLots);
   if(sd<=0) return 0;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=bal*RiskPercent/100.0;
   double tv=symInfo.TickValue(), ts=symInfo.TickSize();
   if(tv<=0||ts<=0) return symInfo.LotsMin();
   return NormalizeLots(risk/((sd/ts)*tv));
  }
int CountOpenTrades()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     if(posInfo.SelectByIndex(i))
       if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol) c++;
   return c;
  }
int OpenTradeDir()  // 1 long, -1 short, 0 flat (this EA/symbol)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     if(posInfo.SelectByIndex(i))
       if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol)
         return (posInfo.PositionType()==POSITION_TYPE_BUY)?1:-1;
   return 0;
  }
void CloseAllThisEA(string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      ulong tk=posInfo.Ticket();
      if(trade.PositionClose(tk))
        {
         TriggerFlash(reason,ColExit,false,0,0,0);
         DispatchAlert(reason+" | "+_Symbol);
        }
     }
  }
void ManagePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double pt=symInfo.Point(); ulong tk=posInfo.Ticket();
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid(), pp=(bid-op)/pt;
          if(UseBreakEven && pp>=BEat_Runtime){ double ns=op+BEprofit_Runtime*pt; if(sl<ns) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailStart_Runtime){ double ts=bid-TrailStep_Runtime*pt; if(ts>sl) trade.PositionModify(tk,ts,tp); } }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask(), pp=(op-ask)/pt;
          if(UseBreakEven && pp>=BEat_Runtime){ double ns=op-BEprofit_Runtime*pt; if(sl>ns||sl==0) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailStart_Runtime){ double ts=ask+TrailStep_Runtime*pt; if(ts<sl||sl==0) trade.PositionModify(tk,ts,tp); } }
     }
  }

//+==================================================================+
//|                 ORDER EXECUTION                                  |
//+==================================================================+
// slAnchor is the structural stop reference (H1 swing for cascade, level±buffer for retest)
void ExecuteBuy(double slAnchor, string tag, color boxCol)
  {
   double ask=symInfo.Ask();
   double minStop=GetMinStopDistance();
   double structDist=ask-slAnchor; if(structDist<0) structDist=0;
   double slDist=CalculateSLDistance(structDist);
   double slPrice=NormalizeDouble(ask-slDist,_Digits);
   if(ask-slPrice<minStop*BrokerStopCushion){ if(DebugLog) Print("BUY skip: SL too close"); return; }
   double slFinal=ask-slPrice;
   double tpPrice=NormalizeDouble(ask+slFinal*RR_Ratio,_Digits);
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("BUY skip: lots<=0"); return; }
   if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,TradeComment))
     {
      TriggerFlash(tag,boxCol,true,ask,slPrice,tpPrice);
      DispatchAlert(StringFormat("%s | %s | E:%s SL:%s TP:%s",
        tag,_Symbol,DoubleToString(ask,_Digits),DoubleToString(slPrice,_Digits),DoubleToString(tpPrice,_Digits)));
     }
   else
      PrintFormat("BUY FAILED [%d]: %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
void ExecuteSell(double slAnchor, string tag, color boxCol)
  {
   double bid=symInfo.Bid();
   double minStop=GetMinStopDistance();
   double structDist=slAnchor-bid; if(structDist<0) structDist=0;
   double slDist=CalculateSLDistance(structDist);
   double slPrice=NormalizeDouble(bid+slDist,_Digits);
   if(slPrice-bid<minStop*BrokerStopCushion){ if(DebugLog) Print("SELL skip: SL too close"); return; }
   double slFinal=slPrice-bid;
   double tpPrice=NormalizeDouble(bid-slFinal*RR_Ratio,_Digits);
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("SELL skip: lots<=0"); return; }
   if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,TradeComment))
     {
      TriggerFlash(tag,boxCol,true,bid,slPrice,tpPrice);
      DispatchAlert(StringFormat("%s | %s | E:%s SL:%s TP:%s",
        tag,_Symbol,DoubleToString(bid,_Digits),DoubleToString(slPrice,_Digits),DoubleToString(tpPrice,_Digits)));
     }
   else
      PrintFormat("SELL FAILED [%d]: %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }

//+==================================================================+
//|                 SIGNAL ROUTING                                   |
//+==================================================================+
void TryEntries()
  {
   if(UseSessionFilter && !IsWithinSession()) return;

   // --- cascade continuation edges ---
   double trigClose=iClose(_Symbol,TrigTF,1);
   bool buyCont = UseCascadeEntries && alignBull && wkLastHi>0 && trigClose>wkLastHi;
   bool sellCont= UseCascadeEntries && alignBear && wkLastLo>0 && trigClose<wkLastLo;
   bool cascBuy  = buyCont  && !prevBuyCont;
   bool cascSell = sellCont && !prevSellCont;
   prevBuyCont=buyCont; prevSellCont=sellCont;

   bool buySig  = cascBuy  || retestBuySig;
   bool sellSig = cascSell || retestSellSig;

   int dir=OpenTradeDir();

   // --- close on opposite signal ---
   if(CloseOnOpposite && dir==1 && sellSig){ CloseAllThisEA("EXIT LONG"); dir=0; }
   if(CloseOnOpposite && dir==-1 && buySig){ CloseAllThisEA("EXIT SHORT"); dir=0; }

   if(CountOpenTrades()>=MaxOpenTrades) return;
   if(dir!=0) return;

   // --- entries when flat: retest takes priority ---
   if(retestBuySig)
     { double anchor=retestSigLevel-g_slBuf; ExecuteBuy(anchor,"RETEST BUY",ColRBuy); return; }
   if(retestSellSig)
     { double anchor=retestSigLevel+g_slBuf; ExecuteSell(anchor,"RETEST SELL",ColRSell); return; }
   if(cascBuy)
     { ExecuteBuy(wkLastLo,"BUY ENTRY",ColBuy); return; }
   if(cascSell)
     { ExecuteSell(wkLastHi,"SELL ENTRY",ColSell); return; }
  }

bool IsWithinSession()
  {
   MqlDateTime dt; TimeCurrent(dt);
   if(SessionStartHour<SessionEndHour) return(dt.hour>=SessionStartHour && dt.hour<SessionEndHour);
   return(dt.hour>=SessionStartHour || dt.hour<SessionEndHour);
  }
bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0); if(ct!=lt){ lt=ct; return true; } return false; }

//+==================================================================+
//|                 DASHBOARD                                        |
//+==================================================================+
void UpdateDashboard()
  {
   if(!ShowDashboard){ Comment(""); return; }
   string bD=biasD1==1?"^":biasD1==-1?"v":"-";
   string b4=biasH4==1?"^":biasH4==-1?"v":"-";
   string b1=biasH1==1?"^":biasH1==-1?"v":"-";
   string b5=biasM15==1?"^":biasM15==-1?"v":"-";
   string casc=alignBull?"^ ALIGNED LONG":alignBear?"v ALIGNED SHORT":"x NOT ALIGNED";
   int dir=OpenTradeDir();
   string pos=dir==1?"LONG":dir==-1?"SHORT":"flat";
   string d ="=== ICC TradesBySci EA v1.0 =============\n";
   d+=" Cascade (D1 H4 H1 M15): "+bD+" "+b4+" "+b1+" "+b5+"\n";
   d+=" Status:   "+casc+"\n";
   d+=" Position: "+pos+"  ("+IntegerToString(CountOpenTrades())+"/"+IntegerToString(MaxOpenTrades)+")\n";
   d+=" S/R lvls: "+IntegerToString(ActiveSRCount())+"  | armed: "+IntegerToString(ArmedCount())+"\n";
   d+="=========================================";
   Comment(d);
  }

//+==================================================================+
//|                 LIFECYCLE                                        |
//+==================================================================+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   symInfo.Name(_Symbol); symInfo.Refresh();

   g_pip     = _Point*((_Digits==3||_Digits==5)?10:1);
   g_tol     = SR_TolPips        *g_pip;
   g_brkBuf  = BrkBufPips        *g_pip;
   g_confBuf = RetestConfBufPips *g_pip;
   g_slBuf   = RetestSLbufPips   *g_pip;

   AssetClass=DetectAssetClass();
   ApplyAssetClassScaling();

   atrHandle=iATR(_Symbol,_Period,ATR_Period);
   if(atrHandle==INVALID_HANDLE) Print("WARNING: ATR handle failed; ATR SL will fallback.");
   g_maHandle=iMA(_Symbol,_Period,SR_RefLen,0,MODE_SMA,PRICE_CLOSE);
   if(g_maHandle==INVALID_HANDLE) Print("WARNING: SMA handle failed; S/R classifier will fallback.");

   EvaluateCascade();
   PrintBrokerDiagnostics();

   if(FlashOn) EventSetMillisecondTimer(FlashMs);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(g_maHandle!=INVALID_HANDLE) IndicatorRelease(g_maHandle);
   ObjectsDeleteAll(0,SR_PFX);
   ObjectsDeleteAll(0,SW_PFX);
   ClearFlashBox();
   Comment("");
  }

void OnTimer()
  {
   if(!FlashOn) return;
   if(!g_flashActive) return;
   g_flashPhase=!g_flashPhase;
   DrawFlashBox(g_flashPhase);
   g_flashTicks--;
   if(g_flashTicks<=0){ g_flashActive=false; ClearFlashBox(); }
   ChartRedraw();
  }

void OnTick()
  {
   // Exits are broker-enforced via the SL/TP attached at entry.
   // ManagePositions() only advances trailing-stop / break-even.
   ManagePositions();
   if(!IsNewBar()) return;
   symInfo.Refresh();
   g_barCount++;

   // just-closed bar body + time
   double c = iClose(_Symbol,_Period,1);
   datetime t = iTime(_Symbol,_Period,1);
   double barHi = iHigh(_Symbol,_Period,1);
   double barLo = iLow (_Symbol,_Period,1);

   // 1) cascade bias
   EvaluateCascade();
   // 2) swing rays (visual)
   ProcessSwing();
   // 3) body-close S/R with broken + retest + confirmation
   if(SR_Show)
     {
      SR_CheckBroken(c);
      SR_CheckRetest(barHi,barLo,c);
      SR_CheckConfirm(c);       // sets retestBuySig / retestSellSig
      ProcessBar(c,t);
      ExpireLevels(iTime(_Symbol,_Period,0));
      UpdateActiveLevels(iTime(_Symbol,_Period,0));
     }
   else { retestBuySig=false; retestSellSig=false; }
   // 4) entry routing (real orders)
   TryEntries();
   // 5) dashboard
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
