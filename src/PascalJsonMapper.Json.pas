unit PascalJsonMapper.Json;

{$I pjm.inc}

{ Small JSON DOM, parser and writer, shared by both compilers.

  Why not System.JSON / fpjson: each exists on one compiler only, and they
  disagree on output (fpjson writes 0.1 as "1.0000000000000001E-001") and on
  \u escapes (fpjson 3.2.2 decodes them through the system code page unless
  DefaultSystemCodePage is UTF-8). Owning ~600 lines of JSON makes the text
  this library reads and writes identical on Delphi and FPC.

  Strings: on Delphi, string is UTF-16 (UnicodeString). On FPC under
  MODE DELPHI, string is AnsiString and this unit treats its bytes as
  UTF-8 (the Lazarus convention): non-ASCII bytes pass through untouched,
  and \uXXXX escapes are decoded to UTF-8. Either way, the JSON text and the
  decoded values use the compiler's native string type.

  Numbers keep their source text (TJsonValue.NumberText), so an Int64 larger
  than 2^53 survives a round trip; conversion to Int64/Double happens only on
  request, always with '.' as decimal separator regardless of locale. }

interface

uses
  SysUtils;

type
  EJsonError = class(Exception);

  EJsonParseError = class(EJsonError)
  private
    FPosition: Integer;
  public
    constructor CreatePos(const AMessage: string; APosition: Integer);
    // 1-based index into the parsed string (a char index: UTF-16 units on
    // Delphi, bytes on FPC).
    property Position: Integer read FPosition;
  end;

  TJsonKind = (jkNull, jkBoolean, jkNumber, jkString, jkArray, jkObject);

  { A node of the tree. Owns its children: freeing the root frees all. }
  TJsonValue = class
  private
    FKind: TJsonKind;
    FText: string;      // string value, or number source text
    FBool: Boolean;
    FItems: array of TJsonValue;
    FNames: array of string;  // object member names, parallel to FItems
    FCount: Integer;
    function GetItem(AIndex: Integer): TJsonValue;
    function GetName(AIndex: Integer): string;
    procedure Append(const AName: string; AValue: TJsonValue);
    procedure RequireKind(AKind: TJsonKind);
  public
    constructor CreateNull;
    constructor CreateBoolean(AValue: Boolean);
    constructor CreateNumberText(const AText: string);
    constructor CreateInt64(AValue: Int64);
    constructor CreateString(const AValue: string);
    constructor CreateArray;
    constructor CreateObject;
    destructor Destroy; override;

    function IsNull: Boolean;
    function AsString: string;
    function AsBoolean: Boolean;
    function AsInt64: Int64;
    function AsDouble: Double;
    function TryAsInt64(out AValue: Int64): Boolean;
    property NumberText: string read FText;

    // Arrays and objects
    property Kind: TJsonKind read FKind;
    property Count: Integer read FCount;
    property Items[AIndex: Integer]: TJsonValue read GetItem; default;
    property Names[AIndex: Integer]: string read GetName;
    procedure Add(AValue: TJsonValue);
    procedure AddPair(const AName: string; AValue: TJsonValue);
    // Object lookup; nil if absent. First match wins on duplicate names.
    function Find(const AName: string; AIgnoreCase: Boolean = False): TJsonValue;

    function ToJson: string;
  end;

  { Appends JSON text. Tracks commas itself, so callers just emit tokens in
    order: BeginObject, Name('x'), WriteInt64(1), EndObject...

    Name() is deferred: the member name is only emitted together with the
    next value. A Name() followed by another Name() or by EndObject is
    dropped, which is how a converter omits a member (it simply writes
    nothing). }
  TJsonWriter = class
  private
    FBuf: string;
    FLen: Integer;
    FNeedComma: array of Boolean;
    FDepth: Integer;
    FPendingName: string;
    FHasPendingName: Boolean;
    procedure Raw(const S: string);
    procedure RawChar(C: Char);
    procedure BeforeValue;
    procedure Push;
    procedure Pop;
    procedure WriteQuoted(const AValue: string);
  public
    constructor Create;
    procedure BeginObject;
    procedure EndObject;
    procedure BeginArray;
    procedure EndArray;
    procedure Name(const AName: string);
    procedure WriteNull;
    procedure WriteBoolean(AValue: Boolean);
    procedure WriteString(const AValue: string);
    procedure WriteInt64(AValue: Int64);
    procedure WriteDouble(AValue: Double);
    procedure WriteSingle(AValue: Single);
    procedure WriteCurrency(AValue: Currency);
    // Writes AText as-is: the caller guarantees it is a valid JSON number.
    procedure WriteNumberText(const AText: string);
    procedure WriteValue(AValue: TJsonValue);
    function ToString: string; override;
  end;

// Parses a complete JSON text. Raises EJsonParseError on any syntax error or
// trailing content. The caller owns the result.
function ParseJson(const AText: string): TJsonValue;

// Shortest decimal text that reads back as exactly the same Double/Single.
// Raises EJsonError for NaN and infinities (JSON has no representation).
function JsonFloatToStr(AValue: Double): string;
function JsonSingleToStr(AValue: Single): string;
function JsonCurrencyToStr(AValue: Currency): string;

// ISO 8601. Output has no zone designator: TDateTime carries no zone, so the
// value is written as is. Input accepts date-only, date-time with optional
// seconds/fraction, and an optional 'Z' or +hh:mm/-hh:mm offset; when an
// offset is present the result is converted to UTC.
function JsonDateTimeToStr(AValue: TDateTime): string;
function JsonDateToStr(AValue: TDateTime): string;
function JsonTimeToStr(AValue: TDateTime): string;
function JsonStrToDateTime(const AText: string): TDateTime;
function JsonStrToTime(const AText: string): TDateTime;

function JsonFormatSettings: TFormatSettings;

// One Unicode code point in the native string encoding: UTF-16 on Delphi,
// UTF-8 bytes on FPC.
function JsonCodePointToStr(ACodePoint: Cardinal): string;

implementation

uses
  Math, DateUtils;

var
  GFormatSettings: TFormatSettings;

function JsonFormatSettings: TFormatSettings;
begin
  Result := GFormatSettings;
end;

{ Code point helpers }

procedure AppendCodePoint(var S: string; ACodePoint: Cardinal);
begin
{$IFDEF FPC}
  // FPC string holds UTF-8 bytes.
  if ACodePoint < $80 then
    S := S + Char(ACodePoint)
  else if ACodePoint < $800 then
    S := S + Char($C0 or (ACodePoint shr 6)) + Char($80 or (ACodePoint and $3F))
  else if ACodePoint < $10000 then
    S := S + Char($E0 or (ACodePoint shr 12)) +
      Char($80 or ((ACodePoint shr 6) and $3F)) + Char($80 or (ACodePoint and $3F))
  else
    S := S + Char($F0 or (ACodePoint shr 18)) +
      Char($80 or ((ACodePoint shr 12) and $3F)) +
      Char($80 or ((ACodePoint shr 6) and $3F)) + Char($80 or (ACodePoint and $3F));
{$ELSE}
  // Delphi string holds UTF-16.
  if ACodePoint < $10000 then
    S := S + Char(ACodePoint)
  else
  begin
    Dec(ACodePoint, $10000);
    S := S + Char($D800 or (ACodePoint shr 10)) + Char($DC00 or (ACodePoint and $3FF));
  end;
{$ENDIF}
end;

function JsonCodePointToStr(ACodePoint: Cardinal): string;
begin
  Result := '';
  AppendCodePoint(Result, ACodePoint);
end;

{ EJsonParseError }

constructor EJsonParseError.CreatePos(const AMessage: string; APosition: Integer);
begin
  inherited CreateFmt('%s (at position %d)', [AMessage, APosition]);
  FPosition := APosition;
end;

{ TJsonValue }

constructor TJsonValue.CreateNull;
begin
  inherited Create;
  FKind := jkNull;
end;

constructor TJsonValue.CreateBoolean(AValue: Boolean);
begin
  inherited Create;
  FKind := jkBoolean;
  FBool := AValue;
end;

constructor TJsonValue.CreateNumberText(const AText: string);
begin
  inherited Create;
  FKind := jkNumber;
  FText := AText;
end;

constructor TJsonValue.CreateInt64(AValue: Int64);
begin
  CreateNumberText(IntToStr(AValue));
end;

constructor TJsonValue.CreateString(const AValue: string);
begin
  inherited Create;
  FKind := jkString;
  FText := AValue;
end;

constructor TJsonValue.CreateArray;
begin
  inherited Create;
  FKind := jkArray;
end;

constructor TJsonValue.CreateObject;
begin
  inherited Create;
  FKind := jkObject;
end;

destructor TJsonValue.Destroy;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
    FItems[I].Free;
  inherited;
end;

procedure TJsonValue.RequireKind(AKind: TJsonKind);
const
  KindNames: array[TJsonKind] of string =
    ('null', 'boolean', 'number', 'string', 'array', 'object');
begin
  if FKind <> AKind then
    raise EJsonError.CreateFmt('JSON %s expected, found %s',
      [KindNames[AKind], KindNames[FKind]]);
end;

function TJsonValue.IsNull: Boolean;
begin
  Result := FKind = jkNull;
end;

function TJsonValue.AsString: string;
begin
  RequireKind(jkString);
  Result := FText;
end;

function TJsonValue.AsBoolean: Boolean;
begin
  RequireKind(jkBoolean);
  Result := FBool;
end;

function TJsonValue.TryAsInt64(out AValue: Int64): Boolean;
begin
  Result := (FKind = jkNumber) and (LastDelimiter('.eE', FText) = 0) and
    TryStrToInt64(FText, AValue);
end;

function TJsonValue.AsInt64: Int64;
begin
  RequireKind(jkNumber);
  if not TryAsInt64(Result) then
    raise EJsonError.CreateFmt('JSON number %s is not an Int64', [FText]);
end;

function TJsonValue.AsDouble: Double;
begin
  RequireKind(jkNumber);
  Result := StrToFloat(FText, GFormatSettings);
end;

function TJsonValue.GetItem(AIndex: Integer): TJsonValue;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EJsonError.CreateFmt('JSON index %d out of bounds (count %d)', [AIndex, FCount]);
  Result := FItems[AIndex];
end;

function TJsonValue.GetName(AIndex: Integer): string;
begin
  RequireKind(jkObject);
  GetItem(AIndex);
  Result := FNames[AIndex];
end;

procedure TJsonValue.Append(const AName: string; AValue: TJsonValue);
begin
  if FCount = Length(FItems) then
  begin
    SetLength(FItems, FCount * 2 + 4);
    if FKind = jkObject then
      SetLength(FNames, Length(FItems));
  end;
  FItems[FCount] := AValue;
  if FKind = jkObject then
    FNames[FCount] := AName;
  Inc(FCount);
end;

procedure TJsonValue.Add(AValue: TJsonValue);
begin
  RequireKind(jkArray);
  Append('', AValue);
end;

procedure TJsonValue.AddPair(const AName: string; AValue: TJsonValue);
begin
  RequireKind(jkObject);
  Append(AName, AValue);
end;

function TJsonValue.Find(const AName: string; AIgnoreCase: Boolean): TJsonValue;
var
  I: Integer;
begin
  RequireKind(jkObject);
  for I := 0 to FCount - 1 do
    if (FNames[I] = AName) or (AIgnoreCase and SameText(FNames[I], AName)) then
      Exit(FItems[I]);
  Result := nil;
end;

function TJsonValue.ToJson: string;
var
  W: TJsonWriter;
begin
  W := TJsonWriter.Create;
  try
    W.WriteValue(Self);
    Result := W.ToString;
  finally
    W.Free;
  end;
end;

{ Parser }

const
  MaxDepth = 512;

type
  TJsonParser = class
  private
    FText: string;
    FPos: Integer;
    FLen: Integer;
    procedure Fail(const AMessage: string);
    procedure SkipWhitespace;
    function ParseValue(ADepth: Integer): TJsonValue;
    function ParseString: string;
    function ParseNumber: string;
    function ParseHex4: Cardinal;
    procedure ExpectLiteral(const ALiteral: string);
  public
    constructor Create(const AText: string);
    function Parse: TJsonValue;
  end;

constructor TJsonParser.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FLen := Length(AText);
  FPos := 1;
  // Skip a byte order mark, if the caller left one in.
{$IFDEF FPC}
  if (FLen >= 3) and (FText[1] = #$EF) and (FText[2] = #$BB) and (FText[3] = #$BF) then
    FPos := 4;
{$ELSE}
  if (FLen >= 1) and (FText[1] = #$FEFF) then
    FPos := 2;
{$ENDIF}
end;

procedure TJsonParser.Fail(const AMessage: string);
begin
  raise EJsonParseError.CreatePos(AMessage, FPos);
end;

procedure TJsonParser.SkipWhitespace;
begin
  while (FPos <= FLen) and ((FText[FPos] = ' ') or (FText[FPos] = #9) or
    (FText[FPos] = #10) or (FText[FPos] = #13)) do
    Inc(FPos);
end;

function TJsonParser.Parse: TJsonValue;
begin
  SkipWhitespace;
  Result := ParseValue(0);
  try
    SkipWhitespace;
    if FPos <= FLen then
      Fail('Unexpected content after the JSON value');
  except
    Result.Free;
    raise;
  end;
end;

procedure TJsonParser.ExpectLiteral(const ALiteral: string);
begin
  if Copy(FText, FPos, Length(ALiteral)) <> ALiteral then
    Fail('Invalid literal');
  Inc(FPos, Length(ALiteral));
end;

function TJsonParser.ParseHex4: Cardinal;
var
  I: Integer;
  C: Char;
begin
  Result := 0;
  for I := 1 to 4 do
  begin
    if FPos > FLen then
      Fail('Unterminated \u escape');
    C := FText[FPos];
    case C of
      '0'..'9': Result := Result * 16 + Cardinal(Ord(C) - Ord('0'));
      'a'..'f': Result := Result * 16 + Cardinal(Ord(C) - Ord('a') + 10);
      'A'..'F': Result := Result * 16 + Cardinal(Ord(C) - Ord('A') + 10);
    else
      Fail('Invalid hex digit in \u escape');
    end;
    Inc(FPos);
  end;
end;

function TJsonParser.ParseString: string;
var
  Start: Integer;
  C: Char;
  CP, Low: Cardinal;
begin
  // FText[FPos] = '"'
  Inc(FPos);
  Result := '';
  Start := FPos;
  while True do
  begin
    if FPos > FLen then
      Fail('Unterminated string');
    C := FText[FPos];
    if C = '"' then
    begin
      Result := Result + Copy(FText, Start, FPos - Start);
      Inc(FPos);
      Exit;
    end;
    if Ord(C) < $20 then
      Fail('Control character in string');
    if C <> '\' then
    begin
      Inc(FPos);
      Continue;
    end;
    // Escape sequence: flush the plain run first.
    Result := Result + Copy(FText, Start, FPos - Start);
    Inc(FPos);
    if FPos > FLen then
      Fail('Unterminated escape');
    C := FText[FPos];
    Inc(FPos);
    case C of
      '"': Result := Result + '"';
      '\': Result := Result + '\';
      '/': Result := Result + '/';
      'b': Result := Result + #8;
      'f': Result := Result + #12;
      'n': Result := Result + #10;
      'r': Result := Result + #13;
      't': Result := Result + #9;
      'u':
        begin
          CP := ParseHex4;
          if (CP >= $D800) and (CP <= $DBFF) then
          begin
            // High surrogate: pair it only with an immediately following
            // low-surrogate escape. Anything else makes it a lone surrogate.
            if (FPos + 1 <= FLen) and (FText[FPos] = '\') and (FText[FPos + 1] = 'u') then
            begin
              Inc(FPos, 2);
              Low := ParseHex4;
              if (Low >= $DC00) and (Low <= $DFFF) then
                CP := $10000 + ((CP - $D800) shl 10) + (Low - $DC00)
              else
              begin
                AppendCodePoint(Result, $FFFD);
                CP := Low;
                if (CP >= $D800) and (CP <= $DFFF) then
                  CP := $FFFD;
              end;
            end
            else
              CP := $FFFD;
          end
          else if (CP >= $DC00) and (CP <= $DFFF) then
            CP := $FFFD;  // lone low surrogate
          AppendCodePoint(Result, CP);
        end;
    else
      Dec(FPos);
      Fail('Invalid escape');
    end;
    Start := FPos;
  end;
end;

function TJsonParser.ParseNumber: string;
var
  Start: Integer;

  function IsDigit: Boolean;
  begin
    Result := (FPos <= FLen) and (FText[FPos] >= '0') and (FText[FPos] <= '9');
  end;

  procedure Digits;
  begin
    if not IsDigit then
      Fail('Digit expected');
    while IsDigit do
      Inc(FPos);
  end;

begin
  Start := FPos;
  if FText[FPos] = '-' then
    Inc(FPos);
  if (FPos <= FLen) and (FText[FPos] = '0') then
    Inc(FPos)
  else
    Digits;
  if (FPos <= FLen) and (FText[FPos] = '.') then
  begin
    Inc(FPos);
    Digits;
  end;
  if (FPos <= FLen) and ((FText[FPos] = 'e') or (FText[FPos] = 'E')) then
  begin
    Inc(FPos);
    if (FPos <= FLen) and ((FText[FPos] = '+') or (FText[FPos] = '-')) then
      Inc(FPos);
    Digits;
  end;
  Result := Copy(FText, Start, FPos - Start);
end;

function TJsonParser.ParseValue(ADepth: Integer): TJsonValue;
var
  Name: string;
begin
  if ADepth > MaxDepth then
    Fail('Maximum nesting depth exceeded');
  if FPos > FLen then
    Fail('Value expected');
  case FText[FPos] of
    '{':
      begin
        Result := TJsonValue.CreateObject;
        try
          Inc(FPos);
          SkipWhitespace;
          if (FPos <= FLen) and (FText[FPos] = '}') then
          begin
            Inc(FPos);
            Exit;
          end;
          while True do
          begin
            SkipWhitespace;
            if (FPos > FLen) or (FText[FPos] <> '"') then
              Fail('Member name expected');
            Name := ParseString;
            SkipWhitespace;
            if (FPos > FLen) or (FText[FPos] <> ':') then
              Fail('":" expected');
            Inc(FPos);
            SkipWhitespace;
            Result.Append(Name, ParseValue(ADepth + 1));
            SkipWhitespace;
            if FPos > FLen then
              Fail('"," or "}" expected');
            if FText[FPos] = ',' then
              Inc(FPos)
            else if FText[FPos] = '}' then
            begin
              Inc(FPos);
              Exit;
            end
            else
              Fail('"," or "}" expected');
          end;
        except
          Result.Free;
          raise;
        end;
      end;
    '[':
      begin
        Result := TJsonValue.CreateArray;
        try
          Inc(FPos);
          SkipWhitespace;
          if (FPos <= FLen) and (FText[FPos] = ']') then
          begin
            Inc(FPos);
            Exit;
          end;
          while True do
          begin
            SkipWhitespace;
            Result.Append('', ParseValue(ADepth + 1));
            SkipWhitespace;
            if FPos > FLen then
              Fail('"," or "]" expected');
            if FText[FPos] = ',' then
              Inc(FPos)
            else if FText[FPos] = ']' then
            begin
              Inc(FPos);
              Exit;
            end
            else
              Fail('"," or "]" expected');
          end;
        except
          Result.Free;
          raise;
        end;
      end;
    '"':
      Result := TJsonValue.CreateString(ParseString);
    '-', '0'..'9':
      Result := TJsonValue.CreateNumberText(ParseNumber);
    't':
      begin
        ExpectLiteral('true');
        Result := TJsonValue.CreateBoolean(True);
      end;
    'f':
      begin
        ExpectLiteral('false');
        Result := TJsonValue.CreateBoolean(False);
      end;
    'n':
      begin
        ExpectLiteral('null');
        Result := TJsonValue.CreateNull;
      end;
  else
    Fail('Unexpected character');
    Result := nil;
  end;
end;

function ParseJson(const AText: string): TJsonValue;
var
  P: TJsonParser;
begin
  P := TJsonParser.Create(AText);
  try
    Result := P.Parse;
  finally
    P.Free;
  end;
end;

{ Number formatting

  Shortest text that reads back as the same value, built from a 17-digit
  decimal expansion: round that digit string to 1, 2, ... digits and keep
  the first that parses back exactly. Not FloatToStrF(ffGeneral, 17): on FPC
  3.2.2 Win64 (Extended = Double) it stops at ~15 significant digits, so
  0.30000000000000004 came out as "0.3". FPC's Str(Double) does give 17.

  Layout follows JavaScript's Number.toString: fixed notation when the
  decimal exponent is in -7 < X < 21, else d.dddE[-]X. }

// Significant digits (no leading zeros) and the exponent X such that
// |AValue| = d1.d2d3... x 10^X. AValue must be finite and non-zero.
procedure DecimalDigits(AValue: Double; out ADigits: string; out AExp: Integer);
var
  S, Mantissa: string;
  P, I: Integer;
begin
{$IFDEF FPC}
  Str(Abs(AValue), S);
{$ELSE}
  S := FloatToStrF(Abs(AValue), ffExponent, 17, 0, GFormatSettings);
{$ENDIF}
  S := Trim(S);
  P := Pos('E', UpperCase(S));
  Mantissa := Copy(S, 1, P - 1);
  AExp := StrToInt(Copy(S, P + 1, MaxInt));
  ADigits := '';
  for I := 1 to Length(Mantissa) do
    if (Mantissa[I] >= '0') and (Mantissa[I] <= '9') then
      ADigits := ADigits + Mantissa[I];
end;

// Rounds a digit string to ACount digits (half up on the decimal text).
// A carry out of the first digit (9.99 -> 10.0) increments AExp.
function RoundDigits(const ADigits: string; ACount: Integer; var AExp: Integer): string;
var
  I: Integer;
begin
  Result := Copy(ADigits, 1, ACount);
  if (ACount < Length(ADigits)) and (ADigits[ACount + 1] >= '5') then
  begin
    I := ACount;
    while (I >= 1) and (Result[I] = '9') do
    begin
      Result[I] := '0';
      Dec(I);
    end;
    if I >= 1 then
      Result[I] := Char(Ord(Result[I]) + 1)
    else
    begin
      Result := '1' + Result;
      SetLength(Result, ACount);
      Inc(AExp);
    end;
  end;
  I := Length(Result);
  while (I > 1) and (Result[I] = '0') do
    Dec(I);
  SetLength(Result, I);
end;

function LayoutNumber(ANegative: Boolean; const ADigits: string; AExp: Integer): string;
var
  K: Integer;
begin
  K := Length(ADigits);
  if (AExp > -7) and (AExp < 21) then
  begin
    if AExp >= K - 1 then
      Result := ADigits + StringOfChar('0', AExp - K + 1)
    else if AExp >= 0 then
      Result := Copy(ADigits, 1, AExp + 1) + '.' + Copy(ADigits, AExp + 2, MaxInt)
    else
      Result := '0.' + StringOfChar('0', -AExp - 1) + ADigits;
  end
  else
  begin
    Result := ADigits[1];
    if K > 1 then
      Result := Result + '.' + Copy(ADigits, 2, MaxInt);
    Result := Result + 'E' + IntToStr(AExp);
  end;
  if ANegative then
    Result := '-' + Result;
end;

procedure CheckFinite(AValue: Double);
begin
  if IsNan(AValue) or IsInfinite(AValue) then
    raise EJsonError.Create('NaN and infinity have no JSON representation');
end;

function JsonFloatToStr(AValue: Double): string;
var
  Digits, Candidate: string;
  Exp, E, P: Integer;
  Back: Double;
begin
  CheckFinite(AValue);
  if AValue = 0 then
    Exit('0');
  DecimalDigits(AValue, Digits, Exp);
  Result := '';
  for P := 1 to Length(Digits) do
  begin
    E := Exp;
    Candidate := RoundDigits(Digits, P, E);
    Result := LayoutNumber(AValue < 0, Candidate, E);
    // Through a Double: on Delphi Win32 StrToFloat returns an 80-bit
    // Extended, which never equals the Double it should round-trip to.
    Back := StrToFloat(Result, GFormatSettings);
    if Back = AValue then
      Exit;
  end;
end;

function JsonSingleToStr(AValue: Single): string;
var
  Digits, Candidate: string;
  Exp, E, P: Integer;
  Back: Single;
begin
  CheckFinite(AValue);
  if AValue = 0 then
    Exit('0');
  // A Single is exactly representable as a Double: expand that.
  DecimalDigits(AValue, Digits, Exp);
  Result := '';
  for P := 1 to Length(Digits) do
  begin
    E := Exp;
    Candidate := RoundDigits(Digits, P, E);
    Result := LayoutNumber(AValue < 0, Candidate, E);
    Back := StrToFloat(Result, GFormatSettings);
    if Back = AValue then
      Exit;
  end;
end;

function JsonCurrencyToStr(AValue: Currency): string;
var
  L: Integer;
begin
  Result := CurrToStrF(AValue, ffFixed, 4, GFormatSettings);
  L := Length(Result);
  while Result[L] = '0' do
    Dec(L);
  if Result[L] = '.' then
    Dec(L);
  SetLength(Result, L);
end;

{ Dates }

function JsonDateToStr(AValue: TDateTime): string;
var
  Y, M, D: Word;
begin
  DecodeDate(AValue, Y, M, D);
  Result := Format('%.4d-%.2d-%.2d', [Y, M, D]);
end;

function JsonTimeToStr(AValue: TDateTime): string;
var
  H, N, S, MS: Word;
begin
  DecodeTime(AValue, H, N, S, MS);
  Result := Format('%.2d:%.2d:%.2d', [H, N, S]);
  if MS <> 0 then
    Result := Result + Format('.%.3d', [MS]);
end;

function JsonDateTimeToStr(AValue: TDateTime): string;
begin
  Result := JsonDateToStr(AValue) + 'T' + JsonTimeToStr(AValue);
end;

type
  TIsoReader = record
    Text: string;
    Pos: Integer;
    procedure Fail;
    function Number(ADigits: Integer): Integer;
    function Peek: Char;
    function AtEnd: Boolean;
    procedure Expect(C: Char);
  end;

procedure TIsoReader.Fail;
begin
  raise EJsonError.CreateFmt('Invalid ISO 8601 date/time: "%s"', [Text]);
end;

function TIsoReader.AtEnd: Boolean;
begin
  Result := Pos > Length(Text);
end;

function TIsoReader.Peek: Char;
begin
  if AtEnd then
    Result := #0
  else
    Result := Text[Pos];
end;

procedure TIsoReader.Expect(C: Char);
begin
  if Peek <> C then
    Fail;
  Inc(Pos);
end;

function TIsoReader.Number(ADigits: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to ADigits do
  begin
    if (Peek < '0') or (Peek > '9') then
      Fail;
    Result := Result * 10 + Ord(Text[Pos]) - Ord('0');
    Inc(Pos);
  end;
end;

// Reads hh:mm[:ss[.fff...]] [Z|+hh:mm|-hh:mm]; returns the time part and the
// offset in minutes (0 when absent).
procedure ReadTime(var R: TIsoReader; out ATime: TDateTime; out AOffsetMin: Integer);
var
  H, N, S, MS, Scale: Integer;
  Sign: Integer;
begin
  H := R.Number(2);
  R.Expect(':');
  N := R.Number(2);
  S := 0;
  MS := 0;
  if R.Peek = ':' then
  begin
    Inc(R.Pos);
    S := R.Number(2);
    if (R.Peek = '.') or (R.Peek = ',') then
    begin
      Inc(R.Pos);
      if (R.Peek < '0') or (R.Peek > '9') then
        R.Fail;
      Scale := 100;
      while (R.Peek >= '0') and (R.Peek <= '9') do
      begin
        MS := MS + (Ord(R.Peek) - Ord('0')) * Scale;
        Scale := Scale div 10;
        Inc(R.Pos);
      end;
    end;
  end;
  if (H > 23) or (N > 59) or (S > 59) then
    R.Fail;
  ATime := EncodeTime(H, N, S, MS);
  AOffsetMin := 0;
  case R.Peek of
    'Z', 'z':
      Inc(R.Pos);
    '+', '-':
      begin
        if R.Peek = '-' then
          Sign := -1
        else
          Sign := 1;
        Inc(R.Pos);
        H := R.Number(2);
        if R.Peek = ':' then
          Inc(R.Pos);
        N := R.Number(2);
        AOffsetMin := Sign * (H * 60 + N);
      end;
  end;
end;

function JsonStrToDateTime(const AText: string): TDateTime;
var
  R: TIsoReader;
  Y, M, D, OffsetMin: Integer;
  T: TDateTime;
begin
  R.Text := Trim(AText);
  R.Pos := 1;
  Y := R.Number(4);
  R.Expect('-');
  M := R.Number(2);
  R.Expect('-');
  D := R.Number(2);
  if not TryEncodeDate(Y, M, D, Result) then
    R.Fail;
  if (R.Peek = 'T') or (R.Peek = 't') or (R.Peek = ' ') then
  begin
    Inc(R.Pos);
    ReadTime(R, T, OffsetMin);
    Result := Result + T;
    if OffsetMin <> 0 then
      Result := IncMinute(Result, -OffsetMin);
  end;
  if not R.AtEnd then
    R.Fail;
end;

function JsonStrToTime(const AText: string): TDateTime;
var
  R: TIsoReader;
  OffsetMin: Integer;
begin
  R.Text := Trim(AText);
  R.Pos := 1;
  ReadTime(R, Result, OffsetMin);
  if not R.AtEnd then
    R.Fail;
end;

{ TJsonWriter }

constructor TJsonWriter.Create;
begin
  inherited Create;
  SetLength(FBuf, 256);
  SetLength(FNeedComma, 16);
  FNeedComma[0] := False;
end;

procedure TJsonWriter.Raw(const S: string);
var
  L: Integer;
begin
  L := Length(S);
  if L = 0 then
    Exit;
  if FLen + L > Length(FBuf) then
    SetLength(FBuf, (FLen + L) * 2);
  Move(S[1], FBuf[FLen + 1], L * SizeOf(Char));
  Inc(FLen, L);
end;

procedure TJsonWriter.RawChar(C: Char);
begin
  if FLen + 1 > Length(FBuf) then
    SetLength(FBuf, (FLen + 1) * 2);
  Inc(FLen);
  FBuf[FLen] := C;
end;

procedure TJsonWriter.BeforeValue;
begin
  if FNeedComma[FDepth] then
    RawChar(',');
  FNeedComma[FDepth] := True;
  if FHasPendingName then
  begin
    FHasPendingName := False;
    WriteQuoted(FPendingName);
    RawChar(':');
  end;
end;

procedure TJsonWriter.Push;
begin
  Inc(FDepth);
  if FDepth >= Length(FNeedComma) then
    SetLength(FNeedComma, FDepth * 2);
  FNeedComma[FDepth] := False;
end;

procedure TJsonWriter.Pop;
begin
  if FDepth = 0 then
    raise EJsonError.Create('Unbalanced EndObject/EndArray');
  Dec(FDepth);
end;

procedure TJsonWriter.BeginObject;
begin
  BeforeValue;
  RawChar('{');
  Push;
end;

procedure TJsonWriter.EndObject;
begin
  FHasPendingName := False;
  Pop;
  RawChar('}');
end;

procedure TJsonWriter.BeginArray;
begin
  BeforeValue;
  RawChar('[');
  Push;
end;

procedure TJsonWriter.EndArray;
begin
  Pop;
  RawChar(']');
end;

procedure TJsonWriter.Name(const AName: string);
begin
  FPendingName := AName;
  FHasPendingName := True;
end;

procedure TJsonWriter.WriteNull;
begin
  BeforeValue;
  Raw('null');
end;

procedure TJsonWriter.WriteBoolean(AValue: Boolean);
begin
  BeforeValue;
  if AValue then
    Raw('true')
  else
    Raw('false');
end;

procedure TJsonWriter.WriteString(const AValue: string);
begin
  BeforeValue;
  WriteQuoted(AValue);
end;

procedure TJsonWriter.WriteQuoted(const AValue: string);
const
  Hex: array[0..15] of Char = ('0', '1', '2', '3', '4', '5', '6', '7', '8',
    '9', 'a', 'b', 'c', 'd', 'e', 'f');
var
  I, Start: Integer;
  C: Char;
begin
  RawChar('"');
  Start := 1;
  for I := 1 to Length(AValue) do
  begin
    C := AValue[I];
    if (C <> '"') and (C <> '\') and (Ord(C) >= $20) then
      Continue;
    Raw(Copy(AValue, Start, I - Start));
    case C of
      '"': Raw('\"');
      '\': Raw('\\');
      #8: Raw('\b');
      #9: Raw('\t');
      #10: Raw('\n');
      #12: Raw('\f');
      #13: Raw('\r');
    else
      Raw('\u00');
      RawChar(Hex[Ord(C) shr 4]);
      RawChar(Hex[Ord(C) and $F]);
    end;
    Start := I + 1;
  end;
  Raw(Copy(AValue, Start, MaxInt));
  RawChar('"');
end;

procedure TJsonWriter.WriteNumberText(const AText: string);
begin
  BeforeValue;
  Raw(AText);
end;

procedure TJsonWriter.WriteInt64(AValue: Int64);
begin
  WriteNumberText(IntToStr(AValue));
end;

procedure TJsonWriter.WriteDouble(AValue: Double);
begin
  WriteNumberText(JsonFloatToStr(AValue));
end;

procedure TJsonWriter.WriteSingle(AValue: Single);
begin
  WriteNumberText(JsonSingleToStr(AValue));
end;

procedure TJsonWriter.WriteCurrency(AValue: Currency);
begin
  WriteNumberText(JsonCurrencyToStr(AValue));
end;

procedure TJsonWriter.WriteValue(AValue: TJsonValue);
var
  I: Integer;
begin
  case AValue.Kind of
    jkNull: WriteNull;
    jkBoolean: WriteBoolean(AValue.FBool);
    jkNumber: WriteNumberText(AValue.FText);
    jkString: WriteString(AValue.FText);
    jkArray:
      begin
        BeginArray;
        for I := 0 to AValue.Count - 1 do
          WriteValue(AValue.FItems[I]);
        EndArray;
      end;
    jkObject:
      begin
        BeginObject;
        for I := 0 to AValue.Count - 1 do
        begin
          Name(AValue.FNames[I]);
          WriteValue(AValue.FItems[I]);
        end;
        EndObject;
      end;
  end;
end;

function TJsonWriter.ToString: string;
begin
  if FDepth <> 0 then
    raise EJsonError.Create('Unclosed object/array');
  Result := Copy(FBuf, 1, FLen);
end;

initialization
  GFormatSettings := FormatSettings;
  GFormatSettings.DecimalSeparator := '.';
  GFormatSettings.ThousandSeparator := ',';

end.
