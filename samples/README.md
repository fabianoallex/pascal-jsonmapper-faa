# Samples

Console programs showing how to use pascal-jsonmapper-faa. Each sample is **one source file for both compilers**: open the `.dproj` in Delphi or the `.lpi` in Lazarus. They're also in `PascalJsonMapper.groupproj` and `PascalJsonMapper.lpg`. None needs anything outside this repository.

| Sample | Shows |
|---|---|
| [01-basics](01-basics/Basics.dpr) | An order read from JSON into a DTO interface (`Int64` above 2^53, enum, `TDateTime`, `Currency`, an array of nested DTOs, an unknown member ignored), written back after a change, `Naming := jnAsDeclared`, `PopulateObject` filling an existing plain object and its nested object in place, and what bad input reports: a wrong value type with its JSON path, malformed JSON with its position |
| [02-custom-converter](02-custom-converter/CustomConverter.dpr) | Three `IJsonConverter`s, one for each thing a converter can do: change the format of a type the mapper knows (an enum written as `"paid"`), add a type it doesn't know (an `IMoney` value object written as `"1234.50 BRL"`), and omit a member (a `TOptionalDate` of 0 left out, other values handed back to the mapper as ISO 8601); errors inside a converter carry the JSON path. See [docs/converters.md](../docs/converters.md) |

Each folder has an `expected.txt` with the program's exact output. `tools/test_samples_docker.sh` builds the samples on Linux FPC with heaptrc and fails on any difference from it, a non-zero exit code or a leak. The output is the same with FPC on Windows, apart from line endings.

Optionals (absent / null / value, as in a PATCH body) are shown with real types in pascal-db-faa's [06-json](https://github.com/fabianoallex/pascal-db-faa/tree/main/samples/06-json), through its `PascalDb.JsonMapper.Optionals` bridge.
