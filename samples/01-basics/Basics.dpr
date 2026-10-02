program Basics;

(* Sample 01: the mapper's everyday use.

  1. An order arrives as JSON and becomes an IOrder: a DTO interface backed
     by a class whose PUBLISHED properties the mapper fills (Int64, enum,
     TDateTime, Currency, and an array of nested IOrderItem).
  2. The same order goes back out as JSON, after a change: camelCase names,
     declaration order, exact numbers.
  3. Naming := jnAsDeclared keeps the declared names instead.
  4. PopulateObject fills an object that already exists: a plain class (no
     interface) whose nested object property is populated in place, and
     whose members absent from the JSON keep their defaults.
  5. What bad input looks like: a value of the wrong type is reported with
     its JSON path, malformed JSON with its position.

  The DTOs live in this file to keep the sample in one place; a real
  application declares each in its own unit and registers it in that unit's
  initialization.

  Same source for Delphi (Basics.dproj) and Lazarus/FPC (Basics.lpi). The
  output is checked line by line against expected.txt by
  tools/test_samples_docker.sh. *)

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF FPC}
    {$IFDEF UNIX}
  cthreads,
    {$ENDIF}
  {$ENDIF}
  SysUtils,
  DateUtils,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper;

type
  TOrderStatus = (osPending, osPaid, osShipped);

  IOrderItem = interface
    ['{5BDDADE7-FBC4-4B8B-A968-B98241F80F09}']
    function GetSku: string;
    function GetQty: Integer;
    function GetPrice: Currency;
  end;

  TOrderItems = array of IOrderItem;

  IOrder = interface
    ['{EF53ED8B-DAA1-4743-8D7F-A0907209ACAE}']
    function GetId: Int64;
    function GetCustomer: string;
    function GetStatus: TOrderStatus;
    function GetCreatedAt: TDateTime;
    function GetItems: TOrderItems;
    function Total: Currency;
  end;

  // The mapper sees published properties only, on both compilers: declare
  // the DTO classes under $M+ and publish what goes to and from JSON.
{$M+}
  TOrderItem = class(TInterfacedObject, IOrderItem)
  private
    FSku: string;
    FQty: Integer;
    FPrice: Currency;
  public
    constructor Create; overload;
    constructor Create(const ASku: string; AQty: Integer; APrice: Currency); overload;
    function GetSku: string;
    function GetQty: Integer;
    function GetPrice: Currency;
  published
    property Sku: string read FSku write FSku;
    property Qty: Integer read FQty write FQty;
    property Price: Currency read FPrice write FPrice;
  end;

  TOrder = class(TInterfacedObject, IOrder)
  private
    FId: Int64;
    FCustomer: string;
    FStatus: TOrderStatus;
    FCreatedAt: TDateTime;
    FItems: TOrderItems;
  public
    function GetId: Int64;
    function GetCustomer: string;
    function GetStatus: TOrderStatus;
    function GetCreatedAt: TDateTime;
    function GetItems: TOrderItems;
    function Total: Currency;
  published
    property Id: Int64 read FId write FId;
    property Customer: string read FCustomer write FCustomer;
    property Status: TOrderStatus read FStatus write FStatus;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Items: TOrderItems read FItems write FItems;
  end;

  // A plain class: the mapper never creates objects for class-typed
  // properties (it wouldn't know who frees them). It fills the instance the
  // owner already created.
  TDatabaseSettings = class
  private
    FHost: string;
    FPort: Integer;
  published
    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
  end;

  TAppSettings = class
  private
    FName: string;
    FWorkers: Integer;
    FDatabase: TDatabaseSettings;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Name: string read FName write FName;
    property Workers: Integer read FWorkers write FWorkers;
    property Database: TDatabaseSettings read FDatabase;
  end;
{$M-}

{ TOrderItem }

constructor TOrderItem.Create;
begin
  inherited Create;
end;

constructor TOrderItem.Create(const ASku: string; AQty: Integer; APrice: Currency);
begin
  inherited Create;
  FSku := ASku;
  FQty := AQty;
  FPrice := APrice;
end;

function TOrderItem.GetSku: string;
begin
  Result := FSku;
end;

function TOrderItem.GetQty: Integer;
begin
  Result := FQty;
end;

function TOrderItem.GetPrice: Currency;
begin
  Result := FPrice;
end;

{ TOrder }

function TOrder.GetId: Int64;
begin
  Result := FId;
end;

function TOrder.GetCustomer: string;
begin
  Result := FCustomer;
end;

function TOrder.GetStatus: TOrderStatus;
begin
  Result := FStatus;
end;

function TOrder.GetCreatedAt: TDateTime;
begin
  Result := FCreatedAt;
end;

function TOrder.GetItems: TOrderItems;
begin
  Result := FItems;
end;

function TOrder.Total: Currency;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FItems) do
    Result := Result + FItems[I].GetQty * FItems[I].GetPrice;
end;

{ TAppSettings }

constructor TAppSettings.Create;
begin
  inherited Create;
  FName := 'unnamed';
  FWorkers := 4;
  FDatabase := TDatabaseSettings.Create;
  FDatabase.Host := 'localhost';
  FDatabase.Port := 5432;
end;

destructor TAppSettings.Destroy;
begin
  FDatabase.Free;
  inherited;
end;

const
  OrderJson =
    '{"id": 9007199254740993, "customer": "Ana", "status": "osPaid",' +
    ' "createdAt": "2026-10-02T14:30:00",' +
    ' "items": [{"sku": "RICE-5KG", "qty": 2, "price": 27.9},' +
    '           {"sku": "BEANS-1KG", "qty": 3, "price": 8.45}],' +
    ' "couponCode": "IGNORED-UNKNOWN-MEMBER"}';

procedure Title(const AText: string);
begin
  Writeln;
  Writeln('== ', AText);
end;

procedure ReadAnOrder;
var
  Order: IOrder;
  I: Integer;
begin
  Title('1. JSON -> IOrder');
  Order := TJsonMapper.Shared.FromJson<IOrder>(OrderJson);
  Writeln('id:       ', Order.GetId, '  (2^53 + 1: kept exact as Int64)');
  Writeln('customer: ', Order.GetCustomer);
  Writeln('status:   ', Ord(Order.GetStatus), ' (osPaid)');
  Writeln('created:  ', JsonDateTimeToStr(Order.GetCreatedAt));
  for I := 0 to High(Order.GetItems) do
    Writeln('item ', I, ':   ', Order.GetItems[I].GetSku, ' x', Order.GetItems[I].GetQty,
      ' @ ', JsonCurrencyToStr(Order.GetItems[I].GetPrice));
  Writeln('total:    ', JsonCurrencyToStr(Order.Total));
end;

procedure WriteAnOrder;
var
  Order: IOrder;
  Items: TOrderItems;
begin
  Title('2. IOrder -> JSON');
  Order := TJsonMapper.Shared.FromJson<IOrder>(OrderJson);
  (Order as TOrder).Status := osShipped;
  Items := Order.GetItems;
  SetLength(Items, Length(Items) + 1);
  Items[High(Items)] := TOrderItem.Create('SALT-1KG', 1, 3.2);
  (Order as TOrder).Items := Items;
  Writeln(TJsonMapper.Shared.ToJson<IOrder>(Order));
end;

procedure DeclaredNames;
var
  Mapper: TJsonMapper;
  Item: IOrderItem;
begin
  Title('3. Naming := jnAsDeclared');
  Mapper := TJsonMapper.Create;
  try
    Mapper.Naming := jnAsDeclared;
    Item := TOrderItem.Create('RICE-5KG', 2, 27.9);
    Writeln(Mapper.ToJson<IOrderItem>(Item));
  finally
    Item := nil;
    Mapper.Free;
  end;
end;

procedure PopulateSettings;
var
  Settings: TAppSettings;
begin
  Title('4. PopulateObject on an existing object');
  Settings := TAppSettings.Create;
  try
    Writeln('defaults: ', TJsonMapper.Shared.ObjectToJson(Settings));
    // Only some members: the rest keep their values. "database" fills the
    // TDatabaseSettings the constructor created; its host stays.
    TJsonMapper.Shared.PopulateObject(Settings,
      '{"name": "billing", "database": {"port": 6543}}');
    Writeln('after:    ', TJsonMapper.Shared.ObjectToJson(Settings));
  finally
    Settings.Free;
  end;
end;

procedure BadInput;
var
  Order: IOrder;
begin
  Title('5. Bad input');
  try
    Order := TJsonMapper.Shared.FromJson<IOrder>(
      '{"id": 1, "items": [{"sku": "A", "qty": 1}, {"sku": "B", "qty": "two"}]}');
  except
    on E: EJsonMapperError do
      Writeln('EJsonMapperError: ', E.Message);
  end;
  try
    Order := TJsonMapper.Shared.FromJson<IOrder>(
      '{"id": 1, "status": "osLost"}');
  except
    on E: EJsonMapperError do
      Writeln('EJsonMapperError: ', E.Message);
  end;
  try
    Order := TJsonMapper.Shared.FromJson<IOrder>('{"id": 1, "customer": "Ana",}');
  except
    on E: EJsonParseError do
      Writeln('EJsonParseError:  ', E.Message);
  end;
end;

begin
  try
    // A real application does this in the initialization of the unit that
    // declares each DTO.
    TJsonMapper.Shared.RegisterMapping<IOrderItem, TOrderItem>;
    TJsonMapper.Shared.RegisterMapping<IOrder, TOrder>;

    ReadAnOrder;
    WriteAnOrder;
    DeclaredNames;
    PopulateSettings;
    BadInput;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
