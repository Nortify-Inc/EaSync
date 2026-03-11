cmake_minimum_required(VERSION 3.16)
project(easync_ai LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(Threads REQUIRED)

if(NOT DEFINED ORT_INCLUDE OR NOT DEFINED ORT_LIB)
    if(NOT DEFINED ORT_ROOT)
        if(DEFINED ENV{ORT_ROOT})
            set(ORT_ROOT $ENV{ORT_ROOT})
        else()
            message(FATAL_ERROR "Defina ORT_ROOT: cmake .. -DORT_ROOT=/caminho/onnxruntime")
        endif()
    endif()

    set(ORT_INCLUDE "${ORT_ROOT}/include")
    file(GLOB _ORT_SO "${ORT_ROOT}/lib/libonnxruntime.so*"
                      "${ORT_ROOT}/lib/libonnxruntime.dylib"
                      "${ORT_ROOT}/lib/onnxruntime.lib")
    list(GET _ORT_SO 0 ORT_LIB)
endif()

if(NOT EXISTS "${ORT_LIB}")
    message(FATAL_ERROR "libonnxruntime não encontrada: ${ORT_LIB}")
endif()

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION             "${ORT_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${ORT_INCLUDE}"
)

add_library(easync_ai SHARED
    src/engine.cpp
    src/SGLM.cpp
    src/tokenizer.cpp
)

target_include_directories(easync_ai PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${ORT_INCLUDE}
)

target_link_libraries(easync_ai PRIVATE
    onnxruntime
    Threads::Threads
)

set_target_properties(easync_ai PROPERTIES
    OUTPUT_NAME easync_ai
)

if(NOT ANDROID)
    install(TARGETS easync_ai
        LIBRARY DESTINATION /usr/lib
    )
    install(FILES "${ORT_LIB}"
        DESTINATION /usr/lib
    )
endif()