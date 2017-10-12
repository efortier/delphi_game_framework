unit rng_multiplywithcarry;

interface

type

  // Multiply With Carry, AKA: The Mother of all RNGs.
  TRngMWC = record
  const

    MW = 521288629;
    MZ = 362436069;

    // DO NOT SET AS A SINGLE OR DOUBLE, or whatever else!
    OneOverMax = 1 / 4294967295;
    OneOver32Bits = 1 / 4294967296;

  private
    M_W: UInt32;
    M_Z: UInt32;
  public

    procedure Randomize; overload; inline;
    procedure Randomize( const seed: UInt32 ); overload; inline;
    procedure Randomize( const seed: UInt64 ); overload; inline;
    procedure Randomize( const z, w: UInt32 ); overload;

    // generate a number from 0..$FFFFFFFF
    function Generate: UInt32; overload;

    // generate a float in the range [0..1), ie: EXCLUDING 1.
    function GenerateUniform: Single; inline;

    // generate a number between Min and Max, INCLUDING min and max.
    function Generate(const Min, Max: UInt32): UInt32; overload; inline;

  end;

implementation

uses
  Winapi.Windows;

procedure TRngMWC.Randomize;
var
  Counter: Int64;
begin
  if QueryPerformanceCounter( Counter ) then
    Randomize( UInt64( Counter ) )
  else
    Randomize( UInt32( GetTickCount ) );
end;

procedure TRngMWC.Randomize( const seed: UInt32 );
begin
  Assert( seed <> 0, 'Seed must be NON-ZERO.' );
  Randomize( UInt32( Seed shr 16 ), UInt32( Seed and $FFFFFFFF ) );
end;

procedure TRngMWC.Randomize( const seed: UInt64 );
begin
  Assert( seed <> 0, 'Seed must be NON-ZERO.' );
  Randomize( UInt32( Seed shr 32 ), UInt32( Seed and $FFFFFFFF ) );
end;

procedure TRngMWC.Randomize( const z, w: UInt32 );
begin

  if( z <> 0 ) then
    M_Z := z
  else
    M_Z := MZ;

  if( w <> 0 ) then
    M_W := w
  else
    M_W := MW;

end;

function TRngMWC.Generate: UInt32;
begin
  m_z := 36969 * ( m_z and $FFFF ) + ( m_z shr 16 );
  m_w := 18000 * ( M_W and $FFFF ) + ( m_w shr 16 );
  Result := ( m_z shl 16 ) + m_w;
end;

function TRngMWC.GenerateUniform: Single;
begin
  Result := Generate * OneOver32BITS;
end;

function TRngMWC.Generate(const Min, Max: UInt32): UInt32;
begin
  Assert( Max - Min <> $FFFFFFFF, 'Using Generate(Min,Max) with 0,$FFFFFFFF for generating a range will produce a rollover (Max - Min + 1). Review your code or use Generate() with no range.' );
  Result := Min + Trunc( Generate * OneOver32Bits * ( Max - Min + 1 ) );
  Assert( ( Result >= Min ) and ( Result <= Max ) );
end;

{$ifdef DEBUG}
procedure DoTests;
var
  R: TRngMWC;
  Value: Single;
  Num: UInt32;
  i: UInt32;
begin

  // test randomize with default values and known results.
  R.Randomize( R.MZ, R.MW );
  Assert( R.M_W = R.MW );
  Assert( R.M_Z = R.MZ );
  Num := R.Generate;
  Assert( Num = 820856226 );
  Num := R.Generate;
  Assert( Num = 2331188998 );
  Num := R.Generate;
  Assert( Num = 4033440000 );
  Num := R.Generate;
  Assert( Num = 3169966213 );

  // test randomize with time value.
  R.M_W := 0;
  R.M_Z := 0;
  R.Randomize;
  Assert( R.M_W <> 0 );
  Assert( R.M_Z <> 0 );

  // test randomized numbers with pre-defined seed.
  R.Randomize( $B00B, $F00D );

  Value := R.GenerateUniform;
  Assert( Value = Single(0.6501704454422) );

  Value := R.GenerateUniform;
  Assert( Trunc( Value * 100000000 ) = 45763057 );

  Value := R.GenerateUniform;
  Assert( Trunc( Value * 100000000 ) = 95653378 );

  Value := R.GenerateUniform;
  Assert( Trunc( Value * 100000000 ) = 97507566 );

  Value := R.GenerateUniform;
  Assert( Trunc( Value * 100000000 ) = 98670405 );

  // test single number random generation.
  for i := 0 to 99 do
  begin
    Num := R.Generate( i, i );
    Assert( Num = i );
  end;

  R.Randomize( $B00B, $F00D );
  Assert( R.Generate( 1, 10 ) = 7 );

  R.Randomize( $B00B, $F00D );
  Assert( R.Generate = 2792460816 );
  Assert( R.Generate = 1965508334 );

  R.Randomize( $B00B, $F00D );
  Assert( R.Generate( 1, 2 ) = 2 );

  // a rare seed generating $FFFFFFFF
  R.Randomize( $C8AFE9D1 );
  Assert( R.Generate = $FFFFFFFF );

  R.Randomize( $C8AFE9D1 );
  Assert( R.Generate( 1, 2 ) = 2 );

  R.Randomize( $B00B, $F00D );
  Num := 0;
  for I := 1 to 100 do
  begin
    if( R.Generate( 1, 2 ) = 2 ) then
      Inc( Num );
  end;
  Assert( Num = 60 ); // 4959 on 10.000 iterations

end;
{$endif}

initialization
  {$ifdef DEBUG}
  DoTests;
  {$endif}
end.

