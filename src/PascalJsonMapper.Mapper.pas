unit PascalJsonMapper.Mapper;

{$I pjm.inc}

{ Maps JSON to objects and back through RTTI, identically on Delphi and FPC.

  The contract (what RTTI sees on both compilers, see the dual-compiler
  skill's rtti-gotchas.md):
  - Only PUBLISHED properties are mapped. Declare DTO classes under $M+
    (or descend from a class that is), and put every mapped property in a
    published section. Public properties are invisible to FPC 3.2.2's RTTI,
    so they are ignored on Delphi too, to keep both sides equal.
  - Interfaces are created through RegisterMapping<IFoo, TFoo>: the JSON
    object becomes a TFoo (its own constructor runs) and is returned as IFoo.
  - Class-typed properties are never created by the mapper (it would not
    know who frees them): reading populates the instance the property
    already holds; writing serializes it.
  - Anything else (optionals, value objects, custom formats) goes through a
    registered IJsonConverter, consulted before the built-in rules.

  JSON names: written in camelCase by default (Naming: also as declared or
  snake_case; RenameMember for single members, e.g. a property Kind for the
  member "type", a Pascal keyword); read case-insensitively. Unknown JSON
  members are ignored by default (UnknownMembers := umError rejects them);
  absent members leave the property untouched. Two properties that would
  share a JSON name are an error, raised the first time the class is used.

  Thread safety: register mappings, converters and renames, and set the
  options, at startup; afterwards a mapper can be used from any number of
  threads. Class metadata is cached
  globally under a lock (FPC 3.2.2's TRttiInstanceType.GetProperties fills
  its own cache without one). }

interface

uses
  SysUtils, TypInfo, Rtti, Generics.Collections,
  PascalJsonMapper.Json;

type
  EJsonMapperError = class(Exception);

  TJsonMapper = class;

  { One JSON member of a class, as the mapper reads and writes it (see
    TJsonMapper.Members). }
  TJsonMember = record
    PropertyName: string;   // the published property, as declared
    JsonName: string;       // its member name in JSON: Naming and RenameMember applied
    TypeInfo: PTypeInfo;    // the property's type
    Readable: Boolean;      // written by ToJson/WriteObject
    Writable: Boolean;      // filled by FromJson/ReadObject
  end;
  TJsonMemberArray = array of TJsonMember;

  { Extension point for types the built-in rules don't cover. The owner of a
    type ships its converter (e.g. a bridge unit in the library that defines
    the type), so neither library depends on the other's core. }
  IJsonConverter = interface
    ['{7C1F4B0E-3D52-4E8B-9A61-2F0C5D8E4B13}']
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    // AJson is never nil: absent members never reach a converter (the
    // property is left untouched). It can be a JSON null. Return False to
    // leave the destination untouched; True to assign AValue, which must be
    // of type ATypeInfo.
    // APath is where the value sits ('$.items[2].price'): pass it on when
    // recursing through AMapper.ReadValue/WriteValue. Raise EJsonError (or
    // let TJsonValue's accessors raise it) for bad input: the mapper turns it
    // into an EJsonMapperError carrying APath.
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
    // Write exactly one value, or nothing and return False to omit it: a
    // property is then left out of the object; an array element becomes
    // null.
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
  end;

  { Creates an instance through the class's own constructor. RegisterMapping
    specializes it per class: FPC 3.2.2 has no closures, and TClass.Create
    would run TObject.Create, skipping the DTO's constructor. }
  TJsonInstanceFactory = class
  public
    class function CreateInstance: TObject; virtual; abstract;
  end;
  TJsonInstanceFactoryClass = class of TJsonInstanceFactory;

  TJsonInstanceFactoryOf<C: class, constructor> = class(TJsonInstanceFactory)
  public
    class function CreateInstance: TObject; override;
  end;

  // How a property name becomes a JSON member name (unless renamed):
  //   jnCamelCase   CreatedAt -> createdAt (default)
  //   jnAsDeclared  CreatedAt -> CreatedAt
  //   jnSnakeCase   CreatedAt -> created_at, UserID -> user_id,
  //                 HTTPStatus -> http_status (see JsonSnakeCase)
  TJsonNaming = (jnCamelCase, jnAsDeclared, jnSnakeCase);

  // What reading does with a JSON member no published property matches.
  TJsonUnknownMembers = (umIgnore, umError);

  // The JSON names of one class's properties under one mapper's settings,
  // parallel to the class's property metadata.
  TJsonClassNames = class
  public
    Names: array of string;
    Renamed: array of Boolean;
  end;

  TJsonMapping = record
    ImplClass: TClass;
    Factory: TJsonInstanceFactoryClass;
  end;

  TJsonMapper = class
  private
    FMappings: TDictionary<TGUID, TJsonMapping>;
    FConverters: array of IJsonConverter;
    FNaming: TJsonNaming;
    FIndent: Integer;
    FUnknownMembers: TJsonUnknownMembers;
    FRenames: TDictionary<string, string>;
    FNames: TDictionary<TClass, TJsonClassNames>;
    FNamesLock: TObject;
    function FindConverter(ATypeInfo: PTypeInfo): IJsonConverter;
    function ApplyNaming(const APropName: string): string;
    function ClassNames(AClass: TClass): TJsonClassNames;
    function BuildClassNames(AClass: TClass): TJsonClassNames;
    procedure ClearClassNames;
    procedure SetNaming(AValue: TJsonNaming);
    function CreateFromJson(ATypeInfo: PTypeInfo; AJson: TJsonValue;
      const APath: string): IInterface;
    function DoReadValue(AJson: TJsonValue; ATypeInfo: PTypeInfo;
      const APath: string; out AValue: TValue): Boolean;
    function DoWriteValue(AWriter: TJsonWriter; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string): Boolean;
    procedure DoRegisterMapping(AInterface: PTypeInfo; AClass: TClass;
      AFactory: TJsonInstanceFactoryClass);
  public
    constructor Create;
    destructor Destroy; override;

    // Process-wide instance, for code that registers DTOs at unit
    // initialization. Tests and isolated setups can create their own.
    class function Shared: TJsonMapper;

    procedure RegisterMapping<I: IInterface; C: class, constructor>;
    // Last registered wins when several converters accept a type.
    procedure RegisterConverter(const AConverter: IJsonConverter);
    // The JSON member name for one published property of AClass (and of its
    // descendants, unless one of them renames it again), used as is: Naming
    // doesn't apply, and only that name (case-insensitively) matches when
    // reading. For members whose name can't be a Pascal identifier (a
    // keyword such as "type"), or that no Naming produces.
    procedure RenameMember(AClass: TClass; const APropertyName, AJsonName: string);
    function FindImplClass(AInterface: PTypeInfo): TClass;
    // The JSON members of AClass's published properties, in the order the
    // mapper writes them and with the names it uses (Naming and RenameMember
    // applied, so a later change of either shows here too). For code that
    // describes the JSON instead of producing it: documentation, schemas.
    // Raises EJsonMapperError when two properties map to the same name, as
    // reading or writing would.
    function Members(AClass: TClass): TJsonMemberArray;

    function FromJson<I: IInterface>(const AJson: string): I;
    function ToJson<I: IInterface>(const AValue: I): string;

    // Any supported type at the top level: a dynamic array (of DTO
    // interfaces, numbers, strings...), an interface, a scalar.
    //   Json := Mapper.Serialize<TOrderArray>(Orders);
    //   Orders := Mapper.Deserialize<TOrderArray>(Json);
    // On FPC, name the array type (TOrderArray = TArray<IOrder>):
    // Serialize<TArray<IOrder>> doesn't parse there (">>" reads as shr).
    // Deserialize of JSON null gives Default(T). Class types can't be
    // created: use PopulateObject.
    function Serialize<T>(const AValue: T): string;
    function Deserialize<T>(const AJson: string): T;
    function ObjectToJson(AObject: TObject): string;
    procedure PopulateObject(AObject: TObject; const AJson: string);

    // Building blocks, also for converters that need to recurse.
    // ReadValue returns False when the destination must be left untouched
    // (JSON null for a scalar). WriteValue returns False when the value was
    // omitted (a converter decided so).
    function ReadValue(AJson: TJsonValue; ATypeInfo: PTypeInfo;
      const APath: string; out AValue: TValue): Boolean;
    function WriteValue(AWriter: TJsonWriter; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string): Boolean;
    procedure ReadObject(AObject: TObject; AJson: TJsonValue; const APath: string);
    procedure WriteObject(AWriter: TJsonWriter; AObject: TObject; const APath: string);

    property Naming: TJsonNaming read FNaming write SetNaming;
    // umIgnore (default): JSON members that match no property are skipped.
    // umError: they raise EJsonMapperError with their path, before anything
    // is assigned (so PopulateObject leaves the object untouched).
    property UnknownMembers: TJsonUnknownMembers read FUnknownMembers write FUnknownMembers;
    // 0 (default): compact. N > 0: one member/element per line, N spaces
    // per level (see TJsonWriter).
    property Indent: Integer read FIndent write FIndent;
  end;

// Helpers for converters and DTO code.
function JsonTypeName(ATypeInfo: PTypeInfo): string;
// PascalCase -> snake_case: a '_' before an upper-case letter that follows a
// lower-case letter or a digit, or that starts a word after an acronym
// (HTTPStatus -> http_status); everything lower-cased. UserID -> user_id,
// Address2 -> address2, Line2Text -> line2_text. An existing '_' is kept and
// never doubled.
function JsonSnakeCase(const AName: string): string;
function JsonIsStringKind(AKind: TTypeKind): Boolean;
function JsonIsBooleanType(ATypeInfo: PTypeInfo): Boolean;

implementation

uses
  Classes, SyncObjs;

{ Helpers }

function JsonTypeName(ATypeInfo: PTypeInfo): string;
begin
{$IFDEF FPC}
  Result := string(ATypeInfo^.Name);
{$ELSE}
  Result := GetTypeName(ATypeInfo);
{$ENDIF}
end;

function IsUpper(C: Char): Boolean;
begin
  Result := (C >= 'A') and (C <= 'Z');
end;

function IsLowerOrDigit(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= '0') and (C <= '9'));
end;

function JsonSnakeCase(const AName: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(AName) do
  begin
    C := AName[I];
    if IsUpper(C) and (I > 1) and (AName[I - 1] <> '_') and
      (IsLowerOrDigit(AName[I - 1]) or
       (IsUpper(AName[I - 1]) and (I < Length(AName)) and
        (AName[I + 1] >= 'a') and (AName[I + 1] <= 'z'))) then
      Result := Result + '_';
    if IsUpper(C) then
      Result := Result + Char(Ord(C) + 32)
    else
      Result := Result + C;
  end;
end;

function PropInfoName(AProp: PPropInfo): string;
begin
{$IFDEF FPC}
  Result := string(AProp^.Name);
{$ELSE}
  Result := UTF8ToString(AProp^.Name);
{$ENDIF}
end;

function JsonIsStringKind(AKind: TTypeKind): Boolean;
begin
  // FPC declares tkString as an alias of tkSString: listing both is a
  // duplicate set element, hence the split.
  Result := AKind in [{$IFDEF FPC}tkSString, tkAString{$ELSE}tkString{$ENDIF},
    tkLString, tkWString, tkUString];
end;

function JsonIsBooleanType(ATypeInfo: PTypeInfo): Boolean;
begin
  // Compare the PTypeInfo, not the kind: Boolean is tkEnumeration on Delphi
  // and tkBool on FPC.
  Result := (ATypeInfo = TypeInfo(Boolean)) or (ATypeInfo = TypeInfo(ByteBool)) or
    (ATypeInfo = TypeInfo(WordBool)) or (ATypeInfo = TypeInfo(LongBool))
    {$IFDEF FPC} or (ATypeInfo^.Kind = tkBool){$ENDIF};
end;

function DynArrayElementType(ATypeInfo: PTypeInfo): PTypeInfo;
begin
{$IFDEF FPC}
  Result := GetTypeData(ATypeInfo)^.ElType2;
{$ELSE}
  Result := GetTypeData(ATypeInfo)^.elType2^;
{$ENDIF}
end;

function MemberPath(const APath, AName: string): string;
begin
  Result := APath + '.' + AName;
end;

function IndexPath(const APath: string; AIndex: Integer): string;
begin
  Result := APath + '[' + IntToStr(AIndex) + ']';
end;

const
  // GUID_NULL is Winapi.ActiveX-only on Delphi; TGUID.Empty is a Delphi helper.
  EMPTY_GUID: TGUID = '{00000000-0000-0000-0000-000000000000}';

  JsonKindNames: array[TJsonKind] of string =
    ('null', 'boolean', 'number', 'string', 'array', 'object');

procedure Mismatch(const APath, AExpected: string; AJson: TJsonValue);
begin
  raise EJsonMapperError.CreateFmt('%s: expected %s, found JSON %s',
    [APath, AExpected, JsonKindNames[AJson.Kind]]);
end;

procedure Unsupported(const APath: string; ATypeInfo: PTypeInfo);
begin
  raise EJsonMapperError.CreateFmt(
    '%s: type %s is not supported (register an IJsonConverter for it)',
    [APath, JsonTypeName(ATypeInfo)]);
end;

{ Ordinal storage. TValue.Make copies the type's own size from the buffer,
  so ordinals are staged in an Int64 (all supported targets are
  little-endian) and read back by OrdType. }

function ReadOrdinal(AData: Pointer; ATypeInfo: PTypeInfo): Int64;
begin
  case GetTypeData(ATypeInfo)^.OrdType of
    otSByte: Result := PShortInt(AData)^;
    otUByte: Result := PByte(AData)^;
    otSWord: Result := PSmallInt(AData)^;
    otUWord: Result := PWord(AData)^;
    otULong: Result := PCardinal(AData)^;
  else
    Result := PInteger(AData)^;
  end;
end;

procedure OrdinalRange(ATypeInfo: PTypeInfo; out AMin, AMax: Int64);
var
  TD: PTypeData;
begin
  TD := GetTypeData(ATypeInfo);
  if TD^.OrdType = otULong then
  begin
    // MinValue/MaxValue are 32-bit signed fields: Cardinal's max reads as -1.
    AMin := Cardinal(TD^.MinValue);
    AMax := Cardinal(TD^.MaxValue);
  end
  else
  begin
    AMin := TD^.MinValue;
    AMax := TD^.MaxValue;
  end;
end;

{ Class metadata cache }

type
  TJsonPropMeta = record
    Name: string;
    TypeInfo: PTypeInfo;
    Prop: TRttiProperty;
    Readable: Boolean;
    Writable: Boolean;
  end;

  TJsonClassMeta = class
  public
    Props: array of TJsonPropMeta;
  end;

  TJsonMetaCache = class
  private
    FLock: TCriticalSection;
    FContext: TRttiContext;
    FItems: TDictionary<TClass, TJsonClassMeta>;
    function Build(AClass: TClass): TJsonClassMeta;
  public
    constructor Create;
    destructor Destroy; override;
    function Get(AClass: TClass): TJsonClassMeta;
  end;

var
  GMetaCache: TJsonMetaCache;
  GDefaultMapper: TJsonMapper;

constructor TJsonMetaCache.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FContext := TRttiContext.Create;
  FItems := TDictionary<TClass, TJsonClassMeta>.Create;
end;

destructor TJsonMetaCache.Destroy;
var
  Meta: TJsonClassMeta;
begin
  for Meta in FItems.Values do
    Meta.Free;
  FItems.Free;
  FContext.Free;
  FLock.Free;
  inherited;
end;

function TJsonMetaCache.Build(AClass: TClass): TJsonClassMeta;
var
  PropList: PPropList;
  Count, I, N: Integer;
  RType: TRttiType;
  Prop: TRttiProperty;
  Name: string;
  Seen: TStringList;
begin
  Result := TJsonClassMeta.Create;
  // GetPropList orders by NameIndex on both compilers: ancestors first, then
  // declaration order. TRttiType.GetProperties doesn't agree across them.
  Count := GetPropList(AClass.ClassInfo, PropList);
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := False;
    Seen.Sorted := True;
    RType := FContext.GetType(AClass);
    SetLength(Result.Props, Count);
    N := 0;
    for I := 0 to Count - 1 do
    begin
      Name := PropInfoName(PropList^[I]);
      if Seen.IndexOf(Name) >= 0 then
        Continue;
      Seen.Add(Name);
      Prop := RType.GetProperty(Name);
      if Prop = nil then
        Continue;
      Result.Props[N].Name := Name;
      Result.Props[N].Prop := Prop;
      Result.Props[N].TypeInfo := Prop.PropertyType.Handle;
      Result.Props[N].Readable := Prop.IsReadable;
      Result.Props[N].Writable := Prop.IsWritable;
      Inc(N);
    end;
    SetLength(Result.Props, N);
  finally
    Seen.Free;
    if Count > 0 then
      FreeMem(PropList);
  end;
end;

function TJsonMetaCache.Get(AClass: TClass): TJsonClassMeta;
begin
  FLock.Enter;
  try
    if not FItems.TryGetValue(AClass, Result) then
    begin
      Result := Build(AClass);
      FItems.Add(AClass, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

{ TJsonInstanceFactoryOf<C> }

class function TJsonInstanceFactoryOf<C>.CreateInstance: TObject;
begin
  Result := C.Create;
end;

{ TJsonMapper }

constructor TJsonMapper.Create;
begin
  inherited Create;
  FMappings := TDictionary<TGUID, TJsonMapping>.Create;
  FRenames := TDictionary<string, string>.Create;
  FNames := TDictionary<TClass, TJsonClassNames>.Create;
  FNamesLock := TCriticalSection.Create;
end;

destructor TJsonMapper.Destroy;
begin
  ClearClassNames;
  FNames.Free;
  FNamesLock.Free;
  FRenames.Free;
  FConverters := nil;
  FMappings.Free;
  inherited;
end;

class function TJsonMapper.Shared: TJsonMapper;
begin
  Result := GDefaultMapper;
end;

procedure TJsonMapper.DoRegisterMapping(AInterface: PTypeInfo; AClass: TClass;
  AFactory: TJsonInstanceFactoryClass);
var
  Guid: TGUID;
  Mapping: TJsonMapping;
begin
  Guid := GetTypeData(AInterface)^.Guid;
  if IsEqualGUID(Guid, EMPTY_GUID) then
    raise EJsonMapperError.CreateFmt('Interface %s has no GUID',
      [JsonTypeName(AInterface)]);
  if AClass.GetInterfaceEntry(Guid) = nil then
    raise EJsonMapperError.CreateFmt('Class %s does not implement %s',
      [AClass.ClassName, JsonTypeName(AInterface)]);
  Mapping.ImplClass := AClass;
  Mapping.Factory := AFactory;
  FMappings.AddOrSetValue(Guid, Mapping);
end;

procedure TJsonMapper.RegisterMapping<I, C>;
begin
  DoRegisterMapping(TypeInfo(I), C, TJsonInstanceFactoryOf<C>);
end;

procedure TJsonMapper.RegisterConverter(const AConverter: IJsonConverter);
begin
  SetLength(FConverters, Length(FConverters) + 1);
  FConverters[High(FConverters)] := AConverter;
end;

function TJsonMapper.FindImplClass(AInterface: PTypeInfo): TClass;
var
  Mapping: TJsonMapping;
begin
  if FMappings.TryGetValue(GetTypeData(AInterface)^.Guid, Mapping) then
    Result := Mapping.ImplClass
  else
    Result := nil;
end;

function TJsonMapper.FindConverter(ATypeInfo: PTypeInfo): IJsonConverter;
var
  I: Integer;
begin
  for I := High(FConverters) downto 0 do
    if FConverters[I].CanConvert(ATypeInfo) then
      Exit(FConverters[I]);
  Result := nil;
end;

function TJsonMapper.ApplyNaming(const APropName: string): string;
begin
  case FNaming of
    jnCamelCase: Result := LowerCase(Copy(APropName, 1, 1)) + Copy(APropName, 2, MaxInt);
    jnSnakeCase: Result := JsonSnakeCase(APropName);
  else
    Result := APropName;
  end;
end;

function RenameKey(AClass: TClass; const APropName: string): string;
begin
  Result := IntToHex(Int64(NativeUInt(AClass)), 16) + '.' + UpperCase(APropName);
end;

procedure TJsonMapper.SetNaming(AValue: TJsonNaming);
begin
  FNaming := AValue;
  ClearClassNames;
end;

procedure TJsonMapper.ClearClassNames;
var
  Names: TJsonClassNames;
begin
  TCriticalSection(FNamesLock).Enter;
  try
    for Names in FNames.Values do
      Names.Free;
    FNames.Clear;
  finally
    TCriticalSection(FNamesLock).Leave;
  end;
end;

procedure TJsonMapper.RenameMember(AClass: TClass; const APropertyName, AJsonName: string);
var
  Meta: TJsonClassMeta;
  I: Integer;
begin
  if AJsonName = '' then
    raise EJsonMapperError.Create('RenameMember: the JSON name is empty');
  Meta := GMetaCache.Get(AClass);
  for I := 0 to High(Meta.Props) do
    if SameText(Meta.Props[I].Name, APropertyName) then
    begin
      FRenames.AddOrSetValue(RenameKey(AClass, Meta.Props[I].Name), AJsonName);
      ClearClassNames;
      Exit;
    end;
  raise EJsonMapperError.CreateFmt('RenameMember: %s has no published property "%s"',
    [AClass.ClassName, APropertyName]);
end;

function TJsonMapper.BuildClassNames(AClass: TClass): TJsonClassNames;
var
  Meta: TJsonClassMeta;
  I, J: Integer;
  C: TClass;
  Renamed: string;
begin
  Meta := GMetaCache.Get(AClass);
  Result := TJsonClassNames.Create;
  try
    SetLength(Result.Names, Length(Meta.Props));
    SetLength(Result.Renamed, Length(Meta.Props));
    for I := 0 to High(Meta.Props) do
    begin
      // The most derived rename wins.
      Result.Renamed[I] := False;
      C := AClass;
      while (C <> nil) and not Result.Renamed[I] do
      begin
        if FRenames.TryGetValue(RenameKey(C, Meta.Props[I].Name), Renamed) then
        begin
          Result.Names[I] := Renamed;
          Result.Renamed[I] := True;
        end;
        C := C.ClassParent;
      end;
      if not Result.Renamed[I] then
        Result.Names[I] := ApplyNaming(Meta.Props[I].Name);
    end;
    // Reading matches names case-insensitively, so compare that way.
    for I := 0 to High(Result.Names) do
      for J := I + 1 to High(Result.Names) do
        if SameText(Result.Names[I], Result.Names[J]) then
          raise EJsonMapperError.CreateFmt(
            '%s: properties %s and %s both map to the JSON member "%s"',
            [AClass.ClassName, Meta.Props[I].Name, Meta.Props[J].Name, Result.Names[J]]);
  except
    Result.Free;
    raise;
  end;
end;

function TJsonMapper.ClassNames(AClass: TClass): TJsonClassNames;
begin
  TCriticalSection(FNamesLock).Enter;
  try
    if not FNames.TryGetValue(AClass, Result) then
    begin
      Result := BuildClassNames(AClass);
      FNames.Add(AClass, Result);
    end;
  finally
    TCriticalSection(FNamesLock).Leave;
  end;
end;

function TJsonMapper.Members(AClass: TClass): TJsonMemberArray;
var
  Meta: TJsonClassMeta;
  Names: TJsonClassNames;
  I: Integer;
begin
  Meta := GMetaCache.Get(AClass);
  Names := ClassNames(AClass);
  Result := nil;
  SetLength(Result, Length(Meta.Props));
  for I := 0 to High(Meta.Props) do
  begin
    Result[I].PropertyName := Meta.Props[I].Name;
    Result[I].JsonName := Names.Names[I];
    Result[I].TypeInfo := Meta.Props[I].TypeInfo;
    Result[I].Readable := Meta.Props[I].Readable;
    Result[I].Writable := Meta.Props[I].Writable;
  end;
end;

{ Reading }

function TJsonMapper.CreateFromJson(ATypeInfo: PTypeInfo; AJson: TJsonValue;
  const APath: string): IInterface;
var
  Guid: TGUID;
  Mapping: TJsonMapping;
  Obj: TObject;
begin
  // Registration first: for an interface nobody registered, "expected
  // object" would point at the JSON instead of the missing mapping.
  Guid := GetTypeData(ATypeInfo)^.Guid;
  if not FMappings.TryGetValue(Guid, Mapping) then
    raise EJsonMapperError.CreateFmt(
      '%s: no class registered for interface %s (RegisterMapping), and no ' +
      'IJsonConverter accepts it', [APath, JsonTypeName(ATypeInfo)]);
  if AJson.Kind <> jkObject then
    Mismatch(APath, 'object', AJson);
  Obj := Mapping.Factory.CreateInstance;
  try
    ReadObject(Obj, AJson, APath);
  except
    Obj.Free;
    raise;
  end;
  // Registration checked that the class implements the interface.
  Obj.GetInterface(Guid, Result);
end;

procedure TJsonMapper.ReadObject(AObject: TObject; AJson: TJsonValue;
  const APath: string);
var
  Meta: TJsonClassMeta;
  Names: TJsonClassNames;
  I, K: Integer;
  Member: TJsonValue;
  Value: TValue;
  Path: string;
  Child: TObject;
  Known: Boolean;
begin
  if AJson.Kind <> jkObject then
    Mismatch(APath, 'object', AJson);
  Meta := GMetaCache.Get(AObject.ClassType);
  Names := ClassNames(AObject.ClassType);

  // Before anything is assigned, so a rejected body changes nothing.
  if FUnknownMembers = umError then
    for K := 0 to AJson.Count - 1 do
    begin
      Known := False;
      for I := 0 to High(Meta.Props) do
        if SameText(AJson.Names[K], Names.Names[I]) or
          (not Names.Renamed[I] and SameText(AJson.Names[K], Meta.Props[I].Name)) then
        begin
          Known := True;
          Break;
        end;
      if not Known then
        raise EJsonMapperError.CreateFmt('%s: unknown member (no published property of %s matches it)',
          [MemberPath(APath, AJson.Names[K]), AObject.ClassName]);
    end;

  for I := 0 to High(Meta.Props) do
  begin
    // Exact name first, then case-insensitive; the declared property name
    // too, unless the member was renamed.
    Member := AJson.Find(Names.Names[I]);
    if Member = nil then
      Member := AJson.Find(Names.Names[I], True);
    if (Member = nil) and not Names.Renamed[I] then
      Member := AJson.Find(Meta.Props[I].Name, True);
    if Member = nil then
      Continue;
    Path := MemberPath(APath, Names.Names[I]);

    if (Meta.Props[I].TypeInfo^.Kind = tkClass) and
      (FindConverter(Meta.Props[I].TypeInfo) = nil) then
    begin
      // Never create: populate the instance the property already holds.
      if Member.IsNull or not Meta.Props[I].Readable then
        Continue;
      Child := Meta.Props[I].Prop.GetValue(AObject).AsObject;
      if Child = nil then
        raise EJsonMapperError.CreateFmt(
          '%s: class property is nil; the owner must create it', [Path]);
      ReadObject(Child, Member, Path);
      Continue;
    end;

    if not Meta.Props[I].Writable then
      Continue;
    if ReadValue(Member, Meta.Props[I].TypeInfo, Path, Value) then
      Meta.Props[I].Prop.SetValue(AObject, Value);
  end;
end;

function TJsonMapper.ReadValue(AJson: TJsonValue; ATypeInfo: PTypeInfo;
  const APath: string; out AValue: TValue): Boolean;
begin
  try
    Result := DoReadValue(AJson, ATypeInfo, APath, AValue);
  except
    // From a converter or a TJsonValue accessor: add where it happened.
    // EJsonMapperError is not an EJsonError, so outer levels pass it on.
    on E: EJsonError do
      raise EJsonMapperError.CreateFmt('%s: %s', [APath, E.Message]);
  end;
end;

function TJsonMapper.DoReadValue(AJson: TJsonValue; ATypeInfo: PTypeInfo;
  const APath: string; out AValue: TValue): Boolean;
var
  Converter: IJsonConverter;
  Ord, Min, Max: Int64;
  I64: Int64;
  Intf: IInterface;
  Arr: Pointer;
  Len: NativeInt;
  K: Integer;
  ElemType: PTypeInfo;
  Elem: TValue;
  Sgl: Single;
  Dbl: Double;
  Ext: Extended;
  Cur: Currency;
  Dt: TDateTime;
  S: string;
  {$IFDEF FPC}
  U: UnicodeString;
  {$ELSE}
  A: AnsiString;
  U8: UTF8String;
  {$ENDIF}
  W: WideString;
  C: Char;
begin
  AValue := TValue.Empty;
  Converter := FindConverter(ATypeInfo);
  if Converter <> nil then
    Exit(Converter.ReadJson(Self, AJson, ATypeInfo, APath, AValue));

  if AJson.IsNull then
  begin
    case ATypeInfo^.Kind of
      tkInterface:
        begin
          Intf := nil;
          TValue.Make(@Intf, ATypeInfo, AValue);
          Exit(True);
        end;
      tkDynArray:
        begin
          Arr := nil;
          TValue.Make(@Arr, ATypeInfo, AValue);
          Exit(True);
        end;
    else
      // A scalar can't hold null: leave the destination as it is.
      Exit(False);
    end;
  end;

  Result := True;
  case ATypeInfo^.Kind of
    tkInteger, tkEnumeration{$IFDEF FPC}, tkBool{$ENDIF}:
      begin
        if JsonIsBooleanType(ATypeInfo) then
        begin
          if AJson.Kind <> jkBoolean then
            Mismatch(APath, 'boolean', AJson);
          if ATypeInfo = TypeInfo(Boolean) then
            Ord := System.Ord(AJson.AsBoolean)
          else if AJson.AsBoolean then
            Ord := -1
          else
            Ord := 0;
        end
        else if ATypeInfo^.Kind = tkEnumeration then
        begin
          if AJson.Kind <> jkString then
            Mismatch(APath, 'string (enumeration name)', AJson);
          Ord := GetEnumValue(ATypeInfo, AJson.AsString);
          if Ord < 0 then
            raise EJsonMapperError.CreateFmt('%s: "%s" is not a value of %s',
              [APath, AJson.AsString, JsonTypeName(ATypeInfo)]);
        end
        else
        begin
          if not AJson.TryAsInt64(Ord) then
            Mismatch(APath, 'integer', AJson);
          OrdinalRange(ATypeInfo, Min, Max);
          if (Ord < Min) or (Ord > Max) then
            raise EJsonMapperError.CreateFmt('%s: %d is out of range for %s',
              [APath, Ord, JsonTypeName(ATypeInfo)]);
        end;
        TValue.Make(@Ord, ATypeInfo, AValue);
      end;

    tkInt64{$IFDEF FPC}, tkQWord{$ENDIF}:
      begin
        if not AJson.TryAsInt64(I64) then
          Mismatch(APath, 'integer', AJson);
        TValue.Make(@I64, ATypeInfo, AValue);
      end;

    tkFloat:
      if (ATypeInfo = TypeInfo(TDateTime)) or (ATypeInfo = TypeInfo(TDate)) or
        (ATypeInfo = TypeInfo(TTime)) then
      begin
        if AJson.Kind <> jkString then
          Mismatch(APath, 'ISO 8601 string', AJson);
        try
          if ATypeInfo = TypeInfo(TTime) then
            Dt := JsonStrToTime(AJson.AsString)
          else
            Dt := JsonStrToDateTime(AJson.AsString);
        except
          on E: EJsonError do
            raise EJsonMapperError.CreateFmt('%s: %s', [APath, E.Message]);
        end;
        TValue.Make(@Dt, ATypeInfo, AValue);
      end
      else
      begin
        if AJson.Kind <> jkNumber then
          Mismatch(APath, 'number', AJson);
        case GetTypeData(ATypeInfo)^.FloatType of
          ftSingle:
            begin
              Sgl := JsonStrToSingle(AJson.NumberText);
              TValue.Make(@Sgl, ATypeInfo, AValue);
            end;
          ftDouble:
            begin
              Dbl := JsonStrToDouble(AJson.NumberText);
              TValue.Make(@Dbl, ATypeInfo, AValue);
            end;
          ftExtended:
            begin
              // Read as Double: identical on every target (Extended is Double on
              // Win64/ARM anyway).
              Ext := JsonStrToDouble(AJson.NumberText);
              TValue.Make(@Ext, ATypeInfo, AValue);
            end;
          ftCurr:
            begin
              if not TryStrToCurr(AJson.NumberText, Cur, JsonFormatSettings) then
                Cur := JsonStrToDouble(AJson.NumberText);
              TValue.Make(@Cur, ATypeInfo, AValue);
            end;
        else
          Unsupported(APath, ATypeInfo);
        end;
      end;

    tkChar, tkWChar:
      begin
        if AJson.Kind <> jkString then
          Mismatch(APath, 'string', AJson);
        S := AJson.AsString;
        if ATypeInfo^.Kind = tkWChar then
        begin
          {$IFDEF FPC}
          U := UTF8Decode(S);
          if Length(U) <> 1 then
            raise EJsonMapperError.CreateFmt('%s: one character expected', [APath]);
          TValue.Make(@U[1], ATypeInfo, AValue);
          {$ELSE}
          if Length(S) <> 1 then
            raise EJsonMapperError.CreateFmt('%s: one character expected', [APath]);
          C := S[1];
          TValue.Make(@C, ATypeInfo, AValue);
          {$ENDIF}
        end
        else
        begin
          if Length(S) <> 1 then
            raise EJsonMapperError.CreateFmt('%s: one character expected', [APath]);
          {$IFDEF FPC}
          C := S[1];
          TValue.Make(@C, ATypeInfo, AValue);
          {$ELSE}
          A := AnsiString(S);
          TValue.Make(@A[1], ATypeInfo, AValue);
          {$ENDIF}
        end;
      end;

    tkInterface:
      begin
        Intf := CreateFromJson(ATypeInfo, AJson, APath);
        TValue.Make(@Intf, ATypeInfo, AValue);
      end;

    tkDynArray:
      begin
        if AJson.Kind <> jkArray then
          Mismatch(APath, 'array', AJson);
        ElemType := DynArrayElementType(ATypeInfo);
        Len := AJson.Count;
        Arr := nil;
        DynArraySetLength(Arr, ATypeInfo, 1, @Len);
        // Make takes its own reference; release ours afterwards.
        TValue.Make(@Arr, ATypeInfo, AValue);
        DynArrayClear(Arr, ATypeInfo);
        for K := 0 to AJson.Count - 1 do
          if ReadValue(AJson[K], ElemType, IndexPath(APath, K), Elem) then
            AValue.SetArrayElement(K, Elem);
      end;
  else
    if not JsonIsStringKind(ATypeInfo^.Kind) then
      Unsupported(APath, ATypeInfo);
    if AJson.Kind <> jkString then
      Mismatch(APath, 'string', AJson);
    S := AJson.AsString;
    case ATypeInfo^.Kind of
      tkWString:
        begin
          W := {$IFDEF FPC}UTF8Decode(S){$ELSE}S{$ENDIF};
          TValue.Make(@W, ATypeInfo, AValue);
        end;
      {$IFDEF FPC}
      tkUString:
        begin
          U := UTF8Decode(S);
          TValue.Make(@U, ATypeInfo, AValue);
        end;
      tkAString:
        TValue.Make(@S, ATypeInfo, AValue);
      {$ELSE}
      tkUString:
        TValue.Make(@S, ATypeInfo, AValue);
      tkLString:
        if GetTypeData(ATypeInfo)^.CodePage = CP_UTF8 then
        begin
          U8 := UTF8String(S);
          TValue.Make(@U8, ATypeInfo, AValue);
        end
        else
        begin
          A := AnsiString(S);
          TValue.Make(@A, ATypeInfo, AValue);
        end;
      {$ENDIF}
    else
      Unsupported(APath, ATypeInfo);
    end;
  end;
end;

{ Writing }

procedure TJsonMapper.WriteObject(AWriter: TJsonWriter; AObject: TObject;
  const APath: string);
var
  Meta: TJsonClassMeta;
  Names: TJsonClassNames;
  I: Integer;
  Name: string;
begin
  Meta := GMetaCache.Get(AObject.ClassType);
  Names := ClassNames(AObject.ClassType);
  AWriter.BeginObject;
  for I := 0 to High(Meta.Props) do
  begin
    if not Meta.Props[I].Readable then
      Continue;
    Name := Names.Names[I];
    AWriter.Name(Name);
    // An omitted value leaves the pending name unwritten.
    WriteValue(AWriter, Meta.Props[I].Prop.GetValue(AObject),
      Meta.Props[I].TypeInfo, MemberPath(APath, Name));
  end;
  AWriter.EndObject;
end;

function TJsonMapper.WriteValue(AWriter: TJsonWriter; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string): Boolean;
begin
  try
    Result := DoWriteValue(AWriter, AValue, ATypeInfo, APath);
  except
    on E: EJsonError do
      raise EJsonMapperError.CreateFmt('%s: %s', [APath, E.Message]);
  end;
end;

function TJsonMapper.DoWriteValue(AWriter: TJsonWriter; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string): Boolean;
var
  Converter: IJsonConverter;
  Data: Pointer;
  Ord: Int64;
  Intf: IInterface;
  Obj: TObject;
  K, Len: Integer;
  ElemType: PTypeInfo;
begin
  Converter := FindConverter(ATypeInfo);
  if Converter <> nil then
    Exit(Converter.WriteJson(Self, AValue, ATypeInfo, APath, AWriter));

  Result := True;
  case ATypeInfo^.Kind of
    tkInterface:
      begin
        if AValue.IsEmpty then
          Intf := nil
        else
          Intf := AValue.AsInterface;
        if Intf = nil then
          AWriter.WriteNull
        else
          WriteObject(AWriter, Intf as TObject, APath);
        Exit;
      end;
    tkClass:
      begin
        if AValue.IsEmpty then
          Obj := nil
        else
          Obj := AValue.AsObject;
        if Obj = nil then
          AWriter.WriteNull
        else
          WriteObject(AWriter, Obj, APath);
        Exit;
      end;
    tkDynArray:
      begin
        ElemType := DynArrayElementType(ATypeInfo);
        if AValue.IsEmpty then
          Len := 0
        else
          Len := AValue.GetArrayLength;
        AWriter.BeginArray;
        for K := 0 to Len - 1 do
          if not WriteValue(AWriter, AValue.GetArrayElement(K), ElemType,
            IndexPath(APath, K)) then
            AWriter.WriteNull;
        AWriter.EndArray;
        Exit;
      end;
  end;

  Data := AValue.GetReferenceToRawData;
  case ATypeInfo^.Kind of
    tkInteger, tkEnumeration{$IFDEF FPC}, tkBool{$ENDIF}:
      begin
        Ord := ReadOrdinal(Data, ATypeInfo);
        if JsonIsBooleanType(ATypeInfo) then
          AWriter.WriteBoolean(Ord <> 0)
        else if ATypeInfo^.Kind = tkEnumeration then
          AWriter.WriteString(GetEnumName(ATypeInfo, Ord))
        else
          AWriter.WriteInt64(Ord);
      end;
    tkInt64:
      AWriter.WriteInt64(PInt64(Data)^);
    {$IFDEF FPC}
    tkQWord:
      AWriter.WriteNumberText(IntToStr(PQWord(Data)^));
    {$ENDIF}
    tkFloat:
      if ATypeInfo = TypeInfo(TDateTime) then
        AWriter.WriteString(JsonDateTimeToStr(PDateTime(Data)^))
      else if ATypeInfo = TypeInfo(TDate) then
        AWriter.WriteString(JsonDateToStr(PDateTime(Data)^))
      else if ATypeInfo = TypeInfo(TTime) then
        AWriter.WriteString(JsonTimeToStr(PDateTime(Data)^))
      else
        case GetTypeData(ATypeInfo)^.FloatType of
          ftSingle: AWriter.WriteSingle(PSingle(Data)^);
          ftDouble: AWriter.WriteDouble(PDouble(Data)^);
          ftExtended: AWriter.WriteDouble(PExtended(Data)^);
          ftCurr: AWriter.WriteCurrency(PCurrency(Data)^);
        else
          Unsupported(APath, ATypeInfo);
        end;
    tkChar:
      {$IFDEF FPC}
      AWriter.WriteString(PChar(Data)^);
      {$ELSE}
      AWriter.WriteString(string(PAnsiChar(Data)^));
      {$ENDIF}
    tkWChar:
      {$IFDEF FPC}
      AWriter.WriteString(UTF8Encode(UnicodeString(PWideChar(Data)^)));
      {$ELSE}
      AWriter.WriteString(PWideChar(Data)^);
      {$ENDIF}
    tkWString:
      AWriter.WriteString({$IFDEF FPC}UTF8Encode(PWideString(Data)^){$ELSE}PWideString(Data)^{$ENDIF});
    tkUString:
      AWriter.WriteString({$IFDEF FPC}UTF8Encode(PUnicodeString(Data)^){$ELSE}PUnicodeString(Data)^{$ENDIF});
    {$IFDEF FPC}
    tkAString:
      AWriter.WriteString(PString(Data)^);
    {$ELSE}
    tkLString:
      if GetTypeData(ATypeInfo)^.CodePage = CP_UTF8 then
        AWriter.WriteString(UTF8ToString(PRawByteString(Data)^))
      else
        AWriter.WriteString(string(PAnsiString(Data)^));
    {$ENDIF}
  else
    Unsupported(APath, ATypeInfo);
  end;
end;

{ Entry points }

function TJsonMapper.FromJson<I>(const AJson: string): I;
var
  Root: TJsonValue;
  Intf: IInterface;
begin
  Result := Default(I);
  Root := ParseJson(AJson);
  try
    Intf := CreateFromJson(TypeInfo(I), Root, '$');
  finally
    Root.Free;
  end;
  Supports(Intf, GetTypeData(TypeInfo(I))^.Guid, Result);
end;

function TJsonMapper.ToJson<I>(const AValue: I): string;
var
  Value: TValue;
  Writer: TJsonWriter;
begin
  TValue.Make(@AValue, TypeInfo(I), Value);
  Writer := TJsonWriter.Create(FIndent);
  try
    if not WriteValue(Writer, Value, TypeInfo(I), '$') then
      Writer.WriteNull;
    Result := Writer.ToString;
  finally
    Writer.Free;
  end;
end;

function TJsonMapper.Serialize<T>(const AValue: T): string;
var
  Value: TValue;
  Writer: TJsonWriter;
begin
  TValue.Make(@AValue, TypeInfo(T), Value);
  Writer := TJsonWriter.Create(FIndent);
  try
    if not WriteValue(Writer, Value, TypeInfo(T), '$') then
      Writer.WriteNull;
    Result := Writer.ToString;
  finally
    Writer.Free;
  end;
end;

function TJsonMapper.Deserialize<T>(const AJson: string): T;
var
  Root: TJsonValue;
  Value: TValue;
begin
  Result := Default(T);
  Root := ParseJson(AJson);
  try
    if not ReadValue(Root, TypeInfo(T), '$', Value) then
      Exit;
  finally
    Root.Free;
  end;
  // Result is zeroed (Default above), which is what ExtractRawData needs:
  // FPC moves the data in and adds a reference, Delphi copies it.
  Value.ExtractRawData(@Result);
end;

function TJsonMapper.ObjectToJson(AObject: TObject): string;
var
  Writer: TJsonWriter;
begin
  Writer := TJsonWriter.Create(FIndent);
  try
    if AObject = nil then
      Writer.WriteNull
    else
      WriteObject(Writer, AObject, '$');
    Result := Writer.ToString;
  finally
    Writer.Free;
  end;
end;

procedure TJsonMapper.PopulateObject(AObject: TObject; const AJson: string);
var
  Root: TJsonValue;
begin
  Root := ParseJson(AJson);
  try
    ReadObject(AObject, Root, '$');
  finally
    Root.Free;
  end;
end;

initialization
  GMetaCache := TJsonMetaCache.Create;
  GDefaultMapper := TJsonMapper.Create;

finalization
  GDefaultMapper.Free;
  GMetaCache.Free;

end.
