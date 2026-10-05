unit PascalJsonMapper.TestOptionals;

{ Stand-in for another library's optional types, shaped like
  PascalCommon.Optionals (same interface names and GUIDs, same class layout,
  minus the instance cache) for two value types: string and Integer.

  It knows nothing about the mapper: PascalJsonMapper.TestOptionalsBridge
  is the bridge, the way pascal-common-faa's own bridge unit is.

  Three interfaces per value type, one class implementing all three:
  - IOptXxx: "was it provided?" (HasValue). Absent or a value; no null.
  - INullXxx: "is it null?" (IsNull). Null or a value; never absent.
  - IOptNullXxx: both. Absent, null or a value. }

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils;

type
  IOptionalBase = interface
    ['{E4F4A971-9D82-4072-9FCD-B94B3534D00B}']
    function HasValue: Boolean;
  end;

  INullableBase = interface
    ['{FF676337-9F25-4E4E-987B-759175358B7E}']
    function IsNull: Boolean;
  end;

  IOptionalNullableBase = interface
    ['{F991DB80-57A5-49FA-812F-70692A6893C8}']
    function IsNull: Boolean;
    function HasValue: Boolean;
  end;

  IOptional<T> = interface(IOptionalBase)
    ['{ED862237-1C8B-4B92-95D1-65E47B4D83B7}']
    function GetValue: T;
    property Value: T read GetValue;
  end;

  INullable<T> = interface(INullableBase)
    ['{676D05B3-6E6F-4F82-A9AB-455E9464F866}']
    function GetValue: T;
    property Value: T read GetValue;
  end;

  IOptionalNullable<T> = interface(IOptionalNullableBase)
    ['{B27511F9-7746-4432-9165-CF31D058053A}']
    function GetValue: T;
    property Value: T read GetValue;
  end;

  IOptString = interface(IOptional<string>)
    ['{A761330C-AA4B-44A5-A617-C79E3F745A23}']
  end;

  INullString = interface(INullable<string>)
    ['{C86A1566-0B19-4BE2-B780-D22C3ED385F6}']
  end;

  IOptNullString = interface(IOptionalNullable<string>)
    ['{E166D638-8A7C-4143-A0EE-22161499F6A8}']
  end;

  IOptInteger = interface(IOptional<Integer>)
    ['{472AF43B-BC8E-42A5-B275-2D9B0BEE6667}']
  end;

  INullInteger = interface(INullable<Integer>)
    ['{C040BEFA-C342-4F0A-92AD-6FA7711FA002}']
  end;

  IOptNullInteger = interface(IOptionalNullable<Integer>)
    ['{6092BDE1-A122-4BFB-AF50-4947884DA9FD}']
  end;

  TOptionalNullableBase = class(TInterfacedObject,
    IOptionalBase,
    INullableBase,
    IOptionalNullableBase
  )
  private
    FIsNull: Boolean;
    FHasValue: Boolean;
  public
    constructor Create; overload;      // undefined
    constructor CreateNull; overload;  // null
    function IsNull: Boolean;
    function HasValue: Boolean;
  end;

  TOptionalNullable<T> = class(TOptionalNullableBase,
    IOptional<T>,
    INullable<T>,
    IOptionalNullable<T>
  )
  private
    FValue: T;
  public
    constructor Create(AValue: T); overload;
    function GetValue: T;
    property Value: T read GetValue;
  end;

  TOptNullString = class(TOptionalNullable<string>,
    IOptString, INullString, IOptNullString)
  public
    class function Null: TOptNullString; static;
    class function Undefined: TOptNullString; static;
    class function From(AValue: string): TOptNullString; static;
  end;

  TOptNullInteger = class(TOptionalNullable<Integer>,
    IOptInteger, INullInteger, IOptNullInteger)
  public
    class function Null: TOptNullInteger; static;
    class function Undefined: TOptNullInteger; static;
    class function From(AValue: Integer): TOptNullInteger; static;
  end;

implementation

{ TOptionalNullableBase }

constructor TOptionalNullableBase.Create;
begin
  inherited Create;
  FHasValue := False;
  FIsNull := False;
end;

constructor TOptionalNullableBase.CreateNull;
begin
  inherited Create;
  FHasValue := True;
  FIsNull := True;
end;

function TOptionalNullableBase.IsNull: Boolean;
begin
  Result := FIsNull;
end;

function TOptionalNullableBase.HasValue: Boolean;
begin
  Result := FHasValue;
end;

{ TOptionalNullable<T> }

constructor TOptionalNullable<T>.Create(AValue: T);
begin
  inherited Create;
  FHasValue := True;
  FIsNull := False;
  FValue := AValue;
end;

function TOptionalNullable<T>.GetValue: T;
begin
  Result := FValue;
end;

{ TOptNullString }

class function TOptNullString.Null: TOptNullString;
begin
  Result := TOptNullString.CreateNull;
end;

class function TOptNullString.Undefined: TOptNullString;
begin
  Result := TOptNullString.Create;
end;

class function TOptNullString.From(AValue: string): TOptNullString;
begin
  Result := TOptNullString.Create(AValue);
end;

{ TOptNullInteger }

class function TOptNullInteger.Null: TOptNullInteger;
begin
  Result := TOptNullInteger.CreateNull;
end;

class function TOptNullInteger.Undefined: TOptNullInteger;
begin
  Result := TOptNullInteger.Create;
end;

class function TOptNullInteger.From(AValue: Integer): TOptNullInteger;
begin
  Result := TOptNullInteger.Create(AValue);
end;

end.
