unit PascalJsonMapper.MapperTests;

{ Tests for the RTTI mapper (PascalJsonMapper.Mapper): scalars of every
  supported kind, published-only visibility, inherited properties in
  ancestor-first order, nested interfaces and arrays, null handling,
  class-typed properties populated in place, error paths, registration
  checks, and a converter with three states (absent/null/value) — the shape
  a bridge from another library takes.

  Every test builds its own TJsonMapper (NewTestMapper): no global state
  leaks between tests.

  DUnitX master, written in FPCUnit's assertion dialect (TAssert.*, through
  PascalJsonMapper.DUnitXCompat). The mirror in tests/Unit/fpc is generated
  from the master by tools/gen_fpc_mirror.py — edit only the master. }

interface

uses
  DUnitX.TestFramework,
  PascalJsonMapper.DUnitXCompat,
  SysUtils,
  DateUtils,
  Math,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper,
  PascalJsonMapper.TestTypes;

type
  [TestFixture]
  TMapperReadTests = class
  private
    FMapper: TJsonMapper;
    procedure AssertMapperError(const AJson, AExpectedInMessage: string);
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Scalars_AllKinds;
    [Test]
    procedure Constructor_OfDto_Runs;
    [Test]
    procedure Names_AreCaseInsensitive_UnknownIgnored;
    [Test]
    procedure PublicProperty_IsIgnored;
    [Test]
    procedure ReadOnlyProperty_IsIgnored;
    [Test]
    procedure Null_IntoScalar_KeepsValue;
    [Test]
    procedure Nested_InterfaceAndArrays;
    [Test]
    procedure Null_IntoInterfaceAndArray;
    [Test]
    procedure Unicode_Text;
    [Test]
    procedure Error_TypeMismatch_HasPath;
    [Test]
    procedure Error_OutOfRange;
    [Test]
    procedure Error_UnknownEnumName;
    [Test]
    procedure Error_UnregisteredInterface;
    [Test]
    procedure Error_InvalidJson;
    [Test]
    procedure Error_InsideConverter_HasPath;
    [Test]
    procedure Error_NumberOutOfRange_HasPath;
    [Test]
    procedure Error_CurrencyOutOfRange_HasPath;
    [Test]
    procedure Error_IsoDate_HasPath;
    [Test]
    procedure Error_UnsupportedType_IsNotInputError;
    [Test]
    procedure ClassProperty_PopulatedInPlace;
    [Test]
    procedure ClassProperty_Nil_Raises;
  end;

  [TestFixture]
  TMapperWriteTests = class
  private
    FMapper: TJsonMapper;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Scalars_ExactText_AncestorsFirst;
    [Test]
    procedure Naming_AsDeclared;
    [Test]
    procedure Nested_InterfaceAndArrays;
    [Test]
    procedure NilInterface_IsNull_NilArray_IsEmpty;
    [Test]
    procedure PlainObject_WithClassProperties;
    [Test]
    procedure RoundTrip_PreservesEverything;
    [Test]
    procedure Error_NaN_HasPath;
  end;

  [TestFixture]
  TMapperTopLevelTests = class
  private
    FMapper: TJsonMapper;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Serialize_ArrayOfInterfaces;
    [Test]
    procedure Deserialize_ArrayOfInterfaces;
    [Test]
    procedure Deserialize_ArraysOfScalars;
    [Test]
    procedure Deserialize_Null_IsDefault;
    [Test]
    procedure Scalars_AtTopLevel;
    [Test]
    procedure Deserialize_Errors_HavePath;
    [Test]
    procedure Indent_MapperOutput;
    [Test]
    procedure Indent_RoundTrip;
  end;

  [TestFixture]
  TMapperConverterTests = class
  private
    FMapper: TJsonMapper;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Read_ThreeStates;
    [Test]
    procedure Write_ThreeStates;
    [Test]
    procedure LastRegistered_Wins;
  end;

  [TestFixture]
  TMapperCurrencyTests = class
  private
    FMapper: TJsonMapper;
    procedure AssertAll(ADto: TCurrencyDto; AUnits: Int64);
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RoundTrip_EveryAccessKind_ToTheLimits;
    [Test]
    procedure VirtualAccessors_AreTheOverrides;
    [Test]
    procedure RoundTrip_EveryAccessKind_Random;
    [Test]
    procedure Read_HalfEven_AndExponent;
    [Test]
    procedure TopLevel_AndArrays_ToTheLimits;
  end;

  [TestFixture]
  TMapperRegistrationTests = class
  public
    [Test]
    procedure FindImplClass;
    [Test]
    procedure ClassNotImplementingInterface_Raises;
    [Test]
    procedure Shared_IsAvailable;
  end;

implementation

uses
  TypInfo, Rtti;

type
  // No built-in rule reads a record: Unsupported, a setup error.
  TPlainRecord = record
    A: Integer;
  end;

  // Writes every IOptText as a constant: registered after TOptTextConverter,
  // it must take precedence.
  TConstantConverter = class(TInterfacedObject, IJsonConverter)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
  end;

function TConstantConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(IOptText);
end;

function TConstantConverter.ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
  ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
var
  Opt: IOptText;
begin
  Opt := TOptText.From('constant');
  TValue.Make(@Opt, ATypeInfo, AValue);
  Result := True;
end;

function TConstantConverter.WriteJson(AMapper: TJsonMapper; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
begin
  AWriter.WriteString('constant');
  Result := True;
end;

function Scalar(const AIntf: IScalarDto): TScalarDto;
begin
  Result := AIntf as TScalarDto;
end;

function Order(const AIntf: IOrderDto): TOrderDto;
begin
  Result := AIntf as TOrderDto;
end;

function Patch(const AIntf: IPatchDto): TPatchDto;
begin
  Result := AIntf as TPatchDto;
end;

{ TMapperReadTests }

procedure TMapperReadTests.SetUp;
begin
  FMapper := NewTestMapper;
end;

procedure TMapperReadTests.TearDown;
begin
  FreeAndNil(FMapper);
end;

procedure TMapperReadTests.AssertMapperError(const AJson, AExpectedInMessage: string);
var
  Dto: IOrderDto;
begin
  try
    Dto := FMapper.FromJson<IOrderDto>(AJson);
    TAssert.Fail('Must raise: ' + AJson);
  except
    on E: EJsonInputError do
      TAssert.AssertTrue('Message "' + E.Message + '" must contain "' +
        AExpectedInMessage + '"', Pos(AExpectedInMessage, E.Message) > 0);
  end;
end;

procedure TMapperReadTests.Scalars_AllKinds;
var
  Dto: IScalarDto;
  S: TScalarDto;
begin
  Dto := FMapper.FromJson<IScalarDto>(
    '{"id":9007199254740993,"nome":"Ana","idade":-30,"pequeno":255,' +
    '"preco":0.1,"fator":1.5,"valor":12.3456,"ativo":true,"cor":"clBlue",' +
    '"nascimento":"2026-10-02T13:45:10.5","dia":"2026-10-02","hora":"08:30:00"}');
  S := Scalar(Dto);
  TAssert.AssertEquals(Int64(9007199254740993), S.Id);
  TAssert.AssertEquals('Ana', S.Nome);
  TAssert.AssertEquals(-30, S.Idade);
  TAssert.AssertEquals(255, Integer(S.Pequeno));
  TAssert.AssertEquals(0.1, S.Preco, 0);
  TAssert.AssertEquals(1.5, S.Fator, 0);
  TAssert.AssertEquals(Currency(12.3456), S.Valor);
  TAssert.AssertTrue(S.Ativo);
  TAssert.AssertTrue(S.Cor = clBlue);
  TAssert.AssertEquals(EncodeDateTime(2026, 10, 2, 13, 45, 10, 500), S.Nascimento,
    1 / MSecsPerDay / 2);
  TAssert.AssertEquals(EncodeDate(2026, 10, 2), S.Dia, 0);
  TAssert.AssertEquals(EncodeTime(8, 30, 0, 0), S.Hora, 1 / MSecsPerDay / 2);
end;

procedure TMapperReadTests.Constructor_OfDto_Runs;
var
  Dto: IScalarDto;
begin
  Dto := FMapper.FromJson<IScalarDto>('{}');
  TAssert.AssertEquals(42, Scalar(Dto).Padrao);
  Dto := FMapper.FromJson<IScalarDto>('{"padrao":7}');
  TAssert.AssertEquals(7, Scalar(Dto).Padrao);
end;

procedure TMapperReadTests.Names_AreCaseInsensitive_UnknownIgnored;
var
  Dto: IScalarDto;
begin
  Dto := FMapper.FromJson<IScalarDto>('{"NOME":"x","Idade":3,"naoExiste":[1,{}]}');
  TAssert.AssertEquals('x', Scalar(Dto).Nome);
  TAssert.AssertEquals(3, Scalar(Dto).Idade);
end;

procedure TMapperReadTests.PublicProperty_IsIgnored;
var
  Dto: IScalarDto;
begin
  Dto := FMapper.FromJson<IScalarDto>('{"publica":5}');
  TAssert.AssertEquals(0, Scalar(Dto).Publica);
end;

procedure TMapperReadTests.ReadOnlyProperty_IsIgnored;
var
  Dto: IScalarDto;
begin
  Dto := FMapper.FromJson<IScalarDto>('{"somenteLeitura":"changed"}');
  TAssert.AssertEquals('ro', Scalar(Dto).SomenteLeitura);
end;

procedure TMapperReadTests.Null_IntoScalar_KeepsValue;
var
  Dto: IScalarDto;
begin
  Dto := FMapper.FromJson<IScalarDto>('{"padrao":null,"nome":null}');
  TAssert.AssertEquals(42, Scalar(Dto).Padrao);
  TAssert.AssertEquals('', Scalar(Dto).Nome);
end;

procedure TMapperReadTests.Nested_InterfaceAndArrays;
var
  Dto: IOrderDto;
  O: TOrderDto;
begin
  Dto := FMapper.FromJson<IOrderDto>(
    '{"item":{"code":7},"itens":[{"code":1},null,{"code":3}],' +
    '"numeros":[3,4,5],"tags":["a","b"]}');
  O := Order(Dto);
  TAssert.AssertEquals(7, O.Item.GetCode);
  TAssert.AssertEquals(3, Integer(Length(O.Itens)));
  TAssert.AssertEquals(1, O.Itens[0].GetCode);
  TAssert.AssertTrue(O.Itens[1] = nil);
  TAssert.AssertEquals(3, O.Itens[2].GetCode);
  TAssert.AssertEquals(3, Integer(Length(O.Numeros)));
  TAssert.AssertEquals(5, O.Numeros[2]);
  TAssert.AssertEquals(2, Integer(Length(O.Tags)));
  TAssert.AssertEquals('b', O.Tags[1]);
end;

procedure TMapperReadTests.Null_IntoInterfaceAndArray;
var
  Dto: IOrderDto;
begin
  Dto := FMapper.FromJson<IOrderDto>('{"item":{"code":1},"numeros":[1]}');
  FMapper.PopulateObject(Order(Dto), '{"item":null,"numeros":null}');
  TAssert.AssertTrue(Order(Dto).Item = nil);
  TAssert.AssertEquals(0, Integer(Length(Order(Dto).Numeros)));
end;

procedure TMapperReadTests.Unicode_Text;
var
  Dto: IScalarDto;
  Expected: string;
begin
  Expected := 'S' + U([$E3]) + 'o Jo' + U([$E3]) + 'o ' + U([$1F600]);
  Dto := FMapper.FromJson<IScalarDto>('{"nome":"' + Expected + '"}');
  TAssert.AssertEquals(Expected, Scalar(Dto).Nome);
  Dto := FMapper.FromJson<IScalarDto>('{"nome":"São João 😀"}');
  TAssert.AssertEquals(Expected, Scalar(Dto).Nome);
end;

procedure TMapperReadTests.Error_TypeMismatch_HasPath;
begin
  AssertMapperError('{"itens":[{"code":1},{"code":"x"}]}', '$.itens[1].code');
  AssertMapperError('{"itens":[{"code":1},{"code":"x"}]}', 'expected integer');
  AssertMapperError('{"numeros":{}}', '$.numeros');
  AssertMapperError('{"item":5}', 'expected object');
end;

procedure TMapperReadTests.Error_OutOfRange;
var
  Dto: IScalarDto;
begin
  try
    Dto := FMapper.FromJson<IScalarDto>('{"pequeno":256}');
    TAssert.Fail('256 into a Byte must raise');
  except
    on E: EJsonInputError do
    begin
      TAssert.AssertEquals('$.pequeno: 256 is out of range (0..255)', E.Message);
      TAssert.AssertEquals('$.pequeno', E.Path);
      TAssert.AssertEquals('type Byte', E.Detail);
    end;
  end;
  try
    Dto := FMapper.FromJson<IScalarDto>('{"idade":2147483648}');
    TAssert.Fail('2^31 into an Integer must raise');
  except
    // Detail is "type Integer" on Delphi, "type LongInt" on FPC.
    on E: EJsonInputError do
      TAssert.AssertEquals('$.idade: 2147483648 is out of range (-2147483648..2147483647)',
        E.Message);
  end;
  try
    Dto := FMapper.FromJson<IScalarDto>('{"idade":1.5}');
    TAssert.Fail('1.5 into an Integer must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('expected integer', E.Message) > 0);
  end;
end;

procedure TMapperReadTests.Error_UnknownEnumName;
var
  Dto: IScalarDto;
begin
  try
    Dto := FMapper.FromJson<IScalarDto>('{"cor":"clPink"}');
    TAssert.Fail('Unknown enum name must raise');
  except
    on E: EJsonInputError do
    begin
      TAssert.AssertEquals('$.cor: "clPink" is not an accepted value', E.Message);
      TAssert.AssertEquals('not a value of TColor3', E.Detail);
    end;
  end;
end;

procedure TMapperReadTests.Error_UnregisteredInterface;
var
  Dto: IHasUnmappedDto;
begin
  try
    Dto := FMapper.FromJson<IHasUnmappedDto>('{"other":{}}');
    TAssert.Fail('Unregistered interface must raise');
  except
    // A setup error, not the JSON's fault.
    on E: EJsonMapperError do
    begin
      TAssert.AssertFalse(E.Message, E is EJsonInputError);
      TAssert.AssertTrue(E.Message, Pos('IUnmapped', E.Message) > 0);
    end;
  end;
end;

procedure TMapperReadTests.Error_InvalidJson;
var
  Dto: IScalarDto;
begin
  try
    Dto := FMapper.FromJson<IScalarDto>('{"nome":');
    TAssert.Fail('Invalid JSON must raise');
  except
    on E: EJsonParseError do
      ;
  end;
end;

procedure TMapperReadTests.Error_InsideConverter_HasPath;
var
  Dto: IPatchDto;
begin
  // TOptTextConverter calls AJson.AsString on a number: an EJsonError with
  // no path of its own, which the mapper must locate.
  try
    Dto := FMapper.FromJson<IPatchDto>('{"apelido":5}');
    TAssert.Fail('A number for IOptText must raise');
  except
    on E: EJsonInputError do
    begin
      TAssert.AssertTrue(E.Message, Pos('$.apelido: ', E.Message) = 1);
      TAssert.AssertEquals('$.apelido', E.Path);
      TAssert.AssertEquals('', E.Detail);
    end;
  end;
end;

procedure TMapperReadTests.Error_NumberOutOfRange_HasPath;
var
  Dto: IScalarDto;
begin
  try
    Dto := FMapper.FromJson<IScalarDto>('{"preco":1e309}');
    TAssert.Fail('1e309 into a Double must raise');
  except
    on E: EJsonInputError do
      TAssert.AssertEquals('$.preco: Number 1e309 is out of range', E.Message);
  end;
end;

procedure TMapperReadTests.Error_CurrencyOutOfRange_HasPath;
var
  Dto: IScalarDto;
  Cur: Currency;
begin
  // In 0.4.0, 1e300 raised EInvalidOp, without a path.
  try
    Dto := FMapper.FromJson<IScalarDto>('{"valor":1e300}');
    TAssert.Fail('1e300 into a Currency must raise');
  except
    on E: EJsonInputError do
    begin
      TAssert.AssertEquals('$.valor: Number 1e300 is out of range', E.Message);
      TAssert.AssertEquals('type Currency', E.Detail);
    end;
  end;
  try
    Dto := FMapper.FromJson<IScalarDto>('{"valor":-1e15}');
    TAssert.Fail('-1e15 into a Currency must raise');
  except
    on E: EJsonInputError do
      TAssert.AssertEquals('$.valor: Number -1e15 is out of range', E.Message);
  end;
  // Large values within range (TMapperCurrencyTests goes to the limits),
  // and an exponent.
  Dto := FMapper.FromJson<IScalarDto>('{"valor":900000000000.1234}');
  Cur := Scalar(Dto).Valor;
  TAssert.AssertEquals(Int64(9000000000001234), PInt64(@Cur)^);
  Dto := FMapper.FromJson<IScalarDto>('{"valor":-900000000000.1234}');
  Cur := Scalar(Dto).Valor;
  TAssert.AssertEquals(Int64(-9000000000001234), PInt64(@Cur)^);
  Dto := FMapper.FromJson<IScalarDto>('{"valor":1.5e3}');
  Cur := Scalar(Dto).Valor;
  TAssert.AssertEquals(Int64(15000000), PInt64(@Cur)^);
end;

procedure TMapperReadTests.Error_IsoDate_HasPath;
var
  Dto: IScalarDto;
begin
  try
    Dto := FMapper.FromJson<IScalarDto>('{"nascimento":"2026-13-01"}');
    TAssert.Fail('Month 13 must raise');
  except
    on E: EJsonInputError do
      TAssert.AssertEquals('$.nascimento: Invalid ISO 8601 date/time: "2026-13-01"', E.Message);
  end;
end;

procedure TMapperReadTests.Error_UnsupportedType_IsNotInputError;
var
  R: TPlainRecord;
begin
  try
    R := FMapper.Deserialize<TPlainRecord>('{}');
    TAssert.Fail('A record must raise');
  except
    on E: EJsonMapperError do
    begin
      TAssert.AssertFalse(E.Message, E is EJsonInputError);
      TAssert.AssertTrue(E.Message, Pos('is not supported', E.Message) > 0);
    end;
  end;
end;

procedure TMapperReadTests.ClassProperty_PopulatedInPlace;
var
  P: TPerson;
  Before: TAddress;
begin
  P := TPerson.Create;
  try
    Before := P.Address;
    FMapper.PopulateObject(P, '{"name":"Bia","address":{"street":"Rua A"},"spare":null}');
    TAssert.AssertEquals('Bia', P.Name);
    TAssert.AssertTrue('Same instance', P.Address = Before);
    TAssert.AssertEquals('Rua A', P.Address.Street);
    TAssert.AssertTrue(P.Spare = nil);
  finally
    P.Free;
  end;
end;

procedure TMapperReadTests.ClassProperty_Nil_Raises;
var
  P: TPerson;
begin
  P := TPerson.Create;
  try
    try
      FMapper.PopulateObject(P, '{"spare":{"street":"x"}}');
      TAssert.Fail('A nil class property must raise');
    except
      // The DTO's fault (its constructor), not the JSON's.
      on E: EJsonMapperError do
      begin
        TAssert.AssertFalse(E.Message, E is EJsonInputError);
        TAssert.AssertTrue(E.Message, Pos('$.spare', E.Message) > 0);
      end;
    end;
  finally
    P.Free;
  end;
end;

{ TMapperWriteTests }

procedure TMapperWriteTests.SetUp;
begin
  FMapper := NewTestMapper;
end;

procedure TMapperWriteTests.TearDown;
begin
  FreeAndNil(FMapper);
end;

procedure TMapperWriteTests.Scalars_ExactText_AncestorsFirst;
var
  S: TScalarDto;
  Dto: IScalarDto;
begin
  S := TScalarDto.Create;
  Dto := S;
  S.Id := 9007199254740993;
  S.Nome := 'Ana "A"';
  S.Idade := -30;
  S.Pequeno := 255;
  S.Preco := 0.1;
  S.Fator := 0.1;
  S.Valor := 12.5;
  S.Ativo := True;
  S.Cor := clGreen;
  S.Nascimento := EncodeDateTime(2026, 10, 2, 13, 45, 10, 500);
  S.Dia := EncodeDate(2026, 10, 2);
  S.Hora := EncodeTime(8, 30, 0, 0);
  S.Publica := 99;
  TAssert.AssertEquals(
    '{"id":9007199254740993,"nome":"Ana \"A\"","idade":-30,"pequeno":255,' +
    '"preco":0.1,"fator":0.1,"valor":12.5,"ativo":true,"cor":"clGreen",' +
    '"nascimento":"2026-10-02T13:45:10.500","dia":"2026-10-02",' +
    '"hora":"08:30:00","padrao":42,"somenteLeitura":"ro"}',
    FMapper.ToJson<IScalarDto>(Dto));
end;

procedure TMapperWriteTests.Naming_AsDeclared;
var
  Dto: IOrderDto;
begin
  FMapper.Naming := jnAsDeclared;
  Dto := TOrderDto.Create;
  TAssert.AssertEquals('{"Item":null,"Itens":[],"Numeros":[],"Tags":[]}',
    FMapper.ToJson<IOrderDto>(Dto));
end;

procedure TMapperWriteTests.Nested_InterfaceAndArrays;
var
  O: TOrderDto;
  Dto: IOrderDto;
  Itens: TItemArray;
  Item: TItem;
begin
  O := TOrderDto.Create;
  Dto := O;
  Item := TItem.Create;
  Item.Code := 7;
  O.Item := Item;
  SetLength(Itens, 2);
  Item := TItem.Create;
  Item.Code := 1;
  Itens[0] := Item;
  O.Itens := Itens;
  O.Numeros := TIntArray.Create(3, 4);
  O.Tags := TStrArray.Create('a');
  TAssert.AssertEquals(
    '{"item":{"code":7},"itens":[{"code":1},null],"numeros":[3,4],"tags":["a"]}',
    FMapper.ToJson<IOrderDto>(Dto));
end;

procedure TMapperWriteTests.NilInterface_IsNull_NilArray_IsEmpty;
var
  Dto: IOrderDto;
begin
  Dto := TOrderDto.Create;
  TAssert.AssertEquals('{"item":null,"itens":[],"numeros":[],"tags":[]}',
    FMapper.ToJson<IOrderDto>(Dto));
  Dto := nil;
  TAssert.AssertEquals('null', FMapper.ToJson<IOrderDto>(Dto));
end;

procedure TMapperWriteTests.PlainObject_WithClassProperties;
var
  P: TPerson;
begin
  P := TPerson.Create;
  try
    P.Name := 'Bia';
    P.Address.Street := 'Rua A';
    TAssert.AssertEquals('{"name":"Bia","address":{"street":"Rua A"},"spare":null}',
      FMapper.ObjectToJson(P));
  finally
    P.Free;
  end;
end;

procedure TMapperWriteTests.RoundTrip_PreservesEverything;
const
  Json = '{"item":{"code":7},"itens":[{"code":1},null,{"code":3}],' +
    '"numeros":[-1,0,2147483647],"tags":["x","","\"q\""]}';
var
  Dto: IOrderDto;
begin
  Dto := FMapper.FromJson<IOrderDto>(Json);
  TAssert.AssertEquals(Json, FMapper.ToJson<IOrderDto>(Dto));
end;

procedure TMapperWriteTests.Error_NaN_HasPath;
var
  S: TScalarDto;
  Dto: IScalarDto;
begin
  S := TScalarDto.Create;
  Dto := S;
  S.Preco := NaN;
  try
    FMapper.ToJson<IScalarDto>(Dto);
    TAssert.Fail('NaN must raise');
  except
    // Writing: the value came from the program, not from a JSON text.
    on E: EJsonMapperError do
    begin
      TAssert.AssertFalse(E.Message, E is EJsonInputError);
      TAssert.AssertTrue(E.Message, Pos('$.preco:', E.Message) = 1);
    end;
  end;
end;

{ TMapperTopLevelTests }

procedure TMapperTopLevelTests.SetUp;
begin
  FMapper := NewTestMapper;
end;

procedure TMapperTopLevelTests.TearDown;
begin
  FreeAndNil(FMapper);
end;

function NewItem(ACode: Integer): IItem;
var
  Item: TItem;
begin
  Item := TItem.Create;
  Item.Code := ACode;
  Result := Item;
end;

procedure TMapperTopLevelTests.Serialize_ArrayOfInterfaces;
var
  Items: TItemArray;
begin
  SetLength(Items, 3);
  Items[0] := NewItem(1);
  Items[1] := NewItem(2);
  TAssert.AssertEquals('[{"code":1},{"code":2},null]', FMapper.Serialize<TItemArray>(Items));
  Items := nil;
  TAssert.AssertEquals('[]', FMapper.Serialize<TItemArray>(Items));
end;

procedure TMapperTopLevelTests.Deserialize_ArrayOfInterfaces;
var
  Items: TItemArray;
begin
  Items := FMapper.Deserialize<TItemArray>('[{"code":5},null,{"code":-1}]');
  TAssert.AssertEquals(3, Integer(Length(Items)));
  TAssert.AssertEquals(5, Items[0].GetCode);
  TAssert.AssertTrue(Items[1] = nil);
  TAssert.AssertEquals(-1, Items[2].GetCode);
end;

procedure TMapperTopLevelTests.Deserialize_ArraysOfScalars;
var
  Ints: TIntArray;
  Strs: TStrArray;
begin
  Ints := FMapper.Deserialize<TIntArray>('[1, 2, 3]');
  TAssert.AssertEquals(3, Integer(Length(Ints)));
  TAssert.AssertEquals(3, Ints[2]);
  Strs := FMapper.Deserialize<TStrArray>('["a", "' + U([$E7]) + '"]');
  TAssert.AssertEquals(2, Integer(Length(Strs)));
  TAssert.AssertEquals(U([$E7]), Strs[1]);
  TAssert.AssertEquals('["a","' + U([$E7]) + '"]', FMapper.Serialize<TStrArray>(Strs));
end;

procedure TMapperTopLevelTests.Deserialize_Null_IsDefault;
var
  Items: TItemArray;
  Item: IItem;
begin
  Items := FMapper.Deserialize<TItemArray>('null');
  TAssert.AssertEquals(0, Integer(Length(Items)));
  Item := FMapper.Deserialize<IItem>('null');
  TAssert.AssertTrue(Item = nil);
  TAssert.AssertEquals(0, FMapper.Deserialize<Integer>('null'));
end;

procedure TMapperTopLevelTests.Scalars_AtTopLevel;
var
  Item: IItem;
begin
  TAssert.AssertEquals(42, FMapper.Deserialize<Integer>('42'));
  TAssert.AssertEquals('x', FMapper.Deserialize<string>('"x"'));
  TAssert.AssertEquals('5', FMapper.Serialize<Integer>(5));
  TAssert.AssertEquals('"x"', FMapper.Serialize<string>('x'));
  Item := FMapper.Deserialize<IItem>('{"code":9}');
  TAssert.AssertEquals(9, Item.GetCode);
  TAssert.AssertEquals('{"code":9}', FMapper.Serialize<IItem>(Item));
end;

procedure TMapperTopLevelTests.Deserialize_Errors_HavePath;
var
  Items: TItemArray;
  Ints: TIntArray;
begin
  try
    Items := FMapper.Deserialize<TItemArray>('[{"code":1},{"code":"x"}]');
    TAssert.Fail('Must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$[1].code:', E.Message) = 1);
  end;
  try
    Ints := FMapper.Deserialize<TIntArray>('{"a":1}');
    TAssert.Fail('An object for an array must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$: expected array', E.Message) = 1);
  end;
end;

procedure TMapperTopLevelTests.Indent_MapperOutput;
var
  O: TOrderDto;
  Dto: IOrderDto;
begin
  O := TOrderDto.Create;
  Dto := O;
  O.Item := NewItem(7);
  O.Numeros := TIntArray.Create(1, 2);
  FMapper.Indent := 2;
  TAssert.AssertEquals('{'#10 +
    '  "item": {'#10 +
    '    "code": 7'#10 +
    '  },'#10 +
    '  "itens": [],'#10 +
    '  "numeros": ['#10 +
    '    1,'#10 +
    '    2'#10 +
    '  ],'#10 +
    '  "tags": []'#10 +
    '}', FMapper.ToJson<IOrderDto>(Dto));
end;

procedure TMapperTopLevelTests.Indent_RoundTrip;
const
  Json = '[{"code":1},null,{"code":3}]';
var
  Items: TItemArray;
  Pretty: string;
begin
  Items := FMapper.Deserialize<TItemArray>(Json);
  FMapper.Indent := 3;
  Pretty := FMapper.Serialize<TItemArray>(Items);
  TAssert.AssertTrue(Pretty <> Json);
  Items := FMapper.Deserialize<TItemArray>(Pretty);
  FMapper.Indent := 0;
  TAssert.AssertEquals(Json, FMapper.Serialize<TItemArray>(Items));
end;

{ TMapperConverterTests }

procedure TMapperConverterTests.SetUp;
begin
  FMapper := NewTestMapper;
end;

procedure TMapperConverterTests.TearDown;
begin
  FreeAndNil(FMapper);
end;

procedure TMapperConverterTests.Read_ThreeStates;
var
  Dto: IPatchDto;
begin
  Dto := FMapper.FromJson<IPatchDto>('{"nome":"a"}');
  TAssert.AssertTrue('Absent: property untouched', Patch(Dto).Apelido = nil);

  Dto := FMapper.FromJson<IPatchDto>('{"apelido":null}');
  TAssert.AssertTrue(Patch(Dto).Apelido.HasValue);
  TAssert.AssertTrue(Patch(Dto).Apelido.IsNull);

  Dto := FMapper.FromJson<IPatchDto>('{"apelido":"Zeca"}');
  TAssert.AssertTrue(Patch(Dto).Apelido.HasValue);
  TAssert.AssertFalse(Patch(Dto).Apelido.IsNull);
  TAssert.AssertEquals('Zeca', Patch(Dto).Apelido.GetValue);
end;

procedure TMapperConverterTests.Write_ThreeStates;
var
  P: TPatchDto;
  Dto: IPatchDto;
begin
  P := TPatchDto.Create;
  Dto := P;
  P.Nome := 'a';
  TAssert.AssertEquals('nil: omitted', '{"nome":"a"}', FMapper.ToJson<IPatchDto>(Dto));
  P.Apelido := TOptText.Undefined;
  TAssert.AssertEquals('Undefined: omitted', '{"nome":"a"}', FMapper.ToJson<IPatchDto>(Dto));
  P.Apelido := TOptText.Null;
  TAssert.AssertEquals('{"nome":"a","apelido":null}', FMapper.ToJson<IPatchDto>(Dto));
  P.Apelido := TOptText.From('Zeca');
  TAssert.AssertEquals('{"nome":"a","apelido":"Zeca"}', FMapper.ToJson<IPatchDto>(Dto));
end;

procedure TMapperConverterTests.LastRegistered_Wins;
var
  Dto: IPatchDto;
begin
  FMapper.RegisterConverter(TConstantConverter.Create);
  Dto := FMapper.FromJson<IPatchDto>('{"apelido":"x"}');
  TAssert.AssertEquals('constant', Patch(Dto).Apelido.GetValue);
  TAssert.AssertEquals('{"nome":"","apelido":"constant"}', FMapper.ToJson<IPatchDto>(Dto));
end;

{ TMapperCurrencyTests }

procedure TMapperCurrencyTests.SetUp;
begin
  FMapper := NewTestMapper;
end;

procedure TMapperCurrencyTests.TearDown;
begin
  FreeAndNil(FMapper);
end;

procedure TMapperCurrencyTests.AssertAll(ADto: TCurrencyDto; AUnits: Int64);
begin
  TAssert.AssertEquals('campo', AUnits, UnitsOf(ADto.Campo));
  TAssert.AssertEquals('metodo', AUnits, UnitsOf(ADto.Metodo));
  TAssert.AssertEquals('virt', AUnits, UnitsOf(ADto.Virt));
  TAssert.AssertEquals('indexado', AUnits, UnitsOf(ADto.Indexado));
  TAssert.AssertEquals('misto', AUnits, UnitsOf(ADto.Misto));
  TAssert.AssertEquals('preco', AUnits, UnitsOf(ADto.PrecoValue));
end;

procedure TMapperCurrencyTests.RoundTrip_EveryAccessKind_ToTheLimits;
const
  // Until 0.5.0, on FPC Win64 the large ones lost digits and the top ones
  // raised EInvalidOp, writing and reading.
  Cases: array[0..8] of Int64 = (High(Int64), High(Int64) - 1, Low(Int64),
    Low(Int64) + 1, 9007199254740993, 1234567890123456789, -1234567890123456789,
    -1, 0);
var
  Src, Dst: TCurrencyDto;
  I: Integer;
  Text, Json: string;
begin
  for I := 0 to High(Cases) do
  begin
    Src := TCurrencyDto.Create;
    Dst := TCurrencyDto.Create;
    try
      Src.SetAll(CurrOf(Cases[I]));
      Text := JsonCurrencyToStr(CurrOf(Cases[I]));
      Json := FMapper.ObjectToJson(Src);
      TAssert.AssertEquals('{"campo":' + Text + ',"metodo":' + Text + ',"virt":' + Text +
        ',"indexado":' + Text + ',"misto":' + Text + ',"preco":' + Text + '}', Json);
      FMapper.PopulateObject(Dst, Json);
      AssertAll(Dst, Cases[I]);
    finally
      Src.Free;
      Dst.Free;
    end;
  end;
  // The limits as text, not only as JsonCurrencyToStr writes them.
  Dst := TCurrencyDto.Create;
  try
    FMapper.PopulateObject(Dst, '{"campo":922337203685477.5807,"metodo":922337203685477.5807,' +
      '"virt":922337203685477.5807,"indexado":922337203685477.5807,' +
      '"misto":922337203685477.5807,"preco":922337203685477.5807}');
    AssertAll(Dst, High(Int64));
    FMapper.PopulateObject(Dst, '{"campo":-922337203685477.5808,"metodo":-922337203685477.5808,' +
      '"virt":-922337203685477.5808,"indexado":-922337203685477.5808,' +
      '"misto":-922337203685477.5808,"preco":-922337203685477.5808}');
    AssertAll(Dst, Low(Int64));
  finally
    Dst.Free;
  end;
end;

procedure TMapperCurrencyTests.VirtualAccessors_AreTheOverrides;
var
  Dto: TCurrencyChildDto;
begin
  Dto := TCurrencyChildDto.Create;
  try
    Dto.SetAll(CurrOf(5));
    Dto.VirtReads := 0;
    Dto.VirtWrites := 0;
    TAssert.AssertEquals('{"campo":0.0005,"metodo":0.0005,"virt":0.0005,"indexado":0.0005,' +
      '"misto":0.0005,"preco":0.0005}', FMapper.ObjectToJson(Dto));
    TAssert.AssertEquals(1, Dto.VirtReads);
    FMapper.PopulateObject(Dto, '{"virt":12.5}');
    TAssert.AssertEquals(1, Dto.VirtWrites);
    TAssert.AssertEquals(Int64(125000), UnitsOf(Dto.Virt));
  finally
    Dto.Free;
  end;
end;

procedure TMapperCurrencyTests.RoundTrip_EveryAccessKind_Random;
var
  Src, Dst: TCurrencyDto;
  State: UInt64;
  I: Integer;
  Units: Int64;
begin
  Src := TCurrencyDto.Create;
  Dst := TCurrencyDto.Create;
  try
    State := 88172645463325252;
    for I := 1 to 5000 do
    begin
      Units := RandomCurrencyUnits(State);
      Src.SetAll(CurrOf(Units));
      FMapper.PopulateObject(Dst, FMapper.ObjectToJson(Src));
      AssertAll(Dst, Units);
    end;
  finally
    Src.Free;
    Dst.Free;
  end;
end;

procedure TMapperCurrencyTests.Read_HalfEven_AndExponent;
var
  Dto: TCurrencyDto;
begin
  Dto := TCurrencyDto.Create;
  try
    FMapper.PopulateObject(Dto, '{"campo":0.00025,"metodo":0.00035,"virt":1.5e3,' +
      '"indexado":-0.00005,"misto":0.000049999,"preco":1e-4}');
    TAssert.AssertEquals(Int64(2), UnitsOf(Dto.Campo));
    TAssert.AssertEquals(Int64(4), UnitsOf(Dto.Metodo));
    TAssert.AssertEquals(Int64(15000000), UnitsOf(Dto.Virt));
    TAssert.AssertEquals(Int64(0), UnitsOf(Dto.Indexado));
    TAssert.AssertEquals(Int64(0), UnitsOf(Dto.Misto));
    TAssert.AssertEquals(Int64(1), UnitsOf(Dto.PrecoValue));
  finally
    Dto.Free;
  end;
end;

procedure TMapperCurrencyTests.TopLevel_AndArrays_ToTheLimits;
var
  Arr: TCurrArray;
  C: Currency;
begin
  SetLength(Arr, 3);
  Arr[0] := CurrOf(High(Int64));
  Arr[1] := CurrOf(Low(Int64));
  Arr[2] := CurrOf(-1);
  TAssert.AssertEquals('[922337203685477.5807,-922337203685477.5808,-0.0001]',
    FMapper.Serialize<TCurrArray>(Arr));
  Arr := FMapper.Deserialize<TCurrArray>('[922337203685477.5807,-922337203685477.5808,0.00015]');
  TAssert.AssertEquals(3, Length(Arr));
  TAssert.AssertEquals(High(Int64), UnitsOf(Arr[0]));
  TAssert.AssertEquals(Low(Int64), UnitsOf(Arr[1]));
  TAssert.AssertEquals(Int64(2), UnitsOf(Arr[2]));
  C := CurrOf(High(Int64));
  TAssert.AssertEquals('922337203685477.5807', FMapper.Serialize<Currency>(C));
  C := FMapper.Deserialize<Currency>('-922337203685477.5808');
  TAssert.AssertEquals(Low(Int64), UnitsOf(C));
end;

{ TMapperRegistrationTests }

procedure TMapperRegistrationTests.FindImplClass;
var
  M: TJsonMapper;
begin
  M := NewTestMapper;
  try
    TAssert.AssertTrue(M.FindImplClass(TypeInfo(IScalarDto)) = TScalarDto);
    TAssert.AssertTrue(M.FindImplClass(TypeInfo(IUnmapped)) = nil);
  finally
    M.Free;
  end;
end;

procedure TMapperRegistrationTests.ClassNotImplementingInterface_Raises;
var
  M: TJsonMapper;
begin
  M := TJsonMapper.Create;
  try
    try
      M.RegisterMapping<IScalarDto, TOrderDto>;
      TAssert.Fail('Registering a class that does not implement the interface must raise');
    except
      on E: EJsonMapperError do
        TAssert.AssertTrue(E.Message, Pos('TOrderDto', E.Message) > 0);
    end;
  finally
    M.Free;
  end;
end;

procedure TMapperRegistrationTests.Shared_IsAvailable;
begin
  TAssert.AssertTrue(TJsonMapper.Shared <> nil);
end;

initialization
  TDUnitX.RegisterTestFixture(TMapperReadTests);
  TDUnitX.RegisterTestFixture(TMapperWriteTests);
  TDUnitX.RegisterTestFixture(TMapperTopLevelTests);
  TDUnitX.RegisterTestFixture(TMapperConverterTests);
  TDUnitX.RegisterTestFixture(TMapperCurrencyTests);
  TDUnitX.RegisterTestFixture(TMapperRegistrationTests);

end.
