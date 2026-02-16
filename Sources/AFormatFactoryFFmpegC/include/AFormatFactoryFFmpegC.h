#ifndef AFORMATFACTORY_FFMPEGC_H
#define AFORMATFACTORY_FFMPEGC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AFFOpaqueJob AFFOpaqueJob;

typedef void (*AFFLogCallback)(int level, const char *message, void *context);

typedef struct {
    uint64_t processed_frames;
    double processed_time_seconds;
    double estimated_ratio;
    double bitrate_kbps;
    double speed;
} AFFProgress;

typedef void (*AFFProgressCallback)(AFFProgress progress, void *context);

AFFOpaqueJob *aff_create_job(void);
void aff_destroy_job(AFFOpaqueJob *job);

int aff_set_input_output(AFFOpaqueJob *job, const char *input_path, const char *output_path, int overwrite_existing);
int aff_set_arguments(AFFOpaqueJob *job, const char **arguments, int argument_count);
int aff_set_media_edit_inputs(
    AFFOpaqueJob *job,
    const char *additional_audio_input,
    const char *subtitle_input,
    const char *subtitle_codec
);
int aff_add_metadata(AFFOpaqueJob *job, const char *key, const char *value);
int aff_clear_chapters(AFFOpaqueJob *job);
int aff_add_chapter(AFFOpaqueJob *job, int64_t start_milliseconds, int64_t end_milliseconds, const char *title);

int aff_run_job_async(
    AFFOpaqueJob *job,
    AFFLogCallback log_callback,
    AFFProgressCallback progress_callback,
    void *context
);

int aff_cancel_job(AFFOpaqueJob *job);

int aff_detect_capabilities(char **muxers_json, char **encoders_json);
int aff_probe_media(const char *input_path, char **media_info_json);

const char *aff_copy_last_error(void);
void aff_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
