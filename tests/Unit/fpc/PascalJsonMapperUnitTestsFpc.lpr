program PascalJsonMapperUnitTestsFpc;

{ FPCUnit runner for the unit tests. Same coverage as the DUnitX suite
  (tests/Unit/PascalJsonMapper.UnitTests.dpr): the fixtures in tests/Unit/fpc
  are generated from the DUnitX masters by tools/gen_fpc_mirror.py.

  Console (text output), when called with any parameter:
    .\PascalJsonMapperUnitTestsFpc.exe --all --format=plain
  GUI (test tree + green/red bar), with no parameters:
    .\PascalJsonMapperUnitTestsFpc.exe
  Outside Windows it always runs in console mode (no LCL/widgetset). }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  cwstring,
  {$ENDIF}
  {$IFDEF MSWINDOWS}
  Interfaces, Forms, GuiTestRunner,
  {$ENDIF}
  Classes, consoletestrunner, testregistry,
  PascalJsonMapper.JsonTests,
  PascalJsonMapper.MapperTests,
  PascalJsonMapper.ConcurrencyTests,
  PascalJsonMapper.BridgeTests;

var
  ConsoleApp: TTestRunner;
begin
  // The library treats FPC strings as UTF-8 (Lazarus convention); make the
  // RTL agree, so UTF8Decode/UTF8Encode and console output line up.
  SetMultiByteConversionCodePage(CP_UTF8);

  {$IFDEF MSWINDOWS}
  if ParamCount = 0 then
  begin
    Application.Initialize;
    Application.CreateForm(TGUITestRunner, TestRunner);
    Application.Run;
  end
  else
  {$ENDIF}
  begin
    DefaultFormat := fPlain;
    DefaultRunAllTests := True;
    ConsoleApp := TTestRunner.Create(nil);
    try
      ConsoleApp.Initialize;
      ConsoleApp.Title := 'pascal-jsonmapper-faa - unit tests (FPCUnit)';
      ConsoleApp.Run;
    finally
      ConsoleApp.Free;
    end;
  end;
end.
