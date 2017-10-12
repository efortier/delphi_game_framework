unit game_thread_impl;

{$WRITEABLECONST ON}

{$RANGECHECKS ON}

interface

uses
  game_hackmanager, game_thread, gen_array_ex2, rendercontext, game_renderobject,
  dx11_instancedfillrects, game_fsm_scanning;

type

  TMyGameThread = class( TGameThread )
  private
    procedure SimulateUpdateParticleManager( const DeltaTime: UInt32 );
    procedure SimulateHandleSignals( const DeltaTime: UInt32 );
    procedure SetupStateObjects;
  protected
    procedure InternalSetup; override; final;
    procedure InternalInput( const DeltaTime: UInt32 ); override; final;
    procedure InternalSimulate( const DeltaTime: UInt32 ); override; final;
    procedure InternalRender; override; final;
  end;

  TRenderBase = class( TRenderObject )
  private
    class var FDataBlocksInstancedFill: TInstancedFillRect;
    class var FScanTrailInstancedFill: TInstancedFillRect;
  public
    class constructor Create;
    class destructor Destroy;
  public
    class procedure Initialize; override; final;
    class procedure StopState( const StateIndex: Integer ); static;
    class procedure RenderDataBlocks; static;
    class procedure RenderScanTrailOverlay; static;

    class procedure SimulatePrecalculateBlocksInfo( const DeltaTime: UInt32 ); static;

    class procedure SimulatePrecalculateDecryptedBlocksInfo( const DeltaTime: UInt32 ); static;

  end;

  TClusterViewRenderObject = class( TRenderObject )
  private
    class procedure RandomizeDataBlockIndexArray( const BlockCount: Integer ); static;
    class procedure SimulateEmitScanningParticles( const DeltaTime: UInt32 ); static;
    class procedure RenderParticles; static;
    class procedure RenderScanningStats; static;
  public
    class procedure Render; override;
    class procedure Simulate( const DeltaTime: UInt32 ); override;
  end;

  TScanningRenderObject = class( TRenderObject )
  private
    class var FScanningFSM: TScanningFSM;
  private
    class procedure InternalSimulate( const DeltaTime: UInt32 ); static;
  public
    class destructor Destroy;
  public
    class procedure Initialize; override; final;
    class procedure Render; override; final;
    class procedure Simulate( const DeltaTime: UInt32 ); override; final;
    class procedure InternalCalculateBlockUnderMouse; static;
    class procedure RenderBlockHighlight; static;
  end;

implementation

uses
  game_signals, dx11_floats, System.SysUtils, game_particles_readwrite, game_fsm_databarriertool,
  game_toolmanager, game_fsm_fadeinout, game_states, rng, temp_storage, particle_manager,
  utils_timer, game_fsm_salvagetool, System.Types,
  System.Math;

const
  BLOCK_WIDTH = 8;
  BLOCK_HEIGHT = 8;
  BLOCK_SPACING_X = 3;
  BLOCK_SPACING_Y = 3;

{ TMyGameThread }

procedure TMyGameThread.InternalSetup;
begin
  TRenderObject.Context := RenderContext;
  SetupStateObjects;
end;

procedure TMyGameThread.SetupStateObjects;
begin
  TGameStates.ItemsPtr[STATE_BLANK].RenderObjectClass := nil;
  TGameStates.ItemsPtr[STATE_CLUSTERVIEW].RenderObjectClass := TClusterViewRenderObject;
  TGameStates.ItemsPtr[STATE_SCANNING].RenderObjectClass := TScanningRenderObject;
end;

procedure TMyGameThread.InternalInput( const DeltaTime: UInt32 );
begin
end;

procedure TMyGameThread.InternalSimulate( const DeltaTime: UInt32 );
begin

  if( RenderContext.BlockManager.Clusters.Count > 0 ) then
  begin

    SimulateHandleSignals( DeltaTime );
    SimulateUpdateParticleManager( DeltaTime );

    if( TGameStates.CurrentStateData.RenderObjectClass <> nil ) then
      TGameStates.CurrentStateData.RenderObjectClass.Simulate( DeltaTime );

  end;

end;

procedure TMyGameThread.InternalRender;
begin

  if( RenderContext.BlockManager.Clusters.Count <> 0 ) then
  begin

    RenderContext.TempStorage.Push;

    if( TGameStates.CurrentStateData.RenderObjectClass <> nil ) then
      TGameStates.CurrentStateData.RenderObjectClass.Render;

    RenderContext.TempStorage.Pop;

  end;

end;

procedure TMyGameThread.SimulateHandleSignals( const DeltaTime: UInt32 );
begin

  // this procedure can be used to transition from one rendering state to another
  // maybe with a fade out/fade in, blend, etc, and it also handles signals.

  if( TGameSignals.ResetIfSet( SIGNAL_SWITCHTOSTATE_BLANK ) = True ) then
  begin
    TRenderBase.StopState( TGameStates.CurrentState );
    TGameStates.SetState( STATE_BLANK );
    TGameStates.InitializeState;
  end

  // hack init needs to always the first signal sent before
  // starting the actual hack.
  else if( TGameSignals.ResetIfSet( SIGNAL_HACK_INIT ) = True ) then
  begin
    TRenderBase.Initialize;
    TGameSignals.Signal( SIGNAL_SWITCHTOSTATE_CLUSTERVIEW );
  end

  else if( TGameSignals.ResetIfSet( SIGNAL_SWITCHTOSTATE_CLUSTERVIEW ) = True ) then
  begin
    TRenderBase.StopState( TGameStates.CurrentState );
    TGameStates.SetState( STATE_CLUSTERVIEW );
    TGameStates.InitializeState;
  end

  else if( TGameSignals.ResetIfSet( SIGNAL_SWITCHTOSTATE_SCANNER ) = True ) then
  begin
    TRenderBase.StopState( TGameStates.CurrentState );
    TGameStates.SetState( STATE_SCANNING );
    TGameStates.InitializeState;
  end;

end;

procedure TMyGameThread.SimulateUpdateParticleManager( const DeltaTime: UInt32 );
begin
  RenderContext.ParticleManager.Update( DeltaTime );
end;

{ TRenderBase }

class constructor TRenderBase.Create;
begin
end;

class destructor TRenderBase.Destroy;
begin
  if( FDataBlocksInstancedFill <> nil ) then
    FDataBlocksInstancedFill.Free;
  if( FScanTrailInstancedFill <> nil ) then
    FScanTrailInstancedFill.Free;
end;

class procedure TRenderBase.Initialize;
begin

  with Context^ do
  begin

    Runtime.EncryptedBlockCount := BlockManager.GetBlockTypeCount( BlockManager.GetSelectedCluster, [BT_ENCRYPTED] );

    // HERE ***

//    BlocksRenderRectWidth := Context.Runtime.MaxBlocksPerRow * BLOCK_WIDTH + Context.Runtime.MaxBlocksPerRow * BLOCK_SPACING_X - BLOCK_SPACING_X;
//    EncryptedRowCount := Ceil( EncryptedBlockCount / Context.Runtime.RenderBlocksColCount );
  end;

end;

class procedure TRenderBase.SimulatePrecalculateDecryptedBlocksInfo( const DeltaTime: UInt32 );
var
  Block: PDataBlock;
  BlockColCount: Integer;
  BlockCount: Integer;
  BlocksRenderRectWidth: Integer;
  Cluster: TDataCluster;
  DecryptedBlocksLeft: Integer;
  DecryptedBlocksTop: Integer;
  SX: Integer;
  X: Integer;
  Y: Integer;
  i: Integer;
  SY: Integer;
begin

  DecryptedBlocksTop := Context.Runtime.BlocksRenderRect.Top + BLOCK_SPACING_Y * 2;
  DecryptedBlocksLeft := Context.Runtime.BlocksRenderRect.Left;

  BlockCount := Context.Runtime.EncryptedBlockCount;

  // pre-calculate blocks color and position.
  BlocksRenderRectWidth := Context.Runtime.MaxBlocksPerRow * BLOCK_WIDTH + Context.Runtime.MaxBlocksPerRow * BLOCK_SPACING_X;
  SX := ( Context.DX.DisplaySize.cx - BlocksRenderRectWidth ) div 2;
  SY := 80;
  X := SX;
  Y := SY;

  Cluster := Context.BlockManager.GetSelectedCluster;
  BlockCount := Cluster.Blocks.Count;

  Context.Runtime.RenderBlocksColCount := 0;
  Context.Runtime.RenderBlocksRowCount := 0;
  BlockColCount := 0;
  for i := 0 to BlockCount - 1 do
  begin

    Block := Cluster.Blocks.ItemAsPointer[i];

    Block.Runtime.RenderColor := Context.BlockManager.GetColorForBlock( Block );
    Block.Runtime.RenderPosition.x1 := X;
    Block.Runtime.RenderPosition.y1 := Y;
    Block.Runtime.RenderPosition.x2 := X + BLOCK_WIDTH - 1;
    Block.Runtime.RenderPosition.y2 := Y + BLOCK_HEIGHT - 1;

    Inc( X, BLOCK_WIDTH + BLOCK_SPACING_X );
    Inc( BlockColCount );

    if( BlockColCount >= Context.Runtime.MaxBlocksPerRow ) then
    begin

      BlockColCount := 0;

      X := SX;

      Inc( Y, BLOCK_HEIGHT + BLOCK_SPACING_Y );

      if( Context.Runtime.RenderBlocksColCount = 0 ) then
        Context.Runtime.RenderBlocksColCount := i + 1;

      Inc( Context.Runtime.RenderBlocksRowCount );

    end;

  end;

  Context.Runtime.BlocksRenderRect.Left := SX;
  Context.Runtime.BlocksRenderRect.Top := SY;
  Context.Runtime.BlocksRenderRect.Right := SX + Context.Runtime.RenderBlocksColCount * BLOCK_WIDTH + Context.Runtime.RenderBlocksColCount * BLOCK_SPACING_X - BLOCK_SPACING_X;
  Context.Runtime.BlocksRenderRect.Bottom := SY + ( Context.Runtime.RenderBlocksRowCount - 0 ) * BLOCK_HEIGHT + ( Context.Runtime.RenderBlocksRowCount - 0 ) * BLOCK_SPACING_Y - BLOCK_SPACING_Y;

end;

class procedure TRenderBase.SimulatePrecalculateBlocksInfo( const DeltaTime: UInt32 );
var
  Block: PDataBlock;
  BlockColCount: Integer;
  BlockCount: Integer;
  BlocksRenderRectWidth: Integer;
  Cluster: TDataCluster;
  SX: Integer;
  X: Integer;
  Y: Integer;
  i: Integer;
  SY: Integer;
begin

  // pre-calculate blocks color and position.
  // TODO: the position should only be recalculated if the blocks moved.
  BlocksRenderRectWidth := Context.Runtime.MaxBlocksPerRow * BLOCK_WIDTH + Context.Runtime.MaxBlocksPerRow * BLOCK_SPACING_X;
  SX := ( Context.DX.DisplaySize.cx - BlocksRenderRectWidth ) div 2;
  SY := 80;
  X := SX;
  Y := SY;

  Cluster := Context.BlockManager.GetSelectedCluster;
  BlockCount := Cluster.Blocks.Count;

  Context.Runtime.RenderBlocksColCount := 0;
  Context.Runtime.RenderBlocksRowCount := 0;
  BlockColCount := 0;
  for i := 0 to BlockCount - 1 do
  begin

    Block := Cluster.Blocks.ItemAsPointer[i];

    Block.Runtime.RenderColor := Context.BlockManager.GetColorForBlock( Block );
    Block.Runtime.RenderPosition.x1 := X;
    Block.Runtime.RenderPosition.y1 := Y;
    Block.Runtime.RenderPosition.x2 := X + BLOCK_WIDTH - 1;
    Block.Runtime.RenderPosition.y2 := Y + BLOCK_HEIGHT - 1;

    Inc( X, BLOCK_WIDTH + BLOCK_SPACING_X );
    Inc( BlockColCount );

    if( BlockColCount >= Context.Runtime.MaxBlocksPerRow ) then
    begin

      BlockColCount := 0;

      X := SX;

      Inc( Y, BLOCK_HEIGHT + BLOCK_SPACING_Y );

      if( Context.Runtime.RenderBlocksColCount = 0 ) then
        Context.Runtime.RenderBlocksColCount := i + 1;

      Inc( Context.Runtime.RenderBlocksRowCount );

    end;

  end;

  Context.Runtime.BlocksRenderRect.Left := SX;
  Context.Runtime.BlocksRenderRect.Top := SY;
  Context.Runtime.BlocksRenderRect.Right := SX + Context.Runtime.RenderBlocksColCount * BLOCK_WIDTH + Context.Runtime.RenderBlocksColCount * BLOCK_SPACING_X - BLOCK_SPACING_X;
  Context.Runtime.BlocksRenderRect.Bottom := SY + ( Context.Runtime.RenderBlocksRowCount - 0 ) * BLOCK_HEIGHT + ( Context.Runtime.RenderBlocksRowCount - 0 ) * BLOCK_SPACING_Y - BLOCK_SPACING_Y;

end;

class procedure TRenderBase.StopState( const StateIndex: Integer );
begin
  if( TGameStates.Items[StateIndex].StateMachine <> nil ) then
    TGameStates.Items[StateIndex].StateMachine.Stop;
end;

class procedure TRenderBase.RenderDataBlocks;
var
  InstancedBuffer: PInstancedFillType;
  InstancedBufferMem: PInstancedFillType;
  Block: PDataBlock;
  BlockCount: Integer;
  Cluster: TDataCluster;
  i: Integer;
  R: TRect;
begin

  Cluster := Context.BlockManager.GetSelectedCluster;
  BlockCount := Cluster.Blocks.Count;

  if( Context.Runtime.RenderSingleBlocks = False ) then
  begin

    // TODO: Do a better job of managing state-specific objects like these. ie: do not place them in class variables.
    if( FDataBlocksInstancedFill = nil ) then
    begin
      FDataBlocksInstancedFill := TInstancedFillRect.Create( Context.Geometry );
      FDataBlocksInstancedFill.SetRect( Float4.Create( 0, 0, BLOCK_WIDTH - 1, BLOCK_HEIGHT - 1 ) );
    end;

    Context.TempStorage.Push;
    InstancedBufferMem := Context.TempStorage.GetMem( BlockCount * SizeOf( TInstancedFillType ) );
    InstancedBuffer := InstancedBufferMem;

    for i := 0 to BlockCount - 1 do
    begin
      InstancedBuffer.Position := Float4.Create( Cluster.Blocks[i].Runtime.RenderPosition.X, Cluster.Blocks[i].Runtime.RenderPosition.Y, -5, 0 );
      InstancedBuffer.Color := Cluster.Blocks[i].Runtime.RenderColor;
      Inc( InstancedBuffer );
    end;

    Context.InstancedLineShader.SetContext;
    FDataBlocksInstancedFill.SetBuffers( BlockCount );
    FDataBlocksInstancedFill.Draw( InstancedBufferMem, BlockCount );
    Context.TempStorage.Pop;

  end else
  begin

    with Context^ do
    begin

      LineShader.SetContext;
      Geometry.SetFillBuffers( BlockCount );
      BlockCount := Cluster.Blocks.Count;
      for i := 0 to BlockCount - 1 do
      begin
        Block := Cluster.Blocks.ItemAsPointer[i];
        LineShader.Update( Block.Runtime.RenderColor );
        Geometry.FillRect( Block.Runtime.RenderPosition.x1, Block.Runtime.RenderPosition.y1, Block.Runtime.RenderPosition.x2, Block.Runtime.RenderPosition.y2 );
      end;

    end;

  end;

  with Context^ do
  begin
    LineShader.SetContext;
    LineShader.Update( Float4.Create( 1, 1, 1, 1 ) );
    Geometry.SetFrameBuffers( 1 );
    R := Runtime.BlocksRenderRect;
    R.Inflate( 2, 2 );
    Geometry.FrameRect( R );
  end;

end;

class procedure TRenderBase.RenderScanTrailOverlay;
var
  Block: PDataBlock;
  BufferCount: Integer;
  Cluster: TDataCluster;
  i: Integer;
  InstancedBuffer: PInstancedFillType;
  InstancedBufferMem: PInstancedFillType;
begin

  with Context^ do
  begin

    Cluster := BlockManager.GetSelectedCluster;

    TempStorage.Push;

    InstancedBufferMem := Context.TempStorage.GetMem( Cluster.Blocks.Count * SizeOf( TInstancedFillType ) );
    InstancedBuffer := InstancedBufferMem;

    BufferCount := 0;
    for i := 0 to Cluster.Blocks.Count - 1 do
    begin

      Block := Cluster.Blocks.ItemAsPointer[i];

      if( BS_SCANTRAIL in Block.BlockStates ) then
      begin
        InstancedBuffer.Position := Float4.Create( Block.Runtime.RenderPosition.x, Block.Runtime.RenderPosition.y, -5, 0 );
        InstancedBuffer.Color := Float4.Create( Runtime.GameToolsRuntime.Scanning.ScanTrailRGB, Block.Runtime.RenderAlpha );
        Inc( InstancedBuffer );
        Inc( BufferCount );
      end;

    end;

    if( BufferCount > 0 ) then
    begin

      if( FScanTrailInstancedFill = nil ) then
      begin
        FScanTrailInstancedFill := TInstancedFillRect.Create( Context.Geometry );
        FScanTrailInstancedFill.SetRect( Float4.Create( 0, 0, BLOCK_WIDTH - 1, BLOCK_HEIGHT - 1 ) );
      end;

      InstancedLineShader.SetContext;
      FScanTrailInstancedFill.SetBuffers( BufferCount );
      FScanTrailInstancedFill.Draw( InstancedBufferMem, BufferCount );

    end;

    TempStorage.Pop;

  end;

end;

{ TScanningRenderObject }

class procedure TClusterViewRenderObject.Simulate( const DeltaTime: UInt32 );
begin
  TRenderBase.SimulatePrecalculateBlocksInfo( DeltaTime );
  SimulateEmitScanningParticles( DeltaTime );
end;

class procedure TClusterViewRenderObject.SimulateEmitScanningParticles( const DeltaTime: UInt32 );
var
  Block: PDataBlock;
  Block2: PDataBlock;
  BlockIndex: Integer;
  Cluster: TDataCluster;
  i: Integer;
  Particle: TReadWriteParticle;
  ReadParticle: TReadWriteParticle;
begin

  Cluster := Context.BlockManager.GetSelectedCluster;
  if( Context.Runtime.RandomDataBlockIndexArray.Count <> Cluster.Blocks.Count ) then
    RandomizeDataBlockIndexArray( Cluster.Blocks.Count );

  // the particles, ie: block frames.
  with Context^ do
  begin

    // try to emit a particle.
    if( RenderParticles = True ) then
    begin

      // if we're signaled to emit new particles, do it.
      //if( TGameSignals.IsSet( SIGNAL_EMITPARTICLES ) = True ) then
      begin

        Particle := ParticleManager.Emit as TReadWriteParticle;
        if( Particle <> nil ) then
        begin

          // initialize emitted particle.
          Particle.Initialize( GameTimer.GetTicks );
          Particle.BlockIndex := Runtime.RandomDataBlockIndexArray[Runtime.RandomDataBlockIndex];
          Inc( Runtime.RandomDataBlockIndex );
          if( Runtime.RandomDataBlockIndex >= Runtime.RandomDataBlockIndexArray.Count ) then
          begin
            Runtime.RandomDataBlockIndex := 0;
            RandomizeDataBlockIndexArray( Cluster.Blocks.Count );
          end;

          // generate read/write. 1: write.
          Particle.WriteMode := BlockManager.GenerateRandom( 1, 100 ) <= 50;

          // TODO:
          //
          // as blocks are read/written, move them around given some rules.
          //
          // ie: if a block is read that is fragmented, and if a block is written to that is optimized,
          // there is a high chance that the blocks will be swapped, so the block written to appears to now
          // be fragmented.

          // check for fragmentation of write block.
          // is this new particle a write particle?
          if( MoveOptimizedBlocksOnWrite = True ) and ( Particle.WriteMode = True ) then
          begin

            BlockIndex := Particle.BlockIndex;
            Block := Cluster.Blocks.ItemAsPointer[BlockIndex];

            // if so, is it optimized?
            if( Block.BlockType = BT_OPTIMIZED ) then
            begin

              // if so, is there a read particle that is fragmented?
              for i := 0 to ParticleManager.ParticlePool.PoolSize - 1 do
              begin

                ReadParticle := ParticleManager.ParticlePool.Particles[i] as TReadWriteParticle;
                if( ReadParticle.IsEmitted = True ) then
                begin

                  if( ReadParticle.WriteMode = False ) then
                  begin

                    Block2 := Cluster.Blocks.ItemAsPointer[ReadParticle.BlockIndex];
                    if( Block2.BlockType <> BT_OPTIMIZED ) then
                    begin
                      // if so, swap the blocks.
                      Block.BlockType := BT_FRAGMENTED;
                      Cluster.Blocks.Swap( Particle.BlockIndex, ReadParticle.BlockIndex );
                      break;
                    end;

                    // TODO:
                    // if not, is there any fragmented blocks available? (might be better)
                    // if so, swap the blocks.
                    // TODO: chance to fragment optimized block by turning it into fragmented and turning a free block into a fragmented one.

                  end;

                end;

              end;

            end;

          end;

        end;

      end;

    end;

  end;

  //end;

end;

class procedure TClusterViewRenderObject.RandomizeDataBlockIndexArray( const BlockCount: Integer );
var
  i: UInt32;
  NewIndex1, NewIndex2: UInt32;
begin

  if( Context.Runtime.RandomDataBlockIndexArray.Count <> BlockCount ) then
  begin

    Context.Runtime.RandomDataBlockIndexArray.Count := BlockCount;
    for i := 0 to BlockCount - 1 do
      Context.Runtime.RandomDataBlockIndexArray.Items[i] := i;

  end;

  for i := 0 to BlockCount - 1 do
  begin

    // randomize every index after this one.
    repeat
      NewIndex1 := Context.BlockManager.GenerateRandom( 0, BlockCount - 1 );
    until ( i <> NewIndex1 );

    Context.Runtime.RandomDataBlockIndexArray.Swap( i, NewIndex1 );

    repeat
      NewIndex2 := Context.BlockManager.GenerateRandom( 0, BlockCount - 1 );
    until ( i <> NewIndex2 ) and ( NewIndex1 <> NewIndex2 );

    Context.Runtime.RandomDataBlockIndexArray.Swap( NewIndex1, NewIndex2 );

  end;

end;

class procedure TClusterViewRenderObject.RenderParticles;
var
  Block: PDataBlock;
  BufferCount: Integer;
  Cluster: TDataCluster;
  DoDraw: Boolean;
  i: Integer;
  Particle: TReadWriteParticle;
  RectBuffer: PFloat4;
  RectBufferMem: PFloat4;
const
  OFFSET = 1;
begin

  with Context^ do
  begin

    Cluster := BlockManager.GetSelectedCluster;

    // render emitted particles.
    Runtime.ParticlesVisible := 0;
    Runtime.ParticlesEmitted := 0;
    if( ParticleManager.ActiveParticleCount > 0 ) then
    begin

      LineShader.SetContext;
      Runtime.ParticlesEmitted := ParticleManager.CopyUserParticleList;

      if( Runtime.RenderSingleParticles = False ) then
      begin

        // 4 sides, and 2 points per side.
        Geometry.SetFillBuffers( Runtime.ParticlesEmitted );

        RectBufferMem := TempStorage.GetMem( Runtime.ParticlesEmitted * SizeOf( Float4 ) );

        // render write particles.
        RectBuffer := RectBufferMem;
        BufferCount := 0;
        for i := 0 to Runtime.ParticlesEmitted - 1 do
        begin

          Particle := ParticleManager.ActiveParticleList_USER[i] as TReadWriteParticle;
          DoDraw := Particle.IsVisible and Particle.WriteMode;
          if( DoDraw = True ) then
          begin
            Inc( Runtime.ParticlesVisible );
            Block := Cluster.Blocks.ItemAsPointer[Particle.BlockIndex];
            RectBuffer^ := Float4.Create( Block.Runtime.RenderPosition.x1 - OFFSET, Block.Runtime.RenderPosition.y1 - OFFSET, Block.Runtime.RenderPosition.x2 + OFFSET, Block.Runtime.RenderPosition.y2 + OFFSET );
            Inc( RectBuffer );
            Inc( BufferCount );
          end;

        end;

        if( BufferCount > 0 ) then
        begin
          LineShader.Update( Float4.Create( 1, 0.25, 0.25, 1 ) );
          Geometry.FillRects( RectBufferMem, BufferCount );
        end;

        // read particle
        RectBuffer := RectBufferMem;
        BufferCount := 0;
        for i := 0 to Runtime.ParticlesEmitted - 1 do
        begin

          Particle := ParticleManager.ActiveParticleList_USER[i] as TReadWriteParticle;
          DoDraw := Particle.IsVisible and ( Particle.WriteMode = False );
          if( DoDraw = True ) then
          begin
            Inc( Runtime.ParticlesVisible );
            Block := Cluster.Blocks.ItemAsPointer[Particle.BlockIndex];
            RectBuffer^ := Float4.Create( Block.Runtime.RenderPosition.x1 - OFFSET, Block.Runtime.RenderPosition.y1 - OFFSET, Block.Runtime.RenderPosition.x2 + OFFSET, Block.Runtime.RenderPosition.y2 + OFFSET );
            Inc( RectBuffer );
            Inc( BufferCount );
          end;

        end;

        if( BufferCount > 0 ) then
        begin
          LineShader.Update( Float4.Create( 0.25, 1, 0.25, 1 ) );
          Geometry.FillRects( RectBufferMem, BufferCount );
        end;

      end else
      begin

        Geometry.SetFillBuffers( 1 );
        for i := 0 to Runtime.ParticlesEmitted - 1 do
        begin

          Particle := ParticleManager.ActiveParticleList_USER[i] as TReadWriteParticle;
          Assert( Particle.IsEmitted = True );

          if( Particle.IsVisible = True ) then
          begin
            Inc( Runtime.ParticlesVisible );
            Block := Cluster.Blocks.ItemAsPointer[Particle.BlockIndex];

            if( Particle.WriteMode = True ) then
              LineShader.Update( Float4.Create( 1, 0.0, 0.0, 1 ) )
            else
              LineShader.Update( Float4.Create( 0.25, 1, 0.25, 1 ) );
            Geometry.FillRect( Block.Runtime.RenderPosition.x1 - OFFSET, Block.Runtime.RenderPosition.y1 - OFFSET, Block.Runtime.RenderPosition.x2 + OFFSET, Block.Runtime.RenderPosition.y2 + OFFSET, -5 );

          end;

        end;

      end;

    end;

  end;

end;

class procedure TClusterViewRenderObject.RenderScanningStats;
begin
  Context.TrueTypeShader.SetContext;
  Context.TrueTypeShader.Update( Float4.Create( 1, 1, 1, 1 ) );
  Context.DXTextBox2.DrawTextSlow( Format( 'Particles emitted/visible: %d, %d', [Context.Runtime.ParticlesEmitted, Context.Runtime.ParticlesVisible] ), 10, 32, -5 );
end;

class procedure TClusterViewRenderObject.Render;
begin
  TRenderBase.RenderDataBlocks;
  RenderParticles;
  RenderScanningStats;
end;

{ TDefragRenderObject }

class procedure TScanningRenderObject.Render;
begin
  TRenderBase.RenderDataBlocks;
  TRenderBase.RenderScanTrailOverlay;
  RenderBlockHighlight;
end;

class procedure TScanningRenderObject.RenderBlockHighlight;
var
  Block: PDataBlock;
  Cluster: TDataCluster;
begin

  if( Context.Runtime.IndexBlockUnderMouse <> -1 ) then
  begin

    with Context^ do
    begin

      LineShader.SetContext;
      Geometry.SetFrameBuffers( 1 );

      Cluster := Context.BlockManager.GetSelectedCluster;
      Assert( Cluster <> nil );

      Block := Cluster.Blocks.ItemAsPointer[Context.Runtime.IndexBlockUnderMouse];

      LineShader.Update( Float4.Create( 1, 0, 1, 1 ) );
      Geometry.FrameRect( Block.Runtime.RenderPosition.x1 - 1, Block.Runtime.RenderPosition.y1 - 1, Block.Runtime.RenderPosition.x2 + 1, Block.Runtime.RenderPosition.y2 + 1 );

    end;

  end;

end;

class procedure TScanningRenderObject.Simulate( const DeltaTime: UInt32 );
begin
  TRenderBase.SimulatePrecalculateBlocksInfo( DeltaTime );
  InternalSimulate( DeltaTime );
  InternalCalculateBlockUnderMouse;
end;

class procedure TScanningRenderObject.InternalSimulate( const DeltaTime: UInt32 );
begin

  if( FScanningFSM = nil ) then
  begin
    FScanningFSM := TScanningFSM.Create;
    FScanningFSM.BlockManager := Context.BlockManager;
    TGameStates.CurrentStateData.StateMachine := FScanningFSM;
  end;

  if( FScanningFSM.IsRunning = False ) then
  begin
    FScanningFSM.Cluster := Context.BlockManager.GetSelectedCluster;
    FScanningFSM.RowCount := Context.Runtime.RenderBlocksRowCount;
    FScanningFSM.ColCount := Context.Runtime.RenderBlocksColCount;
    FScanningFSM.Start;
    Context.Runtime.GameToolsRuntime.Scanning.ScanTrailRGB := Float3.Create( 0, 1, 0 );
  end;

  if( FScanningFSM.IsRunning = True ) then
    FScanningFSM.Update( DeltaTime );

end;

class destructor TScanningRenderObject.Destroy;
begin
  if( FScanningFSM <> nil ) then
    FScanningFSM.Free;
end;

class procedure TScanningRenderObject.Initialize;
begin
  Context.Runtime.IndexBlockUnderMouse := -1;
end;

class procedure TScanningRenderObject.InternalCalculateBlockUnderMouse;
var
  Block: PDataBlock;
  Block2: PDataBlock;
  BlockCount: Integer;
  Cluster: TDataCluster;
  ColCount: Integer;
  i: Integer;
  RowCount: Integer;
  BlockY, BlockX: Integer;
begin

  // find current mouse pos without going over the whole array of blocks, just the X and Y axis.
  // TODO: can be optimized by using a hash table or something similar.
  Cluster := Context.BlockManager.GetSelectedCluster;
  Assert( Cluster <> nil );

  BlockCount := Cluster.Blocks.Count;
  RowCount := Context.Runtime.RenderBlocksRowCount;
  ColCount := Context.Runtime.RenderBlocksColCount;

  // is the mouse over the grid at all?
  Block := Cluster.Blocks.ItemAsPointer[0];
  Block2 := Cluster.Blocks.ItemAsPointer[( ColCount - 1 ) + ( RowCount - 1 ) * ColCount];
  if( Context.MouseX < Block.Runtime.RenderPosition.x1 ) or
    ( Context.Mousey < Block.Runtime.RenderPosition.y1 ) or
    ( Context.MouseX > Block2.Runtime.RenderPosition.x2 ) or
    ( Context.Mousey > Block2.Runtime.RenderPosition.y2 ) then
  begin
    Context.Runtime.IndexBlockUnderMouse := -1;
    Exit;
  end;

  // locate Y line of mouse.
  BlockY := -1;
  for i := 0 to RowCount - 1 do
  begin

    Block := Cluster.Blocks.ItemAsPointer[i * ColCount];

    // if the mouse is less than this block's top, we're not on the grid.
    if( Context.MouseY < Block.Runtime.RenderPosition.y1 ) then
      break;

    if( Context.MouseY <= Block.Runtime.RenderPosition.y2 ) then
    begin
      BlockY := i;
      break;
    end

  end;

  // if no position was found for Y, the mouse isn't over the grid.
  if( BlockY = -1 ) then
    Exit;

  // now the X.
  BlockX := -1;
  for i := 0 to ColCount - 1 do
  begin

    Block := Cluster.Blocks.ItemAsPointer[i];

    if( Context.MouseX < Block.Runtime.RenderPosition.x1 ) then
      break;

    if( Context.MouseX <= Block.Runtime.RenderPosition.X2 ) then
    begin
      BlockX := i;
      break;
    end

  end;

  if( BlockX = -1 ) then
    Exit;

  // ok, X & Y are valid, calculate index.
  Context.Runtime.IndexBlockUnderMouse := BlockX + BlockY * ColCount;
  Assert( BlockX + BlockY * ColCount < BlockCount );

end;

end.

