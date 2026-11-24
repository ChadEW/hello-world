//+------------------------------------------------------------------+
//| ICC_TradesBySci_EA_v3.4.1_SCI_CORE_CLEAN.mq5                    |
//| SCI-CORE: Indication -> Correction -> Continuation               |
//|                                                                  |
//| This build intentionally removes EA/SMC enhancements that are    |
//| not part of the core ICC state machine: liquidity sweeps,         |
//| displacement scoring, FVG/OB requirements, protected-internal    |
//| swing overrides, S/R/retest entries, cascade/breakout entries,   |
//| opposite-signal exits, trailing stop, break-even, session        |
//| filters, ATR-based SL logic, structural TP, dashboards, flashes, |
//| exit labels and enhancement-specific chart objects.              |
//|                                                                  |
//| CORE INTERPRETATION USED HERE:                                  |
//| 1. HTF structure establishes directional bias.                   |
//| 2. A confirmed WorkTF swing is broken for INDICATION.             |
//| 3. Price pulls back from the indication extreme for CORRECTION.  |
//| 4. A TriggerTF close resumes the indication direction for        |
//|    CONTINUATION / entry.                                         |
//| 5. SL is anchored beyond the correction extreme.                 |
//| 6. TP is fixed risk multiple (default 3R).                      |
//|                                                                  |
//| IMPORTANT: this is an explicit automated interpretation of the   |
//| core ICC concept; it does not claim to reproduce undisclosed      |
//| discretionary rules exactly.                                    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.41"
#property description "SCI-CORE ICC only: HTF bias -> Indication -> Correction -> Continuation -> LTF entry"

#include <Trade/Trade.mqh>

//============================= ENUMS =================================
enum ENUM_ICC_PHASE
  {
   PH_NONE=0,
   PH_INDICATION=1,
   PH_CORRECTION=2
  };

//============================= INPUTS ================================
input group "=== SCI CORE: Timeframes ==="
input ENUM_TIMEFRAMES BiasTF = PERIOD_D1;   // Context / highest structure
input ENUM_TIMEFRAMES MidTF  = PERIOD_H4;   // Primary HTF directional structure
input ENUM_TIMEFRAMES WorkTF = PERIOD_H1;   // Indication / correction structure
input ENUM_TIMEFRAMES TrigTF = PERIOD_M15;  // Lower-timeframe continuation trigger
input int SwingLen = 5;                     // Confirmed pivot strength

input group "=== SCI CORE: HTF Structure ==="
input bool RequireD1Confirmation = false;   // Optional context confirmation; not a sweep/FVG/OB filter
input bool RequireH1Alignment     = false;  // Optional structure alignment; OFF keeps H4 as primary bias

input group "=== SCI CORE: ICC State Machine ==="
input int ICC_ExpiryBars = 30;              // Reset incomplete setup after this many trigger bars

input group "=== SCI CORE: Trade Risk / Execution ==="
input double RiskPercent = 0.5;             // % of account balance risked per trade
input double FixedLots   = 0.0;             // >0 overrides risk-based sizing
input int MaxOpenTrades = 1;
input double SL_Buffer_Points = 50;         // Buffer beyond correction extreme
input double RR_Ratio = 3.0;                // Fixed R multiple
input double BrokerStopCushion = 1.2;       // Execution safety only

input group "=== Diagnostics ==="
input bool ShowDiagnostics = true;
input bool VerboseLog = true;
input ulong MagicNumber = 20260717;
input int Slippage = 30;
input string TradeComment = "SCI-CORE-ICC";

//============================= GLOBALS ===============================
CTrade trade;

struct SwingCache
  {
   double lastHi;
   double prevHi;
   double lastLo;
   double prevLo;
  };

SwingCache cD1,cH4,cH1,cM15;
int biasD1=0,biasH4=0,biasH1=0,biasM15=0;

double wkLastHi=0.0;
double wkLastLo=0.0;

ENUM_ICC_PHASE g_iccPhase=PH_NONE;
int    g_iccDir=0;
double g_indLevel=0.0;
double g_indExtreme=0.0;
double g_corrExtreme=0.0;
int    g_iccStartBar=0;
bool   iccBuySig=false;
bool   iccSellSig=false;
double iccSigSL=0.0;
int    g_barCount=0;

//============================= UTILITIES =============================
bool ValidPrice(double p)
  {
   return(p>0.0 && MathIsValidNumber(p));
  }

bool IsPivotHighTF(ENUM_TIMEFRAMES tf,int shift,int L)
  {
   if(L<1) return false;
   int bars=Bars(_Symbol,tf);
   if(bars<=2*L+shift+1) return false;
   double mid=iHigh(_Symbol,tf,shift);
   if(!ValidPrice(mid)) return false;
   for(int i=1;i<=L;i++)
     {
      if(iHigh(_Symbol,tf,shift-i)>=mid) return false;
      if(iHigh(_Symbol,tf,shift+i)>mid)  return false;
     }
   return true;
  }

bool IsPivotLowTF(ENUM_TIMEFRAMES tf,int shift,int L)
  {
   if(L<1) return false;
   int bars=Bars(_Symbol,tf);
   if(bars<=2*L+shift+1) return false;
   double mid=iLow(_Symbol,tf,shift);
   if(!ValidPrice(mid)) return false;
   for(int i=1;i<=L;i++)
     {
      if(iLow(_Symbol,tf,shift-i)<=mid) return false;
      if(iLow(_Symbol,tf,shift+i)<mid)  return false;
     }
   return true;
  }

void RefreshSwingsTF(ENUM_TIMEFRAMES tf,SwingCache &c)
  {
   c.lastHi=c.prevHi=c.lastLo=c.prevLo=0.0;
   int bars=Bars(_Symbol,tf);
   if(bars<2*SwingLen+10) return;

   int foundH=0,foundL=0;
   int maxShift=bars-SwingLen-2;
   for(int shift=SwingLen+1;shift<=maxShift && (foundH<2 || foundL<2);shift++)
     {
      if(foundH<2 && IsPivotHighTF(tf,shift,SwingLen))
        {
         double p=iHigh(_Symbol,tf,shift);
         if(foundH==0) c.lastHi=p; else c.prevHi=p;
         foundH++;
        }
      if(foundL<2 && IsPivotLowTF(tf,shift,SwingLen))
        {
         double p=iLow(_Symbol,tf,shift);
         if(foundL==0) c.lastLo=p; else c.prevLo=p;
         foundL++;
        }
     }
  }

int BiasOf(const SwingCache &c)
  {
   if(!ValidPrice(c.lastHi) || !ValidPrice(c.prevHi) ||
      !ValidPrice(c.lastLo) || !ValidPrice(c.prevLo)) return 0;

   bool hh=c.lastHi>c.prevHi;
   bool hl=c.lastLo>c.prevLo;
   bool lh=c.lastHi<c.prevHi;
   bool ll=c.lastLo<c.prevLo;

   // Direction is based on completed swing structure.
   if(hh && hl) return 1;
   if(lh && ll) return -1;

   // If structure is mixed, do not manufacture a directional bias.
   return 0;
  }

void RefreshStructure()
  {
   RefreshSwingsTF(BiasTF,cD1);
   RefreshSwingsTF(MidTF,cH4);
   RefreshSwingsTF(WorkTF,cH1);
   RefreshSwingsTF(TrigTF,cM15);

   biasD1=BiasOf(cD1);
   biasH4=BiasOf(cH4);
   biasH1=BiasOf(cH1);
   biasM15=BiasOf(cM15);

   wkLastHi=cH1.lastHi;
   wkLastLo=cH1.lastLo;
  }

int HTFBias()
  {
   // H4 is the primary HTF direction. D1/H1 are optional confirmations.
   if(biasH4==0) return 0;
   if(RequireD1Confirmation && biasD1!=biasH4) return 0;
   if(RequireH1Alignment && biasH1!=biasH4) return 0;
   return biasH4;
  }

string PhaseText()
  {
   if(g_iccPhase==PH_INDICATION) return "IND";
   if(g_iccPhase==PH_CORRECTION) return "COR";
   return "---";
  }

void ICC_Reset()
  {
   g_iccPhase=PH_NONE;
   g_iccDir=0;
   g_indLevel=0.0;
   g_indExtreme=0.0;
   g_corrExtreme=0.0;
   g_iccStartBar=0;
  }

//============================= ICC CORE ==============================
void ICC_Update()
  {
   iccBuySig=false;
   iccSellSig=false;
   iccSigSL=0.0;

   int htf=HTFBias();
   double trigClose=iClose(_Symbol,TrigTF,1);
   double trigHighPrev=iHigh(_Symbol,TrigTF,2);
   double trigLowPrev=iLow(_Symbol,TrigTF,2);
   double workHigh=iHigh(_Symbol,WorkTF,1);
   double workLow=iLow(_Symbol,WorkTF,1);

   if(!ValidPrice(trigClose) || !ValidPrice(trigHighPrev) ||
      !ValidPrice(trigLowPrev) || !ValidPrice(workHigh) || !ValidPrice(workLow))
      return;

   // Cancel an in-progress setup if HTF direction has changed.
   if(g_iccPhase!=PH_NONE && htf!=g_iccDir)
     {
      ICC_Reset();
     }

   // Prevent an old indication from surviving indefinitely.
   if(g_iccPhase!=PH_NONE && g_iccStartBar>0 &&
      (g_barCount-g_iccStartBar)>ICC_ExpiryBars)
     {
      ICC_Reset();
     }

   // -------------------------- LONG -------------------------------
   if(htf==1)
     {
      if(g_iccPhase==PH_NONE)
        {
         // INDICATION: HTF bullish bias + confirmed WorkTF swing break.
         if(ValidPrice(wkLastHi) && trigClose>wkLastHi)
           {
            g_iccPhase=PH_INDICATION;
            g_iccDir=1;
            g_indLevel=wkLastHi;
            g_indExtreme=MathMax(workHigh,trigClose);
            g_corrExtreme=workLow;
            g_iccStartBar=g_barCount;
           }
        }
      else if(g_iccPhase==PH_INDICATION)
        {
         // Keep the indication extreme updated while price continues away.
         if(workHigh>g_indExtreme) g_indExtreme=workHigh;

         // CORRECTION: price has moved back from the indication extreme.
         if(workLow<g_indExtreme)
           {
            g_iccPhase=PH_CORRECTION;
            g_corrExtreme=workLow;
           }
        }
      else if(g_iccPhase==PH_CORRECTION)
        {
         // Correction extreme is the structural SL reference.
         if(workLow<g_corrExtreme) g_corrExtreme=workLow;

         // CONTINUATION / ENTRY TRIGGER: closed TrigTF candle resumes up.
         if(trigClose>trigHighPrev)
           {
            iccBuySig=true;
            iccSigSL=g_corrExtreme;
            ICC_Reset();
           }
        }
     }
   // -------------------------- SHORT ------------------------------
   else if(htf==-1)
     {
      if(g_iccPhase==PH_NONE)
        {
         // INDICATION: HTF bearish bias + confirmed WorkTF swing break.
         if(ValidPrice(wkLastLo) && trigClose<wkLastLo)
           {
            g_iccPhase=PH_INDICATION;
            g_iccDir=-1;
            g_indLevel=wkLastLo;
            g_indExtreme=MathMin(workLow,trigClose);
            g_corrExtreme=workHigh;
            g_iccStartBar=g_barCount;
           }
        }
      else if(g_iccPhase==PH_INDICATION)
        {
         if(workLow<g_indExtreme) g_indExtreme=workLow;

         // CORRECTION: price has moved back from the indication extreme.
         if(workHigh>g_indExtreme)
           {
            g_iccPhase=PH_CORRECTION;
            g_corrExtreme=workHigh;
           }
        }
      else if(g_iccPhase==PH_CORRECTION)
        {
         if(workHigh>g_corrExtreme) g_corrExtreme=workHigh;

         // CONTINUATION / ENTRY TRIGGER: closed TrigTF candle resumes down.
         if(trigClose<trigLowPrev)
           {
            iccSellSig=true;
            iccSigSL=g_corrExtreme;
            ICC_Reset();
           }
        }
     }
   else
     {
      if(g_iccPhase!=PH_NONE) ICC_Reset();
     }
  }

//============================= EXECUTION ============================
double MinStopDistance()
  {
   long stops=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*point;
   double d=MathMax((double)stops,(double)freeze)*point;
   d=MathMax(d,spread*3.0);
   d=MathMax(d,point*10.0);
   return d;
  }

double NormalizeLots(double lots)
  {
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0 || maxLot<=0 || step<=0) return 0.0;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   lots=MathFloor(lots/step)*step;
   if(lots<minLot) lots=minLot;
   int volDigits=2;
   if(step<0.01) volDigits=3;
   if(step<0.001) volDigits=4;
   return NormalizeDouble(lots,volDigits);
  }

double CalculateLotSize(double slDistance)
  {
   if(FixedLots>0.0) return NormalizeLots(FixedLots);
   if(slDistance<=0.0 || RiskPercent<=0.0) return 0.0;

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney=balance*(RiskPercent/100.0);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0.0 || tickSize<=0.0) return 0.0;

   double lossPerLot=(slDistance/tickSize)*tickValue;
   if(lossPerLot<=0.0) return 0.0;
   return NormalizeLots(riskMoney/lossPerLot);
  }

int CountOpenTrades()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      count++;
     }
   return count;
  }

bool HasOpenTrade()
  {
   return CountOpenTrades()>0;
  }

bool BuildOrderPrices(int dir,double anchor,double entry,double &sl,double &tp,double &slDistance,string &reason)
  {
   reason="";
   if(!ValidPrice(entry) || !ValidPrice(anchor))
     {
      reason="invalid entry or correction anchor";
      return false;
     }

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double buffer=SL_Buffer_Points*point;
   double minStop=MinStopDistance()*BrokerStopCushion;

   if(dir>0)
     {
      sl=anchor-buffer;
      slDistance=entry-sl;
      if(slDistance<minStop) slDistance=minStop;
      sl=entry-slDistance;
      tp=entry+slDistance*RR_Ratio;
      if(!(sl<entry && tp>entry)) { reason="invalid BUY price geometry"; return false; }
     }
   else
     {
      sl=anchor+buffer;
      slDistance=sl-entry;
      if(slDistance<minStop) slDistance=minStop;
      sl=entry+slDistance;
      tp=entry-slDistance*RR_Ratio;
      if(!(sl>entry && tp<entry)) { reason="invalid SELL price geometry"; return false; }
     }

   sl=NormalizeDouble(sl,_Digits);
   tp=NormalizeDouble(tp,_Digits);

   if(dir>0)
     {
      if(entry-sl<minStop) { reason="BUY SL below broker minimum"; return false; }
      if(tp-entry<minStop) { reason="BUY TP below broker minimum"; return false; }
     }
   else
     {
      if(sl-entry<minStop) { reason="SELL SL below broker minimum"; return false; }
      if(entry-tp<minStop) { reason="SELL TP below broker minimum"; return false; }
     }
   return true;
  }

void LogOrder(const string side,double entry,double sl,double tp,double slDistance,double lots,const string stage,const string reason="")
  {
   if(!ShowDiagnostics) return;
   PrintFormat("[SCI-CORE ORDER] %s | stage=%s | entry=%.*f | SL=%.*f | TP=%.*f | SLdist=%.*f | TPdist=%.*f | lots=%.*f%s%s",
               side,stage,_Digits,entry,_Digits,sl,_Digits,tp,_Digits,slDistance,
               _Digits,(side=="BUY" ? tp-entry : entry-tp),2,lots,
               (reason==""?"":" | reason="),reason);
  }

void ExecuteBuy(double anchor)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || !ValidPrice(tick.ask)) return;

   double sl,tp,sd;
   string reason;
   if(!BuildOrderPrices(1,anchor,tick.ask,sl,tp,sd,reason))
     {
      LogOrder("BUY",tick.ask,sl,tp,sd,0,"REJECT",reason);
      return;
     }

   double lots=CalculateLotSize(sd);
   if(lots<=0.0)
     {
      LogOrder("BUY",tick.ask,sl,tp,sd,lots,"REJECT","lot calculation failed");
      return;
     }

   LogOrder("BUY",tick.ask,sl,tp,sd,lots,"READY");
   if(trade.Buy(lots,_Symbol,tick.ask,sl,tp,TradeComment))
      LogOrder("BUY",tick.ask,sl,tp,sd,lots,"ACCEPTED");
   else
      LogOrder("BUY",tick.ask,sl,tp,sd,lots,"REJECTED",trade.ResultRetcodeDescription());
  }

void ExecuteSell(double anchor)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || !ValidPrice(tick.bid)) return;

   double sl,tp,sd;
   string reason;
   if(!BuildOrderPrices(-1,anchor,tick.bid,sl,tp,sd,reason))
     {
      LogOrder("SELL",tick.bid,sl,tp,sd,0,"REJECT",reason);
      return;
     }

   double lots=CalculateLotSize(sd);
   if(lots<=0.0)
     {
      LogOrder("SELL",tick.bid,sl,tp,sd,lots,"REJECT","lot calculation failed");
      return;
     }

   LogOrder("SELL",tick.bid,sl,tp,sd,lots,"READY");
   if(trade.Sell(lots,_Symbol,tick.bid,sl,tp,TradeComment))
      LogOrder("SELL",tick.bid,sl,tp,sd,lots,"ACCEPTED");
   else
      LogOrder("SELL",tick.bid,sl,tp,sd,lots,"REJECTED",trade.ResultRetcodeDescription());
  }

//============================= ROUTING ===============================
bool IsNewBar()
  {
   static datetime lastBar=0;
   datetime current=iTime(_Symbol,TrigTF,0);
   if(current<=0) return false;
   if(current!=lastBar)
     {
      lastBar=current;
      return true;
     }
   return false;
  }

void RouteSignal()
  {
   if(CountOpenTrades()>=MaxOpenTrades) return;
   if(HasOpenTrade()) return;

   if(iccBuySig)
     {
      ExecuteBuy(iccSigSL);
      return;
     }
   if(iccSellSig)
     {
      ExecuteSell(iccSigSL);
      return;
     }
  }

void PrintCoreState()
  {
   if(!VerboseLog) return;
   PrintFormat("[ICC CORE] bar=%d D1/H4/H1/M15=%d/%d/%d/%d HTF=%d | phase=%s dir=%d ind=%.2f ext=%.2f corr=%.2f | ICC(b/s)=%d/%d",
               g_barCount,biasD1,biasH4,biasH1,biasM15,HTFBias(),PhaseText(),g_iccDir,
               g_indLevel,g_indExtreme,g_corrExtreme,(int)iccBuySig,(int)iccSellSig);
  }

//============================= LIFECYCLE ============================
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(SwingLen<1 || ICC_ExpiryBars<1 || RR_Ratio<=0.0 || RiskPercent<0.0)
      return INIT_PARAMETERS_INCORRECT;

   ICC_Reset();
   RefreshStructure();

   if(ShowDiagnostics)
     {
      Print("==============================================================");
      Print("SCI-CORE ICC engine initialized");
      Print("Symbol=",_Symbol," ChartTF=",EnumToString((ENUM_TIMEFRAMES)_Period));
      Print("BiasTF=",EnumToString(BiasTF)," MidTF=",EnumToString(MidTF),
            " WorkTF=",EnumToString(WorkTF)," TrigTF=",EnumToString(TrigTF));
      Print("RiskPercent=",DoubleToString(RiskPercent,2),
            " FixedLots=",DoubleToString(FixedLots,2),
            " RR_Ratio=",DoubleToString(RR_Ratio,2));
      Print("Removed: liquidity sweep, displacement, FVG, OB, protected-swing override, S/R/retest, cascade, opposite exits, BE, trailing, session filter, ATR SL, structural TP and enhancement visuals.");
      Print("==============================================================");
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
  }

void OnTick()
  {
   if(!IsNewBar()) return;

   g_barCount++;
   RefreshStructure();
   ICC_Update();
   PrintCoreState();
   RouteSignal();
  }
//+------------------------------------------------------------------+
