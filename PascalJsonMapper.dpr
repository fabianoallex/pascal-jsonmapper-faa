program PascalJsonMapper;

{ Smallest end-to-end use of the mapper: a DTO interface backed by a
  published-property class, JSON -> object -> JSON. Builds unchanged with
  Delphi (PascalJsonMapper.dproj) and FPC (PascalJsonMapper.lpi). }

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
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper;

type
  IProduct = interface
    ['{C4B0F1D2-7A3E-4E59-9B21-6D8F0A1B2C3D}']
    function GetName: string;
    function GetPrice: Currency;
  end;

  TTagArray = array of string;

{$M+}
  TProduct = class(TInterfacedObject, IProduct)
  private
    FId: Integer;
    FName: string;
    FPrice: Currency;
    FTags: TTagArray;
  public
    function GetName: string;
    function GetPrice: Currency;
  published
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Price: Currency read FPrice write FPrice;
    property Tags: TTagArray read FTags write FTags;
  end;
{$M-}

function TProduct.GetName: string;
begin
  Result := FName;
end;

function TProduct.GetPrice: Currency;
begin
  Result := FPrice;
end;

var
  Product: IProduct;
begin
  try
    TJsonMapper.Shared.RegisterMapping<IProduct, TProduct>;

    Product := TJsonMapper.Shared.FromJson<IProduct>(
      '{"id": 1, "name": "Rice", "price": 12.5, "tags": ["food", "grain"]}');
    Writeln('Name:  ', Product.GetName);
    Writeln('Price: ', CurrToStr(Product.GetPrice));

    (Product as TProduct).Price := 13.9;
    Writeln('JSON:  ', TJsonMapper.Shared.ToJson<IProduct>(Product));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
