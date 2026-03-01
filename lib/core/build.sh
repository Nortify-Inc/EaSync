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

sudo make install
sudo ldconfig
