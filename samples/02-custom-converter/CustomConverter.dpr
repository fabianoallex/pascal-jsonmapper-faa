program CustomConverter;

(* Sample 02: teaching the mapper your own formats with IJsonConverter.

  Three converters, one per thing a converter can do:

  - TStatusConverter changes the format of a type the mapper already knows:
    TInvoiceStatus goes out as "paid" instead of the enum name "isPaid".
  - TMoneyConverter adds a type the mapper doesn't know: IMoney, an
    immutable value object (amount + currency), written as "12.50 BRL".
    Without it, IMoney would be an interface with no registered class.
  - TOptionalDateConverter omits a member: a TOptionalDate of 0 means "not
    set" and is left out of the JSON by writing nothing. Any other value is
    handed back to the mapper (WriteValue / ReadValue as TDateTime), so it
    gets the mapper's own ISO 8601 text.

  Errors raised inside a converter (EJsonError, or a TJsonValue accessor
  used on the wrong kind) come out as EJsonMapperError with the JSON path.

  The converters are registered on a mapper of their own here; a library
  that ships converters for its types registers them on TJsonMapper.Shared
  in a unit's initialization (see docs/converters.md).

  Same source for Delphi (CustomConverter.dproj) and Lazarus/FPC
  (CustomConverter.lpi). The output is checked line by line against
  expected.txt by tools/test_samples_docker.sh. *)

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
  TypInfo,
  Rtti,
  DateUtils,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper;

type
  TInvoiceStatus = (isDraft, isSent, isPaid);

  // A distinct type (own type info), so its converter doesn't touch every
  // TDateTime in the application. The flip side: without the converter the
  // mapper doesn't treat it as a date at all (dates are recognized by
  // TypeInfo(TDateTime)/TDate/TTime), and it goes out as a plain number.
  TOptionalDate = type TDateTime;

  IMoney = interface
    ['{CA422E15-EA2E-483B-999E-4A36F8A722F5}']
    function Amount: Currency;
    function CurrencyCode: string;
  end;

  TMoney = class(TInterfacedObject, IMoney)
  private
    FAmount: Currency;
    FCode: string;
  public
    constructor Create(AAmount: Currency; const ACode: string);
    function Amount: Currency;
    function CurrencyCode: string;
  end;

  IInvoice = interface
    ['{C3DE47E2-A4E9-46AE-ACBF-C6048C3E37BF}']
  end;

{$M+}
  TInvoice = class(TInterfacedObject, IInvoice)
  private
    FNumber: Integer;
    FStatus: TInvoiceStatus;
    FTotal: IMoney;
    FDueDate: TOptionalDate;
    FPaidAt: TOptionalDate;
  published
    property Number: Integer read FNumber write FNumber;
    property Status: TInvoiceStatus read FStatus write FStatus;
    property Total: IMoney read FTotal write FTotal;
    property DueDate: TOptionalDate read FDueDate write FDueDate;
    property PaidAt: TOptionalDate read FPaidAt write FPaidAt;
  end;
{$M-}

  TStatusConverter = class(TInterfacedObject, IJsonConverter)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
  end;

  TMoneyConverter = class(TInterfacedObject, IJsonConverter)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
  end;

  TOptionalDateConverter = class(TInterfacedObject, IJsonConverter)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
  end;

{ TMoney }

constructor TMoney.Create(AAmount: Currency; const ACode: string);
begin
  inherited Create;
  FAmount := AAmount;
  FCode := ACode;
end;

function TMoney.Amount: Currency;
begin
  Result := FAmount;
end;

function TMoney.CurrencyCode: string;
begin
  Result := FCode;
end;

{ TStatusConverter: enum as a short code }

const
  StatusCodes: array[TInvoiceStatus] of string = ('draft', 'sent', 'paid');

function TStatusConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TInvoiceStatus);
end;

function TStatusConverter.ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
  ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
var
  S: TInvoiceStatus;
begin
  // AsString raises EJsonError on a non-string; the mapper adds the path.
  for S := Low(TInvoiceStatus) to High(TInvoiceStatus) do
    if StatusCodes[S] = AJson.AsString then
    begin
      AValue := TValue.From<TInvoiceStatus>(S);
      Exit(True);
    end;
  raise EJsonError.CreateFmt('unknown invoice status "%s"', [AJson.AsString]);
end;

function TStatusConverter.WriteJson(AMapper: TJsonMapper; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
begin
  // Raw data rather than TValue.AsType<T>, which FPC 3.2.2 lacks.
  AWriter.WriteString(StatusCodes[TInvoiceStatus(PByte(AValue.GetReferenceToRawData)^)]);
  Result := True;
end;

{ TMoneyConverter: value object as "12.50 BRL" }

function TMoneyConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(IMoney);
end;

function TMoneyConverter.ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
  ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
var
  Text, Code: string;
  P: Integer;
  Amount: Currency;
  Money: IMoney;
begin
  if AJson.IsNull then
    Money := nil
  else
  begin
    Text := AJson.AsString;
    P := Pos(' ', Text);
    Code := Copy(Text, P + 1, MaxInt);
    if (P = 0) or (Length(Code) <> 3) or
      not TryStrToCurr(Copy(Text, 1, P - 1), Amount, JsonFormatSettings) then
      raise EJsonError.CreateFmt('"%s" is not "<amount> <currency>"', [Text]);
    Money := TMoney.Create(Amount, Code);
  end;
  TValue.Make(@Money, ATypeInfo, AValue);
  Result := True;
end;

function TMoneyConverter.WriteJson(AMapper: TJsonMapper; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
var
  Money: IMoney;
begin
  Money := nil;
  if not AValue.IsEmpty then
    Supports(AValue.AsInterface, IMoney, Money);
  if Money = nil then
    AWriter.WriteNull
  else
    AWriter.WriteString(CurrToStrF(Money.Amount, ffFixed, 2, JsonFormatSettings) +
      ' ' + Money.CurrencyCode);
  Result := True;
end;

{ TOptionalDateConverter: 0 = not set = omitted }

function TOptionalDateConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TOptionalDate);
end;

function TOptionalDateConverter.ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
  ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
var
  Inner: TValue;
  Date: TOptionalDate;
begin
  if AJson.IsNull then
    Date := 0
  else
  begin
    // The mapper's ISO 8601 rules and errors (with this path).
    AMapper.ReadValue(AJson, TypeInfo(TDateTime), APath, Inner);
    Date := TOptionalDate(PDateTime(Inner.GetReferenceToRawData)^);
  end;
  TValue.Make(@Date, ATypeInfo, AValue);
  Result := True;
end;

function TOptionalDateConverter.WriteJson(AMapper: TJsonMapper; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
var
  Date: TDateTime;
begin
  Date := PDateTime(AValue.GetReferenceToRawData)^;
  if Date = 0 then
    Exit(False);  // write nothing: the member is left out
  Result := AMapper.WriteValue(AWriter, TValue.From<TDateTime>(Date),
    TypeInfo(TDateTime), APath);
end;

{ The sample }

procedure Title(const AText: string);
begin
  Writeln;
  Writeln('== ', AText);
end;

procedure TryRead(AMapper: TJsonMapper; const AJson: string);
var
  Invoice: IInvoice;
begin
  try
    Invoice := AMapper.FromJson<IInvoice>(AJson);
    Writeln('ok:    ', AMapper.ToJson<IInvoice>(Invoice));
  except
    on E: EJsonMapperError do
      Writeln('error: ', E.Message);
  end;
end;

var
  Mapper: TJsonMapper;
  Invoice: TInvoice;
  InvoiceIntf: IInvoice;
begin
  Mapper := TJsonMapper.Create;
  try
    try
      Mapper.RegisterMapping<IInvoice, TInvoice>;

      Title('Without converters');
      Invoice := TInvoice.Create;
      InvoiceIntf := Invoice;
      Invoice.Number := 1042;
      Invoice.Status := isSent;
      Invoice.DueDate := EncodeDate(2026, 11, 1);
      Writeln('the enum goes out by name. TOptionalDate is a type of its own, not');
      Writeln('TDateTime, so it is just a number of days (0 included). And IMoney');
      Writeln('has no registered class, so reading one fails:');
      Writeln(Mapper.ToJson<IInvoice>(InvoiceIntf));
      TryRead(Mapper, '{"number": 1, "total": "10.00 BRL"}');

      Mapper.RegisterConverter(TStatusConverter.Create);
      Mapper.RegisterConverter(TMoneyConverter.Create);
      Mapper.RegisterConverter(TOptionalDateConverter.Create);

      Title('With converters: writing');
      Invoice.Total := TMoney.Create(1234.5, 'BRL');
      Writeln('not paid yet (paidAt = 0 is left out):');
      Writeln(Mapper.ToJson<IInvoice>(InvoiceIntf));
      Invoice.Status := isPaid;
      Invoice.PaidAt := EncodeDateTime(2026, 10, 30, 9, 15, 0, 0);
      Writeln('paid:');
      Writeln(Mapper.ToJson<IInvoice>(InvoiceIntf));

      Title('With converters: reading');
      TryRead(Mapper, '{"number": 7, "status": "draft", "total": "99.90 USD"}');
      TryRead(Mapper, '{"number": 8, "status": "paid", "total": "10.00 BRL", "paidAt": "2026-10-01T12:00:00-03:00"}');

      Title('With converters: bad input');
      TryRead(Mapper, '{"number": 9, "status": "refunded"}');
      TryRead(Mapper, '{"number": 9, "status": 2}');
      TryRead(Mapper, '{"number": 9, "total": "ten reais"}');
      TryRead(Mapper, '{"number": 9, "dueDate": "01/11/2026"}');
    except
      on E: Exception do
      begin
        Writeln(E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    InvoiceIntf := nil;
    Mapper.Free;
  end;
end.
