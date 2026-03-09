#!/usr/bin/env bash
set -euo pipefail

# Build both libeasync_ai.so and libeasync_core.so and install them.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building ai..."
mkdir -p "$ROOT_DIR/ai/build"
(cd "$ROOT_DIR/ai/build" && cmake .. && make -j"$(nproc)")

if [ ! -f "$ROOT_DIR/ai/build/libeasync_ai.so" ]; then
    echo "ERROR: libeasync_ai.so was not generated." >&2
    exit 1
fi

echo "Built $ROOT_DIR/ai/build/libeasync_ai.so"

sudo sh -c "cd '$ROOT_DIR/ai/build' && make install"
sudo ldconfig

echo "Building core..."
mkdir -p "$ROOT_DIR/core/build"
(cd "$ROOT_DIR/core/build" && cmake .. && make -j"$(nproc)")

if [ ! -f "$ROOT_DIR/core/build/libeasync_core.so" ]; then
    echo "ERROR: libeasync_core.so was not generated." >&2
    exit 1
fi

echo "Built $ROOT_DIR/core/build/libeasync_core.so"

sudo sh -c "cd '$ROOT_DIR/core/build' && make install"
sudo ldconfig

echo "All libraries built and installed."
