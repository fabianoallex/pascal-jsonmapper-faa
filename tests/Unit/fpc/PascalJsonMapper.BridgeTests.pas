unit PascalJsonMapper.BridgeTests;

{$mode delphi}{$H+}

{ GENERATED FILE — produced by tools/gen_fpc_mirror.py from
  tests/Unit/PascalJsonMapper.BridgeTests.pas (DUnitX). Do not edit by hand: edit the DUnitX
  master and run the script again. }

{ Tests for a converter shipped by another library, the way pascal-common-faa
  ships one for its optionals: PascalJsonMapper.TestOptionals plays the
  library (same shape and GUIDs as PascalCommon.Optionals, no mapper
  dependency) and PascalJsonMapper.TestOptionalsBridge the bridge unit,
  which registers itself on TJsonMapper.Shared at initialization. The DTO
  below registers itself on Shared the same way, so these tests go through
  Shared only, as an application would.

  Covered: one converter for several interfaces (Opt/Null/OptNull x
  string/Integer), each flavor's absent/null/value rules both ways, arrays
  of optionals (omitted element -> null), errors raised inside the converter
  or inside the value it delegates carrying the JSON path, and the core
  knowing nothing about the types until the bridge is registered.

  DUnitX master, written in FPCUnit's assertion dialect (TAssert.*, through
  PascalJsonMapper.DUnitXCompat). The mirror in tests/Unit/fpc is generated
  from the master by tools/gen_fpc_mirror.py — edit only the master. }

interface

uses
  fpcunit, testregistry,
  SysUtils,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper,
  PascalJsonMapper.TestOptionals,
  PascalJsonMapper.TestOptionalsBridge;

type
  IBridgeDto = interface
    ['{C1AC054D-6033-4A6C-9B17-909F8735E6C8}']
  end;

  TOptNullIntegerArray = array of IOptNullInteger;

{$M+}
  TBridgeDto = class(TInterfacedObject, IBridgeDto)
  private
    FApelido: IOptString;
    FTelefone: INullString;
    FObs: IOptNullString;
    FIdade: IOptInteger;
    FPontos: INullInteger;
    FNivel: IOptNullInteger;
    FNotas: TOptNullIntegerArray;
  published
    property Apelido: IOptString read FApelido write FApelido;
    property Telefone: INullString read FTelefone write FTelefone;
    property Obs: IOptNullString read FObs write FObs;
    property Idade: IOptInteger read FIdade write FIdade;
    property Pontos: INullInteger read FPontos write FPontos;
    property Nivel: IOptNullInteger read FNivel write FNivel;
    property Notas: TOptNullIntegerArray read FNotas write FNotas;
  end;
{$M-}

  TBridgeTests = class(TTestCase)
  private
    function Read(const AJson: string): IBridgeDto;
    procedure AssertReadFails(const AJson, AExpectedPath: string);
  published
    procedure Read_Values;
    procedure Read_Nulls;
    procedure Read_Absent_LeavesNil;
    procedure Read_NullIntoOptionalOnly_RaisesWithPath;
    procedure Read_WrongValueType_RaisesWithPath;
    procedure Write_NeverSet;
    procedure Write_EachFlavorAndState;
    procedure Write_NullInOptionalOnly_IsNull;
    procedure Array_ReadElements;
    procedure Array_OmittedElementIsNull;
    procedure RoundTrip;
    procedure Core_KnowsNothingUntilBridgeRegistered;
  end;

implementation

{ TBridgeTests }

function TBridgeTests.Read(const AJson: string): IBridgeDto;
begin
  Result := TJsonMapper.Shared.FromJson<IBridgeDto>(AJson);
end;

procedure TBridgeTests.AssertReadFails(const AJson, AExpectedPath: string);
var
  Dto: IBridgeDto;
begin
  try
    Dto := TJsonMapper.Shared.FromJson<IBridgeDto>(AJson);
    TAssert.Fail('Must raise: ' + AJson);
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue('Message "' + E.Message + '" must start with "' +
        AExpectedPath + ':"', Pos(AExpectedPath + ':', E.Message) = 1);
  end;
end;

procedure TBridgeTests.Read_Values;
var
  Dto: IBridgeDto;
  D: TBridgeDto;
begin
  Dto := Read('{"apelido":"Zeca","telefone":"5551","obs":"x","idade":30,"pontos":7,"nivel":2}');
  D := Dto as TBridgeDto;
  TAssert.AssertTrue(D.Apelido.HasValue);
  TAssert.AssertEquals('Zeca', D.Apelido.Value);
  TAssert.AssertFalse(D.Telefone.IsNull);
  TAssert.AssertEquals('5551', D.Telefone.Value);
  TAssert.AssertTrue(D.Obs.HasValue and not D.Obs.IsNull);
  TAssert.AssertEquals('x', D.Obs.Value);
  TAssert.AssertEquals(30, D.Idade.Value);
  TAssert.AssertEquals(7, D.Pontos.Value);
  TAssert.AssertEquals(2, D.Nivel.Value);
end;

procedure TBridgeTests.Read_Nulls;
var
  Dto: IBridgeDto;
  D: TBridgeDto;
begin
  Dto := Read('{"telefone":null,"obs":null,"pontos":null,"nivel":null}');
  D := Dto as TBridgeDto;
  TAssert.AssertTrue(D.Telefone.IsNull);
  TAssert.AssertTrue(D.Obs.HasValue);
  TAssert.AssertTrue(D.Obs.IsNull);
  TAssert.AssertTrue(D.Pontos.IsNull);
  TAssert.AssertTrue(D.Nivel.HasValue);
  TAssert.AssertTrue(D.Nivel.IsNull);
end;

procedure TBridgeTests.Read_Absent_LeavesNil;
var
  Dto: IBridgeDto;
  D: TBridgeDto;
begin
  Dto := Read('{}');
  D := Dto as TBridgeDto;
  // Absent members never reach the converter: the DTO's own default
  // (nil here; TOptionals.Safe in a DTO getter over pascal-common-faa) stands.
  TAssert.AssertTrue(D.Apelido = nil);
  TAssert.AssertTrue(D.Telefone = nil);
  TAssert.AssertTrue(D.Obs = nil);
  TAssert.AssertTrue(D.Nivel = nil);
  TAssert.AssertEquals(0, Integer(Length(D.Notas)));
end;

procedure TBridgeTests.Read_NullIntoOptionalOnly_RaisesWithPath;
begin
  // Raised by the converter itself (EJsonError), path added by the mapper.
  AssertReadFails('{"apelido":null}', '$.apelido');
  AssertReadFails('{"idade":null}', '$.idade');
end;

procedure TBridgeTests.Read_WrongValueType_RaisesWithPath;
begin
  // Raised by the mapper's own rules, reached through the converter.
  AssertReadFails('{"idade":"x"}', '$.idade');
  AssertReadFails('{"telefone":5}', '$.telefone');
  AssertReadFails('{"nivel":2147483648}', '$.nivel');
  AssertReadFails('{"notas":[1,2,"x"]}', '$.notas[2]');
end;

procedure TBridgeTests.Write_NeverSet;
var
  Dto: IBridgeDto;
begin
  // nil: Opt flavors omitted, INullXxx written as null, empty array.
  Dto := TBridgeDto.Create;
  TAssert.AssertEquals('{"telefone":null,"pontos":null,"notas":[]}',
    TJsonMapper.Shared.ToJson<IBridgeDto>(Dto));
end;

procedure TBridgeTests.Write_EachFlavorAndState;
var
  D: TBridgeDto;
  Dto: IBridgeDto;
begin
  D := TBridgeDto.Create;
  Dto := D;
  D.Apelido := TOptNullString.Undefined;
  D.Telefone := TOptNullString.Null;
  D.Obs := TOptNullString.Null;
  D.Idade := TOptNullInteger.From(30);
  D.Pontos := TOptNullInteger.From(-5);
  D.Nivel := TOptNullInteger.Undefined;
  TAssert.AssertEquals('{"telefone":null,"obs":null,"idade":30,"pontos":-5,"notas":[]}',
    TJsonMapper.Shared.ToJson<IBridgeDto>(Dto));

  D.Apelido := TOptNullString.From('Zeca');
  D.Telefone := TOptNullString.From('5551');
  D.Obs := TOptNullString.Undefined;
  D.Nivel := TOptNullInteger.Null;
  TAssert.AssertEquals(
    '{"apelido":"Zeca","telefone":"5551","idade":30,"pontos":-5,"nivel":null,"notas":[]}',
    TJsonMapper.Shared.ToJson<IBridgeDto>(Dto));
end;

procedure TBridgeTests.Write_NullInOptionalOnly_IsNull;
var
  D: TBridgeDto;
  Dto: IBridgeDto;
begin
  // TOptNullString.Null compiles into an IOptString; its Value ('') is
  // made up, so it goes out as null rather than as an empty string.
  D := TBridgeDto.Create;
  Dto := D;
  D.Apelido := TOptNullString.Null;
  D.Idade := TOptNullInteger.Null;
  TAssert.AssertEquals('{"apelido":null,"telefone":null,"idade":null,"pontos":null,"notas":[]}',
    TJsonMapper.Shared.ToJson<IBridgeDto>(Dto));
end;

procedure TBridgeTests.Array_ReadElements;
var
  Dto: IBridgeDto;
  D: TBridgeDto;
begin
  Dto := Read('{"notas":[1,null,3]}');
  D := Dto as TBridgeDto;
  TAssert.AssertEquals(3, Integer(Length(D.Notas)));
  TAssert.AssertEquals(1, D.Notas[0].Value);
  TAssert.AssertTrue(D.Notas[1].HasValue);
  TAssert.AssertTrue(D.Notas[1].IsNull);
  TAssert.AssertEquals(3, D.Notas[2].Value);
end;

procedure TBridgeTests.Array_OmittedElementIsNull;
var
  D: TBridgeDto;
  Dto: IBridgeDto;
  Notas: TOptNullIntegerArray;
begin
  D := TBridgeDto.Create;
  Dto := D;
  SetLength(Notas, 4);
  Notas[0] := TOptNullInteger.From(1);
  Notas[1] := TOptNullInteger.Null;
  Notas[2] := TOptNullInteger.Undefined;
  Notas[3] := nil;
  D.Notas := Notas;
  TAssert.AssertEquals('{"telefone":null,"pontos":null,"notas":[1,null,null,null]}',
    TJsonMapper.Shared.ToJson<IBridgeDto>(Dto));
end;

procedure TBridgeTests.RoundTrip;
const
  Json = '{"apelido":"' + 'A\"b' + '","telefone":null,"obs":"","idade":0,' +
    '"pontos":2147483647,"nivel":-2147483648,"notas":[null,0]}';
var
  Dto: IBridgeDto;
begin
  Dto := TJsonMapper.Shared.FromJson<IBridgeDto>(Json);
  TAssert.AssertEquals(Json, TJsonMapper.Shared.ToJson<IBridgeDto>(Dto));
end;

procedure TBridgeTests.Core_KnowsNothingUntilBridgeRegistered;
var
  M: TJsonMapper;
  Dto: IBridgeDto;
begin
  M := TJsonMapper.Create;
  try
    M.RegisterMapping<IBridgeDto, TBridgeDto>;
    try
      Dto := M.FromJson<IBridgeDto>('{"idade":1}');
      TAssert.Fail('Without the bridge an optional is an unmapped interface');
    except
      on E: EJsonMapperError do
        TAssert.AssertTrue(E.Message, Pos('IOptInteger', E.Message) > 0);
    end;
    RegisterOptionalsConverter(M);
    Dto := M.FromJson<IBridgeDto>('{"idade":1}');
    TAssert.AssertEquals(1, (Dto as TBridgeDto).Idade.Value);
  finally
    Dto := nil;
    M.Free;
  end;
end;

initialization
  // The DTO-unit convention: register on the shared mapper at startup.
  TJsonMapper.Shared.RegisterMapping<IBridgeDto, TBridgeDto>;
  RegisterTest(TBridgeTests);

end.
