#!/bin/bash
set -e

# Build libeasync_ai.so
echo "Building ai..."
mkdir -p ai/build
(cd ai/build && cmake .. && make -j$(nproc))

if [ ! -f "ai/build/libeasync_ai.so" ]; then
    echo "ERROR: libeasync_ai.so was not generated." >&2
    exit 1
fi

echo "Built $(pwd)/ai/build/libeasync_ai.so"

sudo (cd ai/build && make install)
sudo ldconfig

# Build libeasync_core.so
echo "Building core..."
mkdir -p core/build
(cd core/build && cmake .. && make -j$(nproc))

if [ ! -f "core/build/libeasync_core.so" ]; then
    echo "ERROR: libeasync_core.so was not generated." >&2
    exit 1
fi

echo "Built $(pwd)/core/build/libeasync_core.so"

sudo (cd core/build && make install)
sudo ldconfig

echo "All libraries built and installed."
#!/bin/bash

##!
# @file build.sh
# @brief Local build script for the EaSync Core native library.
# @param No positional parameters.
# @return 0 on success; non-zero exit code on failure.
# @author Erick Radmann

set -e

mkdir -p build
cd build

cmake ..
make -j$(nproc)

if [ ! -f "libeasync_core.so" ]; then
	echo "ERROR: libeasync_core.so was not generated." >&2
	exit 1
fi

echo "Built $(pwd)/libeasync_core.so"

sudo make install
sudo ldconfig
