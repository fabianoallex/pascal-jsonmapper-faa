unit PascalJsonMapper.JsonTests;

{$mode delphi}{$H+}

{ GENERATED FILE — produced by tools/gen_fpc_mirror.py from
  tests/Unit/PascalJsonMapper.JsonTests.pas (DUnitX). Do not edit by hand: edit the DUnitX
  master and run the script again. }

{ Tests for the JSON layer (PascalJsonMapper.Json): parsing (escapes,
  surrogate pairs, number text kept verbatim, syntax errors with position,
  nesting limit), writing (escaping, deferred member names, number
  formatting identical on both compilers) and ISO 8601 dates.

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
  PascalJsonMapper.TestTypes;

type
  TJsonParserTests = class(TTestCase)
  private
    procedure AssertParseFails(const AJson: string);
  published
    procedure Parse_NestedStructure;
    procedure Parse_SimpleEscapes;
    procedure Parse_UnicodeEscapes_BmpAndSurrogatePair;
    procedure Parse_LatinEscapeFollowedBySurrogatePair;
    procedure Parse_LoneSurrogate_BecomesReplacementChar;
    procedure Parse_RawNonAscii_PassesThrough;
    procedure Parse_BigInteger_KeepsExactText;
    procedure Parse_SyntaxErrors_Raise;
    procedure Parse_Error_ReportsPosition;
    procedure Parse_DeepNesting_Raises;
    procedure Find_IgnoreCase;
  end;

  TJsonWriterTests = class(TTestCase)
  published
    procedure Write_EscapesControlAndQuotes;
    procedure Write_RoundTripIsCompact;
    procedure Write_NameWithoutValue_IsDropped;
    procedure Write_Double_ShortestRoundTrip;
    procedure Write_Single_ShortestRoundTrip;
    procedure Write_Currency;
    procedure Write_NaN_Raises;
  end;

  TJsonNumberTests = class(TTestCase)
  published
    procedure Read_Double_ExactBits;
    procedure Read_Single_ExactBits;
    procedure Read_Invalid_Raises;
    procedure Write_Double_HardCases;
    procedure Write_Single_Subnormal;
    procedure RoundTrip_Double_RandomBits;
    procedure RoundTrip_Single_RandomBits;
  end;

  TJsonDateTests = class(TTestCase)
  published
    procedure DateTime_Format;
    procedure DateTime_FormatWithMilliseconds;
    procedure Parse_DateOnly;
    procedure Parse_WithFractionAndZ;
    procedure Parse_WithOffset_ConvertsToUtc;
    procedure Parse_Invalid_Raises;
  end;

implementation

{ TJsonParserTests }

procedure TJsonParserTests.AssertParseFails(const AJson: string);
var
  V: TJsonValue;
begin
  V := nil;
  try
    V := ParseJson(AJson);
    TAssert.Fail('Must not parse: ' + AJson);
  except
    on E: EJsonParseError do
      ;
  end;
  V.Free;
end;

procedure TJsonParserTests.Parse_NestedStructure;
var
  V: TJsonValue;
begin
  V := ParseJson(' {"a": [1, true, null, "x"], "b": {"c": -2.5e3}} ');
  try
    TAssert.AssertTrue(V.Kind = jkObject);
    TAssert.AssertEquals(2, V.Count);
    TAssert.AssertEquals('a', V.Names[0]);
    TAssert.AssertEquals(4, V[0].Count);
    TAssert.AssertEquals(Int64(1), V[0][0].AsInt64);
    TAssert.AssertTrue(V[0][1].AsBoolean);
    TAssert.AssertTrue(V[0][2].IsNull);
    TAssert.AssertEquals('x', V[0][3].AsString);
    TAssert.AssertEquals(-2500, V.Find('b').Find('c').AsDouble, 0);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_SimpleEscapes;
var
  V: TJsonValue;
begin
  V := ParseJson('"q\" b\\ s\/ n\n t\t r\r"');
  try
    TAssert.AssertEquals('q" b\ s/ n'#10' t'#9' r'#13, V.AsString);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_UnicodeEscapes_BmpAndSurrogatePair;
var
  V: TJsonValue;
begin
  // c-cedilla, euro sign, U+1F600 (as a UTF-16 surrogate pair)
  V := ParseJson('"ç€😀"');
  try
    TAssert.AssertEquals(U([$E7, $20AC, $1F600]), V.AsString);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_LatinEscapeFollowedBySurrogatePair;
var
  V: TJsonValue;
begin
  // fpjson 3.2.2 pairs any two consecutive \u escapes; this one must not.
  V := ParseJson('"[ç😀]"');
  try
    TAssert.AssertEquals('[' + U([$E7, $1F600]) + ']', V.AsString);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_LoneSurrogate_BecomesReplacementChar;
var
  V: TJsonValue;
begin
  V := ParseJson('"a\ud83db\ude00c"');
  try
    TAssert.AssertEquals('a' + U([$FFFD]) + 'b' + U([$FFFD]) + 'c', V.AsString);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_RawNonAscii_PassesThrough;
var
  V: TJsonValue;
  S: string;
begin
  S := 'A' + U([$E7, $E3]) + 'o ' + U([$2603]);
  V := ParseJson('"' + S + '"');
  try
    TAssert.AssertEquals(S, V.AsString);
    TAssert.AssertEquals('"' + S + '"', V.ToJson);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_BigInteger_KeepsExactText;
var
  V: TJsonValue;
begin
  // 2^53 + 1: not representable as a Double.
  V := ParseJson('[9007199254740993, 1.50]');
  try
    TAssert.AssertEquals(Int64(9007199254740993), V[0].AsInt64);
    TAssert.AssertEquals('1.50', V[1].NumberText);
    TAssert.AssertEquals('[9007199254740993,1.50]', V.ToJson);
  finally
    V.Free;
  end;
end;

procedure TJsonParserTests.Parse_SyntaxErrors_Raise;
begin
  AssertParseFails('');
  AssertParseFails('{"a":1,}');
  AssertParseFails('[1,]');
  AssertParseFails('01');
  AssertParseFails('1.');
  AssertParseFails('-');
  AssertParseFails('"abc');
  AssertParseFails('"a'#10'b"');
  AssertParseFails('"\x"');
  AssertParseFails('"\u12G4"');
  AssertParseFails('{a:1}');
  AssertParseFails('tru');
  AssertParseFails('{} {}');
  AssertParseFails('NaN');
end;

procedure TJsonParserTests.Parse_Error_ReportsPosition;
begin
  try
    ParseJson('{"a": tx}').Free;
    TAssert.Fail('Must raise');
  except
    on E: EJsonParseError do
      TAssert.AssertEquals(7, E.Position);
  end;
end;

procedure TJsonParserTests.Parse_DeepNesting_Raises;
var
  S: string;
  I: Integer;
begin
  S := '';
  for I := 1 to 1000 do
    S := '[' + S + ']';
  AssertParseFails(S);
  // 500 levels are fine.
  S := '';
  for I := 1 to 500 do
    S := '[' + S + ']';
  ParseJson(S).Free;
end;

procedure TJsonParserTests.Find_IgnoreCase;
var
  V: TJsonValue;
begin
  V := ParseJson('{"Nome": 1}');
  try
    TAssert.AssertTrue(V.Find('nome') = nil);
    TAssert.AssertEquals(Int64(1), V.Find('nome', True).AsInt64);
  finally
    V.Free;
  end;
end;

{ TJsonWriterTests }

procedure TJsonWriterTests.Write_EscapesControlAndQuotes;
var
  W: TJsonWriter;
begin
  W := TJsonWriter.Create;
  try
    W.WriteString('a"b\c'#10#9#1'/');
    TAssert.AssertEquals('"a\"b\\c\n\t\u0001/"', W.ToString);
  finally
    W.Free;
  end;
end;

procedure TJsonWriterTests.Write_RoundTripIsCompact;
var
  V: TJsonValue;
begin
  V := ParseJson('{ "a" : [ 1 , { "b" : null } , [ ] ] , "c" : { } }');
  try
    TAssert.AssertEquals('{"a":[1,{"b":null},[]],"c":{}}', V.ToJson);
  finally
    V.Free;
  end;
end;

procedure TJsonWriterTests.Write_NameWithoutValue_IsDropped;
var
  W: TJsonWriter;
begin
  W := TJsonWriter.Create;
  try
    W.BeginObject;
    W.Name('omitted1');
    W.Name('a');
    W.WriteInt64(1);
    W.Name('omitted2');
    W.Name('b');
    W.WriteBoolean(False);
    W.Name('omitted3');
    W.EndObject;
    TAssert.AssertEquals('{"a":1,"b":false}', W.ToString);
  finally
    W.Free;
  end;
end;

procedure TJsonWriterTests.Write_Double_ShortestRoundTrip;
begin
  TAssert.AssertEquals('0.1', JsonFloatToStr(0.1));
  TAssert.AssertEquals('1.5', JsonFloatToStr(1.5));
  TAssert.AssertEquals('-2', JsonFloatToStr(-2));
  TAssert.AssertEquals('0', JsonFloatToStr(0));
  // Parsed, not 0.1 + 0.2: the compiler folds that constant in higher
  // precision (and x87 can double-round it at run time).
  TAssert.AssertEquals('0.30000000000000004',
    JsonFloatToStr(StrToFloat('0.30000000000000004', JsonFormatSettings)));
  TAssert.AssertEquals('0.3333333333333333', JsonFloatToStr(1 / 3));
  TAssert.AssertEquals('1E21', JsonFloatToStr(1E21));
  TAssert.AssertEquals('100000000000000000000', JsonFloatToStr(1E20));
  TAssert.AssertEquals('1.5E-7', JsonFloatToStr(1.5E-7));
  TAssert.AssertEquals('0.000001', JsonFloatToStr(StrToFloat('0.000001', JsonFormatSettings)));
  TAssert.AssertEquals('100', JsonFloatToStr(100));
  TAssert.AssertEquals('-0.5', JsonFloatToStr(-0.5));
  TAssert.AssertEquals('123456789012345680',
    JsonFloatToStr(StrToFloat('123456789012345678', JsonFormatSettings)));
  TAssert.AssertEquals('5E-324', JsonFloatToStr(StrToFloat('5E-324', JsonFormatSettings)));
  TAssert.AssertEquals('1.7976931348623157E308',
    JsonFloatToStr(StrToFloat('1.7976931348623157E308', JsonFormatSettings)));
end;

procedure TJsonWriterTests.Write_Single_ShortestRoundTrip;
var
  S: Single;
begin
  S := 0.1;
  TAssert.AssertEquals('0.1', JsonSingleToStr(S));
  S := 3.14159;
  TAssert.AssertEquals('3.14159', JsonSingleToStr(S));
end;

procedure TJsonWriterTests.Write_Currency;
var
  C: Currency;
begin
  C := 12.5;
  TAssert.AssertEquals('12.5', JsonCurrencyToStr(C));
  C := -1000;
  TAssert.AssertEquals('-1000', JsonCurrencyToStr(C));
  C := 0.0001;
  TAssert.AssertEquals('0.0001', JsonCurrencyToStr(C));
  C := 123456789012.3456;
  TAssert.AssertEquals('123456789012.3456', JsonCurrencyToStr(C));
end;

procedure TJsonWriterTests.Write_NaN_Raises;
begin
  try
    JsonFloatToStr(NaN);
    TAssert.Fail('NaN must raise');
  except
    on E: EJsonError do
      ;
  end;
end;

{ TJsonNumberTests }

// Expected bits come from CPython's float/struct (correctly rounded).

function DoubleBits(AValue: Double): Int64;
begin
  Move(AValue, Result, SizeOf(Result));
end;

function DoubleFromBits(ABits: Int64): Double;
begin
  Move(ABits, Result, SizeOf(Result));
end;

function SingleBits(AValue: Single): Int64;
var
  C: Cardinal;
begin
  Move(AValue, C, SizeOf(C));
  Result := C;
end;

function SingleFromBits(ABits: Cardinal): Single;
begin
  Move(ABits, Result, SizeOf(Result));
end;

// xorshift64: shifts and xors only, so no overflow-check trap under $Q+.
function NextRandom(var AState: UInt64): UInt64;
begin
  AState := AState xor (AState shl 13);
  AState := AState xor (AState shr 7);
  AState := AState xor (AState shl 17);
  Result := AState;
end;

procedure AssertDoubleBits(const AText: string; AExpected: Int64);
begin
  TAssert.AssertEquals(AText, AExpected, DoubleBits(JsonStrToDouble(AText)));
end;

procedure TJsonNumberTests.Read_Double_ExactBits;
begin
  AssertDoubleBits('0.1', $3FB999999999999A);
  AssertDoubleBits('0.30000000000000004', $3FD3333333333334);
  AssertDoubleBits('1e23', $44B52D02C7E14AF6);
  AssertDoubleBits('0.000001', $3EB0C6F7A0B5ED8D);
  AssertDoubleBits('123456789012345678901234567890', $45F8EE90FF6C373E);
  // Ties to even
  AssertDoubleBits('9007199254740993', $4340000000000000);
  AssertDoubleBits('9007199254740995', $4340000000000002);
  // Subnormals and the halfway point below the smallest one
  AssertDoubleBits('5e-324', $0000000000000001);
  AssertDoubleBits('2.4703282292062327e-324', $0000000000000000);
  AssertDoubleBits('2.4703282292062328e-324', $0000000000000001);
  AssertDoubleBits('2.2250738585072011e-308', $000FFFFFFFFFFFFF);
  AssertDoubleBits('2.2250738585072014e-308', $0010000000000000);
  AssertDoubleBits('1e-400', $0000000000000000);
  // Largest finite, power of two, negative zero
  AssertDoubleBits('1.7976931348623157e308', $7FEFFFFFFFFFFFFF);
  AssertDoubleBits('8.98846567431158e307', $7FE0000000000000);
  AssertDoubleBits('-0', Int64($8000000000000000));
  AssertDoubleBits('-0.1', Int64($BFB999999999999A));
end;

procedure TJsonNumberTests.Read_Single_ExactBits;
begin
  TAssert.AssertEquals(Int64($3DCCCCCD), SingleBits(JsonStrToSingle('0.1')));
  TAssert.AssertEquals(Int64($7F7FFFFF), SingleBits(JsonStrToSingle('3.4028235e38')));
  TAssert.AssertEquals(Int64($00000001), SingleBits(JsonStrToSingle('1.4e-45')));
  TAssert.AssertEquals(Int64($4B800000), SingleBits(JsonStrToSingle('16777217')));
  TAssert.AssertEquals(Int64($40490FD0), SingleBits(JsonStrToSingle('3.14159')));
end;

procedure TJsonNumberTests.Read_Invalid_Raises;
const
  Bad: array[0..6] of string = ('', '-', '1.', '.5', '1e', '0x10', '1e309');
var
  I: Integer;
begin
  for I := 0 to High(Bad) do
    try
      JsonStrToDouble(Bad[I]);
      TAssert.Fail('Must raise: "' + Bad[I] + '"');
    except
      on E: EJsonError do
        ;
    end;
  try
    JsonStrToSingle('3.5e38');
    TAssert.Fail('Single overflow must raise');
  except
    on E: EJsonError do
      ;
  end;
end;

procedure TJsonNumberTests.Write_Double_HardCases;
begin
  TAssert.AssertEquals('5E-324', JsonFloatToStr(DoubleFromBits($0000000000000001)));
  TAssert.AssertEquals('2.225073858507201E-308', JsonFloatToStr(DoubleFromBits($000FFFFFFFFFFFFF)));
  TAssert.AssertEquals('2.2250738585072014E-308', JsonFloatToStr(DoubleFromBits($0010000000000000)));
  TAssert.AssertEquals('8.98846567431158E307', JsonFloatToStr(DoubleFromBits($7FE0000000000000)));
  TAssert.AssertEquals('1E23', JsonFloatToStr(DoubleFromBits($44B52D02C7E14AF6)));
  TAssert.AssertEquals('9007199254740992', JsonFloatToStr(DoubleFromBits($4340000000000000)));
  TAssert.AssertEquals('1.2345678901234568E29', JsonFloatToStr(DoubleFromBits($45F8EE90FF6C373E)));
  TAssert.AssertEquals('-0.1', JsonFloatToStr(DoubleFromBits(Int64($BFB999999999999A))));
end;

procedure TJsonNumberTests.Write_Single_Subnormal;
begin
  TAssert.AssertEquals('1E-45', JsonSingleToStr(SingleFromBits($00000001)));
  TAssert.AssertEquals('3.4028235E38', JsonSingleToStr(SingleFromBits($7F7FFFFF)));
end;

procedure TJsonNumberTests.RoundTrip_Double_RandomBits;
var
  State, Bits: UInt64;
  I, Checked: Integer;
  Text: string;
begin
  State := 88172645463325252;
  Checked := 0;
  for I := 1 to 20000 do
  begin
    Bits := NextRandom(State);
    if (Bits shr 52) and $7FF = $7FF then
      Continue;  // NaN/infinity
    Text := JsonFloatToStr(DoubleFromBits(Int64(Bits)));
    if DoubleBits(JsonStrToDouble(Text)) <> Int64(Bits) then
      TAssert.Fail('Round trip of ' + IntToHex(Int64(Bits), 16) + ' via ' + Text);
    Inc(Checked);
  end;
  TAssert.AssertTrue(Checked > 19000);
end;

procedure TJsonNumberTests.RoundTrip_Single_RandomBits;
var
  State: UInt64;
  Bits: Cardinal;
  I: Integer;
  Text: string;
begin
  State := 2463534242;
  for I := 1 to 20000 do
  begin
    Bits := Cardinal(NextRandom(State) and $FFFFFFFF);
    if (Bits shr 23) and $FF = $FF then
      Continue;
    Text := JsonSingleToStr(SingleFromBits(Bits));
    if SingleBits(JsonStrToSingle(Text)) <> Int64(Bits) then
      TAssert.Fail('Round trip of ' + IntToHex(Int64(Bits), 8) + ' via ' + Text);
  end;
end;

{ TJsonDateTests }

procedure TJsonDateTests.DateTime_Format;
begin
  TAssert.AssertEquals('2026-10-02T13:45:10',
    JsonDateTimeToStr(EncodeDateTime(2026, 10, 2, 13, 45, 10, 0)));
  TAssert.AssertEquals('2026-10-02', JsonDateToStr(EncodeDate(2026, 10, 2)));
end;

procedure TJsonDateTests.DateTime_FormatWithMilliseconds;
begin
  TAssert.AssertEquals('2026-10-02T13:45:10.007',
    JsonDateTimeToStr(EncodeDateTime(2026, 10, 2, 13, 45, 10, 7)));
end;

procedure TJsonDateTests.Parse_DateOnly;
begin
  TAssert.AssertEquals(EncodeDate(2026, 10, 2), JsonStrToDateTime('2026-10-02'), 0);
end;

procedure TJsonDateTests.Parse_WithFractionAndZ;
begin
  TAssert.AssertEquals(EncodeDateTime(2026, 10, 2, 13, 45, 10, 123),
    JsonStrToDateTime('2026-10-02T13:45:10.1239Z'), 1 / MSecsPerDay / 2);
end;

procedure TJsonDateTests.Parse_WithOffset_ConvertsToUtc;
begin
  TAssert.AssertEquals(EncodeDateTime(2026, 10, 2, 16, 45, 0, 0),
    JsonStrToDateTime('2026-10-02T13:45:00-03:00'), 1 / MSecsPerDay / 2);
end;

procedure TJsonDateTests.Parse_Invalid_Raises;
begin
  try
    JsonStrToDateTime('2026-02-30');
    TAssert.Fail('Invalid date must raise');
  except
    on E: EJsonError do
      ;
  end;
  try
    JsonStrToDateTime('02/10/2026');
    TAssert.Fail('Non-ISO date must raise');
  except
    on E: EJsonError do
      ;
  end;
end;

initialization
  RegisterTest(TJsonParserTests);
  RegisterTest(TJsonWriterTests);
  RegisterTest(TJsonNumberTests);
  RegisterTest(TJsonDateTests);

end.
