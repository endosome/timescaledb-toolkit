#!/bin/bash
# Builds timescaledb_toolkit as a PGlite side module and packages it as a PGlite extension bundle.
# Runs in an image built from pglite/Dockerfile. Paths, with their defaults:
#   SRC     this repository (/src)
#   PGLITE  PGlite's build output, postgres-pglite/dist (/pglite)
#   OUT     where the outputs go ($SRC/target-pglite)
#
# Outputs in $OUT:
#   timescaledb_toolkit.tar.gz    the extension bundle
#   timescaledb_toolkit.imports   symbols PGlite has to export, for PGlite's own build
set -euo pipefail
SRC=${SRC:-/src}
PGLITE=${PGLITE:-/pglite}
OUT=${OUT:-$SRC/target-pglite}
export HOME=${HOME:-/tmp/home} && mkdir -p $HOME
export CARGO_TARGET_DIR=$OUT/cargo
VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' $SRC/extension/Cargo.toml | head -1)

# pgrx reads PostgreSQL's build configuration from PGlite's pg_config
export PGRX_PG_CONFIG_PATH=$PGLITE/bin/pg_config
export PGRX_HOME=$HOME/.pgrx

# pgrx's C shim is compiled like PGlite's own extensions: PIC, and PGlite's setjmp/longjmp
export CC_wasm32_unknown_emscripten=emcc AR_wasm32_unknown_emscripten=emar
export CFLAGS_wasm32_unknown_emscripten="-fPIC -O2 -sSUPPORT_LONGJMP=emscripten -D__PGLITE__ -Dlongjmp=pgl_longjmp -Dsiglongjmp=pgl_siglongjmp"

# bindgen uses the system clang: give it emscripten's include directories, the macros emscripten's
# newer clang predefines, and default visibility (wasm defaults to hidden, which bindgen skips)
SYSROOT=/emsdk/upstream/emscripten/cache/sysroot
INT_C_MACROS="-D__INT8_C(c)=c -D__INT16_C(c)=c -D__INT32_C(c)=c -D__INT64_C(c)=c##LL -D__UINT8_C(c)=c -D__UINT16_C(c)=c -D__UINT32_C(c)=c##U -D__UINT64_C(c)=c##ULL -D__INTMAX_C(c)=c##LL -D__UINTMAX_C(c)=c##ULL"
export BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="--sysroot=$SYSROOT -isystem $SYSROOT/include/compat -isystem $SYSROOT/include -D__EMSCRIPTEN__ -D__PGLITE__ -fvisibility=default $INT_C_MACROS"

# A side module that exports all its symbols (SIDE_MODULE=1): Rust code reaches its own statics
# through the GOT, which the loader fills from the module's exports. Replaces build.rustflags
# from .cargo/config.toml, a macOS linker flag. No debug info: wasm-opt fails on it.
export RUSTFLAGS="-C relocation-model=pic -C debuginfo=0 -C strip=debuginfo \
  -C link-arg=-lunwind-wasmexcept -C link-arg=-lc++abi-wasmexcept -C link-arg=-sSIDE_MODULE=1"

# the unwinder and exception tag the module links (see Dockerfile); built again in case
# emscripten's cache was cleared, as PGlite's build does
embuilder --pic build libunwind-wasmexcept libc++abi-wasmexcept > /dev/null

cd $SRC/extension
cargo build --release --target wasm32-unknown-emscripten --no-default-features --features pg18
WASM=$CARGO_TARGET_DIR/wasm32-unknown-emscripten/release/timescaledb_toolkit.wasm

# the bundle: library, control file and install script (pglite/timescaledb_toolkit.sql, see
# schema.sh), laid out like PGlite's other bundles
STAGE=$OUT/stage && rm -rf $STAGE && mkdir -p $STAGE/lib/postgresql $STAGE/share/postgresql/extension
cp $WASM $STAGE/lib/postgresql/timescaledb_toolkit-$VERSION.so
sed -e "s/@CARGO_VERSION@/$VERSION/" -e "s|^module_pathname = .*|module_pathname = '\$libdir/timescaledb_toolkit-$VERSION'|" \
  timescaledb_toolkit.control > $STAGE/share/postgresql/extension/timescaledb_toolkit.control
cp $SRC/pglite/timescaledb_toolkit.sql $STAGE/share/postgresql/extension/timescaledb_toolkit--$VERSION.sql
(cd $STAGE && tar -czf $OUT/timescaledb_toolkit.tar.gz $(find . -type f | sed 's|^\./||'))

# what PGlite has to export for this module: its function imports and the GOT entries it does not
# define itself, without emscripten's runtime functions and Rust's own symbols
python3 $SRC/pglite/wasm_imports.py $WASM | grep -v -E '^(invoke_|__|_R[A-Za-z0-9_]+$)' > $OUT/timescaledb_toolkit.imports
echo "built $OUT/timescaledb_toolkit.tar.gz (timescaledb_toolkit $VERSION)"
