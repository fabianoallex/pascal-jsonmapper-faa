unit PascalJsonMapper.TestOptionalsBridge;

{ Bridge between the mapper and PascalJsonMapper.TestOptionals: the unit a
  library that owns optional types (pascal-common-faa) ships in a package
  of its own, so that neither core depends on the other.

  One converter covers every optional interface (here 6: Opt/Null/OptNull x
  string/Integer). The JSON rules per flavor:

               reading                     writing
    IOptXxx     null -> error               nil/undefined -> member omitted;
                                            null -> null [1]
    INullXxx    null -> Null                nil/null      -> null
    IOptNullXxx null -> Null                nil/undefined -> omitted; null -> null

  [1] IOptXxx has no Null state, but TOptNullXxx.Null assigned to one
  compiles (one class implements the three flavors); its Value would be a
  made-up '' or 0, so it is written as null. Same rule as pascal-common-faa's
  PascalCommon.JsonMapper.Optionals, which this unit models.

  A value is read and written by delegating to the mapper (ReadValue /
  WriteValue with the same path), so number/string rules and error paths are
  the mapper's own. Inside an array an omitted element becomes null.

  Using this unit registers the converter on TJsonMapper.Shared; mappers
  created by hand get it from RegisterOptionalsConverter.

  Note on querying the value: IOptional<string> and IOptional<Integer> share
  one GUID (it is declared on the generic), so Supports(X, IOptional<T>)
  can't tell the specializations apart. Query the concrete interface
  (IOptString, IOptInteger...) instead, as below. }

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils, TypInfo, Rtti,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper,
  PascalJsonMapper.TestOptionals;

type
  TOptFlavor = (ofOpt, ofNull, ofOptNull);

  TOptionalsJsonConverter = class(TInterfacedObject, IJsonConverter)
  private
    function Describe(ATypeInfo: PTypeInfo; out AValueType: PTypeInfo;
      out AFlavor: TOptFlavor): Boolean;
    function NewNull(AValueType: PTypeInfo): TOptionalNullableBase;
    function NewFrom(AValueType: PTypeInfo; const AValue: TValue): TOptionalNullableBase;
    function ValueOf(const AIntf: IInterface; ATypeInfo: PTypeInfo): TValue;
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
      ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
    function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
      ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
  end;

procedure RegisterOptionalsConverter(AMapper: TJsonMapper);

implementation

procedure RegisterOptionalsConverter(AMapper: TJsonMapper);
begin
  AMapper.RegisterConverter(TOptionalsJsonConverter.Create);
end;

{ TOptionalsJsonConverter }

function TOptionalsJsonConverter.Describe(ATypeInfo: PTypeInfo;
  out AValueType: PTypeInfo; out AFlavor: TOptFlavor): Boolean;
begin
  Result := True;
  if ATypeInfo = TypeInfo(IOptString) then
  begin
    AValueType := TypeInfo(string);
    AFlavor := ofOpt;
  end
  else if ATypeInfo = TypeInfo(INullString) then
  begin
    AValueType := TypeInfo(string);
    AFlavor := ofNull;
  end
  else if ATypeInfo = TypeInfo(IOptNullString) then
  begin
    AValueType := TypeInfo(string);
    AFlavor := ofOptNull;
  end
  else if ATypeInfo = TypeInfo(IOptInteger) then
  begin
    AValueType := TypeInfo(Integer);
    AFlavor := ofOpt;
  end
  else if ATypeInfo = TypeInfo(INullInteger) then
  begin
    AValueType := TypeInfo(Integer);
    AFlavor := ofNull;
  end
  else if ATypeInfo = TypeInfo(IOptNullInteger) then
  begin
    AValueType := TypeInfo(Integer);
    AFlavor := ofOptNull;
  end
  else
  begin
    AValueType := nil;
    AFlavor := ofOpt;
    Result := False;
  end;
end;

function TOptionalsJsonConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
var
  ValueType: PTypeInfo;
  Flavor: TOptFlavor;
begin
  Result := Describe(ATypeInfo, ValueType, Flavor);
end;

function TOptionalsJsonConverter.NewNull(AValueType: PTypeInfo): TOptionalNullableBase;
begin
  if AValueType = TypeInfo(string) then
    Result := TOptNullString.Null
  else
    Result := TOptNullInteger.Null;
end;

function TOptionalsJsonConverter.NewFrom(AValueType: PTypeInfo;
  const AValue: TValue): TOptionalNullableBase;
begin
  if AValueType = TypeInfo(string) then
    Result := TOptNullString.From(AValue.AsString)
  else
    Result := TOptNullInteger.From(AValue.AsInteger);
end;

function TOptionalsJsonConverter.ValueOf(const AIntf: IInterface;
  ATypeInfo: PTypeInfo): TValue;
begin
  if ATypeInfo = TypeInfo(IOptString) then
    Result := TValue.From<string>((AIntf as IOptString).Value)
  else if ATypeInfo = TypeInfo(INullString) then
    Result := TValue.From<string>((AIntf as INullString).Value)
  else if ATypeInfo = TypeInfo(IOptNullString) then
    Result := TValue.From<string>((AIntf as IOptNullString).Value)
  else if ATypeInfo = TypeInfo(IOptInteger) then
    Result := TValue.From<Integer>((AIntf as IOptInteger).Value)
  else if ATypeInfo = TypeInfo(INullInteger) then
    Result := TValue.From<Integer>((AIntf as INullInteger).Value)
  else
    Result := TValue.From<Integer>((AIntf as IOptNullInteger).Value);
end;

function TOptionalsJsonConverter.ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
  ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
var
  ValueType: PTypeInfo;
  Flavor: TOptFlavor;
  Inner: TValue;
  Obj: TOptionalNullableBase;
  Intf: IInterface;
begin
  Describe(ATypeInfo, ValueType, Flavor);
  if AJson.IsNull then
  begin
    if Flavor = ofOpt then
      raise EJsonError.Create('null is not allowed here (optional, not nullable)');
    Obj := NewNull(ValueType);
  end
  else
  begin
    // The mapper's own rules for the value, errors included (it adds APath).
    AMapper.ReadValue(AJson, ValueType, APath, Inner);
    Obj := NewFrom(ValueType, Inner);
  end;
  // TOptNullXxx implements all three flavors; ask for the declared one.
  Obj.GetInterface(GetTypeData(ATypeInfo)^.Guid, Intf);
  TValue.Make(@Intf, ATypeInfo, AValue);
  Result := True;
end;

function TOptionalsJsonConverter.WriteJson(AMapper: TJsonMapper; const AValue: TValue;
  ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
var
  ValueType: PTypeInfo;
  Flavor: TOptFlavor;
  Intf: IInterface;
  Opt: IOptionalBase;
  Nul: INullableBase;
  Absent, IsNull: Boolean;
begin
  Describe(ATypeInfo, ValueType, Flavor);
  Intf := nil;
  if not AValue.IsEmpty then
    Intf := AValue.AsInterface;

  // nil means "never set": absent for the Opt flavors, null for INullXxx
  // (the same reading TOptionals.Safe gives it in pascal-common-faa).
  Absent := (Intf = nil) or (Supports(Intf, IOptionalBase, Opt) and not Opt.HasValue);
  IsNull := (Intf = nil) or (Supports(Intf, INullableBase, Nul) and Nul.IsNull);

  case Flavor of
    ofOpt:
      if Absent then
        Exit(False)
      else if IsNull and (Intf <> nil) then
      begin
        AWriter.WriteNull;
        Exit(True);
      end;
    ofNull:
      if IsNull then
      begin
        AWriter.WriteNull;
        Exit(True);
      end;
    ofOptNull:
      if Absent then
        Exit(False)
      else if IsNull then
      begin
        AWriter.WriteNull;
        Exit(True);
      end;
  end;
  Result := AMapper.WriteValue(AWriter, ValueOf(Intf, ATypeInfo), ValueType, APath);
end;

initialization
  // What "using the bridge unit" does in a real application.
  RegisterOptionalsConverter(TJsonMapper.Shared);

end.
