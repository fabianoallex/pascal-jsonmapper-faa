# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/). While the version is 0.x, a minor version
may change the API; each such change is listed here.

## [Unreleased]

## [0.5.0] - 2026-10-15

### Added

- `EJsonInputError = class(EJsonMapperError)`: raised when the JSON being read is at fault. That
  covers an unknown member (umError), a duplicate member, a JSON type that doesn't fit, an
  integer out of its type's range, a name that is no value of the enum, a number beyond Double or
  Currency, a bad ISO 8601 date, and an `EJsonError` raised by a converter while reading. `Path` holds the JSON path. `Detail` holds the Pascal side
  (class, property, type) for logs, or `''`. The message has JSON terms only, so an API can
  return it to the client. Setup and programming errors (type without converter, unregistered
  interface, nil class property, two properties sharing a JSON name, writing NaN) stay plain
  `EJsonMapperError`, even when their message starts with a path. `EJsonParseError` is
  unchanged.

### Changed

- **Messages changed**: four reading errors no longer name Pascal classes, properties or types.
  That detail moved to `Detail`:
  - `$.qty: unknown member (no published property of TOrder matches it)` → `$.qty: unknown
    member`
  - `$.name: duplicate member ("name" and "NAME" both match property TOrder.Name)` → `$.name:
    duplicate member ("name" and "NAME")`
  - `$.cor: "cBlue" is not a value of TColor3` → `$.cor: "cBlue" is not an accepted value`
  - `$.b: 300 is out of range for Byte` → `$.b: 300 is out of range (0..255)`

  The other messages keep their text; only their class is now `EJsonInputError` where the JSON
  is at fault.
- `docs/converters.md`: an `EJsonError` a converter raises while reading becomes
  `EJsonInputError`, so its message should not name Pascal types either.

### Fixed

- A number beyond Currency's range (`{"valor":1e300}`) raised `EInvalidOp` without a path. It
  now raises `EJsonInputError`: `$.valor: Number 1e300 is out of range`.

## [0.4.0] - 2026-10-15

### Changed

- **Behavior change**: reading rejects duplicate members. When two JSON members match the same
  property, `EJsonMapperError` is raised with the path, e.g. `$.name: duplicate member ("name"
  and "NAME" both match property TPerson.Name)`, before anything at that level is assigned. It
  applies with any `UnknownMembers` setting and at any depth (nested objects, array elements,
  class properties). "Same property" means what reading already matched: a repeated name, names
  that differ only in ASCII case, and the declared name next to the `Naming` one (`CreatedAt`
  and `created_at` under `jnSnakeCase`). After `RenameMember`, the declared name matches nothing,
  so it isn't a duplicate. Until 0.3.0 one of the values was used silently, and which one
  depended on spelling, not on order: the exact name won wherever it was (`{"NAME":"First",
  "name":"Second"}` gave `Second`), otherwise the first match won, the `Naming` name beat the
  declared one, and a leading `null` left the property untouched. JavaScript, Python and Go
  keep the last value, so a component that reads the body before the API (gateway, WAF, audit
  log) could see different data than the API.
- **Behavior change**: one JSON member feeds at most one property. A member that matches one
  property's JSON name and another property's declared name goes to the first one only. That
  takes a rename onto another property's declared name: with `jnSnakeCase` and `Kind` renamed
  to `"CreatedAt"`, `{"CreatedAt":"x"}` now sets `Kind` and leaves `CreatedAt` alone; until
  0.3.0 it set both.
- `TJsonValue.Find(AName, True)` returns an exact match before a case variant. It used to return
  the first match ignoring case, even when an exact one came later (`{"Nome":1,"nome":2}`:
  `Find('nome', True)` gave 1, now 2). `ParseJson` still keeps duplicate names, in order.

## [0.3.0] - 2026-10-08

### Added

- `TJsonMapper.Members(AClass)`: the JSON members of a class's published properties, in the order
  the mapper writes them, each with its property name, JSON name (`Naming` and `RenameMember`
  applied), type and whether it is read and written (`TJsonMember`, `TJsonMemberArray`). For code
  that describes the JSON instead of producing it; pascal-api-infra-faa's OpenAPI generator uses
  it so the documented names are the ones on the wire. Raises on a name collision, as reading
  and writing do.

## [0.2.1] - 2026-10-05

### Changed

- Documentation only, no code or behavior change. The optionals bridge used as the worked
  example moved from pascal-db-faa (`PascalDb.JsonMapper.Optionals`, package
  `pascal_db_faa_jsonmapper`) to pascal-common-faa (`PascalCommon.JsonMapper.Optionals`, package
  `pascal_common_faa_jsonmapper`, types in `PascalCommon.Optionals`, same interface names and
  GUIDs). `docs/converters.md`, the READMEs and the test comments now point there, and the
  "The real bridge" link no longer gives a 404. `docs/converters.md` adds the rule for projects
  that use the bridge: its `.lpk` requires `pascaljsonmapper_pkg` by name only, so the project
  lists its own copy of the mapper with `DefaultFilename` and `Prefer="True"` before the bridge,
  or lazbuild silently uses the one registered in the IDE.

## [0.2.0] - 2026-10-03

### Added

- `Naming := jnSnakeCase`: `CreatedAt` → `created_at`, `UserID` → `user_id`, `HTTPStatus` →
  `http_status`, `Address2` → `address2`. The rule is `JsonSnakeCase`, which is public.
- `TJsonMapper.RenameMember(AClass, 'Kind', 'type')`: one property's own JSON name, for members
  that can't be Pascal identifiers (keywords) or that no `Naming` produces. Descendants inherit it,
  and a descendant can rename the property again. Only the new name matches when reading. An unknown
  property or an empty name raises.
- `UnknownMembers := umError` (strict mode): a JSON member that matches no published property
  raises `EJsonMapperError` with its path, before anything is assigned.
- Two properties that would share a JSON name (compared case-insensitively, as reading does)
  raise `EJsonMapperError` naming both, the first time the class is mapped.

The defaults are unchanged: `jnCamelCase` and `umIgnore`.

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

[Unreleased]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/fabianoallex/pascal-jsonmapper-faa/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fabianoallex/pascal-jsonmapper-faa/releases/tag/v0.1.0
