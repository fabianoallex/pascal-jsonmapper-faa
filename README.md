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

`PascalJsonMapper.dpr` at the root is this example, runnable on both compilers.

## Contract

- **Only `published` properties are mapped**, on both compilers. FPC 3.2.2's RTTI doesn't see `public` properties, so Delphi ignores them too, to keep both sides equal. Declare DTOs under `{$M+}`.
- **Interfaces** are created through `RegisterMapping<I, C>`. The class's own constructor runs. **Class-typed properties** are never created: reading populates the instance the property already holds.
- **Names**: written in camelCase (`Naming := jnAsDeclared` keeps the declared names) and read case-insensitively. Unknown JSON members are ignored. An absent member leaves the property untouched. `null` into a scalar keeps the current value.
- **Types**: strings, chars, all integer sizes (range-checked), `Int64`, `Single`/`Double`/`Extended`/`Currency`, `Boolean`, enums (by name), `TDateTime`/`TDate`/`TTime` (ISO 8601, no zone written; an offset on input converts to UTC), interfaces, dynamic arrays, objects. Anything else raises `EJsonMapperError` with the JSON path (`$.items[1].code`). The fix for an unsupported type is a converter.
- **Converters** (`IJsonConverter`) run before the built-in rules, and the last registered wins. A converter can omit a member by writing nothing, which is how a bridge for optional types encodes *absent / null / value*. The library that owns a type should ship its converter in a separate unit or package, so neither core depends on the other.
- **Threads**: register at startup, then use from any thread. Class metadata is cached under a lock.
- **FPC strings** are treated as UTF-8 (the Lazarus convention). Delphi strings are UTF-16.

## JSON layer

`PascalJsonMapper.Json` is a small DOM, parser and writer of its own, not System.JSON or fpjson. Output is byte-identical on both compilers. Numbers keep their source text, so an `Int64` above 2^53 survives a round trip, and floats are written as the shortest text that reads back exactly. That second point needed work: FPC 3.2.2 Win64's `FloatToStrF` stops at ~15 digits.

## Tests

The DUnitX masters live in `tests/Unit/*Tests.pas`, written in FPCUnit's assertion dialect. The FPCUnit mirrors in `tests/Unit/fpc` are generated:

```
python tools/gen_fpc_mirror.py          # regenerate
python tools/gen_fpc_mirror.py --check  # fail if stale
lazbuild tests/Unit/fpc/PascalJsonMapperUnitTestsFpc.lpi
tests/Unit/fpc/PascalJsonMapperUnitTestsFpc.exe --all --format=plain
```

On Delphi, open `PascalJsonMapper.groupproj` and run `PascalJsonMapper.UnitTests`. Both suites must end with 0 leaks.
