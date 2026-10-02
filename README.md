# pascal-jsonmapper-faa

JSON ⇄ object mapper for Object Pascal that compiles and behaves the same on **Delphi** and **Free Pascal / Lazarus** (FPC 3.2.2+, `{$MODE DELPHI}`).

It extracts the idea of `Common.JsonMapper` from `delphi-api-infra-faa` (DTO interfaces, `RegisterMapping<I, C>`, `FromJson<I>`/`ToJson<I>`). It is not a drop-in replacement for that mapper.

## Usage

```pascal
type
  IProduct = interface
    ['{C4B0F1D2-7A3E-4E59-9B21-6D8F0A1B2C3D}']
    function GetName: string;
  end;

{$M+}
  TProduct = class(TInterfacedObject, IProduct)
  private
    FName: string;
    FPrice: Currency;
  public
    function GetName: string;
  published
    property Name: string read FName write FName;
    property Price: Currency read FPrice write FPrice;
  end;
{$M-}

TJsonMapper.Shared.RegisterMapping<IProduct, TProduct>;
Product := TJsonMapper.Shared.FromJson<IProduct>('{"name":"Rice","price":12.5}');
Json := TJsonMapper.Shared.ToJson<IProduct>(Product);   // {"name":"Rice","price":12.5}
```

## Samples

[`samples/`](samples/README.md) has runnable console programs, one source file each for both compilers:

| Sample | Shows |
|---|---|
| [01-basics](samples/01-basics/Basics.dpr) | DTO interfaces with nested arrays, `FromJson`/`ToJson`, `Naming`, `PopulateObject` on an existing object, errors with JSON path and position |
| [02-custom-converter](samples/02-custom-converter/CustomConverter.dpr) | `IJsonConverter`: a different format for a known type, a new type (a money value object), omitting a member |

Optionals (absent / null / value, as in a PATCH) are shown with pascal-db-faa's types in its own [06-json](https://github.com/fabianoallex/pascal-db-faa/tree/main/samples/06-json) sample.

## Contract

- **Only `published` properties are mapped**, on both compilers. FPC 3.2.2's RTTI doesn't see `public` properties, so Delphi ignores them too, to keep both sides equal. Declare DTOs under `{$M+}`.
- **Interfaces** are created through `RegisterMapping<I, C>`. The class's own constructor runs. **Class-typed properties** are never created: reading populates the instance the property already holds.
- **Names**: written in camelCase (`Naming := jnAsDeclared` keeps the declared names) and read case-insensitively. Unknown JSON members are ignored. An absent member leaves the property untouched. `null` into a scalar keeps the current value.
- **Types**: strings, chars, all integer sizes (range-checked), `Int64`, `Single`/`Double`/`Extended`/`Currency`, `Boolean`, enums (by name), `TDateTime`/`TDate`/`TTime` (ISO 8601, no zone written; an offset on input converts to UTC), interfaces, dynamic arrays, objects. Anything else raises `EJsonMapperError` with the JSON path (`$.items[1].code`). The fix for an unsupported type is a converter.
- **Converters** (`IJsonConverter`) run before the built-in rules, and the last registered wins. A converter can omit a member by writing nothing, which is how a bridge for optional types encodes *absent / null / value*. The library that owns a type should ship its converter in a separate unit or package, so neither core depends on the other. See [docs/converters.md](docs/converters.md) for how to write one, with pascal-db-faa's optionals as the worked example.
- **Threads**: register at startup, then use from any thread. Class metadata is cached under a lock.
- **FPC strings** are treated as UTF-8 (the Lazarus convention). Delphi strings are UTF-16.

## JSON layer

`PascalJsonMapper.Json` is a small DOM, parser and writer of its own, not System.JSON or fpjson. Output is byte-identical on both compilers. Numbers keep their source text, so an `Int64` above 2^53 survives a round trip.

`Double`/`Single` conversion doesn't use the RTL either. Writing uses Burger & Dybvig's algorithm, which gives the shortest text that reads back exactly. Reading rounds half to even. Both use exact integer arithmetic, so every compiler and target produces the same text and the same bits. The RTL's conversions differ in the last digit: FPC 3.2.2 Win64's `FloatToStrF` stops at 15 digits, and Delphi 12 Win64 printed `0.30000000000000004` as `0.30000000000000006`.

## Tests

The DUnitX masters live in `tests/Unit/*Tests.pas`, written in FPCUnit's assertion dialect. The FPCUnit mirrors in `tests/Unit/fpc` are generated:

```
python tools/gen_fpc_mirror.py          # regenerate
python tools/gen_fpc_mirror.py --check  # fail if stale
lazbuild tests/Unit/fpc/PascalJsonMapperUnitTestsFpc.lpi
tests/Unit/fpc/PascalJsonMapperUnitTestsFpc.exe --all --format=plain
```

On Linux, through Docker, the same suite builds with plain `fpc` from a read-only copy of the tree:

```
sh tools/test_fpc_docker.sh             # FPC_IMAGE=<image with FPC 3.2.2>, default fpc322-bookworm
sh tools/test_samples_docker.sh         # builds and runs the samples, diffs each output with its expected.txt
```

On Delphi, open `PascalJsonMapper.groupproj` and run `PascalJsonMapper.UnitTests`. "Build All" only builds the active platform, so switch the target platform to build Win64. Every suite must end with 0 leaks.

Last verified: FPC 3.2.2 Win64 and x86_64-linux (10 runs, including 5 pinned to one CPU), and Delphi 12 CE Win32 and Win64. Each passed 76/76 with 0 leaks.

## License

MIT. See [LICENSE](LICENSE).
