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

# Normalize ORT_ROOT to an absolute real path to avoid unnormalized ../ segments
get_filename_component(ORT_ROOT_REAL "${ORT_ROOT}" REALPATH BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
if(ORT_ROOT_REAL)
    set(ORT_ROOT "${ORT_ROOT_REAL}")
endif()

# If the resolved ORT_ROOT doesn't exist, prefer the repository default under lib/thirdParty
if(NOT EXISTS "${ORT_ROOT}")
    set(_DEFAULT_ORT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/thirdParty/onnxruntime-android-1.20.1")
    get_filename_component(_DEFAULT_ORT_ROOT_REAL "${_DEFAULT_ORT_ROOT}" REALPATH BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    if(EXISTS "${_DEFAULT_ORT_ROOT_REAL}")
        message(STATUS "Provided ORT_ROOT (${ORT_ROOT}) not found; using repo thirdParty: ${_DEFAULT_ORT_ROOT_REAL}")
        set(ORT_ROOT "${_DEFAULT_ORT_ROOT_REAL}")
    else()
        message(STATUS "ORT_ROOT (${ORT_ROOT}) not found and default repo path also missing: ${_DEFAULT_ORT_ROOT_REAL}")
    endif()
endif()

if(ANDROID)
    # Normalize include/lib paths for Android
    set(ORT_INCLUDE "${ORT_ROOT}/headers")
    get_filename_component(ORT_INCLUDE "${ORT_INCLUDE}" REALPATH BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    set(ORT_LIB "${ORT_ROOT}/jni/${ANDROID_ABI}/libonnxruntime.so")
    get_filename_component(ORT_LIB "${ORT_LIB}" REALPATH BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
else()
    set(ORT_INCLUDE "${ORT_ROOT}/include")
    file(GLOB _ORT_SO "${ORT_ROOT}/lib/libonnxruntime.so*"
                      "${ORT_ROOT}/lib/libonnxruntime.dylib"
                      "${ORT_ROOT}/lib/onnxruntime.lib")
    list(GET _ORT_SO 0 ORT_LIB)
endif()

if(NOT EXISTS "${ORT_LIB}")
    # Try to locate any libonnxruntime under ORT_ROOT as a fallback.
    file(GLOB_RECURSE _FOUND_ORT_SO
         RELATIVE "${ORT_ROOT}"
         "${ORT_ROOT}/*libonnxruntime*.so"
         "${ORT_ROOT}/*libonnxruntime*.dylib")
    if(_FOUND_ORT_SO)
        list(GET _FOUND_ORT_SO 0 _rel)
        set(ORT_LIB "${ORT_ROOT}/${_rel}")
        message(STATUS "Found ORT_LIB fallback: ${ORT_LIB}")
    else()
        message(WARNING "libonnxruntime não encontrada at: ${ORT_LIB}; continuing — build may fail later if ONNX runtime is required at link time.")
        set(ORT_LIB "")
    endif()
endif()

message(STATUS "ORT_ROOT    : ${ORT_ROOT}")
message(STATUS "ORT_INCLUDE : ${ORT_INCLUDE}")
message(STATUS "ORT_LIB     : ${ORT_LIB}")

set(ORT_INCLUDE ${ORT_INCLUDE} CACHE INTERNAL "")
set(ORT_LIB    ${ORT_LIB}     CACHE INTERNAL "")

add_subdirectory(core)
add_subdirectory(ai)