unit hashtable;

interface

uses
  hash_funcs, bucket_list;

type

  // Using the hash table:
  //
  //    - instanciate with a user record and initialize, ie:
  //      CustomHashTable: THashTable< TCustomRecord >;
  //      CustomHashTable.InitializeTable( 32 );  // Power of two.
  //
  //    - set a hasher class:
  //      CustomHashTable.Hasher := MyHasher;
  //
  //    - add data to the table:
  //      Entry := CustomHashTable.Add( String );
  //      Entry.HashData is a pointer to a TCustomRecord.
  //
  //    - find an entry in the table:
  //      Entry := CustomHashTable.Find( String );
  //      Entry is either nil or a pointer to a TCustomRecord.

  THashTable<TKeyType, T> = class
  type

    // the type of hash value stored.
    // ie: Integer for crc32, Int64 for CRC64, etc.
    PHashType = ^THashType;
    THashType = UInt32;

    PHashEntry = ^THashEntry;
    THashEntry = record

      Used: Boolean;

      // the string to hash.
      HashKey: TKeyType;

      // the value of the hashed value for the key.
      HashValue: THashType;

      // user-defined data.
      Data: T;

      // linked-list next pointer.
      Next: PHashEntry;

      procedure Clear;

    end;

    // the hash table holds an array of pointers to actual entries in a list.
    TItemsArray = array of PHashEntry;

    // the array holding the actual hash entries.
    THashEntryBucketList = TBucketList<THashEntry>;

    TEnumInfo = record
      Entry: PHashEntry;
      Index: Integer;
      Count: Integer;
    end;

  private

    FCapacity: UInt32;
    FCount: UInt32;
    FItems: TItemsArray;
    FInitialTableSize: Integer;
    FEnumEntry: TEnumInfo;

  private

    FHashEntryBucketList: THashEntryBucketList;

  strict private

    // used to calculate the actual hash value.
    FHasher: TBaseHasher;

  private

    procedure SetItem( Index: UInt32; const Value: THashEntry ); inline;
    procedure SetCapacity( const NewSize: UInt32 );
    function GetHigh: UInt32; inline;
    function GetCount: UInt32; inline;
    function GetItem( Index: UInt32 ): THashEntry; inline;
    function GetItemPtr( Index: UInt32 ): Pointer; inline;
    function HashToIndex( const Value: THashType ): UInt32;
    function GetAssignedCount: UInt32;
  protected

    // NOTE: to get the pointer of a [ansi]string key, do this: @key[1], not this: @key.
    function GetKeyPointer( var Key: TKeyType ): Pointer; virtual; abstract;
    function GetKeyLength( const Key: TKeyType ): Integer; virtual; abstract;
    function CompareKey( const Key1, Key2: TKeyType ): Boolean; virtual; abstract;

  public

    constructor Create( Hasher: TBaseHasher; const InitialTableSize: Integer );
    destructor Destroy; override;

    function AcquireNewEntry: PHashEntry; inline;
    function DoHashOnKey( const Key: TKeyType ): THashType;

    procedure BeginEnum;
    function Enumerate( out Data: Pointer ): Boolean; virtual;
    function EnumerateHash( out Hash: PHashEntry ): Boolean;

  public

    procedure Clear; overload;
    procedure InitializeTable( const Count: Integer );
    function Add( const Key: TKeyType ): PHashEntry; overload; virtual;
    function Add( const Key: TKeyType; const Value: T ): PHashEntry; overload; inline;
    function Find( const Key: TKeyType ): PHashEntry;
    function FindAsDataPtr( const Key: TKeyType ): Pointer;
    function HashEntryToUserDataPtr( const HashEntry: PHashEntry ): Pointer; inline;
    procedure Delete( const Key: TKeyType ); overload; inline;
    procedure Delete(HashEntry: PHashEntry); overload; inline;
    function GetIndexForKey( const Key: TKeyType; var Value: THashType ): UInt32; overload;
    function GetIndexForKey( const Key: TKeyType ): UInt32; overload;
    function GetItemCount: Integer;
    procedure InitializeStorage;

    // assign could potentially cause problems if the type T is a pointer.
    procedure Assign( Table: THashTable<TKeyType, T> );

  public

    property BucketList: THashEntryBucketList read FHashEntryBucketList;
    property Capacity: UInt32 read FCapacity write SetCapacity;
    property Count: UInt32 read GetCount;
    property AssignedCount: UInt32 read GetAssignedCount;
    property High: UInt32 read GetHigh;
    property Items[Index: UInt32]: THashEntry read GetItem write SetItem; default;
    property ItemsPtr[Index: UInt32]: Pointer read GetItemPtr;
    property Hasher: TBaseHasher read FHasher;

  end;

implementation

uses
  Winapi.Windows, System.SysUtils;

procedure THashTable<TKeyType, T>.SetCapacity( const NewSize: UInt32 );
begin
  FCapacity := NewSize;
  System.SetLength( FItems, FCapacity );
  FCount := FCapacity;
end;

function THashTable<TKeyType, T>.GetCount: UInt32;
begin
  Result := FCount;
end;

function THashTable<TKeyType, T>.GetHigh: UInt32;
begin
  Result := GetCount - 1;
end;

function THashTable<TKeyType, T>.GetItem( Index: UInt32 ): THashEntry;
begin
  Result := FItems[Index]^;
end;

function THashTable<TKeyType, T>.GetItemPtr( Index: UInt32 ): Pointer;
begin
  Result := FItems[Index];
end;

function THashTable<TKeyType, T>.AcquireNewEntry: PHashEntry;
begin
  Result := FHashEntryBucketList.New;
end;

procedure THashTable<TKeyType, T>.SetItem( Index: UInt32; const Value: THashEntry );
begin
  FItems[Index]^ := Value;
end;

procedure THashTable<TKeyType, T>.Clear;
begin
  Finalize( FItems );
  FCapacity := 0;
  FCount := 0;
  InitializeStorage;
end;

constructor THashTable<TKeyType, T>.Create( Hasher: TBaseHasher; const InitialTableSize: Integer );
begin
  inherited Create;
  FHasher := Hasher;
  FInitialTableSize := InitialTableSize;
  InitializeStorage;
end;

destructor THashTable<TKeyType, T>.Destroy;
begin
  FHasher.Free;
  FHashEntryBucketList.Free;
  inherited;
end;

function THashTable<TKeyType, T>.Add( const Key: TKeyType; const Value: T ): PHashEntry;
begin
  Result := Add( Key );
  Assert( Result <> nil );
  Result.Data := Value;
end;

function THashTable<TKeyType, T>.Add( const Key: TKeyType ): PHashEntry;
var
  Index: Integer;
  Item: PHashEntry;
  PreviousItem: PHashEntry;
  HashValue: THashType;
begin

  Assert( FCount > 0, 'Check array was initialized properly.' );

  Index := GetIndexForKey( Key, HashValue );
  Item := FItems[Index];

  if( Item = nil ) then
  begin
    Item := AcquireNewEntry;
    Item.Clear;
    FItems[Index] := Item;
  end else
  begin

    if( Item.Used = True ) then
    begin

      // search for the end of the chain in this hash slot.
      repeat
        PreviousItem := Item;
        Item := Item.Next;
      until ( Item = nil ) or ( Item.Used = False );

      // if we have no unused item, get a new one.
      if( Item = nil ) then
        Item := PreviousItem;

      Assert( Item <> nil );
      Assert( Item.Next = nil );

    end;

    // we reached the last entry.
    Item.Next := AcquireNewEntry;
    Item.Next.Clear;
    Item := Item.Next;

  end;

  Assert( Item <> nil );

  // set item data.
  Item.Used := True;
  Item.HashValue := HashValue;
  Item.HashKey := Key;

  // done.
  Result := Item;

end;

procedure THashTable<TKeyType, T>.Delete( const Key: TKeyType );
var
  HashEntry: PHashEntry;
begin
  HashEntry := Find( Key );
  if( HashEntry <> nil ) then
    Delete( HashEntry );
end;

function THashTable<TKeyType, T>.DoHashOnKey( const Key: TKeyType ): THashType;
var
  KeyVar: TKeyType;
begin
  KeyVar := Key;
  Result := THashType( FHasher.GetHash( GetKeyPointer( KeyVar ), GetKeyLength( KeyVar ) ) );
end;

function THashTable<TKeyType, T>.Find( const Key: TKeyType ): PHashEntry;
var
  Entry: PHashEntry;
  Index: Integer;
  Value: THashType;
begin

  Result := nil;

  Index := GetIndexForKey( Key, Value );
  Entry := FItems[Index];

  while ( Entry <> nil ) do
  begin

    // check if we found the hash for the key.
    if( Entry.Used = True ) and ( Entry.HashValue = Value ) then
    begin
      // if we have, compare keys.
      if( CompareKey( Key, Entry.HashKey ) = True ) then
      begin
        Result := Entry;
        break;
      end;
    end;

    Entry := Entry.Next;

  end;

end;

function THashTable<TKeyType, T>.FindAsDataPtr( const Key: TKeyType): Pointer;
var
  HashEntry: PHashEntry;
begin

  HashEntry := Find( Key );
  if( HashEntry = nil ) then
    exit( nil );

  Result := @HashEntry.Data;

end;

function THashTable<TKeyType, T>.GetIndexForKey( const Key: TKeyType; var Value: THashType ): UInt32;
begin
  Value := DoHashOnKey( Key );
  Result := HashToIndex( Value );
end;

function THashTable<TKeyType, T>.HashEntryToUserDataPtr( const HashEntry: PHashEntry): Pointer;
begin
  Assert( HashEntry <> nil );
  Result := @HashEntry.Data;
end;

function THashTable<TKeyType, T>.HashToIndex( const Value: THashType ): UInt32;
begin
  Result := Value and ( FCount - 1 );
end;

function THashTable<TKeyType, T>.GetIndexForKey( const Key: TKeyType ): UInt32;
var
  Value: THashType;
begin
  Value := DoHashOnKey( Key );
  Result := Value and ( FCount - 1 );
end;

procedure THashTable<TKeyType, T>.InitializeTable( const Count: Integer );
begin
  Assert( Count and ( Count - 1 ) = 0, 'Assert Count is power of two' );
  SetCapacity( Count );
  ZeroMemory( FItems, SizeOf( FItems[0] ) * Count );
end;

procedure THashTable<TKeyType, T>.THashEntry.Clear;
begin
  Used := False;
  HashValue := 0;
  Next := nil;
end;

function THashTable<TKeyType, T>.GetItemCount: Integer;
var
  Index: UInt32;
  t: Integer;
  Item: PHashEntry;
begin

  Result := 0;

  for t := 0 to Length( FItems ) - 1 do
  begin

    Item := FItems[t];
    if( Item <> nil ) and ( Item.Used = True ) then
    begin
      repeat
        Inc( Result );
        Item := Item.Next;
      until ( Item = nil ) or ( Item.Used = False );
    end;

  end;

end;

procedure THashTable<TKeyType, T>.InitializeStorage;
begin
  if( FHashEntryBucketList <> nil ) then
    FHashEntryBucketList.Free;
  FHashEntryBucketList := THashEntryBucketList.Create( FInitialTableSize );
  InitializeTable( FInitialTableSize );
end;

procedure THashTable<TKeyType, T>.BeginEnum;
begin
  FEnumEntry.Entry := nil;
  FEnumEntry.Index := -1;
  FEnumEntry.Count := Count;
end;

function THashTable<TKeyType, T>.Enumerate( out Data: Pointer ): Boolean;
var
  Hash: PHashEntry;
begin

  Result := EnumerateHash( Hash );
  if( Result = True ) then
    Data := @Hash.Data;

end;

function THashTable<TKeyType, T>.EnumerateHash( out Hash: PHashEntry ): Boolean;
begin

  while ( FEnumEntry.Index < FEnumEntry.Count ) do
  begin

    if( FEnumEntry.Entry = nil ) then
    begin
      Inc( FEnumEntry.Index );
      if( FEnumEntry.Index < FEnumEntry.Count ) then
        FEnumEntry.Entry := GetItemPtr( FEnumEntry.Index )
    end;

    if( FEnumEntry.Entry <> nil ) then
    begin

      if( FEnumEntry.Entry.Used = True ) then
      begin
        Hash := FEnumEntry.Entry;
        FEnumEntry.Entry := FEnumEntry.Entry.Next;
        exit( true );
      end else
      begin
        FEnumEntry.Entry := FEnumEntry.Entry.Next;
      end;

    end;

  end;

  Result := False;

end;

function THashTable<TKeyType, T>.GetAssignedCount: UInt32;
var
  OutPtr: Pointer;
begin

  Result := 0;
  BeginEnum;
  while ( Enumerate( OutPtr ) = True ) do
  begin
    inc( Result );
  end;

end;

procedure THashTable<TKeyType, T>.Assign( Table: THashTable<TKeyType, T> );
var
  Hash: PHashEntry;
  NewHash: PHashEntry;
begin

  Clear;

  Table.BeginEnum;
  while ( Table.EnumerateHash( Hash ) = True ) do
  begin

    NewHash := Add( Hash.HashKey );
    Assert( NewHash <> nil );
    if( NewHash <> nil ) then
    begin
      NewHash.Data := Hash.Data;
    end;

  end;

end;

procedure THashTable<TKeyType, T>.Delete(HashEntry: PHashEntry);
begin
  HashEntry.HashValue := 0;
  HashEntry.Used := False;
end;

end.

