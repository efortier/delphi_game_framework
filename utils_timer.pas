unit utils_timer;

interface

uses
  Winapi.MMSystem, System.Types, Winapi.Windows;

type

  TPerfCounter = class;

  // TODO: check to make sure the high perf timer is threadsafe.
  TGameTimer = class
  var
    FTimer: TPerfCounter;
  public
    constructor Create;
    destructor Destroy; override;
  private
  public
    function GetTicks: UInt32; inline;
    function GetMicro: UInt64; inline;
    function GetMS: UInt32; inline;

    //
    // get cpu cycles since last reboot.
    //
    // reference:
    //  https://codereview.stackexchange.com/questions/116154/precise-timings-with-low-jitter-via-rdtsc-for-x86-and-x64#
    //  http://www.intel.com/content/dam/www/public/us/en/documents/white-papers/ia-32-ia-64-benchmark-code-execution-paper.pdf
    //
    class function GetRDTSC: int64;
    class function GetRDTSCP: int64;

  end;

  //
  // updated singleton for thread safety.
  //
  TSingletonGameTimer = class
  private
    class var FInstance: TGameTimer;
    class function GetNewInstance: TGameTimer; static;
  public
    class destructor Destroy;
    class function GetInstance: TGameTimer; static; inline;
  end;

  // on XP and above, the performance counters will always be available, but not always reliable.
  // ie: must be locked to a single processor or the timing will be wrong or produce delays.
  TPerfCounter = class //( TBaseTimer )
  private
    FPerfCounterFreq: Double;
    FPerfCounterStart: TLargeInteger;
    FMilisecondDivider: Double;
    FMicrosecondDivider: Double;
  private
    procedure StartPerfCounter;
  protected
    function GetTicks: UInt32; inline;
    function GetMicro: UInt64; inline;
  public
    constructor Create;
  end;

  TTimeCounter = class //( TBaseTimer )
  protected
    function GetTicks: UInt32; inline;
    function GetMicro: UInt32; inline;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SyncObjs;

{ TGameTimer }

constructor TGameTimer.Create;
begin
  inherited;
  FTimer := TPerfCounter.Create
end;

destructor TGameTimer.Destroy;
begin
  FTimer.Free;
  inherited;
end;

function TGameTimer.GetMicro: UInt64;
begin
  Assert( FTimer <> nil );
  Result := FTimer.GetMicro;
end;

function TGameTimer.GetTicks: UInt32;
begin
  Assert( FTimer <> nil );
  Result := FTimer.GetTicks;
end;

function TGameTimer.GetMS: UInt32;
begin
  Result := GetTicks
end;

function RDTSC: Int64; assembler;
asm
  RDTSC  // ($310F) result Int64 in EAX and EDX
end;

// flushes all instructions before doing a RDTSC
function RDTSCP: Int64; assembler;
asm
  db    $0F, $01, $F9 // opcode for RDTSCP
end;

class function TGameTimer.GetRDTSC: int64;
begin
  Result := RDTSC;  // result Int64 in EAX and EDX
end;

class function TGameTimer.GetRDTSCP: int64;
begin
  Result := RDTSCP
end;

{ TPerfCounter }

constructor TPerfCounter.Create;
begin
  inherited;
//  LockThreadToCore;
  StartPerfCounter;
end;

function TPerfCounter.GetMicro: UInt64;
var
  li: TLargeInteger;
begin
  QueryPerformanceCounter( li );
  Result := Trunc( ( li - FPerfCounterStart ) / FMicrosecondDivider );
end;

function TPerfCounter.GetTicks: UInt32;
var
  li: TLargeInteger;
begin
  QueryPerformanceCounter( li );
  Result := Trunc( ( li - FPerfCounterStart ) / FMilisecondDivider );
end;

procedure TPerfCounter.StartPerfCounter;
var
  Value: TLargeInteger;
begin

  QueryPerformanceFrequency( Value );
  FPerfCounterFreq := Value;
  FMilisecondDivider := Value / 1000.0;
  FMicrosecondDivider := Value / 1000000.0;

  QueryPerformanceCounter( Value );
  FPerfCounterStart := 0;//Value;

end;

//
// this is not needed for Windows 7+ anymore.
//
//procedure TPerfCounter.LockThreadToCore;
//begin
//  old_mask = SetThreadAffinityMask(GetCurrentThread,1);
//  SetThreadAffinityMask ( GetCurrentThread , old_mask ) ;
//end;

{ TTimeCounter }

constructor TTimeCounter.Create;
begin
  inherited;
  timeBeginPeriod( 1 );
end;

destructor TTimeCounter.Destroy;
begin
  timeEndPeriod( 1 );
  inherited;
end;

function TTimeCounter.GetMicro: UInt32;
begin
  Result := 0;
  Assert( False, 'Microseconds not available with TTimeCounter.' );
end;

function TTimeCounter.GetTicks: UInt32;
begin
  Result := timeGetTime;
end;

{ TGameTimerSingleton }

class destructor TSingletonGameTimer.Destroy;
begin
  if( FInstance <> nil ) then
    FInstance.Free;
end;

class function TSingletonGameTimer.GetInstance: TGameTimer;
begin
  if( FInstance <> nil ) then
    Result := FInstance
  else
    Result := GetNewInstance;
end;

class function TSingletonGameTimer.GetNewInstance: TGameTimer;
var
  ObjInstance: TGameTimer;
begin

  ObjInstance := TGameTimer.Create;

  if( TInterlocked.CompareExchange( Pointer( FInstance ), Pointer( ObjInstance ), nil ) <> nil ) then
     ObjInstance.Free;

  Result := FInstance;

end;

end.

