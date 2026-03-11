#pragma once

#include <stdint.h>

extern "C" {

int ai_set_data_dir(void *ctx, const char *path);
int ai_set_system_prompt(void *ctx, const char *system_prompt);
int ai_set_chat_model_script(void *ctx, const char *scriptPath);
int ai_initialize(void *ctx);
int ai_shutdown(void *ctx);


int ai_query(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen);
int ai_process_chat(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen);
int ai_model_process_chat(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen);
int ai_execute_command(void *ctx, const char *reqJson, char *outBuf, uint32_t outLen);
int ai_model_execute_command(void *ctx, const char *reqJson, char *outBuf, uint32_t outLen);


int ai_query_async_start(void *ctx, const char *inputJson, uint64_t *outHandle);
int ai_query_async_poll(void *ctx, uint64_t handle, bool *finished, char *outBuf, uint32_t outLen);

int ai_model_execute_command_async_start(void *ctx, const char *reqJson, uint64_t *outHandle);
int ai_model_execute_command_async_poll(void *ctx, uint64_t handle, bool *finished, char *outBuf, uint32_t outLen);

int ai_set_decode_every(void *ctx, int n);

int ai_get_annotations(void *ctx, char *outBuf, uint32_t outLen);
int ai_learning_snapshot(void *ctx, char *outBuf, uint32_t outLen);
int ai_set_permissions(void *ctx, void *perms);
int ai_get_permissions(void *ctx, void *perms);
int ai_record_pattern(void *ctx, const char *payload, uint64_t timestamp);
int ai_observe_app_open(void *ctx, uint64_t timestamp);
int ai_observe_profile_apply(void *ctx, const char *profile, uint64_t timestamp);

} // extern "C"