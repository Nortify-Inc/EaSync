cmake_minimum_required(VERSION 3.16)

project(easync_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(EASYNC_ENABLE_MQTT ON)
set(EASYNC_ENABLE_WIFI ON)
set(EASYNC_ENABLE_ZIGBEE ON)

if(ANDROID)
    set(EASYNC_ENABLE_MQTT OFF)
    set(EASYNC_ENABLE_WIFI OFF)
    set(EASYNC_ENABLE_ZIGBEE OFF)
endif()

# Sources
set(CORE_SRC
    src/core.cpp
    src/driver.cpp
    src/payloadUtility.cpp
    src/adaptiveLayer.cpp
)

file(GLOB DRIVER_SRC
    drivers/*.cpp
)

if(NOT EASYNC_ENABLE_MQTT)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/mqtt\\.cpp$")
endif()

if(NOT EASYNC_ENABLE_WIFI)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/wifi\\.cpp$")
endif()

if(NOT EASYNC_ENABLE_ZIGBEE)
    list(FILTER DRIVER_SRC EXCLUDE REGEX ".*/zigbee\\.cpp$")
endif()

# Shared library
add_library(easync_core SHARED
    ${CORE_SRC}
    ${DRIVER_SRC}
)

# Includes
target_include_directories(easync_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/drivers
    ${CMAKE_CURRENT_SOURCE_DIR}
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

# Dependencies
if(ANDROID)
    target_link_libraries(easync_core
        log
    )
else()
    target_link_libraries(easync_core
        paho-mqttpp3
        paho-mqtt3as
        curl
        pthread
    )
endif()

# Output name
set_target_properties(easync_core PROPERTIES
    OUTPUT_NAME easync_core
)

if(NOT ANDROID)
    # Install to system
    install(TARGETS easync_core
        LIBRARY DESTINATION /usr/lib
    )
endif()
