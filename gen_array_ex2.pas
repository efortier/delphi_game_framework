unit gen_array_ex2;

interface

uses
  Windows;

const
  GROWTH_POWER_OF_TWO = -1;

type

  TGenArrayEx2<T> = record
  type
    PTypePointer = ^T;
    PItemsArray = ^TItemsArray;
    TItemsArray = array of T;
    TCompareEvent = reference to procedure( const Item1, Item2: T; out CompareResult: Integer );
    TSortCompareFunc = reference to function( const Item1, Item2: T ): Integer;
    TFindFunction = reference to function( const Item: Pointer ): Boolean;
    TEnumFunction = reference to procedure( Item: Pointer );
  private
    FCapacity: Integer;
    FGrowthSize: Integer;
    FCount: Integer;
    FItems: TItemsArray;
    FEnumIndex: Integer;
    FINIT: UINT32;
    procedure SetItem( Index: Integer; const Value: T ); inline;
    procedure DoGrow;
    procedure QuickSort( L, R: Integer; SCompare: TSortCompareFunc );
    function GetHigh: Integer; inline;
    function GetItem( Index: Integer ): T; inline;
    function GetItemAsPointer( Index: Integer ): Pointer; inline;
    function GetItemPtr( Index: Integer ): PTypePointer; inline;
    function Bottom: T;
    function GetIsInit: Boolean; inline;
    procedure SetCount(const Value: Integer);
  public

    procedure Initialize; overload; inline;
    procedure Initialize( const GrowthSize: Integer ); overload;

    procedure Grow; inline;
    procedure Clear; overload;
    function New: Pointer; overload;

    // new and add item.
    function Add: Integer; overload;

    // add existing item.
    function Add( const Item: T ): Integer; overload;

    // insert new item.
    procedure Insert( const Index: Integer ); overload;

    // insert existing item.
    procedure Insert( const Index: Integer; Item: T ); overload;

    function Delete( FindFunc: TFindFunction ): Integer; overload;
    procedure Delete( const Index: Integer ); overload;
    procedure DeleteByPtr( Item: Pointer );

    // stack emulation functions.
    procedure Push( Item: T ); inline; // add to bottom.
    function Pop: T; overload; inline; // pop from bottom.
    procedure Pop( out Value: T ); overload; inline;
    procedure PopTop( out Value: T ); overload; inline; // pop from the top.
    function PopTop: T; overload; inline;

    // TODO: Pack
    function Top: T; inline;
    function First: PTypePointer;
    function Next: PTypePointer;
    procedure Sort( CompareFunc: TSortCompareFunc );
    function Find( FindFunc: TFindFunction ): PTypePointer;
    function IndexOf( FindFunc: TFindFunction ): Integer;
    procedure Enumerate( EnumFunc: TEnumFunction );
    procedure Swap( const From, &To: Integer );
    procedure Assign( var List: TGenArrayEx2<T> );
    procedure DeleteLast; inline;
    function Extract( const Index: Integer ): T;
    procedure SetCapacity( const NewSize: Integer );
    procedure Reverse( const Offset: Integer = 0 );
    function NewItem: PTypePointer;

    // be careful with these...
    procedure CopyTo( var List: TGenArrayEx2<T>; const NewListCount: Integer = -1 ); inline;
    procedure ForceSetCount( const NewCount: Integer ); inline;


  public
    property Count: Integer read FCount write SetCount;
    property GrowthSize: Integer read FGrowthSize write FGrowthSize;
    property High: Integer read GetHigh;
    property Items[Index: Integer]: T read GetItem write SetItem; default;
    property ItemAsPointer[Index: Integer]: Pointer read GetItemAsPointer;
    property ItemsPtr[Index: Integer]: PTypePointer read GetItemPtr;
    property ItemsArray: TItemsArray read FItems write FItems;
    property IsInit: Boolean read GetIsInit;
  end;

implementation

uses
  System.SysUtils;

{ TGenArrayEx2< T > }

procedure TGenArrayEx2<T>.DoGrow;
begin

  Assert( FGrowthSize <> 0 );

  // are we growing using power of two or using FGrowthSize?
  if( FGrowthSize = GROWTH_POWER_OF_TWO ) then
  begin
    if( FCapacity = 0 ) then
      FCapacity := 32;
    Inc( FCapacity, FCapacity );
  end
  else
    Inc( FCapacity, FGrowthSize );

  System.SetLength( FItems, FCapacity );

end;

procedure TGenArrayEx2<T>.Grow;
begin
  if( FCount >= FCapacity ) then
    DoGrow;
end;

procedure TGenArrayEx2<T>.SetCapacity( const NewSize: Integer );
begin
  Finalize( FItems ); // := nil;
  FCount := 0;
  FCapacity := NewSize;
  System.SetLength( FItems, FCapacity );
end;

procedure TGenArrayEx2<T>.SetCount(const Value: Integer);
begin
  SetCapacity( Value );
  FCount := Value;
end;

function TGenArrayEx2<T>.GetHigh: Integer;
begin
  Result := FCount - 1;
end;

function TGenArrayEx2<T>.GetItem( Index: Integer ): T;
begin
  Assert( ( Index >= 0 ) and ( Index < Count ), 'Check index is within bounds.' );
  Result := FItems[Index];
end;

function TGenArrayEx2<T>.GetItemAsPointer( Index: Integer ): Pointer;
begin
  Assert( ( Index >= 0 ) and ( Index < Count ), Format( 'Check index is within bounds (Index: %d, High: %d).', [Index, Count-1] ) );
  Result := @FItems[Index];
end;

function TGenArrayEx2<T>.GetItemPtr( Index: Integer ): PTypePointer;
begin
  Assert( ( Index >= 0 ) and ( Index < Count ), 'Check index is within bounds.' );
  Result := @FItems[Index];
end;

procedure TGenArrayEx2<T>.SetItem( Index: Integer; const Value: T );
begin
  Assert( ( Index >= 0 ) and ( Index < Count ), 'Check index is within bounds.' );
  FItems[Index] := Value;
end;

procedure TGenArrayEx2<T>.QuickSort( L, R: Integer; SCompare: TSortCompareFunc );
var
  I, J: Integer;
  P, Temp: T;
begin

  repeat

    I := L;
    J := R;
    P := FItems[( L + R ) shr 1];
    repeat

      while SCompare( FItems[I], P ) < 0 do
        Inc( I );

      while SCompare( FItems[J], P ) > 0 do
        Dec( J );

      if I <= J then
      begin

        if I <> J then
        begin
          Temp := FItems[I];
          FItems[I] := FItems[J];
          FItems[J] := Temp;
        end;

        Inc( I );
        Dec( J );
      end;

    until I > J;

    if L < J then
      QuickSort( L, J, SCompare );
    L := I;

  until I >= R;

end;

procedure TGenArrayEx2<T>.Clear;
var
  I: Integer;
begin
  FItems := nil;
  FCapacity := 0;
  FCount := 0;
end;

procedure TGenArrayEx2<T>.CopyTo(var List: TGenArrayEx2<T>; const NewListCount: Integer);
begin
  // this function assumes the following:
  //    - both lists hold the same-sized element (T)
  //    - both lists are the same length.
  Assert( SizeOf(T) = SizeOf( List.FItems[0] ) );
  Assert( FCapacity = List.FCapacity );
  Assert( NewListCount <= List.FCapacity );
  if( NewListCount > 0 ) then
    CopyMemory( @List.FItems[0], @FItems[0], sizeof(T) * NewListCount );
  List.FCount := NewListCount;
end;

procedure TGenArrayEx2<T>.Push( Item: T );
begin
  Add( Item );
end;

function TGenArrayEx2<T>.Pop: T;
begin
  Result := Bottom;
  DeleteLast;
end;

procedure TGenArrayEx2<T>.Pop( out Value: T );
begin
  Value := Bottom;
  DeleteLast;
end;

function TGenArrayEx2<T>.Bottom: T;
begin
  Result := FItems[FCount - 1];
end;

procedure TGenArrayEx2<T>.PopTop( out Value: T );
begin
  Value := Top;
  Delete( 0 );
end;

function TGenArrayEx2<T>.PopTop: T;
begin
  Result := Top;
  Delete( 0 );
end;

function TGenArrayEx2<T>.New: Pointer;
begin
  Grow;
  Result := @FItems[FCount];
  Inc( FCount );
end;

function TGenArrayEx2<T>.NewItem: PTypePointer;
begin
  New;
  Result := @FItems[FCount-1];
end;

function TGenArrayEx2<T>.Add: Integer;
begin
  Grow;
  Result := FCount;
  Inc( FCount );
end;

function TGenArrayEx2<T>.Add( const Item: T ): Integer;
begin
  Grow;
  FItems[FCount] := Item;
  Result := FCount;
  Inc( FCount );
end;

procedure TGenArrayEx2<T>.Insert( const Index: Integer );
var
  I: Integer;
begin
  Add;
  if( Index < FCount ) then
    for I := FCount - 1 downto Index + 1 do
      FItems[I] := FItems[I - 1];
end;

procedure TGenArrayEx2<T>.Insert( const Index: Integer; Item: T );
var
  I: Integer;
begin
  Grow;
  Add;
  if( Index < FCount ) then
    for I := FCount - 1 downto Index + 1 do
      FItems[I] := FItems[I - 1];
  FItems[Index] := Item;
end;

procedure TGenArrayEx2<T>.Delete( const Index: Integer );
var
  I: Integer;
begin
  Assert( ( Index >= 0 ) and ( Index < Count ), 'Check index is within bounds.' );

  for I := Index to FCount - 2 do
    FItems[I] := FItems[I + 1];

  Dec( FCount );

end;

procedure TGenArrayEx2<T>.DeleteLast;
begin
  Assert( FCount > 0 );
  Dec( FCount );
end;

procedure TGenArrayEx2<T>.DeleteByPtr( Item: Pointer );
var
  I: Integer;
begin

  for I := 0 to FCount - 1 do
  begin

    if( @FItems[I] = Item ) then
    begin
      Delete( I );
      break;
    end;

  end;

end;

function TGenArrayEx2<T>.Delete( FindFunc: TFindFunction ): Integer;
var
  I: Integer;
begin

  Assert( Assigned( FindFunc ) = True, 'Check FindFunc is assigned in TGenArrayEx<T>.Delete.' );

  Result := -1;
  if( Assigned( FindFunc ) = True ) then
  begin

    for I := 0 to FCount - 1 do
    begin

      if( FindFunc( @FItems[I] ) = True ) then
      begin

        // we return the index of the deleted item.
        Result := I;
        Delete( I );

        break;

      end;

    end;

  end;

end;

procedure TGenArrayEx2<T>.Sort( CompareFunc: TSortCompareFunc );
begin
  if( FCount > 1 ) then
    QuickSort( 0, FCount - 1, CompareFunc );
end;

procedure TGenArrayEx2<T>.Swap( const From, &To: Integer );
var
  Item: T;
begin

  Assert( ( From >= 0 ) and ( From < Count ) );
  Assert( ( &To >= 0 ) and ( &To < Count ) );
  Assert( From <> &To );

  Item := FItems[From];
  FItems[From] := FItems[&To];
  FItems[&To] := Item;

end;

function TGenArrayEx2<T>.Find( FindFunc: TFindFunction ): PTypePointer;
begin

  if( Assigned( FindFunc ) = True ) then
  begin

    Result := First;
    while ( Result <> nil ) do
    begin
      if( FindFunc( Result ) = True ) then
        break;
      Result := Next;
    end;

  end
  else
    Result := nil;

end;

function TGenArrayEx2<T>.IndexOf( FindFunc: TFindFunction ): Integer;
var
  I: Integer;
begin

  Result := -1;
  if( Assigned( FindFunc ) = True ) then
  begin

    for I := 0 to High do
    begin

      if( FindFunc( @FItems[I] ) = True ) then
      begin
        Result := I;
        break;
      end;

    end;

  end;

end;

procedure TGenArrayEx2<T>.Initialize;
begin
  Initialize( GROWTH_POWER_OF_TWO );
end;

procedure TGenArrayEx2<T>.Initialize( const GrowthSize: Integer );
begin
  FINIT := $B00BF00D;
  FGrowthSize := GrowthSize;
  Clear;
end;

function TGenArrayEx2<T>.Top: T;
begin
  Assert( Count > 0 );
  Result := FItems[0];
end;

function TGenArrayEx2<T>.First: PTypePointer;
begin
  FEnumIndex := 0;
  Result := Next;
end;

procedure TGenArrayEx2<T>.ForceSetCount(const NewCount: Integer);
begin
  FCount := NewCount;
end;

function TGenArrayEx2<T>.Next: PTypePointer;
begin
  if( FEnumIndex < FCount ) then
    Result := @FItems[FEnumIndex]
  else
    Result := nil;
  Inc( FEnumIndex );
end;

procedure TGenArrayEx2<T>.Enumerate( EnumFunc: TEnumFunction );
var
  Item: PTypePointer;
  I: Integer;
begin
  for I := 0 to FCount - 1 do
    EnumFunc( @FItems[I] );
end;

function TGenArrayEx2<T>.Extract( const Index: Integer ): T;
begin
  Result := Items[Index];
  Delete( Index );
end;

procedure TGenArrayEx2<T>.Assign( var List: TGenArrayEx2<T> );
var
  I: Integer;
begin

  // make sure we grow the same as the list we're assigning from.
  Initialize( List.FGrowthSize );

  FCapacity := List.FCapacity;
  FCount := List.FCount;
  FEnumIndex := List.FEnumIndex;
  System.SetLength( FItems, FCapacity );

  for I := 0 to List.High do
    FItems[I] := List.FItems[I];

end;

procedure TGenArrayEx2<T>.Reverse( const Offset: Integer = 0 );
var
  I: Integer;
  IndexBottom: Integer;
  IndexTop: Integer;
begin

  if( Count >= ( 2 + Offset ) ) then
  begin

    IndexTop := Offset;
    IndexBottom := High;
    while ( IndexTop < IndexBottom ) do
    begin
      Swap( Indextop, IndexBottom );
      Inc( IndexTop );
      Dec( IndexBottom );
    end;

  end;

end;

function TGenArrayEx2<T>.GetIsInit: Boolean;
begin
  Result := FINIT = $B00BF00D;
end;

end.

