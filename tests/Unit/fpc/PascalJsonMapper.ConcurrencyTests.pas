unit PascalJsonMapper.ConcurrencyTests;

{$mode delphi}{$H+}

{ GENERATED FILE — produced by tools/gen_fpc_mirror.py from
  tests/Unit/PascalJsonMapper.ConcurrencyTests.pas (DUnitX). Do not edit by hand: edit the DUnitX
  master and run the script again. }

{ Concurrency tests for the mapper: many threads, released together by an
  event, mapping DTO classes no other test touches. The first use of a class
  builds its metadata (GetPropList + TRttiType.GetProperties, the latter
  without a lock of its own on FPC 3.2.2), so these tests aim straight at
  that first-build race, then keep hammering the warm cache. Every round
  trip is checked; a failure records the first error message.

  No Sleep: the threads synchronize only through the start event and
  WaitFor (see the dual-compiler skill on timing in tests).

  DUnitX master, written in FPCUnit's assertion dialect (TAssert.*, through
  PascalJsonMapper.DUnitXCompat). The mirror in tests/Unit/fpc is generated
  from the master by tools/gen_fpc_mirror.py — edit only the master. }

interface

uses
  fpcunit, testregistry,
  Classes,
  SysUtils,
  SyncObjs,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper;

type
  IConcLine = interface
    ['{A1B2C3D4-0001-4E5F-8A9B-0C1D2E3F4A01}']
  end;

  IConcOrder = interface
    ['{A1B2C3D4-0002-4E5F-8A9B-0C1D2E3F4A02}']
  end;

  IConcCustomer = interface
    ['{A1B2C3D4-0003-4E5F-8A9B-0C1D2E3F4A03}']
  end;

  TConcLineArray = array of IConcLine;

{$M+}
  TConcLine = class(TInterfacedObject, IConcLine)
  private
    FSku: string;
    FQty: Integer;
  published
    property Sku: string read FSku write FSku;
    property Qty: Integer read FQty write FQty;
  end;

  TConcOrder = class(TInterfacedObject, IConcOrder)
  private
    FNumber: Int64;
    FTotal: Double;
    FLines: TConcLineArray;
  published
    property Number: Int64 read FNumber write FNumber;
    property Total: Double read FTotal write FTotal;
    property Lines: TConcLineArray read FLines write FLines;
  end;

  TConcCustomer = class(TInterfacedObject, IConcCustomer)
  private
    FName: string;
    FActive: Boolean;
    FLastOrder: IConcOrder;
  published
    property Name: string read FName write FName;
    property Active: Boolean read FActive write FActive;
    property LastOrder: IConcOrder read FLastOrder write FLastOrder;
  end;
{$M-}

  TMapperWorker = class(TThread)
  private
    FMapper: TJsonMapper;
    FStart: TEvent;
    FIndex: Integer;
    FIterations: Integer;
  protected
    procedure Execute; override;
  public
    Failures: Integer;
    FirstError: string;
    constructor Create(AMapper: TJsonMapper; AStart: TEvent; AIndex, AIterations: Integer);
  end;

  TMapperConcurrencyTests = class(TTestCase)
  private
    procedure RunWorkers(AMapper: TJsonMapper; AThreads, AIterations: Integer);
  published
    procedure ColdCache_ManyThreads_SameMapper;
    procedure ParseAndWrite_ManyThreads_NoSharedState;
  end;

implementation

const
  OrderJson = '{"number":9007199254740993,"total":0.1,' +
    '"lines":[{"sku":"A-1","qty":2},{"sku":"B-2","qty":-7}]}';
  CustomerJson = '{"name":"Ana","active":true,"lastOrder":' + OrderJson + '}';

function NewConcurrencyMapper: TJsonMapper;
begin
  Result := TJsonMapper.Create;
  Result.RegisterMapping<IConcLine, TConcLine>;
  Result.RegisterMapping<IConcOrder, TConcOrder>;
  Result.RegisterMapping<IConcCustomer, TConcCustomer>;
end;

{ TMapperWorker }

constructor TMapperWorker.Create(AMapper: TJsonMapper; AStart: TEvent;
  AIndex, AIterations: Integer);
begin
  FMapper := AMapper;
  FStart := AStart;
  FIndex := AIndex;
  FIterations := AIterations;
  inherited Create(False);
end;

procedure TMapperWorker.Execute;
var
  I: Integer;
  Customer: IConcCustomer;
  Order: IConcOrder;
  Line: IConcLine;
  Text, Expected: string;
begin
  FStart.WaitFor(INFINITE);
  for I := 1 to FIterations do
  try
    // Rotate which class each thread touches first, so the first builds of
    // the three classes' metadata overlap across threads.
    case (FIndex + I) mod 3 of
      0:
        begin
          Customer := FMapper.FromJson<IConcCustomer>(CustomerJson);
          Text := FMapper.ToJson<IConcCustomer>(Customer);
          Expected := CustomerJson;
        end;
      1:
        begin
          Order := FMapper.FromJson<IConcOrder>(OrderJson);
          Text := FMapper.ToJson<IConcOrder>(Order);
          Expected := OrderJson;
        end;
    else
      Line := FMapper.FromJson<IConcLine>('{"sku":"T' + IntToStr(FIndex) + '","qty":' + IntToStr(I) + '}');
      Text := FMapper.ToJson<IConcLine>(Line);
      Expected := '{"sku":"T' + IntToStr(FIndex) + '","qty":' + IntToStr(I) + '}';
    end;
    if Text <> Expected then
    begin
      Inc(Failures);
      if FirstError = '' then
        FirstError := 'got ' + Text;
    end;
  except
    on E: Exception do
    begin
      Inc(Failures);
      if FirstError = '' then
        FirstError := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TMapperConcurrencyTests }

procedure TMapperConcurrencyTests.RunWorkers(AMapper: TJsonMapper;
  AThreads, AIterations: Integer);
var
  Start: TEvent;
  Workers: array of TMapperWorker;
  I, Failures: Integer;
  FirstError: string;
begin
  Start := TEvent.Create(nil, True, False, '');
  try
    SetLength(Workers, AThreads);
    for I := 0 to AThreads - 1 do
      Workers[I] := TMapperWorker.Create(AMapper, Start, I, AIterations);
    Start.SetEvent;
    Failures := 0;
    FirstError := '';
    for I := 0 to AThreads - 1 do
    begin
      Workers[I].WaitFor;
      Inc(Failures, Workers[I].Failures);
      if (FirstError = '') and (Workers[I].FirstError <> '') then
        FirstError := Workers[I].FirstError;
      Workers[I].Free;
    end;
  finally
    Start.Free;
  end;
  TAssert.AssertEquals('Failed round trips (first: ' + FirstError + ')', 0, Failures);
end;

procedure TMapperConcurrencyTests.ColdCache_ManyThreads_SameMapper;
var
  Mapper: TJsonMapper;
begin
  // Must be the first use of the TConc* classes in the process: nothing else
  // references them, so their metadata is built under contention here.
  Mapper := NewConcurrencyMapper;
  try
    RunWorkers(Mapper, 16, 300);
  finally
    Mapper.Free;
  end;
end;

procedure TMapperConcurrencyTests.ParseAndWrite_ManyThreads_NoSharedState;
var
  Mapper: TJsonMapper;
begin
  // Warm cache, more iterations: the steady state a server runs in.
  Mapper := NewConcurrencyMapper;
  try
    RunWorkers(Mapper, 8, 2000);
  finally
    Mapper.Free;
  end;
end;

initialization
  RegisterTest(TMapperConcurrencyTests);

end.
