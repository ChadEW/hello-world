// GENERATED SOURCE ONLY. Not compiled or executed.

// Source-only, local-files-only fault harness. No account APIs or trade libraries.
// Failure modes: 1 cleanup, 2 open, 3 short write, 4 seek, 5 short temporary
// read, 6 corrupt temporary read, 7 rename, 8 final open, 9 short final read,
// 10 rename completed but caller receives failure, 11 flush, 12 close.
int fault=0,openCalls=0,readCalls=0,closeCalls=0,failures=0,checks=0;
string testFile="";
int Test_FileOpen(string name,int flags)
  {
   openCalls++;
   if((fault==2 && openCalls==1) || (fault==8 && openCalls==2)) return INVALID_HANDLE;
   return FileOpen(name,flags);
  }
bool Test_FileDelete(string name,int common)
  { if(fault==1) return false; return FileDelete(name,common); }
uint Test_FileWriteArray(int h,const uchar &bytes[],int start,int count)
  { return FileWriteArray(h,bytes,start,fault==3?count/2:count); }
void Test_FileFlush(int h)
  { FileFlush(h); if(fault==11) SetUserError(245); }
bool Test_FileSeek(int h,long offset,ENUM_FILE_POSITION origin)
  { if(fault==4) return false; return FileSeek(h,offset,origin); }
uint Test_FileReadArray(int h,uchar &bytes[],int start,int count)
  {
   readCalls++;
   uint n=FileReadArray(h,bytes,start,count);
   if(((fault==5 && readCalls==1) || (fault==9 && readCalls==2)) && n>0) return n-1;
   if(fault==6 && readCalls==1 && n>0) bytes[0]=(uchar)(bytes[0]^1);
   return n;
  }
void Test_FileClose(int h)
  { closeCalls++; FileClose(h); if(fault==12 && closeCalls==1) SetUserError(246); }
bool Test_FileMove(string from,int common,string to,int flags)
  { if(fault==7) return false; bool ok=FileMove(from,common,to,flags); return fault==10?false:ok; }
void Check(bool ok,string label)
  { checks++; if(!ok) failures++; PrintFormat("[HANDLEVERIFY_F2_TEST] %s %s",ok?"PASS":"FAIL",label); }
bool Seed(string name,string text)
  {
   int h=FileOpen(name,FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   uchar b[];int n=StringToCharArray(text,b,0,WHOLE_ARRAY,CP_UTF8)-1;
   uint written=FileWriteArray(h,b,0,n);FileFlush(h);FileClose(h);
   return written==(uint)n;
  }
string Read(string name)
  {
   int h=FileOpen(name,FILE_READ|FILE_BIN);if(h==INVALID_HANDLE) return "READ_FAILED";
   int n=(int)FileSize(h);
   if(n==0) { FileClose(h); return ""; }
   uchar b[];ArrayResize(b,n);
   uint got=FileReadArray(h,b,0,n);FileClose(h);
   if(got!=(uint)n) return "READ_FAILED";
   return CharArrayToString(b,0,n,CP_UTF8);
  }
void ResetCounters(int value) { fault=value;openCalls=0;readCalls=0;closeCalls=0;ResetLastError(); }
void OnStart()
  {
   testFile="R245_HANDLEVERIFY_F2_TEST_"+StringFormat("%I64u",GetMicrosecondCount())+".state";
   // Refuse existing names; never touch an EA recovery namespace.
   if(FileIsExist(testFile) || FileIsExist(testFile+".new")) { Print("TEST ABORT: filename exists");return; }
   string old="old committed bytes",next="new bytes";
   for(int mode=1;mode<=12;mode++)
     {
      ResetCounters(0);
      if(!Seed(testFile,old) || !Seed(testFile+".new",next+"stale trailing data"))
        { Check(false,"fixture seed");break; }
      ResetCounters(mode);
      Check(!R244_WriteFile(testFile,next),"reject injected failure "+IntegerToString(mode));
      Check(Read(testFile)==((mode==8 || mode==9 || mode==10)?next:old),"committed contents "+IntegerToString(mode));
      ResetCounters(0);
      Check(R244_WriteFile(testFile,next) && Read(testFile)==next,"retry "+IntegerToString(mode));
      Check(openCalls==2,"two opens on successful retry "+IntegerToString(mode));
      ResetCounters(0);
      Check(R244_WriteFile(testFile,next) && Read(testFile)==next,"repeat "+IntegerToString(mode));
     }
   ResetCounters(0);
   bool emptyOK=R244_WriteFile(testFile,"");
   int emptyErr=GetLastError();
   Check(emptyOK && Read(testFile)=="","empty payload");
   PrintFormat("[HANDLEVERIFY_F2_TEST] empty diagnostic write_ok=%d error=%d opens=%d reads=%d",(int)emptyOK,emptyErr,openCalls,readCalls);
   ResetCounters(0);Check(R244_WriteFile(testFile,"Euro €\n") && Read(testFile)=="Euro €\n","UTF8 payload");
   // Local generated fixtures only, never FILE_COMMON or a trading-account path.
   FileDelete(testFile);if(FileIsExist(testFile+".new")) FileDelete(testFile+".new");
   PrintFormat("[HANDLEVERIFY_F2_TEST] END checks=%d failures=%d",checks,failures);
  }

// F2: explicit zero-byte payload handling; no zero-count array I/O.
// HANDLEVERIFY F: flush and verify temporary bytes on the writing handle.
// Final file is still independently reopened and verified before success.
ulong r245fSeekCalls=0,r245fSeekTotal=0,r245fSeekMax=0;
bool R245F_SeekStart(const int h)
  {
   ulong started=GetMicrosecondCount();
   bool ok=Test_FileSeek(h,0,SEEK_SET);
   ulong elapsed=GetMicrosecondCount()-started;
   r245fSeekCalls++; r245fSeekTotal+=elapsed;
   if(elapsed>r245fSeekMax) r245fSeekMax=elapsed;
   return ok;
  }
void R245F_Report()
  {
   Print("[R245 HANDLEVERIFY F2] temporary=flushed_same_handle final=independent_reopen saves=unchanged");
   PrintFormat("[R245 HANDLEVERIFY F2] stage=seek_temporary calls=%I64u total_us=%I64u max_us=%I64u",r245fSeekCalls,r245fSeekTotal,r245fSeekMax);
  }
// Retained E stage counters; F temporary reopen/verification-close counters stay zero.
ulong r245eCalls[12],r245eTotal[12],r245eMax[12];
void R245E_Record(const int slot,const ulong elapsed)
  {
   r245eCalls[slot]++;
   r245eTotal[slot]+=elapsed;
   if(elapsed>r245eMax[slot]) r245eMax[slot]=elapsed;
  }
void R245E_Close(const int h,const int role)
  {
   ulong started=GetMicrosecondCount();
   Test_FileClose(h);
   R245E_Record(role*6+4,GetMicrosecondCount()-started);
  }
void R245E_Report()
  {
   Print("[R245 VERIFY TIMING E] BEGIN elapsed microseconds; nested within SAVE TIMING C verification stages");
   PrintFormat("[R245 VERIFY TIMING E] file=temporary stage=open calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[0],r245eTotal[0],r245eMax[0]);
   PrintFormat("[R245 VERIFY TIMING E] file=temporary stage=size calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[1],r245eTotal[1],r245eMax[1]);
   PrintFormat("[R245 VERIFY TIMING E] file=temporary stage=allocate calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[2],r245eTotal[2],r245eMax[2]);
   PrintFormat("[R245 VERIFY TIMING E] file=temporary stage=read calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[3],r245eTotal[3],r245eMax[3]);
   PrintFormat("[R245 VERIFY TIMING E] file=temporary stage=close calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[4],r245eTotal[4],r245eMax[4]);
   PrintFormat("[R245 VERIFY TIMING E] file=temporary stage=compare calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[5],r245eTotal[5],r245eMax[5]);
   PrintFormat("[R245 VERIFY TIMING E] file=final stage=open calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[6],r245eTotal[6],r245eMax[6]);
   PrintFormat("[R245 VERIFY TIMING E] file=final stage=size calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[7],r245eTotal[7],r245eMax[7]);
   PrintFormat("[R245 VERIFY TIMING E] file=final stage=allocate calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[8],r245eTotal[8],r245eMax[8]);
   PrintFormat("[R245 VERIFY TIMING E] file=final stage=read calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[9],r245eTotal[9],r245eMax[9]);
   PrintFormat("[R245 VERIFY TIMING E] file=final stage=close calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[10],r245eTotal[10],r245eMax[10]);
   PrintFormat("[R245 VERIFY TIMING E] file=final stage=compare calls=%I64u total_us=%I64u max_us=%I64u",r245eCalls[11],r245eTotal[11],r245eMax[11]);
   Print("[R245 VERIFY TIMING E] END");
  }

// R245 BYTEVERIFY D: source-only candidate; user compilation and runtime verification pending.
// SAVE TIMING C: source-only diagnostic; preserves PREFILTER B recovery operations.
#define R245C_COUNT 9
ulong r245cCalls[R245C_COUNT],r245cTotal[R245C_COUNT],r245cMax[R245C_COUNT];
ulong r245cBytes=0,r245cMaxBytes=0,r245cWriteAttempts=0;
ulong r245cTicksWithSaves=0,r245cTicksMultipleSaves=0,r245cSavesInTicks=0,r245cMaxSavesPerTick=0;
void R245C_Record(const int slot,const ulong elapsed)
  {
   r245cCalls[slot]++;
   r245cTotal[slot]+=elapsed;
   if(elapsed>r245cMax[slot]) r245cMax[slot]=elapsed;
  }
void R245C_Report()
  {
   Print("[R245 SAVE TIMING C] BEGIN elapsed microseconds; stages are subsets of existing inclusive timers; write+flush intentionally combined");
   PrintFormat("[R245 SAVE TIMING C] stage=pack_state calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[0],r245cTotal[0],r245cMax[0]);
   PrintFormat("[R245 SAVE TIMING C] stage=checksum_document calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[1],r245cTotal[1],r245cMax[1]);
   PrintFormat("[R245 SAVE TIMING C] stage=encode_utf8 calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[2],r245cTotal[2],r245cMax[2]);
   PrintFormat("[R245 SAVE TIMING C] stage=open_temporary calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[3],r245cTotal[3],r245cMax[3]);
   PrintFormat("[R245 SAVE TIMING C] stage=write_and_flush calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[4],r245cTotal[4],r245cMax[4]);
   PrintFormat("[R245 SAVE TIMING C] stage=close_temporary calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[5],r245cTotal[5],r245cMax[5]);
   PrintFormat("[R245 SAVE TIMING C] stage=verify_temporary calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[6],r245cTotal[6],r245cMax[6]);
   PrintFormat("[R245 SAVE TIMING C] stage=replace_file calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[7],r245cTotal[7],r245cMax[7]);
   PrintFormat("[R245 SAVE TIMING C] stage=verify_final calls=%I64u total_us=%I64u max_us=%I64u",r245cCalls[8],r245cTotal[8],r245cMax[8]);
   PrintFormat("[R245 SAVE TIMING C] encoded_write_attempts=%I64u attempted_bytes=%I64u max_snapshot_bytes=%I64u",r245cWriteAttempts,r245cBytes,r245cMaxBytes);
   PrintFormat("[R245 SAVE TIMING C] ticks_with_saves=%I64u ticks_multiple_saves=%I64u saves_in_ticks=%I64u max_saves_per_tick=%I64u",r245cTicksWithSaves,r245cTicksMultipleSaves,r245cSavesInTicks,r245cMaxSavesPerTick);
   Print("[R245 SAVE TIMING C] END");
  }


ulong r245RewriteCount=0;
bool R245D_VerifyBytes(string file,const uchar &expected[],const int expectedSize,const int role)
  {
   if(expectedSize<0 || expectedSize>100000000 || ArraySize(expected)<expectedSize) return false;
   ulong r245eStarted=GetMicrosecondCount();
   int h=Test_FileOpen(file,FILE_READ|FILE_BIN|0);
   R245E_Record(role*6,GetMicrosecondCount()-r245eStarted);
   if(h==INVALID_HANDLE) return false;
   r245eStarted=GetMicrosecondCount();
   ResetLastError();
   ulong size=FileSize(h);
   int sizeErr=GetLastError();
   R245E_Record(role*6+1,GetMicrosecondCount()-r245eStarted);
   if(sizeErr!=0 || size!=(ulong)expectedSize) { R245E_Close(h,role); return false; }
   if(expectedSize==0) { R245E_Close(h,role); return true; }
   uchar actual[];
   r245eStarted=GetMicrosecondCount();
   int allocated=ArrayResize(actual,expectedSize);
   R245E_Record(role*6+2,GetMicrosecondCount()-r245eStarted);
   if(allocated!=expectedSize) { R245E_Close(h,role); return false; }
   r245eStarted=GetMicrosecondCount();
   uint read=Test_FileReadArray(h,actual,0,expectedSize);
   R245E_Record(role*6+3,GetMicrosecondCount()-r245eStarted);
   R245E_Close(h,role);
   if(read!=(uint)expectedSize) return false;
   if(expectedSize==0) return true;
   r245eStarted=GetMicrosecondCount();
   int compared=ArrayCompare(actual,expected,0,0,expectedSize);
   R245E_Record(role*6+5,GetMicrosecondCount()-r245eStarted);
   return compared==0;
  }

// Caller owns and closes h on every path. Never acknowledges persistence here.
bool R245F_VerifyHandle(const int h,const uchar &expected[],const int expectedSize)
  {
   if(h==INVALID_HANDLE || expectedSize<0 || expectedSize>100000000 || ArraySize(expected)<expectedSize) return false;
   if(!R245F_SeekStart(h)) return false;
   ulong started=GetMicrosecondCount();
   ResetLastError();
   ulong size=FileSize(h);
   int sizeErr=GetLastError();
   R245E_Record(1,GetMicrosecondCount()-started);
   if(sizeErr!=0 || size!=(ulong)expectedSize) return false;
   if(expectedSize==0) return true;
   uchar actual[];
   started=GetMicrosecondCount();
   int allocated=ArrayResize(actual,expectedSize);
   R245E_Record(2,GetMicrosecondCount()-started);
   if(allocated!=expectedSize) return false;
   started=GetMicrosecondCount();
   uint read=Test_FileReadArray(h,actual,0,expectedSize);
   R245E_Record(3,GetMicrosecondCount()-started);
   if(read!=(uint)expectedSize) return false;
   if(expectedSize==0) return true;
   started=GetMicrosecondCount();
   int compared=ArrayCompare(actual,expected,0,0,expectedSize);
   R245E_Record(5,GetMicrosecondCount()-started);
   return compared==0;
  }

bool R244_WriteFile(string file,string text)
  {
   r245RewriteCount++;
   string temporary=file+".new";
   uchar bytes[];
   ulong r245cStarted=GetMicrosecondCount();
   int size=0;
   if(StringLen(text)>0) size=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;
   R245C_Record(2,GetMicrosecondCount()-r245cStarted);
   if(size<0 || size>100000000) return false;
   r245cWriteAttempts++; r245cBytes+=(ulong)size;
   if((ulong)size>r245cMaxBytes) r245cMaxBytes=(ulong)size;
   r245cStarted=GetMicrosecondCount();
   // READ|WRITE preserves existing contents. Remove only the uncommitted scratch
   // file first; never remove the last committed file. Failed cleanup blocks save.
   if(FileIsExist(temporary,0) && !Test_FileDelete(temporary,0)) return false;
   int h=Test_FileOpen(temporary,FILE_READ|FILE_WRITE|FILE_BIN|0);
   R245C_Record(3,GetMicrosecondCount()-r245cStarted);
   if(h==INVALID_HANDLE) return false;
   // Fail closed if an unexpected file appeared or cleanup did not empty it.
   ResetLastError();
   ulong initialSize=FileSize(h);
   if(GetLastError()!=0 || initialSize!=0) { Test_FileClose(h); return false; }
   r245cStarted=GetMicrosecondCount();
   ResetLastError();
   uint written=0;
   if(size>0) written=Test_FileWriteArray(h,bytes,0,size);
   Test_FileFlush(h);
   int err=GetLastError();
   R245C_Record(4,GetMicrosecondCount()-r245cStarted);
   if(err!=0 || written!=(uint)size) { Test_FileClose(h); return false; }
   r245cStarted=GetMicrosecondCount();
   bool r245cTempOK=R245F_VerifyHandle(h,bytes,size);
   R245C_Record(6,GetMicrosecondCount()-r245cStarted);
   r245cStarted=GetMicrosecondCount();
   ResetLastError();
   Test_FileClose(h);
   int closeErr=GetLastError();
   R245C_Record(5,GetMicrosecondCount()-r245cStarted);
   if(!r245cTempOK || closeErr!=0) return false;
   r245cStarted=GetMicrosecondCount();
   bool r245cMoveOK=Test_FileMove(temporary,0,file,0|FILE_REWRITE);
   R245C_Record(7,GetMicrosecondCount()-r245cStarted);
   if(!r245cMoveOK) return false;
   r245cStarted=GetMicrosecondCount();
   bool r245cFinalOK=R245D_VerifyBytes(file,bytes,size,1);
   R245C_Record(8,GetMicrosecondCount()-r245cStarted);
   return r245cFinalOK;
  }
