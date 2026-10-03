# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor version
may change the API; each such change is listed here.

## [Unreleased]

## [0.1.0] - 2026-10-03

First release: a JSON ⇄ object mapper that compiles and behaves the same on Delphi and Free
Pascal / Lazarus (FPC 3.2.2+, `{$MODE DELPHI}`). Verified on FPC 3.2.2 Win64 and
x86_64-linux and on Delphi 12 CE Win32 and Win64.

### Added

- `TJsonMapper` (`PascalJsonMapper.Mapper`): maps the **published** properties of `{$M+}`
  classes, the RTTI both compilers see. `RegisterMapping<I, C>` ties a DTO interface to its
  class (the class's own constructor runs). `FromJson<I>` / `ToJson<I>` work on a DTO,
  `Serialize<T>` / `Deserialize<T>` on any supported type at the top level (arrays of DTOs,
  arrays of scalars, scalars). `PopulateObject` / `ObjectToJson` work on existing objects. A
  class-typed property is filled in place, never created. `TJsonMapper.Shared` is the
  process-wide instance, and mappers can also be created standalone.
- Types: strings, chars, all integer sizes (range-checked), `Int64`, `Single` / `Double` /
  `Extended` / `Currency`, `Boolean`, enums (by name), `TDateTime` / `TDate` / `TTime` (ISO 8601;
  an offset on input converts to UTC), interfaces, dynamic arrays, objects.
- Names written in camelCase (`Naming := jnAsDeclared` keeps the declared names), read
  case-insensitively; unknown members ignored; absent members leave the property untouched.
- `IJsonConverter`: the extension point for other types and formats, consulted before the
  built-in rules (last registered wins). A converter can omit a member by writing nothing, and
  can recurse through `ReadValue` / `WriteValue` with the JSON path.
  [docs/converters.md](docs/converters.md) explains how a library ships one for its own types;
  pascal-db-faa's optionals bridge is the worked example.
- Errors: `EJsonMapperError` messages start with the JSON path (`$.items[1].qty: ...`),
  including errors raised inside converters. `EJsonParseError` carries the position.
- `PascalJsonMapper.Json`: its own DOM, parser and writer (not System.JSON or fpjson), so output
  is byte-identical on both compilers. Number text is kept, so an `Int64` above 2^53 survives a
  round trip. `Double` / `Single` ⇄ text conversion is exact, done with integer arithmetic and
  not the RTL: shortest round-trip digits (Burger & Dybvig) when writing, correctly rounded when
  reading. The RTL's results differ by compiler and target: FPC Win64's `FloatToStrF` stops at
  15 digits, and Delphi 12 Win64 is off by one ulp or one digit. Optional indented output
  (`Indent`).
- Thread safety: register at startup, then map from any number of threads; class metadata is
  cached under a lock (FPC 3.2.2's `GetProperties` fills its cache without one).
- Samples `01-basics` and `02-custom-converter`, each with an `expected.txt` of its exact output.
- Tests: 86 DUnitX tests with generated FPCUnit mirrors (`tools/gen_fpc_mirror.py`), including
  a modeled third-party bridge, concurrency on a cold metadata cache, and 40 000 random-bit float
  round trips; Linux runs through Docker (`tools/test_fpc_docker.sh`,
  `tools/test_samples_docker.sh`); CI on every push (`tools/ci-test.sh`).

[Unreleased]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/fabianoallex/pascal-jsonmapper-faa/releases/tag/v0.1.0
