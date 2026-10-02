unit PascalJsonMapper.MapperTests;

{$mode delphi}{$H+}

{ GENERATED FILE — produced by tools/gen_fpc_mirror.py from
  tests/Unit/PascalJsonMapper.MapperTests.pas (DUnitX). Do not edit by hand: edit the DUnitX
  master and run the script again. }

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
  fpcunit, testregistry,
  SysUtils,
  DateUtils,
  Math,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper,
  PascalJsonMapper.TestTypes;

type
  TMapperReadTests = class(TTestCase)
  private
    FMapper: TJsonMapper;
    procedure AssertMapperError(const AJson, AExpectedInMessage: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Scalars_AllKinds;
    procedure Constructor_OfDto_Runs;
    procedure Names_AreCaseInsensitive_UnknownIgnored;
    procedure PublicProperty_IsIgnored;
    procedure ReadOnlyProperty_IsIgnored;
    procedure Null_IntoScalar_KeepsValue;
    procedure Nested_InterfaceAndArrays;
    procedure Null_IntoInterfaceAndArray;
    procedure Unicode_Text;
    procedure Error_TypeMismatch_HasPath;
    procedure Error_OutOfRange;
    procedure Error_UnknownEnumName;
    procedure Error_UnregisteredInterface;
    procedure Error_InvalidJson;
    procedure Error_InsideConverter_HasPath;
    procedure Error_NumberOutOfRange_HasPath;
    procedure ClassProperty_PopulatedInPlace;
    procedure ClassProperty_Nil_Raises;
  end;

  TMapperWriteTests = class(TTestCase)
  private
    FMapper: TJsonMapper;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Scalars_ExactText_AncestorsFirst;
    procedure Naming_AsDeclared;
    procedure Nested_InterfaceAndArrays;
    procedure NilInterface_IsNull_NilArray_IsEmpty;
    procedure PlainObject_WithClassProperties;
    procedure RoundTrip_PreservesEverything;
    procedure Error_NaN_HasPath;
  end;

  TMapperConverterTests = class(TTestCase)
  private
    FMapper: TJsonMapper;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Read_ThreeStates;
    procedure Write_ThreeStates;
    procedure LastRegistered_Wins;
  end;

  TMapperRegistrationTests = class(TTestCase)
  published
    procedure FindImplClass;
    procedure ClassNotImplementingInterface_Raises;
    procedure Shared_IsAvailable;
  end;

implementation

uses
  TypInfo, Rtti;

type
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
    on E: EJsonMapperError do
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
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('out of range', E.Message) > 0);
  end;
  try
    Dto := FMapper.FromJson<IScalarDto>('{"idade":2147483648}');
    TAssert.Fail('2^31 into an Integer must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('out of range', E.Message) > 0);
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
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('clPink', E.Message) > 0);
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
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('IUnmapped', E.Message) > 0);
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
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$.apelido:', E.Message) = 1);
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
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$.preco:', E.Message) = 1);
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
      on E: EJsonMapperError do
        TAssert.AssertTrue(E.Message, Pos('$.spare', E.Message) > 0);
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
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$.preco:', E.Message) = 1);
  end;
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
  RegisterTest(TMapperReadTests);
  RegisterTest(TMapperWriteTests);
  RegisterTest(TMapperConverterTests);
  RegisterTest(TMapperRegistrationTests);

end.
