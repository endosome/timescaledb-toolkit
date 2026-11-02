# PGlite's builder image plus Rust, for building the extension as a PGlite side module.
FROM electricsql/pglite-builder:6.0.5-1

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends libclang-dev clang curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.99.0 \
    && rustup target add wasm32-unknown-emscripten \
    && chmod -R a+rwX /opt/rustup /opt/cargo

# Rust panics on wasm32-unknown-emscripten use WebAssembly exceptions. PGlite's main module is
# built without them, so the side module links the unwinder and the exception tag itself.
RUN embuilder --pic build libunwind-wasmexcept libc++abi-wasmexcept > /dev/null \
    && chmod -R a+rwX /emsdk/upstream/emscripten/cache
