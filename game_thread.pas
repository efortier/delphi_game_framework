unit game_thread;

interface

uses
  DX11, dx11_floats, utils_timer, dx11_textbox2, System.Types, System.Classes, rendergraph,
  System.SysUtils, rendercontext, temp_storage;

type

  TGameThread = class( TThread )
    RenderContext: PRenderContext;
    FrameCounter: UInt64;
    SoftSuspend: Boolean;
  private
    procedure RenderTimingGraph;
    procedure RenderCrosshair;
  protected

    // InternalSetup() occurs just before the main loop starts.
    procedure InternalSetup; virtual;

    procedure InternalInput( const DeltaTime: UInt32 ); virtual;
    procedure InternalSimulate( const DeltaTime: UInt32 ); virtual;
    procedure InternalRender; virtual;
    procedure Execute; override;
  public
    property Terminated;
    property ReturnValue;
  end;

implementation

uses
  utils_delta, game_states, Winapi.D3D11;

{ TRenderThread }

procedure TGameThread.Execute;
var
  dt: UInt32;
begin

  ReturnValue := 1;

  RenderContext.Initialize;
  RenderContext.FrameGraph := TFrameGraph.Create;
  RenderContext.FrameGraph.StartTiming( RenderContext.GameTimer.GetMS );

  FrameCounter := 0;

  InternalSetup;
  while ( Terminated = false ) do
  begin

    if( SoftSuspend = True ) then
    begin
      Sleep( 1 );
      continue;
    end;

    // throttle input + sim to some updates per second.
    dt := RenderContext.GameTimer.GetTicks - RenderContext.Runtime.LastSimulateTime;
    if( dt >= ( 1000 div 60 ) ) then
    begin
      RenderContext.Runtime.LastSimulateTime := RenderContext.GameTimer.GetTicks;
      InternalInput( dt );
      // TODO: make sure this Lock() is needed;
      RenderContext.BlockManager.Lock;
      InternalSimulate( dt );
      RenderContext.BlockManager.Unlock;
    end;

    RenderContext.Rendering := True;
    with RenderContext^ do
    begin

      TempStorage.Reset;

      TDeltaManager.GetInstance.Update( UInt32( GameTimer.GetMicro ) );

      DX.EnableAlphablend;
      DX.UpdateAndSetViewport;
      DX.SetDefaultRenderTarget;
      DX.ClearRenderTarget( 0, 0, 0, 0 );

      TrueTypeShader.SetContext;
      TrueTypeShader.Update( Float4.Create( 1, 1, 1, 1 ) );

      DXTextBox2.DrawTextSlow( Format( 'Mouse: %d, %d', [MouseX, MouseY] ), 10, 10, -5 );
      DXTextBox2.DrawTextSlow( Format( 'Frame: %d us, #%d', [FrameGraph.GraphInfo.Runtime.MaxTiming, FrameCounter]), 148, 10, -5 );
      DXTextBox2.DrawTextSlow( Format( 'Avg FPS: %.2f', [1000000.0 / FrameGraph.GraphInfo.Runtime.MaxTiming]), 340, 10, -5 );
      DXTextBox2.DrawTextSlow( Format( 'State: %d, HackCount: %d', [TGameStates.GetState, Runtime.HackCount]), 528, 10, -5 );

      if( RenderFrameGraph = True ) then
        RenderTimingGraph;

      // descendant override InternalRender() to render.
      // TODO: make sure this Lock() is needed;
      RenderContext.BlockManager.Lock;
      InternalRender;
      RenderContext.BlockManager.Unlock;

//      RenderCrosshair;

      DX.Present;

      // add timing to our graph.
      FrameGraph.AddTiming( GameTimer.GetMicro );
      Inc( FrameCounter );

    end;

    RenderContext.Rendering := False;

  end;

  RenderContext.FrameGraph.Free;

  ReturnValue := 0;

end;

procedure TGameThread.RenderTimingGraph;
var
  BarIndex: Integer;
  BW: Integer;
  GH: Integer;
  GW: Integer;
  RectBuffer: PFloat4;
  RectBufferMem: PFloat4;
  RectBufferSize: Integer;
  t: Integer;
  Value: Int64;
begin

  with RenderContext^ do
  begin

    LineShader.SetContext;

    // get graph size.
    BW := FrameGraph.GraphInfo.BarWidth;
    GW := FrameGraph.GraphInfo.BarCount * FrameGraph.GraphInfo.BarWidth;
    GH := FrameGraph.GraphInfo.TargetTiming * 2 * FrameGraph.GraphInfo.TimingHeight; //FFrameGraph.GraphInfo.Runtime.MaxTiming * FFrameGraph.GraphInfo.TimingHeight;

    Geometry.SetFillBuffers( 1 );
    LineShader.Update( Float4.Create( 0, 0, 0.5, 0.5 ) );
    Geometry.FillRect( FrameGraph.GraphInfo.Position.X, FrameGraph.GraphInfo.Position.Y, FrameGraph.GraphInfo.Position.X + GW, FrameGraph.GraphInfo.Position.Y + GH );

    //
    // batch the graph bars drawing.
    //
    RectBufferSize := FrameGraph.GraphInfo.BarCount * SizeOf( Float4 );
    RectBufferMem := TempStorage.GetMem( RectBufferSize );

    RectBuffer := RectBufferMem;
    for t := 0 to FrameGraph.GraphInfo.BarCount - 1 do
    begin
      Value := FrameGraph.GraphInfo.Frames[t].FrameTime * FrameGraph.GraphInfo.TimingHeight;
      RectBuffer^ := Float4.Create( FrameGraph.GraphInfo.Position.X + t * BW, FrameGraph.GraphInfo.Position.Y + GH - Value, FrameGraph.GraphInfo.Position.X + t * BW + BW, FrameGraph.GraphInfo.Position.Y + GH );
      Inc( RectBuffer );
    end;

    // draw bars.
    LineShader.Update( Float4.Create( 0.5, 0, 0, 0.5 ) );
    Geometry.SetFillBuffers( FrameGraph.GraphInfo.BarCount );
    Geometry.FillRects( RectBufferMem, FrameGraph.GraphInfo.BarCount );

    // draw current.
    LineShader.Update( Float4.Create( 1, 0, 0, 0.75 ) );
    BarIndex := FrameGraph.GraphInfo.Runtime.BarIndex - 1;
    if( BarIndex < 0 ) then
      BarIndex := FrameGraph.GraphInfo.BarCount - 1;
    Value := FrameGraph.GraphInfo.Frames[BarIndex].FrameTime * FrameGraph.GraphInfo.TimingHeight;
    Geometry.FillRect( FrameGraph.GraphInfo.Position.X + BarIndex * BW, FrameGraph.GraphInfo.Position.Y + GH - Value, FrameGraph.GraphInfo.Position.X + BarIndex * BW + BW, FrameGraph.GraphInfo.Position.Y + GH );

    TempStorage.FreeMem( RectBufferSize );

    // target timing
    Geometry.SetLineBuffers( 1 );
    LineShader.Update( Float4.Create( 0, 0, 1, 0.5 ) );
    Value := FrameGraph.GraphInfo.TargetTiming * FrameGraph.GraphInfo.TimingHeight;
    Geometry.DrawLine( FrameGraph.GraphInfo.Position.X, FrameGraph.GraphInfo.Position.Y + GH - Value, FrameGraph.GraphInfo.Position.X + GW, FrameGraph.GraphInfo.Position.Y + GH - Value );

    // max timing
    if( FrameGraph.GraphInfo.Runtime.MaxTiming > FrameGraph.GraphInfo.TargetTiming ) then
      LineShader.Update( Float4.Create( 1, 0, 0, 0.5 ) )
    else
      LineShader.Update( Float4.Create( 0, 1, 0, 0.5 ) );

    Value := FrameGraph.GraphInfo.Runtime.MaxTiming * FrameGraph.GraphInfo.TimingHeight;
    Geometry.DrawLine( FrameGraph.GraphInfo.Position.X, FrameGraph.GraphInfo.Position.Y + GH - Value, FrameGraph.GraphInfo.Position.X + GW, FrameGraph.GraphInfo.Position.Y + GH - Value );

  end;

end;

procedure TGameThread.RenderCrosshair;
const
  CROSS_LEN = 8;
begin
  with RenderContext^ do
  begin
    LineShader.SetContext;
    LineShader.Update( Float4.Create( 1, 0, 0, 1 ) );
    Geometry.SetLineBuffers( 1 );
    Geometry.DrawLine( MouseX, MouseY - CROSS_LEN, MouseX, MouseY + CROSS_LEN );
    Geometry.DrawLine( MouseX - CROSS_LEN, MouseY, MouseX + CROSS_LEN, MouseY );
  end;
end;

procedure TGameThread.InternalInput( const DeltaTime: UInt32 );
begin
end;

procedure TGameThread.InternalRender;
begin
end;

procedure TGameThread.InternalSetup;
begin
end;

procedure TGameThread.InternalSimulate( const DeltaTime: UInt32 );
begin
end;

end.

