cmake_minimum_required(VERSION 3.16)

project(easync_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(EASYNC_ENABLE_MQTT   ON)
set(EASYNC_ENABLE_WIFI   ON)
set(EASYNC_ENABLE_ZIGBEE ON)
set(EASYNC_ENABLE_BLE    ON)

if(NOT DEFINED EASYNC_THIRD_PARTY_DIR)
    set(EASYNC_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../thirdParty")
endif()
get_filename_component(EASYNC_THIRD_PARTY_DIR "${EASYNC_THIRD_PARTY_DIR}" ABSOLUTE)

if(ANDROID)
    set(ABI_SUBDIR "${ANDROID_ABI}")
    set(OPENSSL_INSTALL  "${EASYNC_THIRD_PARTY_DIR}/openssl/install-android-${ABI_SUBDIR}")
    set(PAHO_C_INSTALL   "${EASYNC_THIRD_PARTY_DIR}/paho.mqtt.c/install-android-${ABI_SUBDIR}")
    set(PAHO_CPP_INSTALL "${EASYNC_THIRD_PARTY_DIR}/paho.mqtt.cpp/install-android-${ABI_SUBDIR}")
    set(CURL_INSTALL     "${EASYNC_THIRD_PARTY_DIR}/curl/install-android-${ABI_SUBDIR}")
elseif(IOS)
    set(ABI_SUBDIR "${CMAKE_OSX_ARCHITECTURES}")
    set(OPENSSL_INSTALL  "${EASYNC_THIRD_PARTY_DIR}/openssl/install-ios-${ABI_SUBDIR}")
    set(PAHO_C_INSTALL   "${EASYNC_THIRD_PARTY_DIR}/paho.mqtt.c/install-ios-${ABI_SUBDIR}")
    set(PAHO_CPP_INSTALL "${EASYNC_THIRD_PARTY_DIR}/paho.mqtt.cpp/install-ios-${ABI_SUBDIR}")
    set(CURL_INSTALL     "${EASYNC_THIRD_PARTY_DIR}/curl/install-ios-${ABI_SUBDIR}")
else()
    set(OPENSSL_INSTALL  "${EASYNC_THIRD_PARTY_DIR}/openssl/install")
    set(PAHO_C_INSTALL   "${EASYNC_THIRD_PARTY_DIR}/paho.mqtt.c/install")
    set(PAHO_CPP_INSTALL "${EASYNC_THIRD_PARTY_DIR}/paho.mqtt.cpp/install")
    set(CURL_INSTALL     "${EASYNC_THIRD_PARTY_DIR}/curl/install")
endif()

if(NOT EXISTS "${OPENSSL_INSTALL}/include/openssl/ssl.h")
    message(FATAL_ERROR "OpenSSL headers not found: ${OPENSSL_INSTALL}")
endif()

if(NOT EXISTS "${PAHO_C_INSTALL}/include/MQTTAsync.h")
    message(FATAL_ERROR "Paho C headers not found: ${PAHO_C_INSTALL}")
endif()

if(NOT EXISTS "${PAHO_CPP_INSTALL}/include/mqtt/async_client.h")
    message(FATAL_ERROR "Paho C++ headers not found: ${PAHO_CPP_INSTALL}")
endif()

if(NOT EXISTS "${CURL_INSTALL}/include/curl/curl.h")
    message(FATAL_ERROR "cURL headers not found: ${CURL_INSTALL}")
endif()

if(EXISTS "${OPENSSL_INSTALL}/lib64")
    set(OPENSSL_LIB_DIR "${OPENSSL_INSTALL}/lib64")
else()
    set(OPENSSL_LIB_DIR "${OPENSSL_INSTALL}/lib")
endif()

set(PAHO_C_LIB
    "${PAHO_C_INSTALL}/lib/libpaho-mqtt3as.a"
)

set(PAHO_CPP_LIB
    "${PAHO_CPP_INSTALL}/lib/libpaho-mqttpp3.a"
)

set(CURL_LIB
    "${CURL_INSTALL}/lib/libcurl.a"
)

foreach(lib ${PAHO_C_LIB} ${PAHO_CPP_LIB} ${CURL_LIB})
    if(NOT EXISTS ${lib})
        message(FATAL_ERROR "Missing lib: ${lib}")
    endif()
endforeach()

message(STATUS "Paho C   : ${PAHO_C_LIB}")
message(STATUS "Paho C++ : ${PAHO_CPP_LIB}")
message(STATUS "cURL     : ${CURL_LIB}")

set(CORE_SRC
    src/core.cpp
    src/driver.cpp
    src/payloadUtility.cpp
    src/adaptiveLayer.cpp
)

file(GLOB DRIVER_SRC drivers/*.cpp)

if(NOT EASYNC_ENABLE_MQTT)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/mqtt\\.cpp$")
endif()
if(NOT EASYNC_ENABLE_WIFI)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/wifi\\.cpp$")
endif()
if(NOT EASYNC_ENABLE_ZIGBEE)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/zigbee\\.cpp$")
endif()
if(NOT EASYNC_ENABLE_BLE)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/ble\\.cpp$")
endif()

add_library(easync_core SHARED
    ${CORE_SRC}
    ${DRIVER_SRC}
)

target_include_directories(easync_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/drivers
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${OPENSSL_INSTALL}/include
    ${PAHO_C_INSTALL}/include
    ${PAHO_CPP_INSTALL}/include
    ${CURL_INSTALL}/include
)

if(EASYNC_ENABLE_MQTT)
    target_compile_definitions(easync_core PRIVATE EASYNC_ENABLE_MQTT_DRIVER=1)
endif()
if(EASYNC_ENABLE_WIFI)
    target_compile_definitions(easync_core PRIVATE EASYNC_ENABLE_WIFI_DRIVER=1)
endif()
if(EASYNC_ENABLE_ZIGBEE)
    target_compile_definitions(easync_core PRIVATE EASYNC_ENABLE_ZIGBEE_DRIVER=1)
endif()
if(EASYNC_ENABLE_BLE)
    target_compile_definitions(easync_core PRIVATE EASYNC_ENABLE_BLE_DRIVER=1)
endif()

if(ANDROID)
    target_link_libraries(easync_core
        ${PAHO_CPP_LIB}
        ${PAHO_C_LIB}
        ${CURL_LIB}
        ${OPENSSL_LIB_DIR}/libssl.a
        ${OPENSSL_LIB_DIR}/libcrypto.a
        z
        log
    )
else()
    target_link_libraries(easync_core
        ${PAHO_CPP_LIB}
        ${PAHO_C_LIB}
        ${CURL_LIB}
        ${OPENSSL_LIB_DIR}/libssl.a
        ${OPENSSL_LIB_DIR}/libcrypto.a
        pthread
        dl
        z
    )
endif()

set_target_properties(easync_core PROPERTIES OUTPUT_NAME easync_core)

if(NOT ANDROID)
    install(TARGETS easync_core LIBRARY DESTINATION /usr/lib)
endif()