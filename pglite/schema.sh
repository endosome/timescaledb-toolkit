#!/bin/bash
# Generates the extension's SQL install script with a native build against PostgreSQL 18; the SQL
# does not depend on the target the library is built for. Runs in postgres:18 with this
# repository at /src (read-only) and writes /src-out/timescaledb_toolkit.sql.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq build-essential curl ca-certificates pkg-config libssl-dev libclang-dev clang \
  postgresql-server-dev-18 >/dev/null
export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal --default-toolchain 1.99.0 >/dev/null
cargo install -q --locked cargo-pgrx --version 0.18.1

PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
export CARGO_TARGET_DIR=/tmp/target-native PGRX_HOME=/tmp/pgrx-home
mkdir -p $PGRX_HOME && printf '[configs]\npg18 = "%s"\n' $PG_CONFIG > $PGRX_HOME/config.toml
cp -a /src /tmp/src && cd /tmp/src/extension
cargo pgrx schema --no-default-features --features pg18 --pg-config $PG_CONFIG -o /src-out/timescaledb_toolkit.sql
