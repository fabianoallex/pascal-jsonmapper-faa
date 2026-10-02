unit PascalJsonMapper.TestTypes;

{ DTOs and a sample converter shared by the DUnitX masters and their FPCUnit
  mirrors. Framework-free, so the same file compiles in both suites.

  TOptTextConverter is the shape a "bridge" converter takes: the library
  that owns a type (here, an optional modeled like PascalDb.Optionals'
  IOptString, derived from a generic interface) teaches the mapper its
  three states — absent (member omitted), null, value — without the mapper
  core knowing the type. }

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils, TypInfo, Rtti,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper;

type
  TColor3 = (clRed, clGreen, clBlue);

  IItem = interface
    ['{0E7B6C1A-5D44-4C1B-8E2F-1A9B3C4D5E61}']
    function GetCode: Integer;
  end;

  IScalarDto = interface
    ['{2B8D7E3F-6A15-4F2C-9D30-2B0C4D5E6F72}']
  end;

  IOrderDto = interface
    ['{3C9E8F40-7B26-4A3D-8E41-3C1D5E6F7083}']
  end;

  IUnmapped = interface
    ['{4DAF9051-8C37-4B4E-9F52-4D2E6F708194}']
  end;

  IHasUnmappedDto = interface
    ['{5EB0A162-9D48-4C5F-A063-5E3F708192A5}']
  end;

  IOptionalBase = interface
    ['{6FC1B273-AE59-4D60-B174-6F40819203B6}']
    function HasValue: Boolean;
    function IsNull: Boolean;
  end;

  IOptional<T> = interface(IOptionalBase)
    ['{70D2C384-BF6A-4E71-8285-705192A314C7}']
    function GetValue: T;
  end;

  IOptText = interface(IOptional<string>)
    ['{81E3D495-C07B-4F82-9396-8162A3B425D8}']
  end;

  IPatchDto = interface
    ['{92F4E5A6-D18C-4093-A4A7-9273B4C536E9}']
  end;

  TItemArray = array of IItem;
  TIntArray = array of Integer;
  TStrArray = array of string;

{$M+}
  TItem = class(TInterfacedObject, IItem)
  private
    FCode: Integer;
  public
    function GetCode: Integer;
  published
    property Code: Integer read FCode write FCode;
  end;

  TBaseDto = class(TInterfacedObject)
  private
    FId: Int64;
  published
    property Id: Int64 read FId write FId;
  end;

  TScalarDto = class(TBaseDto, IScalarDto)
  private
    FNome: string;
    FIdade: Integer;
    FPequeno: Byte;
    FPreco: Double;
    FFator: Single;
    FValor: Currency;
    FAtivo: Boolean;
    FCor: TColor3;
    FNascimento: TDateTime;
    FDia: TDate;
    FHora: TTime;
    FPadrao: Integer;
    FSomenteLeitura: string;
    FPublica: Integer;
  public
    constructor Create;
    // Public, not published: invisible to the mapper on both compilers.
    property Publica: Integer read FPublica write FPublica;
  published
    property Nome: string read FNome write FNome;
    property Idade: Integer read FIdade write FIdade;
    property Pequeno: Byte read FPequeno write FPequeno;
    property Preco: Double read FPreco write FPreco;
    property Fator: Single read FFator write FFator;
    property Valor: Currency read FValor write FValor;
    property Ativo: Boolean read FAtivo write FAtivo;
    property Cor: TColor3 read FCor write FCor;
    property Nascimento: TDateTime read FNascimento write FNascimento;
    property Dia: TDate read FDia write FDia;
    property Hora: TTime read FHora write FHora;
    // Set by the constructor: proves the DTO's own constructor runs.
    property Padrao: Integer read FPadrao write FPadrao;
    property SomenteLeitura: string read FSomenteLeitura;
  end;

  TOrderDto = class(TInterfacedObject, IOrderDto)
  private
    FItem: IItem;
    FItens: TItemArray;
    FNumeros: TIntArray;
    FTags: TStrArray;
  published
    property Item: IItem read FItem write FItem;
    property Itens: TItemArray read FItens write FItens;
    property Numeros: TIntArray read FNumeros write FNumeros;
    property Tags: TStrArray read FTags write FTags;
  end;

  THasUnmappedDto = class(TInterfacedObject, IHasUnmappedDto)
  private
    FOther: IUnmapped;
  published
    property Other: IUnmapped read FOther write FOther;
  end;

  // Plain (non-interface) classes: the owner creates and frees children.
  TAddress = class
  private
    FStreet: string;
  published
    property Street: string read FStreet write FStreet;
  end;

  TPerson = class
  private
    FName: string;
    FAddress: TAddress;
    FSpare: TAddress;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Name: string read FName write FName;
    property Address: TAddress read FAddress;
    // Left nil on purpose.
    property Spare: TAddress read FSpare write FSpare;
  end;

  TPatchDto = class(TInterfacedObject, IPatchDto)
  private
    FNome: string;
    FApelido: IOptText;
  published
    property Nome: string read FNome write FNome;
    property Apelido: IOptText read FApelido write FApelido;
  end;
{$M-}

  TOptText = class(TInterfacedObject, IOptionalBase, IOptText)
  private
    FHasValue: Boolean;
    FIsNull: Boolean;
    FValue: string;
  public
    class function Undefined: IOptText;
    class function Null: IOptText;
    class function From(const AValue: string): IOptText;
    function HasValue: Boolean;
    function IsNull: Boolean;
    function GetValue: string;
  end;

  TOptTextConverter = class(TInterfacedObject, IJsonConverter)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; out AValue: TValue): Boolean;
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; AWriter: TJsonWriter): Boolean;
  end;

// Native string from code points (UTF-16 on Delphi, UTF-8 on FPC), so test
// bodies with non-ASCII text are identical on both compilers.
function U(const ACodePoints: array of Cardinal): string;

// A mapper with every test DTO registered.
function NewTestMapper: TJsonMapper;

implementation

function U(const ACodePoints: array of Cardinal): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ACodePoints) do
    Result := Result + JsonCodePointToStr(ACodePoints[I]);
end;

function NewTestMapper: TJsonMapper;
begin
  Result := TJsonMapper.Create;
  Result.RegisterMapping<IItem, TItem>;
  Result.RegisterMapping<IScalarDto, TScalarDto>;
  Result.RegisterMapping<IOrderDto, TOrderDto>;
  Result.RegisterMapping<IHasUnmappedDto, THasUnmappedDto>;
  Result.RegisterMapping<IPatchDto, TPatchDto>;
  Result.RegisterConverter(TOptTextConverter.Create);
end;

{ TItem }

function TItem.GetCode: Integer;
begin
  Result := FCode;
end;

{ TScalarDto }

constructor TScalarDto.Create;
begin
  inherited Create;
  FPadrao := 42;
  FSomenteLeitura := 'ro';
end;

{ TPerson }

constructor TPerson.Create;
begin
  inherited Create;
  FAddress := TAddress.Create;
end;

destructor TPerson.Destroy;
begin
  FAddress.Free;
  FSpare.Free;
  inherited;
end;

{ TOptText }

class function TOptText.Undefined: IOptText;
begin
  Result := TOptText.Create;
end;

class function TOptText.Null: IOptText;
var
  O: TOptText;
begin
  O := TOptText.Create;
  O.FHasValue := True;
  O.FIsNull := True;
  Result := O;
end;

class function TOptText.From(const AValue: string): IOptText;
var
  O: TOptText;
begin
  O := TOptText.Create;
  O.FHasValue := True;
  O.FValue := AValue;
  Result := O;
end;

function TOptText.HasValue: Boolean;
begin
  Result := FHasValue;
end;

function TOptText.IsNull: Boolean;
begin
  Result := FIsNull;
end;

function TOptText.GetValue: string;
begin
  Result := FValue;
end;

{ TOptTextConverter }

function TOptTextConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(IOptText);
end;

function TOptTextConverter.ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
  ATypeInfo: PTypeInfo; out AValue: TValue): Boolean;
var
  Opt: IOptText;
begin
  if AJson.IsNull then
    Opt := TOptText.Null
  else
    Opt := TOptText.From(AJson.AsString);
  TValue.Make(@Opt, ATypeInfo, AValue);
  Result := True;
end;

function TOptTextConverter.WriteJson(AMapper: TJsonMapper; const AValue: TValue;
  ATypeInfo: PTypeInfo; AWriter: TJsonWriter): Boolean;
var
  Opt: IOptText;
begin
  Opt := nil;
  if not AValue.IsEmpty then
    Supports(AValue.AsInterface, IOptText, Opt);
  // nil and Undefined both mean "absent": omit the member.
  if (Opt = nil) or not Opt.HasValue then
    Exit(False);
  if Opt.IsNull then
    AWriter.WriteNull
  else
    AWriter.WriteString(Opt.GetValue);
  Result := True;
end;

end.
