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

    function ToJson(AIndent: Integer = 0): string;
  end;

  { Appends JSON text. Tracks commas itself, so callers just emit tokens in
    order: BeginObject, Name('x'), WriteInt64(1), EndObject...

    Name() is deferred: the member name is only emitted together with the
    next value. A Name() followed by another Name() or by EndObject is
    dropped, which is how a converter omits a member (it simply writes
    nothing).

    Indent > 0 puts every member and element on a line of its own, indented
    by that many spaces per level, with ": " after names. Line breaks are
    always #10, on every platform, so the text is the same everywhere. }
  TJsonWriter = class
  private
    FBuf: string;
    FLen: Integer;
    FNeedComma: array of Boolean;
    FDepth: Integer;
    FPendingName: string;
    FHasPendingName: Boolean;
    FIndent: Integer;
    procedure Raw(const S: string);
    procedure NewLine(ADepth: Integer);
    procedure RawChar(C: Char);
    procedure BeforeValue;
    procedure Push;
    procedure Pop;
    procedure WriteQuoted(const AValue: string);
  public
    constructor Create(AIndent: Integer = 0);
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
    property Indent: Integer read FIndent;
  end;

// Parses a complete JSON text. Raises EJsonParseError on any syntax error or
// trailing content. The caller owns the result.
function ParseJson(const AText: string): TJsonValue;

// Shortest decimal text that reads back as exactly the same Double/Single,
// and its inverse, correctly rounded. Computed with exact integer arithmetic,
// not the RTL, so every compiler/target gives the same text and the same
// bits. JsonFloatToStr raises EJsonError for NaN and infinities (JSON has no
// representation); the readers raise it for malformed or out-of-range text.
function JsonFloatToStr(AValue: Double): string;
function JsonSingleToStr(AValue: Single): string;
function JsonStrToDouble(const AText: string): Double;
function JsonStrToSingle(const AText: string): Single;
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
  Result := JsonStrToDouble(FText);
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

function TJsonValue.ToJson(AIndent: Integer): string;
var
  W: TJsonWriter;
begin
  W := TJsonWriter.Create(AIndent);
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

{ Number conversion

  Binary <-> decimal conversion of Double/Single is done here with exact
  big-integer arithmetic, not with the RTL: FloatToStrF stops at 15 digits
  on FPC targets without an 80-bit Extended (Win64, ARM), and on Delphi 12
  Win64 the RTL round trip printed 0.30000000000000004 as
  0.30000000000000006. Doing it here makes the text identical on every
  compiler and target, by construction.

  Writing: Burger & Dybvig's free-format algorithm ("Printing Floating-Point
  Numbers Quickly and Accurately", 1996): the shortest digit string that
  reads back as the same value. Reading: exact quotient of the decimal
  number by a power of two, rounded half to even.

  Layout follows JavaScript's Number.toString: fixed notation when the
  decimal exponent is in -7 < X < 21, else d.dddE[-]X. }

type
  // Unsigned big integer, little-endian base 2^32, with a fixed capacity:
  // conversions never touch the heap (allocating per operation made them
  // ~20x slower under heaptrc, and slow without it too). Sizes needed:
  // writing <= ~1150 bits; reading <= ~3820 bits (800 significant digits
  // scaled by 10^1131, shifted by 55 for the quotient).
  TBig = record
    Len: Integer;
    W: array[0..159] of Cardinal;
  end;

  TFloatFormatInfo = record
    Precision: Integer;  // mantissa bits, hidden bit included
    MinE: Integer;       // exponent of the smallest subnormal (value = F * 2^E)
    MaxE: Integer;       // largest E with a finite value
  end;

const
  BigWords = 160;
  DoubleFormat: TFloatFormatInfo = (Precision: 53; MinE: -1074; MaxE: 971);
  SingleFormat: TFloatFormatInfo = (Precision: 24; MinE: -149; MaxE: 104);

procedure BigOverflow;
begin
  // Unreachable with the input bounds enforced by the callers.
  raise EJsonError.Create('Internal error: number conversion exceeded its capacity');
end;

procedure BigNormalize(var A: TBig);
begin
  while (A.Len > 0) and (A.W[A.Len - 1] = 0) do
    Dec(A.Len);
end;

procedure BigSetU64(var A: TBig; AValue: UInt64);
begin
  A.W[0] := Cardinal(AValue and $FFFFFFFF);
  A.W[1] := Cardinal(AValue shr 32);
  A.Len := 2;
  BigNormalize(A);
end;

function BigCmp(const A, B: TBig): Integer;
var
  I: Integer;
begin
  if A.Len <> B.Len then
  begin
    if A.Len > B.Len then
      Exit(1);
    Exit(-1);
  end;
  for I := A.Len - 1 downto 0 do
    if A.W[I] <> B.W[I] then
    begin
      if A.W[I] > B.W[I] then
        Exit(1);
      Exit(-1);
    end;
  Result := 0;
end;

// A := A + B
procedure BigAdd(var A: TBig; const B: TBig);
var
  I, N: Integer;
  X, Y: Cardinal;
  Sum: UInt64;
begin
  N := A.Len;
  if B.Len > N then
    N := B.Len;
  Sum := 0;
  for I := 0 to N - 1 do
  begin
    if I < A.Len then X := A.W[I] else X := 0;
    if I < B.Len then Y := B.W[I] else Y := 0;
    Sum := UInt64(X) + Y + (Sum shr 32);
    A.W[I] := Cardinal(Sum and $FFFFFFFF);
  end;
  A.Len := N;
  if (Sum shr 32) <> 0 then
  begin
    if N >= BigWords then
      BigOverflow;
    A.W[N] := Cardinal(Sum shr 32);
    A.Len := N + 1;
  end;
end;

// A := A - B, with A >= B
procedure BigSub(var A: TBig; const B: TBig);
var
  I: Integer;
  Y: Cardinal;
  Diff, Borrow: Int64;
begin
  Borrow := 0;
  for I := 0 to A.Len - 1 do
  begin
    if I < B.Len then
      Y := B.W[I]
    else
    begin
      if Borrow = 0 then
        Break;
      Y := 0;
    end;
    Diff := Int64(A.W[I]) - Int64(Y) - Borrow;
    if Diff < 0 then
    begin
      Diff := Diff + $100000000;
      Borrow := 1;
    end
    else
      Borrow := 0;
    A.W[I] := Cardinal(Diff);
  end;
  BigNormalize(A);
end;

// A := A * AFactor
procedure BigMulSmall(var A: TBig; AFactor: Cardinal);
var
  I: Integer;
  Product: UInt64;
begin
  Product := 0;
  for I := 0 to A.Len - 1 do
  begin
    Product := UInt64(A.W[I]) * AFactor + (Product shr 32);
    A.W[I] := Cardinal(Product and $FFFFFFFF);
  end;
  if (Product shr 32) <> 0 then
  begin
    if A.Len >= BigWords then
      BigOverflow;
    A.W[A.Len] := Cardinal(Product shr 32);
    Inc(A.Len);
  end;
  BigNormalize(A);
end;

// R := A * B (R must be a different variable from A and B)
procedure BigMul(var R: TBig; const A, B: TBig);
var
  I, J: Integer;
  Product, Carry: UInt64;
begin
  if (A.Len = 0) or (B.Len = 0) then
  begin
    R.Len := 0;
    Exit;
  end;
  if A.Len + B.Len > BigWords then
    BigOverflow;
  for I := 0 to A.Len + B.Len - 1 do
    R.W[I] := 0;
  for I := 0 to A.Len - 1 do
  begin
    Carry := 0;
    for J := 0 to B.Len - 1 do
    begin
      // (2^32-1)^2 + 2 * (2^32-1) = 2^64 - 1: never overflows.
      Product := UInt64(A.W[I]) * B.W[J] + R.W[I + J] + Carry;
      R.W[I + J] := Cardinal(Product and $FFFFFFFF);
      Carry := Product shr 32;
    end;
    R.W[I + B.Len] := Cardinal(Carry);
  end;
  R.Len := A.Len + B.Len;
  BigNormalize(R);
end;

// A := A shl ABits
procedure BigShl(var A: TBig; ABits: Integer);
var
  Words, Bits, I: Integer;
  Top: Cardinal;
begin
  if (A.Len = 0) or (ABits = 0) then
    Exit;
  Words := ABits div 32;
  Bits := ABits mod 32;
  if Bits = 0 then
  begin
    if A.Len + Words > BigWords then
      BigOverflow;
    for I := A.Len - 1 downto 0 do
      A.W[I + Words] := A.W[I];
    Top := 0;
  end
  else
  begin
    Top := A.W[A.Len - 1] shr (32 - Bits);
    if A.Len + Words + Ord(Top <> 0) > BigWords then
      BigOverflow;
    if Top <> 0 then
      A.W[A.Len + Words] := Top;
    // Shifts done in 64 bits and masked: a Cardinal shl is 32-bit on Delphi
    // but widened on 64-bit FPC.
    for I := A.Len - 1 downto 1 do
      A.W[I + Words] := Cardinal((UInt64(A.W[I]) shl Bits) and $FFFFFFFF) or
        (A.W[I - 1] shr (32 - Bits));
    A.W[Words] := Cardinal((UInt64(A.W[0]) shl Bits) and $FFFFFFFF);
  end;
  for I := 0 to Words - 1 do
    A.W[I] := 0;
  A.Len := A.Len + Words + Ord(Top <> 0);
end;

// A := 10^AExp
procedure BigPow10(var A: TBig; AExp: Integer);
begin
  BigSetU64(A, 1);
  while AExp >= 9 do
  begin
    BigMulSmall(A, 1000000000);
    Dec(AExp, 9);
  end;
  while AExp > 0 do
  begin
    BigMulSmall(A, 10);
    Dec(AExp);
  end;
end;

function BigBitLength(const A: TBig): Integer;
var
  X: Cardinal;
begin
  if A.Len = 0 then
    Exit(0);
  Result := (A.Len - 1) * 32;
  X := A.W[A.Len - 1];
  while X <> 0 do
  begin
    Inc(Result);
    X := X shr 1;
  end;
end;

// A := the decimal digit string, nine digits at a time.
procedure BigFromDigits(var A: TBig; const ADigits: string);
var
  I, ChunkLen: Integer;
  Chunk, Scale: Cardinal;
  C: TBig;
begin
  A.Len := 0;
  Chunk := 0;
  ChunkLen := 0;
  Scale := 1;
  for I := 1 to Length(ADigits) do
  begin
    Chunk := Chunk * 10 + Cardinal(Ord(ADigits[I]) - Ord('0'));
    Scale := Scale * 10;
    Inc(ChunkLen);
    if (ChunkLen = 9) or (I = Length(ADigits)) then
    begin
      BigMulSmall(A, Scale);
      BigSetU64(C, Chunk);
      BigAdd(A, C);
      Chunk := 0;
      ChunkLen := 0;
      Scale := 1;
    end;
  end;
end;

{ Writing }

// Shortest digits d1d2...dn and K such that the value is 0.d1d2...dn x 10^K
// (Burger & Dybvig, free-format, IEEE round-half-even reader assumed).
procedure ShortestDigits(AF: UInt64; AE: Integer; const AFormat: TFloatFormatInfo;
  AValue: Double; out ADigits: string; out AK: Integer);
var
  R, S, MPlus, MMinus, Scale, T: TBig;
  Est, D: Integer;
  Hidden: UInt64;
  Even, TooLow, TooHigh: Boolean;
begin
  Even := (AF and 1) = 0;
  Hidden := UInt64(1) shl (AFormat.Precision - 1);
  BigSetU64(R, AF);
  if AE >= 0 then
  begin
    if AF <> Hidden then
    begin
      BigShl(R, AE + 1);
      BigSetU64(S, 2);
      BigSetU64(MPlus, 1);
      BigShl(MPlus, AE);
      MMinus := MPlus;
    end
    else
    begin
      // Power of two: the gap below is half the gap above.
      BigShl(R, AE + 2);
      BigSetU64(S, 4);
      BigSetU64(MPlus, 1);
      BigShl(MPlus, AE + 1);
      BigSetU64(MMinus, 1);
      BigShl(MMinus, AE);
    end;
  end
  else if (AE = AFormat.MinE) or (AF <> Hidden) then
  begin
    BigShl(R, 1);
    BigSetU64(S, 1);
    BigShl(S, 1 - AE);
    BigSetU64(MPlus, 1);
    MMinus := MPlus;
  end
  else
  begin
    BigShl(R, 2);
    BigSetU64(S, 1);
    BigShl(S, 2 - AE);
    BigSetU64(MPlus, 2);
    BigSetU64(MMinus, 1);
  end;

  // Estimate K; the fixup below corrects an estimate one too low.
  Est := Ceil(Log10(AValue) - 1E-10);
  if Est >= 0 then
  begin
    BigPow10(Scale, Est);
    T := S;
    BigMul(S, T, Scale);
  end
  else
  begin
    BigPow10(Scale, -Est);
    T := R;
    BigMul(R, T, Scale);
    T := MPlus;
    BigMul(MPlus, T, Scale);
    T := MMinus;
    BigMul(MMinus, T, Scale);
  end;
  T := R;
  BigAdd(T, MPlus);
  if (BigCmp(T, S) > 0) or (Even and (BigCmp(T, S) = 0)) then
    AK := Est + 1
  else
  begin
    AK := Est;
    BigMulSmall(R, 10);
    BigMulSmall(MPlus, 10);
    BigMulSmall(MMinus, 10);
  end;

  ADigits := '';
  while True do
  begin
    D := 0;
    while BigCmp(R, S) >= 0 do
    begin
      BigSub(R, S);
      Inc(D);
    end;
    TooLow := (BigCmp(R, MMinus) < 0) or (Even and (BigCmp(R, MMinus) = 0));
    T := R;
    BigAdd(T, MPlus);
    TooHigh := (BigCmp(T, S) > 0) or (Even and (BigCmp(T, S) = 0));
    if not TooLow and not TooHigh then
    begin
      ADigits := ADigits + Char(Ord('0') + D);
      BigMulSmall(R, 10);
      BigMulSmall(MPlus, 10);
      BigMulSmall(MMinus, 10);
      Continue;
    end;
    if TooLow and TooHigh then
    begin
      // Both neighbours' digits work: take the closer one.
      T := R;
      BigShl(T, 1);
      if BigCmp(T, S) >= 0 then
        Inc(D);
    end
    else if TooHigh then
      Inc(D);
    ADigits := ADigits + Char(Ord('0') + D);
    Break;
  end;
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
  Bits, Mantissa: UInt64;
  Biased, E, K: Integer;
  F: UInt64;
  Digits: string;
begin
  CheckFinite(AValue);
  if AValue = 0 then
    Exit('0');
  Move(AValue, Bits, SizeOf(Bits));
  Mantissa := Bits and ((UInt64(1) shl 52) - 1);
  Biased := Integer((Bits shr 52) and $7FF);
  if Biased = 0 then
  begin
    F := Mantissa;
    E := DoubleFormat.MinE;
  end
  else
  begin
    F := Mantissa or (UInt64(1) shl 52);
    E := Biased - 1075;
  end;
  ShortestDigits(F, E, DoubleFormat, Abs(AValue), Digits, K);
  Result := LayoutNumber(AValue < 0, Digits, K - 1);
end;

function JsonSingleToStr(AValue: Single): string;
var
  Bits, Mantissa: Cardinal;
  Biased, E, K: Integer;
  F: UInt64;
  Digits: string;
begin
  CheckFinite(AValue);
  if AValue = 0 then
    Exit('0');
  Move(AValue, Bits, SizeOf(Bits));
  Mantissa := Bits and $7FFFFF;
  Biased := Integer((Bits shr 23) and $FF);
  if Biased = 0 then
  begin
    F := Mantissa;
    E := SingleFormat.MinE;
  end
  else
  begin
    F := Mantissa or $800000;
    E := Biased - 150;
  end;
  ShortestDigits(F, E, SingleFormat, Abs(AValue), Digits, K);
  Result := LayoutNumber(AValue < 0, Digits, K - 1);
end;

{ Reading }

const
  // Significant digits kept when reading. Beyond this, only "were the dropped
  // digits all zero?" can change the rounding, and a sticky digit keeps that.
  MaxSignificantDigits = 800;

// Splits a JSON number into sign, significant digits (no leading/trailing
// zeros) and a decimal exponent: value = Digits x 10^Exp10.
function SplitNumber(const AText: string; out ANegative: Boolean;
  out ADigits: string; out AExp10: Integer): Boolean;
var
  I, L, FracLen, ExpValue: Integer;
  ExpNegative, Sticky: Boolean;
  IntPart, FracPart: string;
begin
  Result := False;
  L := Length(AText);
  I := 1;
  ANegative := (I <= L) and (AText[I] = '-');
  if ANegative then
    Inc(I);
  IntPart := '';
  while (I <= L) and (AText[I] >= '0') and (AText[I] <= '9') do
  begin
    IntPart := IntPart + AText[I];
    Inc(I);
  end;
  if IntPart = '' then
    Exit;
  FracPart := '';
  if (I <= L) and (AText[I] = '.') then
  begin
    Inc(I);
    while (I <= L) and (AText[I] >= '0') and (AText[I] <= '9') do
    begin
      FracPart := FracPart + AText[I];
      Inc(I);
    end;
    if FracPart = '' then
      Exit;
  end;
  ExpValue := 0;
  if (I <= L) and ((AText[I] = 'e') or (AText[I] = 'E')) then
  begin
    Inc(I);
    ExpNegative := (I <= L) and (AText[I] = '-');
    if (I <= L) and ((AText[I] = '-') or (AText[I] = '+')) then
      Inc(I);
    if (I > L) or (AText[I] < '0') or (AText[I] > '9') then
      Exit;
    while (I <= L) and (AText[I] >= '0') and (AText[I] <= '9') do
    begin
      // Saturate: anything past 10^6 is overflow or zero anyway.
      if ExpValue < 1000000 then
        ExpValue := ExpValue * 10 + Ord(AText[I]) - Ord('0');
      Inc(I);
    end;
    if ExpNegative then
      ExpValue := -ExpValue;
  end;
  if I <= L then
    Exit;

  FracLen := Length(FracPart);
  ADigits := IntPart + FracPart;
  AExp10 := ExpValue - FracLen;
  I := 1;
  while (I < Length(ADigits)) and (ADigits[I] = '0') do
    Inc(I);
  ADigits := Copy(ADigits, I, MaxInt);
  L := Length(ADigits);
  while (L > 0) and (ADigits[L] = '0') do
  begin
    Dec(L);
    Inc(AExp10);
  end;
  SetLength(ADigits, L);
  if ADigits = '' then
    ADigits := '0';
  if Length(ADigits) > MaxSignificantDigits then
  begin
    Sticky := False;
    for I := MaxSignificantDigits + 1 to Length(ADigits) do
      if ADigits[I] <> '0' then
        Sticky := True;
    Inc(AExp10, Length(ADigits) - MaxSignificantDigits);
    SetLength(ADigits, MaxSignificantDigits);
    if Sticky then
    begin
      ADigits := ADigits + '1';
      Dec(AExp10);
    end;
  end;
  Result := True;
end;

// Quotient of N / D known to be below 2^(AMaxBits + 1); ARem gets N mod D.
function BigDivSmallQuotient(const N, D: TBig; AMaxBits: Integer; out ARem: TBig): UInt64;
var
  B: Integer;
  T: TBig;
begin
  Result := 0;
  ARem := N;
  for B := AMaxBits downto 0 do
  begin
    T := D;
    BigShl(T, B);
    if BigCmp(ARem, T) >= 0 then
    begin
      BigSub(ARem, T);
      Result := Result or (UInt64(1) shl B);
    end;
  end;
end;

// Digits x 10^Exp10 as F x 2^E, correctly rounded (half to even) to the
// format. False on overflow. F = 0 on underflow to zero.
function DecimalToBinary(const ADigits: string; AExp10: Integer;
  const AFormat: TFloatFormatInfo; out AF: UInt64; out AE: Integer): Boolean;
var
  N, D, NS, DS, Rem, P, T: TBig;
  Q, Limit: UInt64;
  Cmp: Integer;
begin
  AF := 0;
  AE := 0;
  Result := True;
  if ADigits = '0' then
    Exit;
  // Magnitude bounds, before any big arithmetic: 10^(n+Exp10-1) <= value.
  if Length(ADigits) + AExp10 > 310 then
    Exit(False);
  if Length(ADigits) + AExp10 < -330 then
    Exit;

  BigFromDigits(N, ADigits);
  if AExp10 >= 0 then
  begin
    BigPow10(P, AExp10);
    T := N;
    BigMul(N, T, P);
    BigSetU64(D, 1);
  end
  else
    BigPow10(D, -AExp10);

  Limit := UInt64(1) shl AFormat.Precision;
  AE := BigBitLength(N) - BigBitLength(D) - AFormat.Precision;
  while True do
  begin
    if AE < AFormat.MinE then
      AE := AFormat.MinE;
    NS := N;
    DS := D;
    if AE >= 0 then
      BigShl(DS, AE)
    else
      BigShl(NS, -AE);
    Q := BigDivSmallQuotient(NS, DS, AFormat.Precision + 1, Rem);
    if Q < Limit then
      Break;
    Inc(AE);
  end;

  BigShl(Rem, 1);
  Cmp := BigCmp(Rem, DS);
  if (Cmp > 0) or ((Cmp = 0) and ((Q and 1) = 1)) then
  begin
    Inc(Q);
    if Q = Limit then
    begin
      Q := Q shr 1;
      Inc(AE);
    end;
  end;
  if AE > AFormat.MaxE then
    Exit(False);
  AF := Q;
end;

procedure ReadFloat(const AText: string; const AFormat: TFloatFormatInfo;
  out ANegative: Boolean; out AF: UInt64; out AE: Integer);
var
  Digits: string;
  Exp10: Integer;
begin
  if not SplitNumber(AText, ANegative, Digits, Exp10) then
    raise EJsonError.CreateFmt('Invalid number "%s"', [AText]);
  if not DecimalToBinary(Digits, Exp10, AFormat, AF, AE) then
    raise EJsonError.CreateFmt('Number %s is out of range', [AText]);
end;

function JsonStrToDouble(const AText: string): Double;
var
  Negative: Boolean;
  F, Bits: UInt64;
  E: Integer;
begin
  ReadFloat(AText, DoubleFormat, Negative, F, E);
  if F < (UInt64(1) shl 52) then
    Bits := F  // subnormal or zero: E = MinE
  else
    Bits := (UInt64(E + 1075) shl 52) or (F and ((UInt64(1) shl 52) - 1));
  if Negative then
    Bits := Bits or (UInt64(1) shl 63);
  Move(Bits, Result, SizeOf(Result));
end;

function JsonStrToSingle(const AText: string): Single;
var
  Negative: Boolean;
  F: UInt64;
  Bits: Cardinal;
  E: Integer;
begin
  ReadFloat(AText, SingleFormat, Negative, F, E);
  if F < $800000 then
    Bits := Cardinal(F)
  else
    Bits := (Cardinal(E + 150) shl 23) or (Cardinal(F) and $7FFFFF);
  if Negative then
    Bits := Bits or $80000000;
  Move(Bits, Result, SizeOf(Result));
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

constructor TJsonWriter.Create(AIndent: Integer);
begin
  inherited Create;
  FIndent := AIndent;
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

procedure TJsonWriter.NewLine(ADepth: Integer);
begin
  if FIndent > 0 then
  begin
    RawChar(#10);
    Raw(StringOfChar(' ', ADepth * FIndent));
  end;
end;

procedure TJsonWriter.BeforeValue;
begin
  if FNeedComma[FDepth] then
    RawChar(',');
  if FDepth > 0 then
    NewLine(FDepth);
  FNeedComma[FDepth] := True;
  if FHasPendingName then
  begin
    FHasPendingName := False;
    WriteQuoted(FPendingName);
    RawChar(':');
    if FIndent > 0 then
      RawChar(' ');
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
var
  HadMembers: Boolean;
begin
  FHasPendingName := False;
  HadMembers := FNeedComma[FDepth];
  Pop;
  if HadMembers then
    NewLine(FDepth);
  RawChar('}');
end;

procedure TJsonWriter.BeginArray;
begin
  BeforeValue;
  RawChar('[');
  Push;
end;

procedure TJsonWriter.EndArray;
var
  HadElements: Boolean;
begin
  HadElements := FNeedComma[FDepth];
  Pop;
  if HadElements then
    NewLine(FDepth);
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
