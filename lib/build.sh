#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${1:-}" ]; then
    ORT_ROOT="$1"

elif [ -n "${ORT_ROOT:-}" ]; then
    :

else
    DEFAULT_ORT="$ROOT_DIR/thirdParty/onnxruntime-linux-x64-1.20.1"
    if [ -d "$DEFAULT_ORT" ]; then
        ORT_ROOT="$DEFAULT_ORT"
    else
        echo "ERROR: ORT_ROOT not found." >&2
        echo "       Use: ./build.sh /caminho/onnxruntime" >&2
        echo "       Ou:  export ORT_ROOT=/caminho/onnxruntime && ./build.sh" >&2
        exit 1
    fi
fi

echo "ORT_ROOT: $ORT_ROOT"

echo ""
echo "Building easync_ai..."

mkdir -p "$ROOT_DIR/ai/build"
(cd "$ROOT_DIR/ai/build" && cmake .. -DORT_ROOT="$ORT_ROOT" && make -j"$(nproc)")

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