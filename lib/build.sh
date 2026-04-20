#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
THIRD_PARTY="$ROOT_DIR/thirdParty"
JOBS=$(nproc)

err() { echo ""; echo "ERROR: $*" >&2; exit 1; }

clone_if_missing() {
    local name="$1"
    local url="$2"
    local dir="$THIRD_PARTY/$name"
    if [ ! -d "$dir/.git" ]; then
        git clone --depth=1 --recursive "$url" "$dir"
    fi
}

echo "[1/5] Cloning dependencies..."
mkdir -p "$THIRD_PARTY"

clone_if_missing "openssl" "https://github.com/openssl/openssl"
clone_if_missing "paho.mqtt.c" "https://github.com/eclipse/paho.mqtt.c"
clone_if_missing "paho.mqtt.cpp" "https://github.com/eclipse/paho.mqtt.cpp"
clone_if_missing "curl" "https://github.com/curl/curl"

echo "[1/5] Done."

ANDROID_ABIS=(armeabi-v7a arm64-v8a x86_64)

ANDROID_NDK="${ANDROID_NDK:-}"
if [ -z "$ANDROID_NDK" ]; then
    ANDROID_NDK=$(find "$HOME/Android/Sdk/ndk" -maxdepth 1 -type d | sort | tail -n1)
fi

[ -d "$ANDROID_NDK" ] || err "ANDROID_NDK not found"

export ANDROID_NDK
export ANDROID_NDK_ROOT="$ANDROID_NDK"

TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64"

build_for_abi() {
    local abi="$1"

    export PATH="$TOOLCHAIN/bin:$PATH"

    local OPENSSL_TARGET=""
    case "$abi" in
        arm64-v8a)
            export CC=aarch64-linux-android24-clang
            export CXX=aarch64-linux-android24-clang++
            OPENSSL_TARGET="android-arm64"
            ;;
        armeabi-v7a)
            export CC=armv7a-linux-androideabi24-clang
            export CXX=armv7a-linux-androideabi24-clang++
            OPENSSL_TARGET="android-arm"
            ;;
        x86_64)
            export CC=x86_64-linux-android24-clang
            export CXX=x86_64-linux-android24-clang++
            OPENSSL_TARGET="android-x86_64"
            ;;
        *)
            err "Unsupported ABI: $abi"
            ;;
    esac

    OPENSSL_INSTALL="$THIRD_PARTY/openssl/install-android-$abi"
    PAHO_C_INSTALL="$THIRD_PARTY/paho.mqtt.c/install-android-$abi"
    PAHO_CPP_INSTALL="$THIRD_PARTY/paho.mqtt.cpp/install-android-$abi"
    CURL_INSTALL="$THIRD_PARTY/curl/install-android-$abi"

    OPENSSL_LIB_DIR="$OPENSSL_INSTALL/lib"
    [ -d "$OPENSSL_INSTALL/lib64" ] && OPENSSL_LIB_DIR="$OPENSSL_INSTALL/lib64"

    TOOLCHAIN_ARGS="-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-24"

    # OpenSSL
    if [ ! -f "$OPENSSL_INSTALL/lib/libssl.a" ]; then
        echo "[2/5] OpenSSL ($abi)..."

        rm -rf "$OPENSSL_INSTALL"

        (
            cd "$THIRD_PARTY/openssl"

            make clean >/dev/null 2>&1 || true

            export CFLAGS="-fPIC"
            export CXXFLAGS="-fPIC"

            ./Configure "$OPENSSL_TARGET" no-shared no-tests no-asm -fPIC \
                --prefix="$OPENSSL_INSTALL"

            make -j"$JOBS"
            make install_sw
        )

        [ -f "$OPENSSL_INSTALL/lib/libssl.a" ] || err "OpenSSL failed for $abi"
    fi

    # Paho C
    echo "[2/5] Paho C ($abi)..."
    rm -rf "$THIRD_PARTY/paho.mqtt.c/build-$abi"

    cmake -S "$THIRD_PARTY/paho.mqtt.c" -B "$THIRD_PARTY/paho.mqtt.c/build-$abi" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPAHO_BUILD_STATIC=ON \
        -DPAHO_BUILD_SHARED=OFF \
        -DPAHO_ENABLE_TESTING=OFF \
        -DPAHO_WITH_SSL=ON \
        -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL" \
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INSTALL/include" \
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_LIB_DIR/libssl.a" \
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_LIB_DIR/libcrypto.a" \
        -DCMAKE_INSTALL_PREFIX="$PAHO_C_INSTALL" \
        $TOOLCHAIN_ARGS

    cmake --build "$THIRD_PARTY/paho.mqtt.c/build-$abi" -j"$JOBS"
    cmake --install "$THIRD_PARTY/paho.mqtt.c/build-$abi"

    # Paho C++
    echo "[2/5] Paho C++ ($abi)..."
    rm -rf "$THIRD_PARTY/paho.mqtt.cpp/build-$abi"

    cmake -S "$THIRD_PARTY/paho.mqtt.cpp" -B "$THIRD_PARTY/paho.mqtt.cpp/build-$abi" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPAHO_BUILD_STATIC=ON \
        -DPAHO_BUILD_SHARED=OFF \
        -DPAHO_WITH_SSL=ON \
        -DCMAKE_PREFIX_PATH="$PAHO_C_INSTALL" \
        -Declipse-paho-mqtt-c_DIR="$PAHO_C_INSTALL/lib/cmake/eclipse-paho-mqtt-c" \
        -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL" \
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INSTALL/include" \
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_LIB_DIR/libssl.a" \
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_LIB_DIR/libcrypto.a" \
        -DCMAKE_INSTALL_PREFIX="$PAHO_CPP_INSTALL" \
        $TOOLCHAIN_ARGS

    cmake --build "$THIRD_PARTY/paho.mqtt.cpp/build-$abi" -j"$JOBS"
    cmake --install "$THIRD_PARTY/paho.mqtt.cpp/build-$abi"

    # cURL
    echo "[2/5] cURL ($abi)..."
    rm -rf "$THIRD_PARTY/curl/build-$abi"

    cmake -S "$THIRD_PARTY/curl" -B "$THIRD_PARTY/curl/build-$abi" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCURL_USE_OPENSSL=ON \
        -DCURL_USE_LIBPSL=OFF \
        -DUSE_LIBPSL=OFF \
        -DLIBPSL_INCLUDE_DIR="" \
        -DLIBPSL_LIBRARY="" \
        -DCURL_DISABLE_LDAP=ON \
        -DCURL_DISABLE_LDAPS=ON \
        -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL" \
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INSTALL/include" \
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_LIB_DIR/libssl.a" \
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_LIB_DIR/libcrypto.a" \
        -DCMAKE_INSTALL_PREFIX="$CURL_INSTALL" \
        $TOOLCHAIN_ARGS

    cmake --build "$THIRD_PARTY/curl/build-$abi" -j"$JOBS"
    cmake --install "$THIRD_PARTY/curl/build-$abi"
}

for abi in "${ANDROID_ABIS[@]}"; do
    build_for_abi "$abi"
done

echo "[3/5] Building easync_ai..."

mkdir -p "$ROOT_DIR/ai/build"
cd "$ROOT_DIR/ai/build"

cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$JOBS"

echo "[4/5] Building easync_core..."

mkdir -p "$ROOT_DIR/core/build"
cd "$ROOT_DIR/core/build"

cmake .. -DCMAKE_BUILD_TYPE=Release -DEASYNC_THIRD_PARTY_DIR="$THIRD_PARTY"
make -j"$JOBS"

echo "[5/5] Done."