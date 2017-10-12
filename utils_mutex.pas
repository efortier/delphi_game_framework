unit utils_mutex;

interface

uses
  Winapi.Windows, System.Classes;

type

  //
  // the main interface for a locking mechanism.
  //
  IGameMutex = interface
    function TryLock: Boolean;
    procedure Lock;
    procedure Unlock;
    function GetCounter: Integer; // for testing.
  end;

  // a critical section mutex.
  TCriticalSectionMutex = class( TInterfacedObject, IGameMutex )
  private
    FMutex: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
  public
    function TryLock: Boolean;
    procedure Lock;
    procedure Unlock;
    function GetCounter: Integer; inline;
  end;

  TInterlockedMutex = class( TInterfacedObject, IGameMutex )
  private
    FCounter: Integer;
    FSemaphore: THandle;
  public
    constructor Create;
    destructor Destroy; override;
  public
    procedure Lock; inline;
    procedure Unlock; inline;
    function TryLock: Boolean; inline;
    function GetCounter: Integer; inline;
  end;

  TTestMutexThread = class(TThread)
  public
    Mutex: IGameMutex;
    {$ifdef DEBUG}
    class procedure Test;
    {$endif}
  protected
    procedure Execute; override;
  end;

  TSRWMutex = class( TInterfacedObject, IGameMutex )
  private
    FMutex: TRTLSRWLock;
  public
    constructor Create;
    destructor Destroy; override;
  public
    function TryLock: Boolean;
    procedure Lock;
    procedure Unlock;
    function GetCounter: Integer; inline;
  end;

implementation

{ TGameMutex }

constructor TCriticalSectionMutex.Create;
begin
  inherited;
  InitializeCriticalSection( FMutex );
end;

destructor TCriticalSectionMutex.Destroy;
begin
  DeleteCriticalSection( FMutex );
  inherited;
end;

function TCriticalSectionMutex.GetCounter: Integer;
begin
  Result := -1;
end;

procedure TCriticalSectionMutex.Lock;
begin
  EnterCriticalSection( FMutex );
end;

procedure TCriticalSectionMutex.Unlock;
begin
  LeaveCriticalSection( FMutex );
end;

function TCriticalSectionMutex.TryLock: Boolean;
begin
  Result := TryEnterCriticalSection( FMutex );
end;

{ TInterlockedMutex }

constructor TInterlockedMutex.Create;
begin
  inherited;
  FCounter := 0;
  FSemaphore := CreateSemaphore(nil, 0, 1, nil);
end;

destructor TInterlockedMutex.Destroy;
begin
  CloseHandle( FSemaphore );
  inherited;
end;

function TInterlockedMutex.GetCounter: Integer;
begin
  Result := FCounter;
end;

procedure TInterlockedMutex.Lock;
begin
  if( InterlockedIncrement( FCounter ) > 1 ) then
    WaitForSingleObject( FSemaphore, INFINITE );
end;

function TInterlockedMutex.TryLock: Boolean;
begin
  Result := InterlockedCompareExchange(FCounter, 1, 0) = 0
end;

procedure TInterlockedMutex.Unlock;
begin
  if( InterlockedDecrement( FCounter ) > 0 ) then
    ReleaseSemaphore( FSemaphore, 1, nil );
end;

{ TTTestMutexThread }

procedure TTestMutexThread.Execute;
begin
  ReturnValue := 41;
  Mutex.Lock;
  Sleep( 1 );
  Mutex.Unlock;
  ReturnValue := 42;
end;

{$ifdef DEBUG}
class procedure TTestMutexThread.Test;

  procedure _Test1( Mutex: IGameMutex );
  var
    Res: Boolean;
  begin

    with Mutex do
    begin

      Res := TryLock;
      Assert( ( Res = True ) and ( GetCounter = 1 ) );
      if( Res = True ) then
      begin
        Unlock;
        Assert( GetCounter = 0 );
      end;

    end;

  end;

  procedure _Test2( Mutex: IGameMutex );
  var
    Res: Boolean;
  begin

    with Mutex do
    begin

      Res := TryLock;
      Assert( ( Res = True ) and ( GetCounter = 1 ) );
      if( Res = True ) then
      begin
        Res := TryLock;
        Assert( ( Res = False ) and ( GetCounter = 1 ) );
        Unlock;
        Assert( GetCounter = 0 );
      end;

    end;

  end;

  procedure _Test3( Mutex: IGameMutex );
  var
    TimerCount: DWORD;
    Res: Boolean;
    Thread: TTestMutexThread;
  begin

    // create thread.
    Thread := TTestMutexThread.Create( True );
    Thread.Mutex := Mutex;

    // lock the mutex.
    Res := Mutex.TryLock;
    Assert( Res = True );

    // start thread
    Thread.ReturnValue := 0;
    Thread.Resume;

    // wait until thread starts.
    TimerCount := GetTickCount;
    while( Thread.ReturnValue <> 41 ) do
    begin
      Sleep( 1 );
      if( GetTickCount - TimerCount > 10000 ) then
      begin
        Assert( False );
        break;
      end;
    end;

    // check thread is running.
    Assert( ( Thread.Finished = False ) );

    // unlock mutex, allowing thread to unlock and continue.
    Mutex.Unlock;

    // wait until thread unlocks.
    TimerCount := GetTickCount;
    while( Thread.ReturnValue <> 42 ) and ( Thread.Finished = True ) do
    begin
      Sleep( 1 );
      if( GetTickCount - TimerCount > 10000 ) then
      begin
        Assert( False );
        break;
      end;
    end;

    // done.
    Mutex := nil;
    Thread.Free;

  end;

begin

  // test normal trylock/unlock.
  _Test1( TInterlockedMutex.Create );

  // test multiple trylock.
  _Test2( TInterlockedMutex.Create );

  // test with locking thread.
  _Test3( TInterlockedMutex.Create );
  _Test3( TCriticalSectionMutex.Create );

end;
{$endif}

{ TSRWMutex }

constructor TSRWMutex.Create;
begin
  inherited;
  InitializeSRWLock( FMutex );
end;

destructor TSRWMutex.Destroy;
begin
  inherited;
end;

function TSRWMutex.GetCounter: Integer;
begin
  Result := -1;
end;

procedure TSRWMutex.Lock;
begin
  AcquireSRWLockExclusive( FMutex );
end;

function TSRWMutex.TryLock: Boolean;
begin
  Result := TryAcquireSRWLockExclusive( FMutex );
end;

procedure TSRWMutex.Unlock;
begin
  Assert( FMutex.Ptr <> nil, 'Check to see if mutex has been released already.' );
  ReleaseSRWLockExclusive( FMutex );
end;

initialization
//  TTestMutexThread.Test;
end.
