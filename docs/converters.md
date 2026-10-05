# Writing a converter for your library's types

How a library that owns some types (optionals, value objects, money, IDs...) teaches the mapper to read and write them, without either core depending on the other. The running example is pascal-common-faa's optional types (`PascalCommon.Optionals`).

A working model of the whole thing is in this repository's tests:

- `tests/Unit/common/PascalJsonMapper.TestOptionals.pas` plays the library. It has the same interface names, GUIDs and class layout as `PascalCommon.Optionals`, for `string` and `Integer`, and no mapper dependency.
- `tests/Unit/common/PascalJsonMapper.TestOptionalsBridge.pas` is the bridge, modeled on the one pascal-common-faa ships.
- `tests/Unit/PascalJsonMapper.BridgeTests.pas` holds its tests. They use only `TJsonMapper.Shared`, as an application would.

The real bridge is mostly that file widened from 6 interfaces to all of the library's.

## Where the bridge lives

Put it in **a unit of its own, in a package of its own**, owned by the library that defines the types. For pascal-common-faa that means `bridges/jsonmapper/PascalCommon.JsonMapper.Optionals.pas` in the `pascal_common_faa_jsonmapper.lpk` package, apart from the core `pascal_common_faa.lpk`; on Delphi, the `bridges/jsonmapper` folder goes on the search path. Only applications that use both libraries add it. The pascal-common-faa core never uses the mapper, and the mapper core never knows about pascal-common-faa.

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
- **`ReadJson`** is only called for members that are present. An absent member leaves the property untouched, so the DTO's own default stands (`nil`, which pascal-common-faa's getters turn into `Undefined`/`Null` through `TOptionals.Safe`). `AJson` may be JSON `null`. Return `True` with `AValue` of type `ATypeInfo` (`TValue.Make(@Intf, ATypeInfo, AValue)`), or `False` to leave the destination untouched.
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
- **`TGUID` is a record, and the mapper has no built-in rule for it.** For `IOptGuid`/`INullGuid`/`IOptNullGuid`, read and write the string yourself. pascal-common-faa writes `GUIDToString` (with braces, as the original `Common.JsonMapper` did) and reads with or without braces.
- **An `IOptXxx` can hold a Null.** `TOptNullXxx.Null` assigned to an `IOptXxx` compiles, because one class implements the three flavors. Its `Value` is a made-up `''` or `0`, so write `null` rather than that value.

## pascal-common-faa specifics

The real bridge is [`PascalCommon.JsonMapper.Optionals`](https://github.com/fabianoallex/pascal-common-faa/blob/main/bridges/jsonmapper/PascalCommon.JsonMapper.Optionals.pas), in the [`pascal_common_faa_jsonmapper`](https://github.com/fabianoallex/pascal-common-faa/blob/main/packages/pascal_common_faa_jsonmapper.lpk) package, since pascal-common-faa 0.1.0. The types are in `PascalCommon.Optionals`. It used to be `PascalDb.JsonMapper.Optionals` in pascal-db-faa's `pascal_db_faa_jsonmapper` package; the interface names and GUIDs did not change.

The bridge's `.lpk` requires `pascaljsonmapper_pkg` **by name only**, so the project that uses the bridge decides which copy of the mapper it gets. That project lists its own copy of the mapper, with `DefaultFilename` and `Prefer="True"`, **before** the bridge:

```xml
<Item>
  <PackageName Value="pascaljsonmapper_pkg"/>
  <DefaultFilename Value="..\..\external\pascal-jsonmapper-faa\packages\pascaljsonmapper_pkg.lpk" Prefer="True"/>
</Item>
<Item>
  <PackageName Value="pascal_common_faa_jsonmapper"/>
  <DefaultFilename Value="..\..\external\pascal-common-faa\packages\pascal_common_faa_jsonmapper.lpk" Prefer="True"/>
</Item>
```

Leave out the mapper line and lazbuild **silently** builds against whatever `pascaljsonmapper_pkg` is registered in the IDE (pascal-common-faa's [gotcha 2](https://github.com/fabianoallex/pascal-common-faa/blob/main/docs/gotchas.md#2-lazbuild-builds-against-a-different-copy-of-a-package-silently)); check the paths in the build log when in doubt. On Delphi, put `bridges/jsonmapper` and the mapper's `src` on the search path. Step 4 of pascal-common-faa's [migrating guide](https://github.com/fabianoallex/pascal-common-faa/blob/main/docs/migrating.md) has the details.

There are 9 value types × 3 flavors = 27 interfaces: `String`, `Integer`, `Int64`, `Double`, `Single`, `Currency`, `DateTime`, `Boolean`, `Guid`, each as `IOptXxx`/`INullXxx`/`IOptNullXxx`. Everything but `Guid` can delegate its value to the mapper (`TypeInfo(TDateTime)` gives ISO 8601).

The rules, the same in the real bridge and in this repository's test bridge:

| | reading `null` | writing `nil` / Undefined | writing Null |
|---|---|---|---|
| `IOptXxx` | **error** | member omitted | `null` |
| `INullXxx` | `Null` | **`null`** | `null` |
| `IOptNullXxx` | `Null` | member omitted | `null` |

Two of these differ, on purpose, from `delphi-api-infra-faa`'s original `Common.JsonMapper`:

1. **`null` into an `IOptXxx` is rejected.** The original stored `TOptNullXxx.Null`, a state the type can't express. "May be absent, never null" is exactly what `IOptXxx` says.
2. **A `nil` `INullXxx` is written as `null`.** The original omitted every `nil` interface. `TOptionals.Safe` reads `nil` as Null for that flavor, so `null` is the consistent output, and the member is never missing.

`DecimalPlaces` of `Single`/`Double` is not part of the JSON: written values are the shortest exact text, and read values get the default (`-1`).
