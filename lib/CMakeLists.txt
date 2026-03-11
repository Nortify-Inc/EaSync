cmake_minimum_required(VERSION 3.16)
project(easync LANGUAGES CXX)

if(NOT DEFINED ORT_ROOT)
    if(DEFINED ENV{ORT_ROOT})
        set(ORT_ROOT $ENV{ORT_ROOT})
    elseif(ANDROID)
        # Padrão relativo ao projeto — thirdParty is in the lib/ folder
        set(ORT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/thirdParty/onnxruntime-android-1.20.1")
    else()
        message(FATAL_ERROR "Defina ORT_ROOT: cmake .. -DORT_ROOT=/caminho/onnxruntime")
    endif()
endif()

if(ANDROID)
    set(ORT_INCLUDE "${ORT_ROOT}/headers")
    set(ORT_LIB    "${ORT_ROOT}/jni/${ANDROID_ABI}/libonnxruntime.so")
else()
    set(ORT_INCLUDE "${ORT_ROOT}/include")
    file(GLOB _ORT_SO "${ORT_ROOT}/lib/libonnxruntime.so*"
                      "${ORT_ROOT}/lib/libonnxruntime.dylib"
                      "${ORT_ROOT}/lib/onnxruntime.lib")
    list(GET _ORT_SO 0 ORT_LIB)
endif()

if(NOT EXISTS "${ORT_LIB}")
    message(FATAL_ERROR "libonnxruntime não encontrada: ${ORT_LIB}")
endif()

message(STATUS "ORT_ROOT    : ${ORT_ROOT}")
message(STATUS "ORT_INCLUDE : ${ORT_INCLUDE}")
message(STATUS "ORT_LIB     : ${ORT_LIB}")

set(ORT_INCLUDE ${ORT_INCLUDE} CACHE INTERNAL "")
set(ORT_LIB    ${ORT_LIB}     CACHE INTERNAL "")

add_subdirectory(core)
add_subdirectory(ai)