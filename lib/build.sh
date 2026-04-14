#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "Building easync_ai..."

mkdir -p "$ROOT_DIR/ai/build"
(cd "$ROOT_DIR/ai/build" && make -j"$(nproc)")

if [ ! -f "$ROOT_DIR/ai/build/libeasync_ai.so" ]; then
    echo "ERROR: libeasync_ai.so failed to build." >&2
    exit 1
fi

echo "Built $ROOT_DIR/ai/build/libeasync_ai.so"
sudo sh -c "cd '$ROOT_DIR/ai/build' && make install"

echo ""
echo "Building easync_core..."

mkdir -p "$ROOT_DIR/core/build"
(cd "$ROOT_DIR/core/build" && cmake .. && make -j"$(nproc)")

if [ ! -f "$ROOT_DIR/core/build/libeasync_core.so" ]; then
    echo "ERROR: libeasync_core.so failed to build." >&2
    exit 1
fi

echo "Built $ROOT_DIR/core/build/libeasync_core.so"
sudo sh -c "cd '$ROOT_DIR/core/build' && make install"

sudo ldconfig

echo ""
echo "[100%] Everything built and installed successfully."