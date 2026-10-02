program PascalJsonMapper.UnitTests;

{ DUnitX runner for the unit tests.

  The sibling FPCUnit suite lives in tests/Unit/fpc — same coverage and
  identical test bodies: the files there are GENERATED from these by
  tools/gen_fpc_mirror.py (PascalJsonMapper.DUnitXCompat exists for that). Always
  edit the DUnitX masters here and regenerate the mirror. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  PascalJsonMapper.Json in '..\..\src\PascalJsonMapper.Json.pas',
  PascalJsonMapper.Mapper in '..\..\src\PascalJsonMapper.Mapper.pas',
  PascalJsonMapper.DUnitXCompat in 'PascalJsonMapper.DUnitXCompat.pas',
  PascalJsonMapper.TestTypes in 'common\PascalJsonMapper.TestTypes.pas',
  PascalJsonMapper.TestOptionals in 'common\PascalJsonMapper.TestOptionals.pas',
  PascalJsonMapper.TestOptionalsBridge in 'common\PascalJsonMapper.TestOptionalsBridge.pas',
  PascalJsonMapper.JsonTests in 'PascalJsonMapper.JsonTests.pas',
  PascalJsonMapper.MapperTests in 'PascalJsonMapper.MapperTests.pas',
  PascalJsonMapper.ConcurrencyTests in 'PascalJsonMapper.ConcurrencyTests.pas',
  PascalJsonMapper.BridgeTests in 'PascalJsonMapper.BridgeTests.pas';

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
begin
  // Acceptance criterion on both sides: 0 leaks (FastMM here, heaptrc on FPC).
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;

    if TDUnitX.Options.Include = '' then
      TDUnitX.Options.Include := '.';

    runner := TDUnitX.CreateRunner;
    runner.UseRTTI := True;
    runner.FailsOnNoAsserts := False;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create(
        TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;

    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    results := runner.Execute;

    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    if (TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause) and IsConsole then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
end.
