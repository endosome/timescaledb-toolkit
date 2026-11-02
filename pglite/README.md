# TimescaleDB Toolkit for PGlite

Builds the extension for [PGlite](https://pglite.dev), PostgreSQL 18 compiled to WebAssembly
(`wasm32-unknown-emscripten`), as a side module in a PGlite extension bundle.

## Building

Needs Docker and PGlite's build output, `postgres-pglite/dist`, from a PGlite build.

```bash
docker build -t pglite-rust-builder pglite

# the SQL install script, from a native build against PostgreSQL 18
mkdir -p target-pglite/sql
docker run --rm -v "$PWD:/src:ro" -v "$PWD/target-pglite/sql:/src-out" postgres:18 bash /src/pglite/schema.sh

# the side module and the bundle
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/src" -v /path/to/postgres-pglite/dist:/pglite:ro \
  pglite-rust-builder bash /src/pglite/build.sh
```

This writes `target-pglite/timescaledb_toolkit.tar.gz`, the bundle to load as a PGlite extension, and
`target-pglite/timescaledb_toolkit.imports`. PGlite exports only the PostgreSQL and libc symbols its extensions
use: PGlite's build has to include this file in its extension imports
(`dist/include/postgresql/emscripten/extension/imports/`) before it links PGlite.

## Changes for 32-bit WebAssembly

In 32-bit PostgreSQL, `Datum` is 4 bytes, so 8-byte types such as `int8`, `float8` and `timestamptz` are passed by
reference. pgrx and the extension read some of them as if they were passed by value. `vendor/pgrx` is pgrx 0.18.1
with those reads fixed, and the extension reads such values with `datum_utils::int64_from_datum`.

## Notes

- Rust panics use WebAssembly exception handling. The module links the unwinder and the exception tag itself, since
  PGlite is built without it; PostgreSQL errors keep using PGlite's setjmp/longjmp.
- The module is linked with `-sSIDE_MODULE=1`, so it exports all its symbols, which makes it larger: Rust code
  reaches its own statics through the GOT, and the loader fills the GOT from the module's exports.
