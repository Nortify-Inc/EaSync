cmake_minimum_required(VERSION 3.16)

project(easync_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Sources
set(CORE_SRC
    src/core.cpp
    src/driver.cpp
    src/payload_utility.cpp
)

file(GLOB DRIVER_SRC
    drivers/*.cpp
)

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

# Dependencies
target_link_libraries(easync_core
    paho-mqttpp3
    paho-mqtt3as
    curl
    pthread
)

# Output name
set_target_properties(easync_core PROPERTIES
    OUTPUT_NAME easync_core
)

# Install to system
install(TARGETS easync_core
    LIBRARY DESTINATION /usr/lib
)
