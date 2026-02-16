#!/bin/bash

set -e

mkdir -p build
cd build

cmake ..
make -j$(nproc)

sudo make install
sudo ldconfig
