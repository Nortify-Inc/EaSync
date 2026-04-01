cmake_minimum_required(VERSION 3.16)
project(easync_ai LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

add_compile_options(
    -fdata-sections
    -ffunction-sections
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(
        -O3
        -DNDEBUG
        -fomit-frame-pointer
        -fstrict-aliasing
        -ffp-contract=fast
    )
endif()

if(ANDROID)
    add_compile_options(
        -fPIC
        -funroll-loops
    )
    if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
        add_compile_options(-march=armv8-a)
    endif()
endif()

find_package(Threads REQUIRED)

set(LLAMA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../thirdParty/llama.cpp")
if(NOT EXISTS "${LLAMA_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp not found at ${LLAMA_ROOT}. Clone it into lib/thirdParty/llama.cpp")
endif()

set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_WEBUI OFF CACHE BOOL "" FORCE)
set(LLAMA_TESTS_INSTALL OFF CACHE BOOL "" FORCE)
set(LLAMA_TOOLS_INSTALL OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)

add_subdirectory(${LLAMA_ROOT} ${CMAKE_CURRENT_BINARY_DIR}/llama.cpp)

add_library(easync_ai SHARED
    src/engine.cpp
)

target_include_directories(easync_ai PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(easync_ai PRIVATE
    llama
    Threads::Threads
)

set_target_properties(easync_ai PROPERTIES
    OUTPUT_NAME easync_ai
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_link_options(easync_ai PRIVATE
        -Wl,--gc-sections
        -Wl,-O1
    )
endif()

if(NOT ANDROID)
    add_executable(easync_ai_chat
        src/chat.cpp
    )

    target_include_directories(easync_ai_chat PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )

    target_link_libraries(easync_ai_chat PRIVATE
        easync_ai
        Threads::Threads
    )

    install(TARGETS easync_ai
        LIBRARY DESTINATION /usr/lib
    )
endif()
