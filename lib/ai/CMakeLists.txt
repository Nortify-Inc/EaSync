cmake_minimum_required(VERSION 3.16)

project(easync_ai LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(AI_SRC
    src/engine.cpp
)

add_library(easync_ai SHARED
    ${AI_SRC}
)

target_include_directories(easync_ai PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(easync_ai
    pthread
)

set_target_properties(easync_ai PROPERTIES
    OUTPUT_NAME easync_ai
)

if(NOT ANDROID)
    install(TARGETS easync_ai
        LIBRARY DESTINATION /usr/lib
    )
endif()
