#include "AFormatFactoryFFmpegC_Internal.h"

typedef struct AFFInputRemuxMap {
    AVFormatContext *ctx;
    int *stream_map;
    int stream_map_size;
} AFFInputRemuxMap;

static int create_stream_map_for_input(
    AVFormatContext *input_ctx,
    AVFormatContext *output_ctx,
    int *stream_map,
    enum AVMediaType expected_single_type,
    bool single_stream_only,
    const char *subtitle_codec
) {
    for (unsigned int i = 0; i < input_ctx->nb_streams; i++) {
        stream_map[i] = -1;
    }

    bool single_stream_picked = false;
    for (unsigned int i = 0; i < input_ctx->nb_streams; i++) {
        AVStream *in_stream = input_ctx->streams[i];
        enum AVMediaType type = in_stream->codecpar->codec_type;
        if (!(type == AVMEDIA_TYPE_VIDEO || type == AVMEDIA_TYPE_AUDIO || type == AVMEDIA_TYPE_SUBTITLE)) {
            continue;
        }
        if (expected_single_type != AVMEDIA_TYPE_UNKNOWN && type != expected_single_type) {
            continue;
        }
        if (single_stream_only && single_stream_picked) {
            continue;
        }

        AVStream *out_stream = avformat_new_stream(output_ctx, NULL);
        if (out_stream == NULL) {
            return AVERROR(ENOMEM);
        }

        int err = avcodec_parameters_copy(out_stream->codecpar, in_stream->codecpar);
        if (err < 0) {
            return err;
        }
        out_stream->codecpar->codec_tag = 0;
        out_stream->time_base = in_stream->time_base;
        if (type == AVMEDIA_TYPE_SUBTITLE && subtitle_codec != NULL && str_eq(subtitle_codec, "mov_text")) {
            out_stream->codecpar->codec_id = AV_CODEC_ID_MOV_TEXT;
        }
        stream_map[i] = out_stream->index;
        single_stream_picked = true;
    }
    return 0;
}

static int remux_all_packets(
    AFFOpaqueJob *job,
    AFFInputRemuxMap map,
    AVFormatContext *output_ctx,
    AFFProgressCallback progress_callback,
    void *context,
    int64_t reference_duration
) {
    AVPacket *packet = av_packet_alloc();
    if (packet == NULL) {
        return AVERROR(ENOMEM);
    }

    int err = 0;
    while ((err = av_read_frame(map.ctx, packet)) >= 0) {
        if (job->cancelled) {
            err = set_errorf("job cancelled");
            break;
        }
        if (packet->stream_index < 0 || packet->stream_index >= map.stream_map_size || map.stream_map[packet->stream_index] < 0) {
            av_packet_unref(packet);
            continue;
        }

        AVStream *in_stream = map.ctx->streams[packet->stream_index];
        AVStream *out_stream = output_ctx->streams[map.stream_map[packet->stream_index]];
        int write_err = copy_packet(output_ctx, packet, in_stream, out_stream);
        if (write_err < 0) {
            av_packet_unref(packet);
            err = write_err;
            break;
        }

        if (progress_callback != NULL && reference_duration > 0) {
            int64_t packet_us = av_rescale_q(packet->pts, in_stream->time_base, AV_TIME_BASE_Q);
            AFFProgress progress = {0};
            progress.processed_time_seconds = packet_us > 0 ? ((double)packet_us / AV_TIME_BASE) : 0;
            double ratio = (double)packet_us / (double)reference_duration;
            if (ratio < 0) ratio = 0;
            if (ratio > 1) ratio = 1;
            progress.estimated_ratio = ratio;
            progress_callback(progress, context);
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);

    if (err == AVERROR_EOF) {
        return 0;
    }
    return err;
}

int run_media_edit_job(
    AFFOpaqueJob *job,
    AFFProgressCallback progress_callback,
    void *context
) {
    AVFormatContext *primary = NULL;
    AVFormatContext *additional_audio = NULL;
    AVFormatContext *subtitle = NULL;
    AVFormatContext *output = NULL;
    AFFInputRemuxMap maps[3] = {0};
    int map_count = 0;
    int err = 0;

    err = avformat_open_input(&primary, job->input_path, NULL, NULL);
    if (err < 0) {
        return set_error_av("failed to open primary media input", err);
    }
    err = avformat_find_stream_info(primary, NULL);
    if (err < 0) {
        err = set_error_av("failed to read primary stream info", err);
        goto cleanup;
    }

    if (job->additional_audio_input != NULL && job->additional_audio_input[0] != '\0') {
        err = avformat_open_input(&additional_audio, job->additional_audio_input, NULL, NULL);
        if (err < 0) {
            err = set_error_av("failed to open additional audio input", err);
            goto cleanup;
        }
        err = avformat_find_stream_info(additional_audio, NULL);
        if (err < 0) {
            err = set_error_av("failed to read additional audio stream info", err);
            goto cleanup;
        }
    }

    if (job->subtitle_input != NULL && job->subtitle_input[0] != '\0') {
        err = avformat_open_input(&subtitle, job->subtitle_input, NULL, NULL);
        if (err < 0) {
            err = set_error_av("failed to open subtitle input", err);
            goto cleanup;
        }
        err = avformat_find_stream_info(subtitle, NULL);
        if (err < 0) {
            err = set_error_av("failed to read subtitle stream info", err);
            goto cleanup;
        }
    }

    err = avformat_alloc_output_context2(&output, NULL, NULL, job->output_path);
    if (err < 0 || output == NULL) {
        err = set_error_av("failed to allocate output context", err < 0 ? err : AVERROR_UNKNOWN);
        goto cleanup;
    }

    maps[map_count++] = (AFFInputRemuxMap){
        .ctx = primary,
        .stream_map = (int *)malloc(sizeof(int) * primary->nb_streams),
        .stream_map_size = (int)primary->nb_streams
    };
    if (maps[0].stream_map == NULL) {
        err = set_errorf("failed to allocate primary stream map");
        goto cleanup;
    }
    err = create_stream_map_for_input(primary, output, maps[0].stream_map, AVMEDIA_TYPE_UNKNOWN, false, NULL);
    if (err < 0) {
        err = set_error_av("failed to map primary streams", err);
        goto cleanup;
    }

    if (additional_audio != NULL) {
        maps[map_count] = (AFFInputRemuxMap){
            .ctx = additional_audio,
            .stream_map = (int *)malloc(sizeof(int) * additional_audio->nb_streams),
            .stream_map_size = (int)additional_audio->nb_streams
        };
        if (maps[map_count].stream_map == NULL) {
            err = set_errorf("failed to allocate additional audio stream map");
            goto cleanup;
        }
        err = create_stream_map_for_input(additional_audio, output, maps[map_count].stream_map, AVMEDIA_TYPE_AUDIO, true, NULL);
        if (err < 0) {
            err = set_error_av("failed to map additional audio stream", err);
            goto cleanup;
        }
        map_count += 1;
    }

    if (subtitle != NULL) {
        maps[map_count] = (AFFInputRemuxMap){
            .ctx = subtitle,
            .stream_map = (int *)malloc(sizeof(int) * subtitle->nb_streams),
            .stream_map_size = (int)subtitle->nb_streams
        };
        if (maps[map_count].stream_map == NULL) {
            err = set_errorf("failed to allocate subtitle stream map");
            goto cleanup;
        }
        err = create_stream_map_for_input(subtitle, output, maps[map_count].stream_map, AVMEDIA_TYPE_SUBTITLE, true, job->subtitle_codec);
        if (err < 0) {
            err = set_error_av("failed to map subtitle stream", err);
            goto cleanup;
        }
        map_count += 1;
    }

    av_dict_copy(&output->metadata, primary->metadata, 0);
    AVDictionaryEntry *entry = NULL;
    while ((entry = av_dict_get(job->media_edit_metadata, "", entry, AV_DICT_IGNORE_SUFFIX)) != NULL) {
        av_dict_set(&output->metadata, entry->key, entry->value, 0);
    }

    if (job->chapter_count > 0) {
        output->nb_chapters = (unsigned int)job->chapter_count;
        output->chapters = av_calloc((size_t)job->chapter_count, sizeof(AVChapter *));
        if (output->chapters == NULL) {
            err = set_errorf("failed to allocate chapter list");
            goto cleanup;
        }
        for (int i = 0; i < job->chapter_count; i++) {
            AVChapter *chapter = av_mallocz(sizeof(AVChapter));
            if (chapter == NULL) {
                err = set_errorf("failed to allocate chapter");
                goto cleanup;
            }
            chapter->id = i;
            chapter->time_base = (AVRational){1, 1000};
            chapter->start = job->chapters[i].start_milliseconds;
            chapter->end = job->chapters[i].end_milliseconds;
            av_dict_set(&chapter->metadata, "title", job->chapters[i].title, 0);
            output->chapters[i] = chapter;
        }
    } else if (primary->nb_chapters > 0) {
        output->nb_chapters = primary->nb_chapters;
        output->chapters = av_calloc((size_t)primary->nb_chapters, sizeof(AVChapter *));
        if (output->chapters == NULL) {
            err = set_errorf("failed to allocate source chapter list");
            goto cleanup;
        }
        for (unsigned int i = 0; i < primary->nb_chapters; i++) {
            AVChapter *source = primary->chapters[i];
            AVChapter *chapter = av_mallocz(sizeof(AVChapter));
            if (chapter == NULL) {
                err = set_errorf("failed to allocate source chapter");
                goto cleanup;
            }
            chapter->id = source->id;
            chapter->time_base = source->time_base;
            chapter->start = source->start;
            chapter->end = source->end;
            av_dict_copy(&chapter->metadata, source->metadata, 0);
            output->chapters[i] = chapter;
        }
    }

    if (!(output->oformat->flags & AVFMT_NOFILE)) {
        if (!job->overwrite_existing) {
            FILE *f = fopen(job->output_path, "rb");
            if (f != NULL) {
                fclose(f);
                err = set_errorf("output exists and overwrite is disabled");
                goto cleanup;
            }
        }
        err = avio_open(&output->pb, job->output_path, AVIO_FLAG_WRITE);
        if (err < 0) {
            err = set_error_av("failed to open output", err);
            goto cleanup;
        }
    }

    err = avformat_write_header(output, NULL);
    if (err < 0) {
        err = set_error_av("failed to write output header", err);
        goto cleanup;
    }

    int64_t duration_ref = primary->duration > 0 ? primary->duration : 0;
    for (int i = 0; i < map_count; i++) {
        err = remux_all_packets(job, maps[i], output, progress_callback, context, duration_ref);
        if (err < 0) {
            err = set_error_av("failed to remux input", err);
            goto cleanup;
        }
    }

    err = av_write_trailer(output);
    if (err < 0) {
        err = set_error_av("failed to write trailer", err);
        goto cleanup;
    }
    err = 0;

cleanup:
    for (int i = 0; i < 3; i++) {
        free(maps[i].stream_map);
        maps[i].stream_map = NULL;
    }
    if (output != NULL) {
        if (!(output->oformat->flags & AVFMT_NOFILE) && output->pb != NULL) {
            avio_closep(&output->pb);
        }
        avformat_free_context(output);
    }
    if (subtitle != NULL) {
        avformat_close_input(&subtitle);
    }
    if (additional_audio != NULL) {
        avformat_close_input(&additional_audio);
    }
    if (primary != NULL) {
        avformat_close_input(&primary);
    }

    return err;
}
