// ai/include/engine.hpp
// C API header for the Ai engine shared library (libeasync_ai.so)
#pragma once

#include <stdint.h>

// Return values: 0 == ok, negative == error
extern "C" {

// Synchronous chat/process functions.
int ai_process_chat(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen);
int ai_model_process_chat(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen);
int ai_execute_command(void *ctx, const char *reqJson, char *outBuf, uint32_t outLen);
int ai_model_execute_command(void *ctx, const char *reqJson, char *outBuf, uint32_t outLen);

// Configure runtime (path to python script that will be invoked)
int ai_set_chat_model_script(void *ctx, const char *scriptPath);

// Async API: start returns 0 and outputs a handle via outHandle on success
int ai_model_execute_command_async_start(void *ctx, const char *reqJson, uint64_t *outHandle);
int ai_model_execute_command_async_poll(void *ctx, uint64_t handle, bool *finished, char *outBuf, uint32_t outLen);

// Utility endpoints
int ai_get_annotations(void *ctx, char *outBuf, uint32_t outLen);
int ai_learning_snapshot(void *ctx, char *outBuf, uint32_t outLen);

// Permissions / telemetry hooks (opaque pointers for ABI compatibility)
int ai_set_permissions(void *ctx, void *perms);
int ai_get_permissions(void *ctx, void *perms);
int ai_record_pattern(void *ctx, const char *payload, uint64_t timestamp);
int ai_observe_app_open(void *ctx, uint64_t timestamp);
int ai_observe_profile_apply(void *ctx, const char *profile, uint64_t timestamp);

}
