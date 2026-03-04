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
