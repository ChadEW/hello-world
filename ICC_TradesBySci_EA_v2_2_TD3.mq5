//+------------------------------------------------------------------+
//|                                 ICC_TradesBySci_EA_v2_2_TD3.mq5   |
//|   EXPERT ADVISOR v2.2 — v2.1 (soft D1-weighted ICC pullback)     |
//|   PLUS a self-contained Twin Delayed DDPG (TD3) module.          |
//|                                                                  |
//|   WHAT TD3 DOES HERE (hybrid design — see Appendix J):           |
//|     The deterministic ICC engine remains the ENTRY GATE (fully   |
//|     transparent). TD3 does NOT decide direction. Instead it      |
//|     learns three continuous "knobs" applied to each trade:       |
//|        a0 -> Risk multiplier   (scales RiskPercent)              |
//|        a1 -> RR multiplier     (scales RR_Ratio)                 |
//|        a2 -> SL-distance mult   (scales Smart-SL distance)       |
//|     State  = normalized {HTF bias, HTF score, ICC phase/dir,     |
//|              volatility, recent return, open-position dir/R}.    |
//|     Reward = per-bar equity change in R-units minus a turnover   |
//|              penalty (risk-adjusted; clipped).                   |
//|                                                                  |
//|   TD3 IMPLEMENTATION (pure MQL5, no DLLs, no external libs):     |
//|     - Actor + twin Critics + their target networks (6 MLPs)     |
//|     - Clipped double-Q, delayed policy updates, target-policy    |
//|       smoothing (the three TD3 tricks)                           |
//|     - Experience replay + Adam optimizer, hand-coded backprop    |
//|     - Weights persist to file across runs                        |
//|                                                                  |
//|   SAFETY / SCOPE:                                                 |
//|     * Default UseTD3=false => identical to v2.1.                 |
//|     * This is CPU-only research scaffolding. Training inside the |
//|       Strategy Tester is slow; use small nets. Non-stationarity, |
//|       overfitting and spread/cost sensitivity all apply. Always  |
//|       forward-test on demo before live use. Trading risks loss.  |
//|                                                                  |
//|   Built for Chad Woodyard, July 2026.                            |
//+------------------------------------------------------------------+
#property copyright   "Chad Woodyard"
#property version     "2.20"
#property description "ICC TradesBySci EA v2.2 - v2.1 + hybrid TD3 knob-control (risk/RR/SL)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

#define TD3_PI 3.14159265358979323846
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
enum ENUM_ICC_PHASE   { PH_NONE=0, PH_INDICATION=1, PH_CORRECTION=2 };
//============================= INPUTS ================================
input group "=== Entry Paths (turn either on/off) ==="
input bool   UseICCPullback    = true;          // Sci Indication->Correction->Continuation pullback
input bool   UseCascadeEntries = false;         // v1 breakout path (OFF by default; buys the breakout)
input bool   UseRetestEntries  = true;          // Retest-confirmation entries
input bool   CloseOnOpposite   = true;          // Close open trade on opposite signal

input group "=== Bias / Filter (Sci: HTF sets bias, LTF entry) ==="
input bool   BiasLoose         = true;          // single BOS sets trend (HH w/o LL = bull)
input bool   UseD1Filter       = true;          // let D1 influence HTF bias as a SOFT weight
input double D1Weight          = 0.5;           // D1 weight vs H4 (0=ignore D1, 1.0=~old hard veto, >1 D1 dominates)
input double HTF_MinConviction = 0.5;           // Min net HTF score (same side as H4) required to trade
input bool   StrictAlign       = false;         // v1 lockstep 4-TF gate (leave OFF for Sci style)

input group "=== ICC Pullback Tuning ==="
input double CorrRetraceMin    = 0.500;         // Min pullback into discount/premium (fib of impulse)
input double CorrRetraceMax    = 0.900;         // Max pullback before setup invalidates (fib)
input int    ICC_ExpiryBars    = 30;            // Bars to complete Correction+Continuation, else reset

input group "=== Timeframe Cascade (Sci D1->H4->H1->M15) ==="
input ENUM_TIMEFRAMES BiasTF   = PERIOD_D1;     // Top bias TF
input ENUM_TIMEFRAMES MidTF    = PERIOD_H4;     // Mid / primary Indication TF
input ENUM_TIMEFRAMES WorkTF   = PERIOD_H1;     // Working TF (swing anchor)
input ENUM_TIMEFRAMES TrigTF   = PERIOD_M15;    // Trigger TF (entry timing)
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
input bool   ShowSwings         = true;
input int    SwingLen           = 5;
input int    MaxSwings          = 6;
input color  ColHigh            = clrDodgerBlue;
input color  ColLow             = clrCrimson;
input bool   ShowDashboard      = true;

input group "=== Entry / Exit Flashing Dialog ==="
input bool   FlashOn            = true;
input int    FlashSeconds       = 6;
input int    FlashMs            = 400;
input ENUM_BASE_CORNER FlashCorner = CORNER_LEFT_UPPER;
input int    FlashX             = 220;
input int    FlashY             = 30;
input bool   ShowFlashPrices    = true;
input color  ColBuy             = clrLime;
input color  ColSell            = clrRed;
input color  ColExit            = clrOrange;
input color  ColRBuy            = clrLime;
input color  ColRSell           = clrRed;

input group "=== Alerts ==="
input bool   AlertPopup         = true;
input bool   AlertPush          = false;
input bool   AlertEmail         = false;
input bool   AlertSound         = false;
input string AlertSoundFile     = "alert.wav";

input group "=== EA Settings ==="
input ulong  MagicNumber        = 20260717;
input int    Slippage           = 30;
input string TradeComment       = "ICC-Sci-EA-v2.2";
input bool   DebugLog           = false;        // Print SL/lot skip reasons
input bool   VerboseLog         = true;         // Print bias/phase/signals every bar

input group "=== TD3 Reinforcement Layer (hybrid knob-control) ==="
input bool   UseTD3            = false;   // MASTER: false => identical to v2.1
input bool   TD3_Train         = true;    // true=learn online; false=inference only
input bool   TD3_ResetWeights  = false;   // true=start from fresh random weights
input string TD3_WeightsFile   = "ICC_TD3_weights.bin"; // persisted weights (tester/files)
input int    TD3_Hidden        = 24;      // hidden units per layer
input double TD3_ActorLR       = 0.001;   // actor learning rate
input double TD3_CriticLR      = 0.001;   // critic learning rate
input double TD3_Gamma         = 0.99;    // discount
input double TD3_Tau           = 0.005;   // soft target update
input int    TD3_Batch         = 32;      // minibatch size / bar
input int    TD3_Buffer        = 4096;    // replay capacity
input int    TD3_PolicyDelay   = 2;       // delayed policy updates (TD3 trick 2)
input double TD3_ExplNoise     = 0.10;    // exploration noise sigma (action space)
input double TD3_TargNoise     = 0.20;    // target-policy smoothing sigma (trick 3)
input double TD3_TargClip      = 0.50;    // target noise clip
input int    TD3_WarmupBars    = 200;     // random-action warmup before learning
input double TD3_TurnoverPen   = 0.05;    // reward penalty when a new trade opens
input double TD3_RiskLo        = 0.25;    // risk multiplier lower bound
input double TD3_RiskHi        = 2.00;    // risk multiplier upper bound
input double TD3_RRLo          = 0.50;    // RR multiplier lower bound
input double TD3_RRHi          = 2.00;    // RR multiplier upper bound
input double TD3_SLLo          = 0.75;    // SL-distance multiplier lower bound
input double TD3_SLHi          = 1.50;    // SL-distance multiplier upper bound
//============================ TD3 NEURAL CORE =======================
#define TD3_S 8     // state dimension
#define TD3_A 3     // action dimension
#define ADAM_B1 0.9
#define ADAM_B2 0.999
//------------------------------------------------------------------
//  CMLP : a compact 2-hidden-layer perceptron with hand-coded
//  forward/backward + per-weight Adam. ReLU hidden; output is either
//  tanh (actor) or linear (critic). All arrays are flat 1D.
//------------------------------------------------------------------
class CMLP
  {
public:
   int      nin, nh, nout;
   bool     tanhOut;
   long     adamT;
   double   W1[], b1[], W2[], b2[], W3[], b3[];
   double   mW1[], vW1[], mb1[], vb1[];
   double   mW2[], vW2[], mb2[], vb2[];
   double   mW3[], vW3[], mb3[], vb3[];
   // forward caches
   double   c_in[], z1[], a1[], z2[], a2[], c_out[];
   // backprop input-gradient
   double   m_dIn[];

   void Init(int _nin,int _nh,int _nout,bool _tanhOut);
   void Forward(const double &x[], double &out[]);
   void Backward(const double &dout[], double lr);        // grads+Adam (+m_dIn)
   void BackwardInputOnly(const double &dout[]);          // only m_dIn (no update)
   void SoftUpdateFrom(CMLP &src, double tau);
   void CopyFrom(CMLP &src);
   void Save(int h);
   bool Load(int h);
private:
   double Xavier(int fanin);
   void   AdamUpd(double &w[], int idx, double g, double lr, double bc1, double bc2,
                  double &m[], double &v[]);
  };
//------------------------------------------------------------------
double CMLP::Xavier(int fanin)
  {
   double u1=(MathRand()+1.0)/32769.0, u2=(MathRand()+1.0)/32769.0;
   double gsn=MathSqrt(-2.0*MathLog(u1))*MathCos(2.0*TD3_PI*u2);
   return gsn*MathSqrt(1.0/MathMax(1,fanin));
  }
void CMLP::Init(int _nin,int _nh,int _nout,bool _tanhOut)
  {
   nin=_nin; nh=_nh; nout=_nout; tanhOut=_tanhOut; adamT=0;
   ArrayResize(W1,nh*nin);  ArrayResize(b1,nh);
   ArrayResize(W2,nh*nh);   ArrayResize(b2,nh);
   ArrayResize(W3,nout*nh); ArrayResize(b3,nout);
   ArrayResize(mW1,nh*nin); ArrayResize(vW1,nh*nin); ArrayResize(mb1,nh); ArrayResize(vb1,nh);
   ArrayResize(mW2,nh*nh);  ArrayResize(vW2,nh*nh);  ArrayResize(mb2,nh); ArrayResize(vb2,nh);
   ArrayResize(mW3,nout*nh);ArrayResize(vW3,nout*nh);ArrayResize(mb3,nout);ArrayResize(vb3,nout);
   ArrayInitialize(mW1,0);ArrayInitialize(vW1,0);ArrayInitialize(mb1,0);ArrayInitialize(vb1,0);
   ArrayInitialize(mW2,0);ArrayInitialize(vW2,0);ArrayInitialize(mb2,0);ArrayInitialize(vb2,0);
   ArrayInitialize(mW3,0);ArrayInitialize(vW3,0);ArrayInitialize(mb3,0);ArrayInitialize(vb3,0);
   for(int i=0;i<nh*nin;i++)  W1[i]=Xavier(nin);
   for(int i=0;i<nh;i++)      b1[i]=0.0;
   for(int i=0;i<nh*nh;i++)   W2[i]=Xavier(nh);
   for(int i=0;i<nh;i++)      b2[i]=0.0;
   for(int i=0;i<nout*nh;i++) W3[i]=Xavier(nh);
   for(int i=0;i<nout;i++)    b3[i]=0.0;
   ArrayResize(c_in,nin); ArrayResize(z1,nh); ArrayResize(a1,nh);
   ArrayResize(z2,nh); ArrayResize(a2,nh); ArrayResize(c_out,nout);
   ArrayResize(m_dIn,nin);
  }
void CMLP::Forward(const double &x[], double &out[])
  {
   for(int i=0;i<nin;i++) c_in[i]=x[i];
   for(int j=0;j<nh;j++)
     {
      double s=b1[j];
      for(int i=0;i<nin;i++) s+=W1[j*nin+i]*x[i];
      z1[j]=s; a1[j]=(s>0.0?s:0.0);
     }
   for(int k=0;k<nh;k++)
     {
      double s=b2[k];
      for(int j=0;j<nh;j++) s+=W2[k*nh+j]*a1[j];
      z2[k]=s; a2[k]=(s>0.0?s:0.0);
     }
   ArrayResize(out,nout);
   for(int m=0;m<nout;m++)
     {
      double s=b3[m];
      for(int k=0;k<nh;k++) s+=W3[m*nh+k]*a2[k];
      c_out[m]=(tanhOut? MathTanh(s) : s);
      out[m]=c_out[m];
     }
  }
void CMLP::AdamUpd(double &w[], int idx, double g, double lr, double bc1, double bc2,
                   double &m[], double &v[])
  {
   m[idx]=ADAM_B1*m[idx]+(1.0-ADAM_B1)*g;
   v[idx]=ADAM_B2*v[idx]+(1.0-ADAM_B2)*g*g;
   double mh=m[idx]/bc1, vh=v[idx]/bc2;
   w[idx]-=lr*mh/(MathSqrt(vh)+1e-8);
  }
void CMLP::Backward(const double &dout[], double lr)
  {
   adamT++;
   double bc1=1.0-MathPow(ADAM_B1,(double)adamT);
   double bc2=1.0-MathPow(ADAM_B2,(double)adamT);
   double dO[]; ArrayResize(dO,nout);
   for(int m=0;m<nout;m++)
     {
      double g=dout[m];
      if(tanhOut) g*=(1.0-c_out[m]*c_out[m]);
      dO[m]=g;
     }
   // input-side gradients (use current weights BEFORE update)
   double da2[]; ArrayResize(da2,nh); ArrayInitialize(da2,0);
   for(int k=0;k<nh;k++)
      for(int m=0;m<nout;m++) da2[k]+=W3[m*nh+k]*dO[m];
   double dz2[]; ArrayResize(dz2,nh);
   for(int k=0;k<nh;k++) dz2[k]=(z2[k]>0.0? da2[k] : 0.0);
   double da1[]; ArrayResize(da1,nh); ArrayInitialize(da1,0);
   for(int j=0;j<nh;j++)
      for(int k=0;k<nh;k++) da1[j]+=W2[k*nh+j]*dz2[k];
   double dz1[]; ArrayResize(dz1,nh);
   for(int j=0;j<nh;j++) dz1[j]=(z1[j]>0.0? da1[j] : 0.0);
   for(int i=0;i<nin;i++)
     {
      double s=0.0;
      for(int j=0;j<nh;j++) s+=W1[j*nin+i]*dz1[j];
      m_dIn[i]=s;
     }
   // apply Adam updates
   for(int m=0;m<nout;m++)
     {
      for(int k=0;k<nh;k++) AdamUpd(W3,m*nh+k,dO[m]*a2[k],lr,bc1,bc2,mW3,vW3);
      AdamUpd(b3,m,dO[m],lr,bc1,bc2,mb3,vb3);
     }
   for(int k=0;k<nh;k++)
     {
      for(int j=0;j<nh;j++) AdamUpd(W2,k*nh+j,dz2[k]*a1[j],lr,bc1,bc2,mW2,vW2);
      AdamUpd(b2,k,dz2[k],lr,bc1,bc2,mb2,vb2);
     }
   for(int j=0;j<nh;j++)
     {
      for(int i=0;i<nin;i++) AdamUpd(W1,j*nin+i,dz1[j]*c_in[i],lr,bc1,bc2,mW1,vW1);
      AdamUpd(b1,j,dz1[j],lr,bc1,bc2,mb1,vb1);
     }
  }
void CMLP::BackwardInputOnly(const double &dout[])
  {
   double dO[]; ArrayResize(dO,nout);
   for(int m=0;m<nout;m++)
     {
      double g=dout[m];
      if(tanhOut) g*=(1.0-c_out[m]*c_out[m]);
      dO[m]=g;
     }
   double da2[]; ArrayResize(da2,nh); ArrayInitialize(da2,0);
   for(int k=0;k<nh;k++)
      for(int m=0;m<nout;m++) da2[k]+=W3[m*nh+k]*dO[m];
   double dz2[]; ArrayResize(dz2,nh);
   for(int k=0;k<nh;k++) dz2[k]=(z2[k]>0.0? da2[k] : 0.0);
   double da1[]; ArrayResize(da1,nh); ArrayInitialize(da1,0);
   for(int j=0;j<nh;j++)
      for(int k=0;k<nh;k++) da1[j]+=W2[k*nh+j]*dz2[k];
   double dz1[]; ArrayResize(dz1,nh);
   for(int j=0;j<nh;j++) dz1[j]=(z1[j]>0.0? da1[j] : 0.0);
   for(int i=0;i<nin;i++)
     {
      double s=0.0;
      for(int j=0;j<nh;j++) s+=W1[j*nin+i]*dz1[j];
      m_dIn[i]=s;
     }
  }
void CMLP::SoftUpdateFrom(CMLP &src, double tau)
  {
   for(int i=0;i<ArraySize(W1);i++) W1[i]=(1.0-tau)*W1[i]+tau*src.W1[i];
   for(int i=0;i<ArraySize(b1);i++) b1[i]=(1.0-tau)*b1[i]+tau*src.b1[i];
   for(int i=0;i<ArraySize(W2);i++) W2[i]=(1.0-tau)*W2[i]+tau*src.W2[i];
   for(int i=0;i<ArraySize(b2);i++) b2[i]=(1.0-tau)*b2[i]+tau*src.b2[i];
   for(int i=0;i<ArraySize(W3);i++) W3[i]=(1.0-tau)*W3[i]+tau*src.W3[i];
   for(int i=0;i<ArraySize(b3);i++) b3[i]=(1.0-tau)*b3[i]+tau*src.b3[i];
  }
void CMLP::CopyFrom(CMLP &src)
  {
   ArrayCopy(W1,src.W1); ArrayCopy(b1,src.b1);
   ArrayCopy(W2,src.W2); ArrayCopy(b2,src.b2);
   ArrayCopy(W3,src.W3); ArrayCopy(b3,src.b3);
  }
void CMLP::Save(int h)
  {
   FileWriteInteger(h,ArraySize(W1)); for(int i=0;i<ArraySize(W1);i++) FileWriteDouble(h,W1[i]);
   FileWriteInteger(h,ArraySize(b1)); for(int i=0;i<ArraySize(b1);i++) FileWriteDouble(h,b1[i]);
   FileWriteInteger(h,ArraySize(W2)); for(int i=0;i<ArraySize(W2);i++) FileWriteDouble(h,W2[i]);
   FileWriteInteger(h,ArraySize(b2)); for(int i=0;i<ArraySize(b2);i++) FileWriteDouble(h,b2[i]);
   FileWriteInteger(h,ArraySize(W3)); for(int i=0;i<ArraySize(W3);i++) FileWriteDouble(h,W3[i]);
   FileWriteInteger(h,ArraySize(b3)); for(int i=0;i<ArraySize(b3);i++) FileWriteDouble(h,b3[i]);
  }
bool CMLP::Load(int h)
  {
   int n;
   n=FileReadInteger(h); if(n!=ArraySize(W1)) return false; for(int i=0;i<n;i++) W1[i]=FileReadDouble(h);
   n=FileReadInteger(h); if(n!=ArraySize(b1)) return false; for(int i=0;i<n;i++) b1[i]=FileReadDouble(h);
   n=FileReadInteger(h); if(n!=ArraySize(W2)) return false; for(int i=0;i<n;i++) W2[i]=FileReadDouble(h);
   n=FileReadInteger(h); if(n!=ArraySize(b2)) return false; for(int i=0;i<n;i++) b2[i]=FileReadDouble(h);
   n=FileReadInteger(h); if(n!=ArraySize(W3)) return false; for(int i=0;i<n;i++) W3[i]=FileReadDouble(h);
   n=FileReadInteger(h); if(n!=ArraySize(b3)) return false; for(int i=0;i<n;i++) b3[i]=FileReadDouble(h);
   return true;
  }
//------------------------------------------------------------------
//  CTD3 : actor + twin critics + targets, replay buffer, training.
//------------------------------------------------------------------
class CTD3
  {
public:
   CMLP  actor, actorT;
   CMLP  critic1, critic1T;
   CMLP  critic2, critic2T;
   // replay buffer (flat)
   double bufS[], bufA[], bufR[], bufS2[];
   int    cap, sz, head;
   long   trainStep;
   int    hid;

   void Init(int hidden);
   void Store(const double &s[], const double &a[], double r, const double &s2[]);
   void SelectAction(const double &s[], double sigma, double &out[]);
   void Train(int batch, double aLR, double cLR, double gamma, double tau,
              int policyDelay, double targNoise, double targClip);
   int  Size(){ return sz; }
   bool SaveAll(string fname);
   bool LoadAll(string fname);
  };
//------------------------------------------------------------------
double TD3_Clip(double x,double lo,double hi){ return (x<lo?lo:(x>hi?hi:x)); }
double TD3_Gauss()
  {
   double u1=(MathRand()+1.0)/32769.0, u2=(MathRand()+1.0)/32769.0;
   return MathSqrt(-2.0*MathLog(u1))*MathCos(2.0*TD3_PI*u2);
  }
//------------------------------------------------------------------
void CTD3::Init(int hidden)
  {
   hid=hidden;
   actor.Init(TD3_S,hid,TD3_A,true);    actorT.Init(TD3_S,hid,TD3_A,true);
   critic1.Init(TD3_S+TD3_A,hid,1,false); critic1T.Init(TD3_S+TD3_A,hid,1,false);
   critic2.Init(TD3_S+TD3_A,hid,1,false); critic2T.Init(TD3_S+TD3_A,hid,1,false);
   actorT.CopyFrom(actor);
   critic1T.CopyFrom(critic1);
   critic2T.CopyFrom(critic2);
   cap=TD3_Buffer; sz=0; head=0; trainStep=0;
   ArrayResize(bufS,cap*TD3_S);  ArrayResize(bufA,cap*TD3_A);
   ArrayResize(bufR,cap);        ArrayResize(bufS2,cap*TD3_S);
  }
void CTD3::Store(const double &s[], const double &a[], double r, const double &s2[])
  {
   int i=head;
   for(int k=0;k<TD3_S;k++) bufS[i*TD3_S+k]=s[k];
   for(int k=0;k<TD3_A;k++) bufA[i*TD3_A+k]=a[k];
   bufR[i]=r;
   for(int k=0;k<TD3_S;k++) bufS2[i*TD3_S+k]=s2[k];
   head=(head+1)%cap;
   if(sz<cap) sz++;
  }
void CTD3::SelectAction(const double &s[], double sigma, double &out[])
  {
   actor.Forward(s,out);
   for(int i=0;i<TD3_A;i++)
     {
      if(sigma>0.0) out[i]+=TD3_Gauss()*sigma;
      out[i]=TD3_Clip(out[i],-1.0,1.0);
     }
  }
void CTD3::Train(int batch, double aLR, double cLR, double gamma, double tau,
                 int policyDelay, double targNoise, double targClip)
  {
   if(sz<batch) return;
   double s[], a[], s2[], qin[], qin2[], a2t[], tmp[], dq[];
   ArrayResize(s,TD3_S); ArrayResize(a,TD3_A); ArrayResize(s2,TD3_S);
   ArrayResize(qin,TD3_S+TD3_A); ArrayResize(qin2,TD3_S+TD3_A);
   ArrayResize(a2t,TD3_A); ArrayResize(dq,1);
   for(int b=0;b<batch;b++)
     {
      int j=MathRand()%sz;
      for(int k=0;k<TD3_S;k++){ s[k]=bufS[j*TD3_S+k]; s2[k]=bufS2[j*TD3_S+k]; }
      for(int k=0;k<TD3_A;k++) a[k]=bufA[j*TD3_A+k];
      double r=bufR[j];
      // ---- target action w/ smoothing (trick 3) ----
      actorT.Forward(s2,tmp);
      for(int k=0;k<TD3_A;k++)
        {
         double n=TD3_Clip(TD3_Gauss()*targNoise,-targClip,targClip);
         a2t[k]=TD3_Clip(tmp[k]+n,-1.0,1.0);
        }
      // ---- clipped double-Q target (trick 1) ----
      for(int k=0;k<TD3_S;k++){ qin2[k]=s2[k]; }
      for(int k=0;k<TD3_A;k++){ qin2[TD3_S+k]=a2t[k]; }
      double q1t[],q2t[];
      critic1T.Forward(qin2,q1t);
      critic2T.Forward(qin2,q2t);
      double qt=MathMin(q1t[0],q2t[0]);
      double y=r+gamma*qt;                 // done assumed 0 (continuing task)
      // ---- critic updates ----
      for(int k=0;k<TD3_S;k++){ qin[k]=s[k]; }
      for(int k=0;k<TD3_A;k++){ qin[TD3_S+k]=a[k]; }
      double q1[],q2[];
      critic1.Forward(qin,q1); dq[0]=q1[0]-y; critic1.Backward(dq,cLR);
      critic2.Forward(qin,q2); dq[0]=q2[0]-y; critic2.Backward(dq,cLR);
      trainStep++;
      // ---- delayed policy + target updates (trick 2) ----
      if((trainStep%policyDelay)==0)
        {
         double aout[];
         actor.Forward(s,aout);
         double qin3[]; ArrayResize(qin3,TD3_S+TD3_A);
         for(int k=0;k<TD3_S;k++) qin3[k]=s[k];
         for(int k=0;k<TD3_A;k++) qin3[TD3_S+k]=aout[k];
         double qv[]; critic1.Forward(qin3,qv);
         double dneg[]; ArrayResize(dneg,1); dneg[0]=-1.0; // maximize Q1
         critic1.BackwardInputOnly(dneg);
         double dA[]; ArrayResize(dA,TD3_A);
         for(int k=0;k<TD3_A;k++) dA[k]=critic1.m_dIn[TD3_S+k];
         actor.Backward(dA,aLR);
         actorT.SoftUpdateFrom(actor,tau);
         critic1T.SoftUpdateFrom(critic1,tau);
         critic2T.SoftUpdateFrom(critic2,tau);
        }
     }
  }
bool CTD3::SaveAll(string fname)
  {
   int h=FileOpen(fname,FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   actor.Save(h);  critic1.Save(h);  critic2.Save(h);
   actorT.Save(h); critic1T.Save(h); critic2T.Save(h);
   FileClose(h);
   return true;
  }
bool CTD3::LoadAll(string fname)
  {
   if(!FileIsExist(fname)) return false;
   int h=FileOpen(fname,FILE_READ|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   bool ok=true;
   ok=ok&&actor.Load(h);  ok=ok&&critic1.Load(h);  ok=ok&&critic2.Load(h);
   ok=ok&&actorT.Load(h); ok=ok&&critic1T.Load(h); ok=ok&&critic2T.Load(h);
   FileClose(h);
   return ok;
  }
//============================ GLOBALS ================================
CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;

double g_pip=0, g_tol=0, g_brkBuf=0, g_confBuf=0, g_slBuf=0;
int    g_sessCount=0, g_lastDayKey=-1;
int    g_barCount=0;
int    atrHandle=INVALID_HANDLE;
int    g_maHandle=INVALID_HANDLE;
int    g_uid=0;

ENUM_ASSET_CLASS AssetClass=ASSET_FOREX;
string AssetClassLabel="FOREX";
int    SLBufPts_Runtime=0;
int    TrailStart_Runtime=0, TrailStep_Runtime=0, BEat_Runtime=0, BEprofit_Runtime=0;

string PFX    = "ICCsciEA22_";
string SR_PFX = "ICCsciEA22_SR_";
string SW_PFX = "ICCsciEA22_SW_";

string g_swingNames[];

struct SwingCache { double lastHi, prevHi, lastLo, prevLo; };
SwingCache cD1, cH4, cH1, cM15;
int  biasD1=0, biasH4=0, biasH1=0, biasM15=0;
bool alignBull=false, alignBear=false;
double wkLastHi=0, wkLastLo=0;

// ---- cascade continuation edge detection (v1 path) ----
bool prevBuyCont=false, prevSellCont=false;

// ---- ICC pullback state machine ----
int      g_iccPhase = PH_NONE;
int      g_iccDir   = 0;
double   g_indLevel = 0.0;
double   g_indExtreme = 0.0;
double   g_corrExtreme = 0.0;
int      g_iccStartBar = 0;
bool     iccBuySig=false, iccSellSig=false;
double   iccSigSL=0.0;

// ---- S/R cluster storage ----
double   sr_price[];    int      sr_count[];
datetime sr_birthTime[]; int     sr_birthSes[];
datetime sr_birthBar[];  bool    sr_isRes[];
bool     sr_drawn[];     bool    sr_broken[];
bool     sr_retested[];  bool    sr_armed[];
int      sr_armBar[];    string  sr_name[];

// ---- retest-confirmation outputs ----
bool   retestBuySig=false, retestSellSig=false;
double retestSigLevel=0;
bool   srRetestThisBar=false, srRetestIsRes=false;

datetime lastAlertTime=0;

// ---- flashing dialog state ----
string FLASH_NAME="ICCsciEA22_FLASH";
bool   g_flashActive=false;
int    g_flashTicks=0;
bool   g_flashPhase=false;
string g_flashMsg="";
color  g_flashBase=clrLime;
bool   g_flashHasPx=false;
double g_flashEntry=0, g_flashSL=0, g_flashTP=0;

// ---- TD3 runtime ----
CTD3   g_agent;
bool   g_td3Ready=false;
double g_riskMult=1.0, g_rrMult=1.0, g_slMult=1.0;   // knobs applied to each trade
bool   g_newTradeThisBar=false;
bool   g_havePrev=false;
double g_prevState[], g_prevAction[];
double g_prevEquity=0.0;
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
double RawATR()
  {
   if(atrHandle==INVALID_HANDLE) return 0.0;
   double atr[]; ArraySetAsSeries(atr,true);
   if(CopyBuffer(atrHandle,0,1,1,atr)<1) return 0.0;
   return (atr[0]>0.0? atr[0] : 0.0);
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
   Print("        ICC TradesBySci EA v2.2 - BROKER DIAGNOSTICS          ");
   Print("==============================================================");
   Print(" Symbol:       ", _Symbol, "  Asset: ", AssetClassLabel);
   Print(" Chart TF:     ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print(" Cascade:      ", EnumToString(BiasTF), " -> ", EnumToString(MidTF),
                            " -> ", EnumToString(WorkTF), " -> ", EnumToString(TrigTF));
   Print(" Entry paths:  ICC=", (UseICCPullback?"ON":"OFF"),
                       "  Cascade=", (UseCascadeEntries?"ON":"OFF"),
                       "  Retest=", (UseRetestEntries?"ON":"OFF"));
   Print(" Bias mode:    ", (BiasLoose?"LOOSE (single BOS)":"STRICT (HH+HL)"),
                       "  D1 filter=", (UseD1Filter?"SOFT":"OFF"),
                       "  D1wt=", DoubleToString(D1Weight,2),
                       "  MinConv=", DoubleToString(HTF_MinConviction,2),
                       "  StrictAlign=", (StrictAlign?"ON":"OFF"));
   Print(" TD3 layer:    ", (UseTD3?"ON":"OFF"),
                       "  train=", (TD3_Train?"YES":"NO"),
                       "  hidden=", TD3_Hidden,
                       "  buffer=", TD3_Buffer, "  batch=", TD3_Batch);
   Print(" Stops Level:  ", stopsLvl, " pts   Spread: ", spread, " pts");
   Print(" SL Method:    ", EnumToString(SL_Method), "   RR: ", DoubleToString(RR_Ratio,1));
   Print(" Min SafeStop: ", DoubleToString(GetMinStopDistance(),(int)digits),
         " | x Cushion: ", DoubleToString(GetMinStopDistance()*BrokerStopCushion,(int)digits));
   double m15c = iClose(_Symbol,TrigTF,1);
   double h1h  = iHigh(_Symbol,WorkTF,1);
   if(m15c<=0 || h1h<=0)
      Print(" *** WARNING: ", EnumToString(TrigTF), "/", EnumToString(WorkTF),
            " data not available. If backtesting, set modeling to 'Every tick'. ***");
   Print("==============================================================");
  }
//+==================================================================+
//|                 CASCADE BIAS ENGINE (loosened)                   |
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
   bool hh = c.lastHi>c.prevHi;
   bool hl = c.lastLo>c.prevLo;
   bool lh = c.lastHi<c.prevHi;
   bool ll = c.lastLo<c.prevLo;
   if(BiasLoose)
     {
      if(hh && !ll) return  1;
      if(ll && !hh) return -1;
      return 0;
     }
   if(hh && hl) return  1;
   if(lh && ll) return -1;
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
double HTFscore()
  {
   if(!UseD1Filter) return (double)biasH4;
   return (double)biasH4 + (double)biasD1 * D1Weight;
  }
int HTFbias()
  {
   if(biasH4==0) return 0;
   if(!UseD1Filter) return biasH4;
   double sc = HTFscore();
   if(biasH4==1  && sc >=  HTF_MinConviction) return  1;
   if(biasH4==-1 && sc <= -HTF_MinConviction) return -1;
   return 0;
  }
//+==================================================================+
//|        ICC PULLBACK ENGINE  (Indication -> Correction ->         |
//|        Continuation)  — the genuine Sci-style entry.             |
//+==================================================================+
void ICC_Reset()
  {
   g_iccPhase=PH_NONE; g_iccDir=0;
   g_indLevel=0; g_indExtreme=0; g_corrExtreme=0; g_iccStartBar=0;
  }
void ICC_Update()
  {
   iccBuySig=false; iccSellSig=false; iccSigSL=0;
   if(!UseICCPullback) return;
   int    htf   = HTFbias();
   double m15c1 = iClose(_Symbol,TrigTF,1);
   double m15h2 = iHigh (_Symbol,TrigTF,2);
   double m15l2 = iLow  (_Symbol,TrigTF,2);
   double wkH1  = iHigh (_Symbol,WorkTF,1);
   double wkL1  = iLow  (_Symbol,WorkTF,1);
   if(m15c1<=0 || wkH1<=0 || wkL1<=0) return;
   if(g_iccPhase!=PH_NONE && g_iccDir!=0 && htf!=0 && htf!=g_iccDir)
      ICC_Reset();
   if(g_iccPhase!=PH_NONE && (g_barCount-g_iccStartBar)>ICC_ExpiryBars)
      ICC_Reset();
   if(htf==1)
     {
      if(g_iccPhase==PH_NONE)
        {
         if(wkLastHi>0 && m15c1>wkLastHi)
           {
            g_iccPhase   = PH_INDICATION;
            g_iccDir     = 1;
            g_indLevel   = wkLastHi;
            g_indExtreme = MathMax(wkH1,m15c1);
            g_corrExtreme= wkL1;
            g_iccStartBar= g_barCount;
           }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==1)
        {
         if(wkH1>g_indExtreme) g_indExtreme=wkH1;
         double leg = g_indExtreme-g_indLevel;
         if(leg>0)
           {
            double disc = g_indExtreme - leg*CorrRetraceMin;
            double inval= g_indExtreme - leg*CorrRetraceMax;
            if(wkL1<=inval)
               ICC_Reset();
            else if(wkL1<=disc)
              {
               g_iccPhase   = PH_CORRECTION;
               g_corrExtreme= wkL1;
              }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==1)
        {
         if(wkL1<g_corrExtreme) g_corrExtreme=wkL1;
         double leg  = g_indExtreme-g_indLevel;
         double inval= (leg>0)? g_indExtreme-leg*CorrRetraceMax : 0;
         if(leg>0 && wkL1<=inval)
           { ICC_Reset(); }
         else if(m15h2>0 && m15c1>m15h2)
           {
            iccBuySig=true;
            iccSigSL = g_corrExtreme - g_slBuf;
            ICC_Reset();
           }
        }
     }
   else if(htf==-1)
     {
      if(g_iccPhase==PH_NONE)
        {
         if(wkLastLo>0 && m15c1<wkLastLo)
           {
            g_iccPhase   = PH_INDICATION;
            g_iccDir     = -1;
            g_indLevel   = wkLastLo;
            g_indExtreme = MathMin(wkL1,m15c1);
            g_corrExtreme= wkH1;
            g_iccStartBar= g_barCount;
           }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==-1)
        {
         if(wkL1<g_indExtreme) g_indExtreme=wkL1;
         double leg = g_indLevel-g_indExtreme;
         if(leg>0)
           {
            double prem = g_indExtreme + leg*CorrRetraceMin;
            double inval= g_indExtreme + leg*CorrRetraceMax;
            if(wkH1>=inval)
               ICC_Reset();
            else if(wkH1>=prem)
              {
               g_iccPhase   = PH_CORRECTION;
               g_corrExtreme= wkH1;
              }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==-1)
        {
         if(wkH1>g_corrExtreme) g_corrExtreme=wkH1;
         double leg  = g_indLevel-g_indExtreme;
         double inval= (leg>0)? g_indExtreme+leg*CorrRetraceMax : 0;
         if(leg>0 && wkH1>=inval)
           { ICC_Reset(); }
         else if(m15l2>0 && m15c1<m15l2)
           {
            iccSellSig=true;
            iccSigSL = g_corrExtreme + g_slBuf;
            ICC_Reset();
           }
        }
     }
   else
     {
      if(g_iccPhase==PH_NONE) ICC_Reset();
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
         sr_retested[i]=true; sr_armed[i]=true; sr_armBar[i]=g_barCount;
         srRetestThisBar=true; srRetestIsRes=sr_isRes[i];
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
      bool confBuy =( sr_isRes[i] && c>lvl+g_confBuf);
      bool confSell=(!sr_isRes[i] && c<lvl-g_confBuf);
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
   Print("ICC-Sci-EA v2.2: ",m);
   if(AlertPopup) Alert(m);
   if(AlertPush)  SendNotification(m);
   if(AlertEmail) SendMail("ICC TradesBySci EA v2.2 - "+_Symbol,m);
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
   double risk=bal*RiskPercent/100.0*g_riskMult;   // TD3 risk knob
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
int OpenTradeDir()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     if(posInfo.SelectByIndex(i))
       if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol)
         return (posInfo.PositionType()==POSITION_TYPE_BUY)?1:-1;
   return 0;
  }
double OpenTradeR()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss();
      double risk=MathAbs(op-sl); if(risk<=0) return 0.0;
      double cur=(posInfo.PositionType()==POSITION_TYPE_BUY)?symInfo.Bid():symInfo.Ask();
      int dir=(posInfo.PositionType()==POSITION_TYPE_BUY)?1:-1;
      return dir*(cur-op)/risk;
     }
   return 0.0;
  }
void CloseAllThisEA(string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      ulong tk=posInfo.Ticket();
      if(trade.PositionClose(tk))
        { TriggerFlash(reason,ColExit,false,0,0,0); DispatchAlert(reason+" | "+_Symbol); }
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
void ExecuteBuy(double slAnchor, string tag, color boxCol)
  {
   double ask=symInfo.Ask();
   double minStop=GetMinStopDistance();
   double structDist=ask-slAnchor; if(structDist<0) structDist=0;
   double slDist=CalculateSLDistance(structDist)*g_slMult;   // TD3 SL knob
   double slPrice=NormalizeDouble(ask-slDist,_Digits);
   if(ask-slPrice<minStop*BrokerStopCushion){ if(DebugLog) Print("BUY skip: SL too close"); return; }
   double slFinal=ask-slPrice;
   double tpPrice=NormalizeDouble(ask+slFinal*RR_Ratio*g_rrMult,_Digits);  // TD3 RR knob
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("BUY skip: lots<=0"); return; }
   if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,TradeComment))
     {
      g_newTradeThisBar=true;
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
   double slDist=CalculateSLDistance(structDist)*g_slMult;   // TD3 SL knob
   double slPrice=NormalizeDouble(bid+slDist,_Digits);
   if(slPrice-bid<minStop*BrokerStopCushion){ if(DebugLog) Print("SELL skip: SL too close"); return; }
   double slFinal=slPrice-bid;
   double tpPrice=NormalizeDouble(bid-slFinal*RR_Ratio*g_rrMult,_Digits);  // TD3 RR knob
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("SELL skip: lots<=0"); return; }
   if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,TradeComment))
     {
      g_newTradeThisBar=true;
      TriggerFlash(tag,boxCol,true,bid,slPrice,tpPrice);
      DispatchAlert(StringFormat("%s | %s | E:%s SL:%s TP:%s",
        tag,_Symbol,DoubleToString(bid,_Digits),DoubleToString(slPrice,_Digits),DoubleToString(tpPrice,_Digits)));
     }
   else
      PrintFormat("SELL FAILED [%d]: %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+==================================================================+
//|                 TD3 STATE / STEP                                 |
//+==================================================================+
double TD3_Map(double x,double lo,double hi)
  {
   double c=TD3_Clip(x,-1.0,1.0);
   return lo+(c+1.0)*0.5*(hi-lo);
  }
void TD3_BuildState(double &s[])
  {
   ArrayResize(s,TD3_S);
   double price=iClose(_Symbol,_Period,0); if(price<=0) price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double c1=iClose(_Symbol,_Period,1), c2=iClose(_Symbol,_Period,2);
   double atr=RawATR(); double eps=1e-9;
   s[0]=(double)HTFbias();
   s[1]=MathTanh(HTFscore()/2.0);
   s[2]=(double)g_iccPhase/2.0;
   s[3]=(double)g_iccDir;
   s[4]=MathTanh(atr/MathMax(price*0.002,eps));
   s[5]=MathTanh((c1-c2)/MathMax(atr,eps));
   s[6]=(double)OpenTradeDir();
   s[7]=TD3_Clip(OpenTradeR(),-3.0,3.0)/3.0;
  }
void TD3_Step()
  {
   if(!UseTD3 || !g_td3Ready){ g_riskMult=1.0; g_rrMult=1.0; g_slMult=1.0; return; }
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double denom=MathMax(bal*RiskPercent/100.0,1e-6);
   double curState[]; TD3_BuildState(curState);
   // store transition from previous bar
   if(g_havePrev)
     {
      double r=(eq-g_prevEquity)/denom;
      if(g_newTradeThisBar) r-=TD3_TurnoverPen;
      r=TD3_Clip(r,-5.0,5.0);
      g_agent.Store(g_prevState,g_prevAction,r,curState);
     }
   // choose action for this bar
   double act[]; ArrayResize(act,TD3_A);
   if(TD3_Train && g_barCount<TD3_WarmupBars)
     {
      for(int i=0;i<TD3_A;i++) act[i]=TD3_Clip(2.0*((MathRand()+0.5)/32768.0)-1.0,-1.0,1.0);
     }
   else
     {
      double sigma=(TD3_Train? TD3_ExplNoise : 0.0);
      g_agent.SelectAction(curState,sigma,act);
     }
   g_riskMult=TD3_Map(act[0],TD3_RiskLo,TD3_RiskHi);
   g_rrMult  =TD3_Map(act[1],TD3_RRLo,  TD3_RRHi);
   g_slMult  =TD3_Map(act[2],TD3_SLLo,  TD3_SLHi);
   // remember for next-bar transition
   ArrayResize(g_prevState,TD3_S);  ArrayCopy(g_prevState,curState);
   ArrayResize(g_prevAction,TD3_A); ArrayCopy(g_prevAction,act);
   g_prevEquity=eq; g_havePrev=true;
   // learn
   if(TD3_Train && g_barCount>=TD3_WarmupBars && g_agent.Size()>=TD3_Batch)
      g_agent.Train(TD3_Batch,TD3_ActorLR,TD3_CriticLR,TD3_Gamma,TD3_Tau,
                    TD3_PolicyDelay,TD3_TargNoise,TD3_TargClip);
  }
//+==================================================================+
//|                 SIGNAL ROUTING                                   |
//+==================================================================+
bool IsWithinSession()
  {
   MqlDateTime dt; TimeCurrent(dt);
   if(SessionStartHour<SessionEndHour) return(dt.hour>=SessionStartHour && dt.hour<SessionEndHour);
   return(dt.hour>=SessionStartHour || dt.hour<SessionEndHour);
  }
bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0); if(ct!=lt){ lt=ct; return true; } return false; }
string PhaseTxt(int p){ return p==PH_INDICATION?"IND":p==PH_CORRECTION?"COR":"---"; }
void TryEntries()
  {
   if(UseSessionFilter && !IsWithinSession())
     { if(VerboseLog) Print("[ICC] session filter: outside window, no entries"); return; }
   double trigClose=iClose(_Symbol,TrigTF,1);
   bool buyCont = UseCascadeEntries && alignBull && wkLastHi>0 && trigClose>wkLastHi;
   bool sellCont= UseCascadeEntries && alignBear && wkLastLo>0 && trigClose<wkLastLo;
   bool cascBuy  = buyCont  && !prevBuyCont;
   bool cascSell = sellCont && !prevSellCont;
   prevBuyCont=buyCont; prevSellCont=sellCont;
   bool buySig  = iccBuySig  || retestBuySig  || cascBuy;
   bool sellSig = iccSellSig || retestSellSig || cascSell;
   if(VerboseLog)
      PrintFormat("[ICC] bar=%d bias D1/H4/H1/M15=%d/%d/%d/%d HTF=%d HTFsc=%.2f | phase=%s dir=%d | TD3 risk/rr/sl=%.2f/%.2f/%.2f | sig ICC(b/s)=%d/%d RET(b/s)=%d/%d CASC(b/s)=%d/%d | SR act=%d armed=%d",
         g_barCount,biasD1,biasH4,biasH1,biasM15,HTFbias(),HTFscore(),
         PhaseTxt(g_iccPhase),g_iccDir,g_riskMult,g_rrMult,g_slMult,
         (int)iccBuySig,(int)iccSellSig,(int)retestBuySig,(int)retestSellSig,
         (int)cascBuy,(int)cascSell,ActiveSRCount(),ArmedCount());
   int dir=OpenTradeDir();
   if(CloseOnOpposite && dir==1 && sellSig){ CloseAllThisEA("EXIT LONG"); dir=0; }
   if(CloseOnOpposite && dir==-1 && buySig){ CloseAllThisEA("EXIT SHORT"); dir=0; }
   if(CountOpenTrades()>=MaxOpenTrades) return;
   if(dir!=0) return;
   if(iccBuySig)
     { double anchor=(iccSigSL>0)? iccSigSL : wkLastLo; ExecuteBuy(anchor,"ICC BUY (continuation)",ColBuy); return; }
   if(iccSellSig)
     { double anchor=(iccSigSL>0)? iccSigSL : wkLastHi; ExecuteSell(anchor,"ICC SELL (continuation)",ColSell); return; }
   if(retestBuySig)
     { double anchor=retestSigLevel-g_slBuf; ExecuteBuy(anchor,"RETEST BUY",ColRBuy); return; }
   if(retestSellSig)
     { double anchor=retestSigLevel+g_slBuf; ExecuteSell(anchor,"RETEST SELL",ColRSell); return; }
   if(cascBuy)
     { ExecuteBuy(wkLastLo,"BUY ENTRY (breakout)",ColBuy); return; }
   if(cascSell)
     { ExecuteSell(wkLastHi,"SELL ENTRY (breakout)",ColSell); return; }
  }
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
   string d ="=== ICC TradesBySci EA v2.2 =============\n";
   d+=" Cascade (D1 H4 H1 M15): "+bD+" "+b4+" "+b1+" "+b5+"\n";
   d+=" HTF filter: "+(HTFbias()==1?"^ BULL":HTFbias()==-1?"v BEAR":"- flat")+
      "  score="+DoubleToString(HTFscore(),2)+" (min "+DoubleToString(HTF_MinConviction,2)+")\n";
   d+=" ICC phase: "+PhaseTxt(g_iccPhase)+" (dir "+IntegerToString(g_iccDir)+")\n";
   if(UseTD3)
      d+=" TD3: risk x"+DoubleToString(g_riskMult,2)+"  RR x"+DoubleToString(g_rrMult,2)+
         "  SL x"+DoubleToString(g_slMult,2)+"  buf="+IntegerToString(g_agent.Size())+"\n";
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
   ICC_Reset();
   EvaluateCascade();
   // ---- TD3 init ----
   g_riskMult=1.0; g_rrMult=1.0; g_slMult=1.0; g_havePrev=false;
   if(UseTD3)
     {
      MathSrand((int)(TimeLocal()%2147483647));
      g_agent.Init(TD3_Hidden);
      if(!TD3_ResetWeights)
        {
         if(g_agent.LoadAll(TD3_WeightsFile)) Print("TD3: loaded weights from ",TD3_WeightsFile);
         else Print("TD3: no saved weights; starting fresh.");
        }
      else Print("TD3: reset to fresh random weights.");
      g_prevEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_td3Ready=true;
     }
   PrintBrokerDiagnostics();
   if(FlashOn) EventSetMillisecondTimer(FlashMs);
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(UseTD3 && TD3_Train && g_td3Ready)
     { if(g_agent.SaveAll(TD3_WeightsFile)) Print("TD3: saved weights to ",TD3_WeightsFile); }
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
   ManagePositions();
   if(!IsNewBar()) return;
   symInfo.Refresh();
   g_barCount++;
   g_newTradeThisBar=false;
   double c    = iClose(_Symbol,_Period,1);
   datetime t  = iTime(_Symbol,_Period,1);
   double barHi= iHigh(_Symbol,_Period,1);
   double barLo= iLow (_Symbol,_Period,1);
   // 1) cascade bias (loosened)
   EvaluateCascade();
   // 2) swing rays (visual)
   ProcessSwing();
   // 3) body-close S/R with broken + retest + confirmation
   if(SR_Show)
     {
      SR_CheckBroken(c);
      SR_CheckRetest(barHi,barLo,c);
      SR_CheckConfirm(c);
      ProcessBar(c,t);
      ExpireLevels(iTime(_Symbol,_Period,0));
      UpdateActiveLevels(iTime(_Symbol,_Period,0));
     }
   else { retestBuySig=false; retestSellSig=false; }
   // 4) ICC Indication->Correction->Continuation pullback engine
   ICC_Update();
   // 5) TD3 knob-control: build state, learn, set risk/RR/SL multipliers
   TD3_Step();
   // 6) entry routing (real orders) — uses TD3 knobs when UseTD3=true
   TryEntries();
   // 7) dashboard
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
