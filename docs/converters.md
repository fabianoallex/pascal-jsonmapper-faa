# Writing a converter for your library's types

How a library that owns some types (optionals, value objects, money, IDs...) teaches the mapper to read and write them, without either core depending on the other. The running example is pascal-db-faa's optional types (`PascalDb.Optionals`).

A working model of the whole thing is in this repository's tests:

- `tests/Unit/common/PascalJsonMapper.TestOptionals.pas` plays the library. It has the same interface names, GUIDs and class layout as `PascalDb.Optionals`, for `string` and `Integer`, and no mapper dependency.
- `tests/Unit/common/PascalJsonMapper.TestOptionalsBridge.pas` is the bridge, as pascal-db-faa would ship it.
- `tests/Unit/PascalJsonMapper.BridgeTests.pas` holds its tests. They use only `TJsonMapper.Shared`, as an application would.

The real bridge is mostly that file widened from 6 interfaces to all of the library's.

## Where the bridge lives

Put it in **a unit of its own, in a package of its own**, owned by the library that defines the types. For pascal-db-faa that means `PascalDb.JsonMapper.Optionals.pas` in a `pascal_db_faa_jsonmapper.lpk` (plus its Delphi counterpart), next to the existing `_sqldb` and `_zeos` packages. Only applications that use both libraries install it. The pascal-db-faa core never uses the mapper, and the mapper core never knows about pascal-db-faa.

## The contract

```pascal
IJsonConverter = interface
  function CanConvert(ATypeInfo: PTypeInfo): Boolean;
  function ReadJson(AMapper: TJsonMapper; AJson: TJsonValue;
    ATypeInfo: PTypeInfo; const APath: string; out AValue: TValue): Boolean;
  function WriteJson(AMapper: TJsonMapper; const AValue: TValue;
    ATypeInfo: PTypeInfo; const APath: string; AWriter: TJsonWriter): Boolean;
end;
```

- **`CanConvert`** is called for every value the mapper reads or writes, before its built-in rules. Keep it to `PTypeInfo` comparisons. If several converters accept a type, the last one registered wins.
- **`ReadJson`** is only called for members that are present. An absent member leaves the property untouched, so the DTO's own default stands (`nil`, which pascal-db-faa's getters turn into `Undefined`/`Null` through `TOptionals.Safe`). `AJson` may be JSON `null`. Return `True` with `AValue` of type `ATypeInfo` (`TValue.Make(@Intf, ATypeInfo, AValue)`), or `False` to leave the destination untouched.
- **`WriteJson`** writes exactly one value, or nothing. To omit, write nothing and return `False`: the pending member name is dropped. Inside an array, an omitted element becomes `null`.
- **Errors**: raise `EJsonError`, or just call `TJsonValue` accessors such as `AsString`, which raise it on the wrong kind. The mapper rethrows it as `EJsonMapperError` prefixed with the path: `$.items[2].price: ...`.
- **Delegate values to the mapper** with `AMapper.ReadValue(AJson, TypeInfo(Integer), APath, V)` and `AMapper.WriteValue(AWriter, V, TypeInfo(Integer), APath)`, passing `APath` through. The value then follows the mapper's own rules: range checks, exact float conversion, ISO 8601 dates, error paths.

Converters are shared across threads: keep them stateless.

## Registering

The bridge unit registers itself on the shared mapper at initialization, and also exposes a procedure for mappers created by hand:

```pascal
procedure RegisterOptionalsConverter(AMapper: TJsonMapper);
...
initialization
  RegisterOptionalsConverter(TJsonMapper.Shared);
```

Register at startup only. Reads and writes are thread-safe, registration isn't.

## Pitfalls

- **A generic interface's GUID is shared by every specialization.** `IOptional<string>` and `IOptional<Integer>` carry the same GUID, so `Supports(X, IOptional<string>)` can't tell them apart and may hand back the wrong vtable. Query the concrete interface instead (`IOptString`, `IOptInteger`...), or the property's own `ATypeInfo` GUID.
- **One class implements three interfaces.** `TOptNullXxx` implements `IOptXxx`, `INullXxx` and `IOptNullXxx`. After creating one, return the interface the property declares: `Obj.GetInterface(GetTypeData(ATypeInfo)^.Guid, Intf)`.
- **Read state through the base interfaces.** Use `IOptionalBase.HasValue` and `INullableBase.IsNull` with `Supports`, so a foreign implementation of one flavor still works.
- **`TGUID` is a record, and the mapper has no built-in rule for it.** For `IOptGuid`/`INullGuid`/`IOptNullGuid`, read and write the string yourself (`GUIDToString`/`StringToGUID`). Decide whether the braces stay. The original `Common.JsonMapper` wrote `GUIDToString`, which includes them.

## pascal-db-faa specifics

There are 9 value types × 3 flavors = 27 interfaces: `String`, `Integer`, `Int64`, `Double`, `Single`, `Currency`, `DateTime`, `Boolean`, `Guid`, each as `IOptXxx`/`INullXxx`/`IOptNullXxx`. Everything but `Guid` can delegate its value to the mapper (`TypeInfo(TDateTime)` gives ISO 8601).

The rules the test bridge implements:

| | reading `null` | writing `nil` / Undefined | writing Null |
|---|---|---|---|
| `IOptXxx` | **error** | member omitted | (no such state) |
| `INullXxx` | `Null` | **`null`** | `null` |
| `IOptNullXxx` | `Null` | member omitted | `null` |

**Two decisions to make before writing the real bridge**, because `delphi-api-infra-faa`'s original `Common.JsonMapper` behaved differently:

1. **`null` into an `IOptXxx`.** The original accepted it and stored `TOptNullXxx.Null`. The test bridge rejects it, since an `IOptXxx` has no null state. Accepting it is lenient, but a DTO typed `IOptString` (for example "name may be absent but not null") then gets a value it can't express.
2. **A `nil` `INullXxx` when writing.** The original omitted every `nil` interface. The test bridge writes `null`, matching `TOptionals.Safe`, which reads `nil` as Null for that flavor. Omitting is the original's behavior; writing `null` is the one consistent with the type.

Pin both down with tests in pascal-db-faa, mirrored for DUnitX and FPCUnit like the rest of its suite.
