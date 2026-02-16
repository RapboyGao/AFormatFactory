#include "AFormatFactoryFFmpegC.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct AFFOpaqueJob {
    char *input_path;
    char *output_path;
    char **arguments;
    int argument_count;
    int overwrite_existing;
    bool cancelled;
};

static _Thread_local char g_last_error[1024];

static int set_errorf(const char *message) {
    if (message == NULL) {
        g_last_error[0] = '\0';
        return 0;
    }
    snprintf(g_last_error, sizeof(g_last_error), "%s", message);
    return -1;
}

static void clear_error(void) {
    g_last_error[0] = '\0';
}

AFFOpaqueJob *aff_create_job(void) {
    clear_error();
    AFFOpaqueJob *job = (AFFOpaqueJob *)calloc(1, sizeof(AFFOpaqueJob));
    if (job == NULL) {
        set_errorf("failed to allocate job");
    }
    return job;
}

void aff_destroy_job(AFFOpaqueJob *job) {
    if (job == NULL) {
        return;
    }
    free(job->input_path);
    free(job->output_path);
    for (int i = 0; i < job->argument_count; i++) {
        free(job->arguments[i]);
    }
    free(job->arguments);
    free(job);
}

int aff_set_input_output(AFFOpaqueJob *job, const char *input_path, const char *output_path, int overwrite_existing) {
    if (job == NULL || input_path == NULL || output_path == NULL) {
        return set_errorf("invalid arguments for aff_set_input_output");
    }

    char *input_copy = strdup(input_path);
    char *output_copy = strdup(output_path);
    if (input_copy == NULL || output_copy == NULL) {
        free(input_copy);
        free(output_copy);
        return set_errorf("failed to allocate input/output path");
    }

    free(job->input_path);
    free(job->output_path);
    job->input_path = input_copy;
    job->output_path = output_copy;
    job->overwrite_existing = overwrite_existing;
    clear_error();
    return 0;
}

int aff_set_arguments(AFFOpaqueJob *job, const char **arguments, int argument_count) {
    if (job == NULL || argument_count < 0) {
        return set_errorf("invalid arguments for aff_set_arguments");
    }

    for (int i = 0; i < job->argument_count; i++) {
        free(job->arguments[i]);
    }
    free(job->arguments);
    job->arguments = NULL;
    job->argument_count = 0;

    if (argument_count == 0) {
        clear_error();
        return 0;
    }

    char **copies = (char **)calloc((size_t)argument_count, sizeof(char *));
    if (copies == NULL) {
        return set_errorf("failed to allocate arguments buffer");
    }

    for (int i = 0; i < argument_count; i++) {
        copies[i] = strdup(arguments[i]);
        if (copies[i] == NULL) {
            for (int j = 0; j < i; j++) {
                free(copies[j]);
            }
            free(copies);
            return set_errorf("failed to allocate argument string");
        }
    }

    job->arguments = copies;
    job->argument_count = argument_count;
    clear_error();
    return 0;
}

int aff_run_job_async(
    AFFOpaqueJob *job,
    AFFLogCallback log_callback,
    AFFProgressCallback progress_callback,
    void *context
) {
    (void)progress_callback;

    if (job == NULL || job->input_path == NULL || job->output_path == NULL) {
        return set_errorf("job is not fully configured");
    }

    if (job->cancelled) {
        if (log_callback != NULL) {
            log_callback(1, "job cancelled", context);
        }
        return set_errorf("job cancelled");
    }

    if (log_callback != NULL) {
        log_callback(0, "AFormatFactoryFFmpegC shim is ready. Runtime execution is delegated by Swift engine.", context);
    }

    clear_error();
    return 0;
}

int aff_cancel_job(AFFOpaqueJob *job) {
    if (job == NULL) {
        return set_errorf("invalid job in aff_cancel_job");
    }
    job->cancelled = true;
    clear_error();
    return 0;
}

int aff_detect_capabilities(char **muxers_json, char **encoders_json) {
    if (muxers_json == NULL || encoders_json == NULL) {
        return set_errorf("invalid arguments for aff_detect_capabilities");
    }

    const char *empty = "[]";
    *muxers_json = strdup(empty);
    *encoders_json = strdup(empty);
    if (*muxers_json == NULL || *encoders_json == NULL) {
        free(*muxers_json);
        free(*encoders_json);
        *muxers_json = NULL;
        *encoders_json = NULL;
        return set_errorf("failed to allocate capability json");
    }

    clear_error();
    return 0;
}

int aff_probe_media(const char *input_path, char **media_info_json) {
    (void)input_path;
    if (media_info_json == NULL) {
        return set_errorf("invalid arguments for aff_probe_media");
    }

    const char *empty = "{}";
    *media_info_json = strdup(empty);
    if (*media_info_json == NULL) {
        return set_errorf("failed to allocate probe json");
    }

    clear_error();
    return 0;
}

const char *aff_copy_last_error(void) {
    return g_last_error;
}

void aff_free_string(char *value) {
    free(value);
}
