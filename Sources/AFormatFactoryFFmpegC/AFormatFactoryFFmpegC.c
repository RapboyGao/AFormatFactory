#include "AFormatFactoryFFmpegC_Internal.h"

static _Thread_local char g_last_error[2048];

int set_errorf(const char *message) {
    if (message == NULL) {
        g_last_error[0] = '\0';
        return 0;
    }
    snprintf(g_last_error, sizeof(g_last_error), "%s", message);
    return -1;
}

int set_error_av(const char *prefix, int errnum) {
    char fferr[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_make_error_string(fferr, sizeof(fferr), errnum);

    char merged[2048] = {0};
    snprintf(merged, sizeof(merged), "%s: %s", prefix, fferr);
    return set_errorf(merged);
}

void clear_error(void) {
    g_last_error[0] = '\0';
}

char *dup_string(const char *value) {
    if (value == NULL) {
        return NULL;
    }
    size_t len = strlen(value);
    char *copy = (char *)malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value, len + 1);
    return copy;
}

bool str_eq(const char *lhs, const char *rhs) {
    return lhs != NULL && rhs != NULL && strcmp(lhs, rhs) == 0;
}

static bool starts_with(const char *value, const char *prefix) {
    if (value == NULL || prefix == NULL) {
        return false;
    }
    size_t prefix_len = strlen(prefix);
    return strncmp(value, prefix, prefix_len) == 0;
}

void free_options(AFFParsedOptions *opts) {
    if (opts == NULL) {
        return;
    }
    free(opts->audio_codec);
    free(opts->video_codec);
    free(opts->subtitle_codec);
    free(opts->video_preset);
    free(opts->video_profile);
    free(opts->video_level);
    free(opts->video_tune);
    free(opts->video_pix_fmt);
    free(opts->video_filter);
    free(opts->audio_filter);
    free(opts->output_format);
    av_dict_free(&opts->metadata);
    memset(opts, 0, sizeof(*opts));
}

void free_media_edit_config(AFFOpaqueJob *job) {
    if (job == NULL) {
        return;
    }
    free(job->additional_audio_input);
    free(job->subtitle_input);
    free(job->subtitle_codec);
    job->additional_audio_input = NULL;
    job->subtitle_input = NULL;
    job->subtitle_codec = NULL;
    av_dict_free(&job->media_edit_metadata);

    for (int i = 0; i < job->chapter_count; i++) {
        free(job->chapters[i].title);
    }
    free(job->chapters);
    job->chapters = NULL;
    job->chapter_count = 0;
    job->chapter_capacity = 0;
}

static int parse_int_k_suffix(const char *value) {
    if (value == NULL) {
        return 0;
    }
    char *endptr = NULL;
    long parsed = strtol(value, &endptr, 10);
    if (endptr != NULL && (*endptr == 'k' || *endptr == 'K')) {
        return (int)parsed * 1000;
    }
    return (int)parsed;
}

static double parse_time_seconds(const char *raw) {
    if (raw == NULL || raw[0] == '\0') {
        return 0;
    }

    if (strchr(raw, ':') == NULL) {
        return atof(raw);
    }

    int h = 0;
    int m = 0;
    double s = 0;
    if (sscanf(raw, "%d:%d:%lf", &h, &m, &s) == 3) {
        return (double)h * 3600.0 + (double)m * 60.0 + s;
    }
    return atof(raw);
}

static bool parse_dimensions(const char *raw, int *width, int *height) {
    if (raw == NULL || width == NULL || height == NULL) {
        return false;
    }
    int w = 0;
    int h = 0;
    if (sscanf(raw, "%dx%d", &w, &h) == 2 && w > 0 && h > 0) {
        *width = w;
        *height = h;
        return true;
    }
    return false;
}

static void parse_map_option(AFFParsedOptions *opts, const char *map_spec) {
    if (opts == NULL || map_spec == NULL) {
        return;
    }

    if (!opts->has_explicit_map) {
        opts->has_explicit_map = true;
        opts->map_video = false;
        opts->map_audio = false;
        opts->map_subtitle = false;
        opts->map_audio_index = -1;
    }

    if (starts_with(map_spec, "0:v")) {
        opts->map_video = true;
        return;
    }
    if (starts_with(map_spec, "0:a:")) {
        opts->map_audio = true;
        const char *index_raw = map_spec + 4;
        opts->map_audio_index = atoi(index_raw);
        return;
    }
    if (starts_with(map_spec, "0:a")) {
        opts->map_audio = true;
        return;
    }
    if (starts_with(map_spec, "0:s")) {
        opts->map_subtitle = true;
    }
}

static int parse_options(const AFFOpaqueJob *job, AFFParsedOptions *opts, AFFLogCallback log_callback, void *context) {
    memset(opts, 0, sizeof(*opts));
    opts->keep_metadata = true;
    opts->map_audio_index = -1;

    for (int i = 0; i < job->argument_count; i++) {
        const char *arg = job->arguments[i];
        if (arg == NULL) {
            continue;
        }

        if (str_eq(arg, "-map_metadata") && i + 1 < job->argument_count) {
            i += 1;
            if (str_eq(job->arguments[i], "-1")) {
                opts->keep_metadata = false;
            }
            continue;
        }

        if (str_eq(arg, "-metadata") && i + 1 < job->argument_count) {
            i += 1;
            const char *entry = job->arguments[i];
            const char *eq = strchr(entry, '=');
            if (eq != NULL) {
                size_t klen = (size_t)(eq - entry);
                char *key = (char *)malloc(klen + 1);
                if (key == NULL) {
                    return set_errorf("failed to allocate metadata key");
                }
                memcpy(key, entry, klen);
                key[klen] = '\0';
                const char *value = eq + 1;
                av_dict_set(&opts->metadata, key, value, 0);
                free(key);
            }
            continue;
        }

        if (str_eq(arg, "-vn")) { opts->disable_video = true; continue; }
        if (str_eq(arg, "-an")) { opts->disable_audio = true; continue; }
        if (str_eq(arg, "-sn")) { opts->disable_subtitle = true; continue; }

        if (str_eq(arg, "-c:a") && i + 1 < job->argument_count) {
            i += 1;
            free(opts->audio_codec);
            opts->audio_codec = dup_string(job->arguments[i]);
            opts->copy_audio = str_eq(opts->audio_codec, "copy");
            continue;
        }

        if (str_eq(arg, "-c:v") && i + 1 < job->argument_count) {
            i += 1;
            free(opts->video_codec);
            opts->video_codec = dup_string(job->arguments[i]);
            opts->copy_video = str_eq(opts->video_codec, "copy");
            continue;
        }

        if (str_eq(arg, "-c:s") && i + 1 < job->argument_count) {
            i += 1;
            free(opts->subtitle_codec);
            opts->subtitle_codec = dup_string(job->arguments[i]);
            opts->copy_subtitle = str_eq(opts->subtitle_codec, "copy") || str_eq(opts->subtitle_codec, "mov_text");
            continue;
        }
        if (str_eq(arg, "-map") && i + 1 < job->argument_count) {
            i += 1;
            parse_map_option(opts, job->arguments[i]);
            continue;
        }
        if (str_eq(arg, "-vf") && i + 1 < job->argument_count) {
            i += 1;
            free(opts->video_filter);
            opts->video_filter = dup_string(job->arguments[i]);
            continue;
        }
        if (str_eq(arg, "-af") && i + 1 < job->argument_count) {
            i += 1;
            free(opts->audio_filter);
            opts->audio_filter = dup_string(job->arguments[i]);
            continue;
        }

        if (str_eq(arg, "-b:a") && i + 1 < job->argument_count) { i += 1; opts->audio_bitrate = parse_int_k_suffix(job->arguments[i]); continue; }
        if (str_eq(arg, "-q:a") && i + 1 < job->argument_count) { i += 1; opts->audio_qscale = atof(job->arguments[i]); continue; }
        if (str_eq(arg, "-ar") && i + 1 < job->argument_count) { i += 1; opts->audio_sample_rate = atoi(job->arguments[i]); continue; }
        if (str_eq(arg, "-ac") && i + 1 < job->argument_count) { i += 1; opts->audio_channels = atoi(job->arguments[i]); continue; }
        if (str_eq(arg, "-threads") && i + 1 < job->argument_count) { i += 1; opts->thread_count = atoi(job->arguments[i]); continue; }
        if (str_eq(arg, "-b:v") && i + 1 < job->argument_count) { i += 1; opts->video_bitrate = parse_int_k_suffix(job->arguments[i]); opts->has_video_bitrate = true; continue; }
        if (str_eq(arg, "-q:v") && i + 1 < job->argument_count) { i += 1; opts->video_qscale = atof(job->arguments[i]); continue; }
        if (str_eq(arg, "-g") && i + 1 < job->argument_count) { i += 1; opts->video_gop = atoi(job->arguments[i]); continue; }
        if (str_eq(arg, "-maxrate") && i + 1 < job->argument_count) { i += 1; opts->video_maxrate = parse_int_k_suffix(job->arguments[i]); continue; }
        if (str_eq(arg, "-bufsize") && i + 1 < job->argument_count) { i += 1; opts->video_bufsize = parse_int_k_suffix(job->arguments[i]); continue; }
        if (str_eq(arg, "-r") && i + 1 < job->argument_count) { i += 1; opts->video_frame_rate = atof(job->arguments[i]); continue; }
        if (str_eq(arg, "-crf") && i + 1 < job->argument_count) { i += 1; opts->video_crf = atoi(job->arguments[i]); continue; }
        if (str_eq(arg, "-ss") && i + 1 < job->argument_count) { i += 1; opts->start_seconds = parse_time_seconds(job->arguments[i]); continue; }
        if (str_eq(arg, "-t") && i + 1 < job->argument_count) { i += 1; opts->duration_seconds = parse_time_seconds(job->arguments[i]); continue; }
        if (str_eq(arg, "-preset") && i + 1 < job->argument_count) { i += 1; free(opts->video_preset); opts->video_preset = dup_string(job->arguments[i]); continue; }
        if (str_eq(arg, "-profile:v") && i + 1 < job->argument_count) { i += 1; free(opts->video_profile); opts->video_profile = dup_string(job->arguments[i]); continue; }
        if (str_eq(arg, "-level:v") && i + 1 < job->argument_count) { i += 1; free(opts->video_level); opts->video_level = dup_string(job->arguments[i]); continue; }
        if (str_eq(arg, "-tune") && i + 1 < job->argument_count) { i += 1; free(opts->video_tune); opts->video_tune = dup_string(job->arguments[i]); continue; }
        if (str_eq(arg, "-pix_fmt") && i + 1 < job->argument_count) { i += 1; free(opts->video_pix_fmt); opts->video_pix_fmt = dup_string(job->arguments[i]); continue; }
        if (str_eq(arg, "-f") && i + 1 < job->argument_count) {
            i += 1;
            free(opts->output_format);
            opts->output_format = dup_string(job->arguments[i]);
            continue;
        }
        if (str_eq(arg, "-s") && i + 1 < job->argument_count) {
            i += 1;
            parse_dimensions(job->arguments[i], &opts->output_width, &opts->output_height);
            continue;
        }
        if (str_eq(arg, "-movflags") && i + 1 < job->argument_count) {
            i += 1;
            if (strstr(job->arguments[i], "faststart") != NULL) {
                opts->faststart = true;
            }
            continue;
        }

        if (arg[0] == '-' && log_callback != NULL) {
            char line[512] = {0};
            snprintf(line, sizeof(line), "[aff] ignore unsupported option: %s", arg);
            log_callback(1, line, context);
        }
    }

    if (opts->video_filter != NULL && opts->video_filter[0] != '\0') {
        opts->copy_video = false;
    }
    if (opts->audio_filter != NULL && opts->audio_filter[0] != '\0') {
        opts->copy_audio = false;
    }

    return 0;
}

static const AVCodec *find_audio_encoder(const AFFParsedOptions *opts, const AVOutputFormat *ofmt) {
    if (opts->audio_codec != NULL && !opts->copy_audio) {
        const AVCodec *codec = avcodec_find_encoder_by_name(opts->audio_codec);
        if (codec != NULL) {
            return codec;
        }
    }

    enum AVCodecID codec_id = ofmt->audio_codec;
    if (codec_id == AV_CODEC_ID_NONE) {
        codec_id = AV_CODEC_ID_AAC;
    }
    return avcodec_find_encoder(codec_id);
}

static int choose_sample_rate(const AVCodec *encoder, int requested, int fallback) {
    if (requested > 0) {
        return requested;
    }
    if (fallback > 0) {
        return fallback;
    }

    if (encoder->supported_samplerates == NULL) {
        return 44100;
    }
    return encoder->supported_samplerates[0];
}

static enum AVSampleFormat choose_sample_fmt(const AVCodec *encoder, enum AVSampleFormat fallback) {
    if (encoder->sample_fmts == NULL) {
        return fallback != AV_SAMPLE_FMT_NONE ? fallback : AV_SAMPLE_FMT_FLTP;
    }

    for (const enum AVSampleFormat *fmt = encoder->sample_fmts; *fmt != AV_SAMPLE_FMT_NONE; fmt++) {
        if (*fmt == fallback) {
            return *fmt;
        }
    }
    return encoder->sample_fmts[0];
}

static int configure_audio_encoder(
    AFFAudioTranscoder *audio,
    AVFormatContext *output_ctx,
    AVStream *input_stream,
    AVStream *output_stream,
    const AFFParsedOptions *opts
) {
    int err = 0;

    const AVCodec *decoder = avcodec_find_decoder(input_stream->codecpar->codec_id);
    if (decoder == NULL) {
        return set_errorf("audio decoder not found");
    }

    audio->dec_ctx = avcodec_alloc_context3(decoder);
    if (audio->dec_ctx == NULL) {
        return set_errorf("failed to allocate audio decoder context");
    }

    err = avcodec_parameters_to_context(audio->dec_ctx, input_stream->codecpar);
    if (err < 0) {
        return set_error_av("failed to copy decoder parameters", err);
    }

    err = avcodec_open2(audio->dec_ctx, decoder, NULL);
    if (err < 0) {
        return set_error_av("failed to open audio decoder", err);
    }

    const AVCodec *encoder = find_audio_encoder(opts, output_ctx->oformat);
    if (encoder == NULL) {
        return set_errorf("audio encoder not found");
    }

    audio->enc_ctx = avcodec_alloc_context3(encoder);
    if (audio->enc_ctx == NULL) {
        return set_errorf("failed to allocate audio encoder context");
    }

    audio->enc_ctx->sample_rate = choose_sample_rate(encoder, opts->audio_sample_rate, audio->dec_ctx->sample_rate);
    av_channel_layout_default(&audio->enc_ctx->ch_layout, opts->audio_channels > 0 ? opts->audio_channels : (audio->dec_ctx->ch_layout.nb_channels > 0 ? audio->dec_ctx->ch_layout.nb_channels : 2));
    audio->enc_ctx->sample_fmt = choose_sample_fmt(encoder, audio->dec_ctx->sample_fmt);
    audio->enc_ctx->bit_rate = opts->audio_bitrate > 0 ? opts->audio_bitrate : 192000;
    audio->enc_ctx->time_base = (AVRational){1, audio->enc_ctx->sample_rate};
    if (opts->audio_qscale > 0) {
        audio->enc_ctx->flags |= AV_CODEC_FLAG_QSCALE;
        audio->enc_ctx->global_quality = (int)lrint(opts->audio_qscale * FF_QP2LAMBDA);
    }
    if (opts->thread_count > 0) {
        audio->enc_ctx->thread_count = opts->thread_count;
    }

    if (output_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
        audio->enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    err = avcodec_open2(audio->enc_ctx, encoder, NULL);
    if (err < 0) {
        return set_error_av("failed to open audio encoder", err);
    }

    err = avcodec_parameters_from_context(output_stream->codecpar, audio->enc_ctx);
    if (err < 0) {
        return set_error_av("failed to export encoder parameters", err);
    }

    output_stream->time_base = audio->enc_ctx->time_base;
    audio->in_time_base = input_stream->time_base;

    if (audio->dec_ctx->sample_fmt != audio->enc_ctx->sample_fmt ||
        audio->dec_ctx->sample_rate != audio->enc_ctx->sample_rate ||
        av_channel_layout_compare(&audio->dec_ctx->ch_layout, &audio->enc_ctx->ch_layout) != 0)
    {
        err = swr_alloc_set_opts2(
            &audio->swr,
            &audio->enc_ctx->ch_layout,
            audio->enc_ctx->sample_fmt,
            audio->enc_ctx->sample_rate,
            &audio->dec_ctx->ch_layout,
            audio->dec_ctx->sample_fmt,
            audio->dec_ctx->sample_rate,
            0,
            NULL
        );
        if (err < 0) {
            return set_error_av("failed to allocate swr", err);
        }
        err = swr_init(audio->swr);
        if (err < 0) {
            return set_error_av("failed to init swr", err);
        }
    }

    return 0;
}

static const AVCodec *find_video_encoder(const AFFParsedOptions *opts, const AVOutputFormat *ofmt) {
    if (opts->video_codec != NULL && !opts->copy_video) {
        const AVCodec *codec = avcodec_find_encoder_by_name(opts->video_codec);
        if (codec != NULL) {
            return codec;
        }
    }

    enum AVCodecID codec_id = ofmt->video_codec;
    if (codec_id == AV_CODEC_ID_NONE) {
        codec_id = AV_CODEC_ID_H264;
    }
    return avcodec_find_encoder(codec_id);
}

static enum AVPixelFormat choose_pixel_format(const AVCodec *encoder, enum AVPixelFormat fallback, const char *requested_name) {
    enum AVPixelFormat requested = AV_PIX_FMT_NONE;
    if (requested_name != NULL && requested_name[0] != '\0') {
        requested = av_get_pix_fmt(requested_name);
    }

    if (encoder->pix_fmts == NULL) {
        if (requested != AV_PIX_FMT_NONE) {
            return requested;
        }
        return fallback != AV_PIX_FMT_NONE ? fallback : AV_PIX_FMT_YUV420P;
    }

    if (requested != AV_PIX_FMT_NONE) {
        for (const enum AVPixelFormat *fmt = encoder->pix_fmts; *fmt != AV_PIX_FMT_NONE; fmt++) {
            if (*fmt == requested) {
                return *fmt;
            }
        }
    }

    for (const enum AVPixelFormat *fmt = encoder->pix_fmts; *fmt != AV_PIX_FMT_NONE; fmt++) {
        if (*fmt == fallback) {
            return *fmt;
        }
    }
    return encoder->pix_fmts[0];
}

static int configure_video_encoder(
    AFFVideoTranscoder *video,
    AVFormatContext *input_ctx,
    AVFormatContext *output_ctx,
    AVStream *input_stream,
    AVStream *output_stream,
    const AFFParsedOptions *opts
) {
    int err = 0;

    const AVCodec *decoder = avcodec_find_decoder(input_stream->codecpar->codec_id);
    if (decoder == NULL) {
        return set_errorf("video decoder not found");
    }

    video->dec_ctx = avcodec_alloc_context3(decoder);
    if (video->dec_ctx == NULL) {
        return set_errorf("failed to allocate video decoder context");
    }
    err = avcodec_parameters_to_context(video->dec_ctx, input_stream->codecpar);
    if (err < 0) {
        return set_error_av("failed to copy video decoder parameters", err);
    }
    err = avcodec_open2(video->dec_ctx, decoder, NULL);
    if (err < 0) {
        return set_error_av("failed to open video decoder", err);
    }

    const AVCodec *encoder = find_video_encoder(opts, output_ctx->oformat);
    if (encoder == NULL) {
        return set_errorf("video encoder not found");
    }

    video->enc_ctx = avcodec_alloc_context3(encoder);
    if (video->enc_ctx == NULL) {
        return set_errorf("failed to allocate video encoder context");
    }

    AVRational guessed_rate = av_guess_frame_rate(input_ctx, input_stream, NULL);
    if (guessed_rate.num <= 0 || guessed_rate.den <= 0) {
        guessed_rate = (AVRational){30, 1};
    }
    if (opts->video_frame_rate > 0) {
        guessed_rate = av_d2q(opts->video_frame_rate, 100000);
    }

    int source_width = input_stream->codecpar->width > 0 ? input_stream->codecpar->width : video->dec_ctx->width;
    int source_height = input_stream->codecpar->height > 0 ? input_stream->codecpar->height : video->dec_ctx->height;
    video->enc_ctx->width = opts->output_width > 0 ? opts->output_width : source_width;
    video->enc_ctx->height = opts->output_height > 0 ? opts->output_height : source_height;
    if (video->enc_ctx->width <= 0 || video->enc_ctx->height <= 0) {
        return set_errorf("invalid video dimensions");
    }

    video->enc_ctx->pix_fmt = choose_pixel_format(encoder, video->dec_ctx->pix_fmt, opts->video_pix_fmt);
    video->enc_ctx->time_base = av_inv_q(guessed_rate);
    video->enc_ctx->framerate = guessed_rate;
    if (opts->has_video_bitrate) {
        video->enc_ctx->bit_rate = opts->video_bitrate;
    } else {
        video->enc_ctx->bit_rate = input_stream->codecpar->bit_rate > 0 ? input_stream->codecpar->bit_rate : 2500000;
    }
    video->enc_ctx->gop_size = opts->video_gop > 0 ? opts->video_gop : 0;
    video->enc_ctx->sample_aspect_ratio = input_stream->sample_aspect_ratio.num > 0 ? input_stream->sample_aspect_ratio : video->dec_ctx->sample_aspect_ratio;
    if (opts->thread_count > 0) {
        video->enc_ctx->thread_count = opts->thread_count;
    }
    if (opts->video_qscale > 0) {
        video->enc_ctx->flags |= AV_CODEC_FLAG_QSCALE;
        video->enc_ctx->global_quality = (int)lrint(opts->video_qscale * FF_QP2LAMBDA);
    }

    if (output_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
        video->enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }

    AVDictionary *encoder_opts = NULL;
    if (opts->video_preset != NULL) av_dict_set(&encoder_opts, "preset", opts->video_preset, 0);
    if (opts->video_profile != NULL) av_dict_set(&encoder_opts, "profile", opts->video_profile, 0);
    if (opts->video_tune != NULL) av_dict_set(&encoder_opts, "tune", opts->video_tune, 0);
    if (opts->video_level != NULL) av_dict_set(&encoder_opts, "level", opts->video_level, 0);
    if (opts->video_crf > 0) {
        char crf_buf[16] = {0};
        snprintf(crf_buf, sizeof(crf_buf), "%d", opts->video_crf);
        av_dict_set(&encoder_opts, "crf", crf_buf, 0);
    }
    if (opts->video_maxrate > 0) {
        char maxrate_buf[32] = {0};
        snprintf(maxrate_buf, sizeof(maxrate_buf), "%d", opts->video_maxrate);
        av_dict_set(&encoder_opts, "maxrate", maxrate_buf, 0);
    }
    if (opts->video_bufsize > 0) {
        char bufsize_buf[32] = {0};
        snprintf(bufsize_buf, sizeof(bufsize_buf), "%d", opts->video_bufsize);
        av_dict_set(&encoder_opts, "bufsize", bufsize_buf, 0);
    }

    err = avcodec_open2(video->enc_ctx, encoder, &encoder_opts);
    av_dict_free(&encoder_opts);
    if (err < 0) {
        return set_error_av("failed to open video encoder", err);
    }

    err = avcodec_parameters_from_context(output_stream->codecpar, video->enc_ctx);
    if (err < 0) {
        return set_error_av("failed to export video encoder parameters", err);
    }

    output_stream->time_base = video->enc_ctx->time_base;
    output_stream->avg_frame_rate = video->enc_ctx->framerate;
    video->in_time_base = input_stream->time_base;
    video->out_time_base = output_stream->time_base;

    if (video->dec_ctx->pix_fmt != video->enc_ctx->pix_fmt ||
        video->dec_ctx->width != video->enc_ctx->width ||
        video->dec_ctx->height != video->enc_ctx->height)
    {
        video->sws = sws_getContext(
            video->dec_ctx->width,
            video->dec_ctx->height,
            video->dec_ctx->pix_fmt,
            video->enc_ctx->width,
            video->enc_ctx->height,
            video->enc_ctx->pix_fmt,
            SWS_BICUBIC,
            NULL,
            NULL,
            NULL
        );
        if (video->sws == NULL) {
            return set_errorf("failed to create swscale context");
        }

        video->scaled_frame = av_frame_alloc();
        if (video->scaled_frame == NULL) {
            return set_errorf("failed to allocate scaled frame");
        }
        video->scaled_frame->format = video->enc_ctx->pix_fmt;
        video->scaled_frame->width = video->enc_ctx->width;
        video->scaled_frame->height = video->enc_ctx->height;
        err = av_frame_get_buffer(video->scaled_frame, 0);
        if (err < 0) {
            return set_error_av("failed to allocate scaled frame buffer", err);
        }
    }

    return 0;
}

static int configure_video_filter_graph(AFFVideoTranscoder *video, AVStream *input_stream, const AFFParsedOptions *opts) {
    if (opts->video_filter == NULL || opts->video_filter[0] == '\0') {
        return 0;
    }

    int err = 0;
    char args[512] = {0};
    const AVFilter *buffersrc = avfilter_get_by_name("buffer");
    const AVFilter *buffersink = avfilter_get_by_name("buffersink");
    if (buffersrc == NULL || buffersink == NULL) {
        return set_errorf("video filters are not available");
    }

    video->filter_graph = avfilter_graph_alloc();
    if (video->filter_graph == NULL) {
        return set_errorf("failed to allocate video filter graph");
    }

    AVRational source_time_base = input_stream->time_base.num > 0 ? input_stream->time_base : video->dec_ctx->time_base;
    if (source_time_base.num <= 0 || source_time_base.den <= 0) {
        source_time_base = (AVRational){1, 1000};
    }

    AVRational sample_aspect_ratio = video->dec_ctx->sample_aspect_ratio.num > 0
        ? video->dec_ctx->sample_aspect_ratio
        : (AVRational){1, 1};
    AVRational frame_rate = video->enc_ctx->framerate.num > 0
        ? video->enc_ctx->framerate
        : (AVRational){30, 1};

    snprintf(
        args,
        sizeof(args),
        "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d:frame_rate=%d/%d",
        video->dec_ctx->width,
        video->dec_ctx->height,
        video->dec_ctx->pix_fmt,
        source_time_base.num,
        source_time_base.den,
        sample_aspect_ratio.num,
        sample_aspect_ratio.den,
        frame_rate.num,
        frame_rate.den
    );

    err = avfilter_graph_create_filter(
        &video->buffersrc_ctx,
        buffersrc,
        "in",
        args,
        NULL,
        video->filter_graph
    );
    if (err < 0) {
        return set_error_av("failed to create video buffer source", err);
    }

    err = avfilter_graph_create_filter(
        &video->buffersink_ctx,
        buffersink,
        "out",
        NULL,
        NULL,
        video->filter_graph
    );
    if (err < 0) {
        return set_error_av("failed to create video buffer sink", err);
    }

    enum AVPixelFormat out_pix_fmts[] = { video->enc_ctx->pix_fmt, AV_PIX_FMT_NONE };
    err = av_opt_set_int_list(video->buffersink_ctx, "pix_fmts", out_pix_fmts, AV_PIX_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if (err < 0) {
        return set_error_av("failed to configure video filter sink format", err);
    }

    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs = avfilter_inout_alloc();
    if (outputs == NULL || inputs == NULL) {
        avfilter_inout_free(&outputs);
        avfilter_inout_free(&inputs);
        return set_errorf("failed to allocate video filter endpoints");
    }

    outputs->name = av_strdup("in");
    outputs->filter_ctx = video->buffersrc_ctx;
    outputs->pad_idx = 0;
    outputs->next = NULL;

    inputs->name = av_strdup("out");
    inputs->filter_ctx = video->buffersink_ctx;
    inputs->pad_idx = 0;
    inputs->next = NULL;

    err = avfilter_graph_parse_ptr(video->filter_graph, opts->video_filter, &inputs, &outputs, NULL);
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    if (err < 0) {
        return set_error_av("failed to parse -vf filter graph", err);
    }

    err = avfilter_graph_config(video->filter_graph, NULL);
    if (err < 0) {
        return set_error_av("failed to configure -vf filter graph", err);
    }

    video->filter_sink_time_base = av_buffersink_get_time_base(video->buffersink_ctx);
    if (video->filter_sink_time_base.num <= 0 || video->filter_sink_time_base.den <= 0) {
        video->filter_sink_time_base = source_time_base;
    }
    return 0;
}

static int configure_audio_filter_graph(AFFAudioTranscoder *audio, AVStream *input_stream, const AFFParsedOptions *opts) {
    if (opts->audio_filter == NULL || opts->audio_filter[0] == '\0') {
        return 0;
    }

    int err = 0;
    char args[512] = {0};
    const AVFilter *abuffersrc = avfilter_get_by_name("abuffer");
    const AVFilter *abuffersink = avfilter_get_by_name("abuffersink");
    if (abuffersrc == NULL || abuffersink == NULL) {
        return set_errorf("audio filters are not available");
    }

    audio->filter_graph = avfilter_graph_alloc();
    if (audio->filter_graph == NULL) {
        return set_errorf("failed to allocate audio filter graph");
    }

    AVRational source_time_base = input_stream->time_base.num > 0 ? input_stream->time_base : audio->dec_ctx->time_base;
    if (source_time_base.num <= 0 || source_time_base.den <= 0) {
        source_time_base = (AVRational){1, audio->dec_ctx->sample_rate > 0 ? audio->dec_ctx->sample_rate : 44100};
    }

    char channel_layout_desc[128] = {0};
    if (av_channel_layout_describe(&audio->dec_ctx->ch_layout, channel_layout_desc, sizeof(channel_layout_desc)) < 0) {
        snprintf(channel_layout_desc, sizeof(channel_layout_desc), "stereo");
    }

    const char *sample_fmt_name = av_get_sample_fmt_name(audio->dec_ctx->sample_fmt);
    if (sample_fmt_name == NULL) {
        sample_fmt_name = "fltp";
    }

    snprintf(
        args,
        sizeof(args),
        "time_base=%d/%d:sample_rate=%d:sample_fmt=%s:channel_layout=%s",
        source_time_base.num,
        source_time_base.den,
        audio->dec_ctx->sample_rate,
        sample_fmt_name,
        channel_layout_desc
    );

    err = avfilter_graph_create_filter(
        &audio->buffersrc_ctx,
        abuffersrc,
        "in",
        args,
        NULL,
        audio->filter_graph
    );
    if (err < 0) {
        return set_error_av("failed to create audio buffer source", err);
    }

    err = avfilter_graph_create_filter(
        &audio->buffersink_ctx,
        abuffersink,
        "out",
        NULL,
        NULL,
        audio->filter_graph
    );
    if (err < 0) {
        return set_error_av("failed to create audio buffer sink", err);
    }

    enum AVSampleFormat out_sample_fmts[] = { audio->enc_ctx->sample_fmt, AV_SAMPLE_FMT_NONE };
    int out_sample_rates[] = { audio->enc_ctx->sample_rate, -1 };
    char out_ch_layout_desc[128] = {0};
    if (av_channel_layout_describe(&audio->enc_ctx->ch_layout, out_ch_layout_desc, sizeof(out_ch_layout_desc)) < 0) {
        snprintf(out_ch_layout_desc, sizeof(out_ch_layout_desc), "stereo");
    }

    err = av_opt_set_int_list(audio->buffersink_ctx, "sample_fmts", out_sample_fmts, AV_SAMPLE_FMT_NONE, AV_OPT_SEARCH_CHILDREN);
    if (err < 0) {
        return set_error_av("failed to configure audio filter sink sample format", err);
    }
    err = av_opt_set_int_list(audio->buffersink_ctx, "sample_rates", out_sample_rates, -1, AV_OPT_SEARCH_CHILDREN);
    if (err < 0) {
        return set_error_av("failed to configure audio filter sink sample rate", err);
    }
    err = av_opt_set(audio->buffersink_ctx, "ch_layouts", out_ch_layout_desc, AV_OPT_SEARCH_CHILDREN);
    if (err < 0) {
        return set_error_av("failed to configure audio filter sink channel layout", err);
    }

    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *inputs = avfilter_inout_alloc();
    if (outputs == NULL || inputs == NULL) {
        avfilter_inout_free(&outputs);
        avfilter_inout_free(&inputs);
        return set_errorf("failed to allocate audio filter endpoints");
    }

    outputs->name = av_strdup("in");
    outputs->filter_ctx = audio->buffersrc_ctx;
    outputs->pad_idx = 0;
    outputs->next = NULL;

    inputs->name = av_strdup("out");
    inputs->filter_ctx = audio->buffersink_ctx;
    inputs->pad_idx = 0;
    inputs->next = NULL;

    err = avfilter_graph_parse_ptr(audio->filter_graph, opts->audio_filter, &inputs, &outputs, NULL);
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    if (err < 0) {
        return set_error_av("failed to parse -af filter graph", err);
    }

    err = avfilter_graph_config(audio->filter_graph, NULL);
    if (err < 0) {
        return set_error_av("failed to configure -af filter graph", err);
    }

    audio->filter_sink_time_base = av_buffersink_get_time_base(audio->buffersink_ctx);
    if (audio->filter_sink_time_base.num <= 0 || audio->filter_sink_time_base.den <= 0) {
        audio->filter_sink_time_base = source_time_base;
    }

    return 0;
}

int copy_packet(AVFormatContext *out_ctx, AVPacket *packet, AVStream *in_stream, AVStream *out_stream) {
    av_packet_rescale_ts(packet, in_stream->time_base, out_stream->time_base);
    packet->stream_index = out_stream->index;
    return av_interleaved_write_frame(out_ctx, packet);
}

static int write_audio_frame(AFFAudioTranscoder *audio, AVFormatContext *out_ctx, AVFrame *frame) {
    int err = avcodec_send_frame(audio->enc_ctx, frame);
    if (err < 0) {
        return err;
    }

    AVPacket *enc_pkt = av_packet_alloc();
    if (enc_pkt == NULL) {
        return AVERROR(ENOMEM);
    }

    while ((err = avcodec_receive_packet(audio->enc_ctx, enc_pkt)) >= 0) {
        av_packet_rescale_ts(enc_pkt, audio->enc_ctx->time_base, out_ctx->streams[audio->out_stream_index]->time_base);
        enc_pkt->stream_index = audio->out_stream_index;
        err = av_interleaved_write_frame(out_ctx, enc_pkt);
        av_packet_unref(enc_pkt);
        if (err < 0) {
            av_packet_free(&enc_pkt);
            return err;
        }
    }

    av_packet_free(&enc_pkt);
    if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
        return 0;
    }
    return err;
}

static int write_video_frame(AFFVideoTranscoder *video, AVFormatContext *out_ctx, AVFrame *frame) {
    int err = avcodec_send_frame(video->enc_ctx, frame);
    if (err < 0) {
        return err;
    }

    AVPacket *enc_pkt = av_packet_alloc();
    if (enc_pkt == NULL) {
        return AVERROR(ENOMEM);
    }

    while ((err = avcodec_receive_packet(video->enc_ctx, enc_pkt)) >= 0) {
        av_packet_rescale_ts(enc_pkt, video->enc_ctx->time_base, out_ctx->streams[video->out_stream_index]->time_base);
        enc_pkt->stream_index = video->out_stream_index;
        err = av_interleaved_write_frame(out_ctx, enc_pkt);
        av_packet_unref(enc_pkt);
        if (err < 0) {
            av_packet_free(&enc_pkt);
            return err;
        }
    }

    av_packet_free(&enc_pkt);
    if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
        return 0;
    }
    return err;
}

static int64_t normalize_video_pts(AFFVideoTranscoder *video, int64_t candidate) {
    if (candidate == AV_NOPTS_VALUE) {
        candidate = video->next_pts;
    }
    if (candidate < video->next_pts) {
        candidate = video->next_pts;
    }
    video->next_pts = candidate + 1;
    return candidate;
}

static int transcode_audio_packet(AFFAudioTranscoder *audio, AVPacket *packet, AVFormatContext *out_ctx) {
    int err = avcodec_send_packet(audio->dec_ctx, packet);
    if (err < 0) {
        return err;
    }

    AVFrame *decoded = av_frame_alloc();
    AVFrame *converted = av_frame_alloc();
    if (decoded == NULL || converted == NULL) {
        av_frame_free(&decoded);
        av_frame_free(&converted);
        return AVERROR(ENOMEM);
    }

    while ((err = avcodec_receive_frame(audio->dec_ctx, decoded)) >= 0) {
        if (audio->filter_graph != NULL) {
            int64_t source_pts = decoded->best_effort_timestamp;
            if (source_pts == AV_NOPTS_VALUE) {
                source_pts = decoded->pts;
            }
            if (source_pts == AV_NOPTS_VALUE) {
                source_pts = audio->next_pts;
            } else {
                source_pts = av_rescale_q(source_pts, audio->in_time_base, audio->filter_sink_time_base);
            }
            decoded->pts = source_pts;

            err = av_buffersrc_add_frame_flags(audio->buffersrc_ctx, decoded, AV_BUFFERSRC_FLAG_KEEP_REF);
            av_frame_unref(decoded);
            if (err < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return err;
            }

            while ((err = av_buffersink_get_frame(audio->buffersink_ctx, converted)) >= 0) {
                if (converted->pts == AV_NOPTS_VALUE) {
                    converted->pts = audio->next_pts;
                }
                if (audio->filter_sink_time_base.num > 0 && audio->filter_sink_time_base.den > 0) {
                    converted->pts = av_rescale_q(converted->pts, audio->filter_sink_time_base, audio->enc_ctx->time_base);
                }
                audio->next_pts = converted->pts + converted->nb_samples;

                int write_err = write_audio_frame(audio, out_ctx, converted);
                av_frame_unref(converted);
                if (write_err < 0) {
                    av_frame_free(&decoded);
                    av_frame_free(&converted);
                    return write_err;
                }
            }
            if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
                err = 0;
            }
            if (err < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return err;
            }
            continue;
        }

        AVFrame *output = decoded;
        if (audio->swr != NULL) {
            converted->sample_rate = audio->enc_ctx->sample_rate;
            converted->format = audio->enc_ctx->sample_fmt;
            converted->ch_layout = audio->enc_ctx->ch_layout;
            converted->nb_samples = av_rescale_rnd(
                swr_get_delay(audio->swr, audio->dec_ctx->sample_rate) + decoded->nb_samples,
                audio->enc_ctx->sample_rate,
                audio->dec_ctx->sample_rate,
                AV_ROUND_UP
            );
            int alloc_err = av_frame_get_buffer(converted, 0);
            if (alloc_err < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return alloc_err;
            }
            int sample_count = swr_convert(
                audio->swr,
                converted->data,
                converted->nb_samples,
                (const uint8_t **)decoded->data,
                decoded->nb_samples
            );
            if (sample_count < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return sample_count;
            }
            converted->nb_samples = sample_count;
            output = converted;
        }
        output->pts = audio->next_pts;
        audio->next_pts += output->nb_samples;

        err = write_audio_frame(audio, out_ctx, output);
        av_frame_unref(decoded);
        av_frame_unref(converted);
        if (err < 0) {
            av_frame_free(&decoded);
            av_frame_free(&converted);
            return err;
        }
    }

    av_frame_free(&decoded);
    av_frame_free(&converted);

    if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
        return 0;
    }
    return err;
}

static int flush_audio(AFFAudioTranscoder *audio, AVFormatContext *out_ctx) {
    int err = avcodec_send_packet(audio->dec_ctx, NULL);
    if (err < 0) {
        return err;
    }

    AVFrame *decoded = av_frame_alloc();
    AVFrame *converted = av_frame_alloc();
    if (decoded == NULL || converted == NULL) {
        av_frame_free(&decoded);
        av_frame_free(&converted);
        return AVERROR(ENOMEM);
    }

    while ((err = avcodec_receive_frame(audio->dec_ctx, decoded)) >= 0) {
        if (audio->filter_graph != NULL) {
            int64_t source_pts = decoded->best_effort_timestamp;
            if (source_pts == AV_NOPTS_VALUE) source_pts = decoded->pts;
            if (source_pts == AV_NOPTS_VALUE) source_pts = audio->next_pts;
            else source_pts = av_rescale_q(source_pts, audio->in_time_base, audio->filter_sink_time_base);
            decoded->pts = source_pts;

            err = av_buffersrc_add_frame_flags(audio->buffersrc_ctx, decoded, AV_BUFFERSRC_FLAG_KEEP_REF);
            av_frame_unref(decoded);
            if (err < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return err;
            }

            while ((err = av_buffersink_get_frame(audio->buffersink_ctx, converted)) >= 0) {
                if (converted->pts == AV_NOPTS_VALUE) converted->pts = audio->next_pts;
                if (audio->filter_sink_time_base.num > 0 && audio->filter_sink_time_base.den > 0) {
                    converted->pts = av_rescale_q(converted->pts, audio->filter_sink_time_base, audio->enc_ctx->time_base);
                }
                audio->next_pts = converted->pts + converted->nb_samples;
                int write_err = write_audio_frame(audio, out_ctx, converted);
                av_frame_unref(converted);
                if (write_err < 0) {
                    av_frame_free(&decoded);
                    av_frame_free(&converted);
                    return write_err;
                }
            }
            if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
                err = 0;
            }
            if (err < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return err;
            }
            continue;
        }

        AVFrame *output = decoded;
        if (audio->swr != NULL) {
            converted->sample_rate = audio->enc_ctx->sample_rate;
            converted->format = audio->enc_ctx->sample_fmt;
            converted->ch_layout = audio->enc_ctx->ch_layout;
            converted->nb_samples = av_rescale_rnd(
                swr_get_delay(audio->swr, audio->dec_ctx->sample_rate) + decoded->nb_samples,
                audio->enc_ctx->sample_rate,
                audio->dec_ctx->sample_rate,
                AV_ROUND_UP
            );
            int alloc_err = av_frame_get_buffer(converted, 0);
            if (alloc_err < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return alloc_err;
            }
            int sample_count = swr_convert(
                audio->swr,
                converted->data,
                converted->nb_samples,
                (const uint8_t **)decoded->data,
                decoded->nb_samples
            );
            if (sample_count < 0) {
                av_frame_free(&decoded);
                av_frame_free(&converted);
                return sample_count;
            }
            converted->nb_samples = sample_count;
            output = converted;
        }
        output->pts = audio->next_pts;
        audio->next_pts += output->nb_samples;
        err = write_audio_frame(audio, out_ctx, output);
        av_frame_unref(decoded);
        av_frame_unref(converted);
        if (err < 0) {
            av_frame_free(&decoded);
            av_frame_free(&converted);
            return err;
        }
    }
    av_frame_free(&decoded);
    av_frame_free(&converted);

    if (audio->filter_graph != NULL) {
        err = av_buffersrc_add_frame_flags(audio->buffersrc_ctx, NULL, 0);
        if (err < 0 && err != AVERROR_EOF) {
            return err;
        }
        AVFrame *filtered = av_frame_alloc();
        if (filtered == NULL) {
            return AVERROR(ENOMEM);
        }
        while ((err = av_buffersink_get_frame(audio->buffersink_ctx, filtered)) >= 0) {
            if (filtered->pts == AV_NOPTS_VALUE) filtered->pts = audio->next_pts;
            if (audio->filter_sink_time_base.num > 0 && audio->filter_sink_time_base.den > 0) {
                filtered->pts = av_rescale_q(filtered->pts, audio->filter_sink_time_base, audio->enc_ctx->time_base);
            }
            audio->next_pts = filtered->pts + filtered->nb_samples;
            int write_err = write_audio_frame(audio, out_ctx, filtered);
            av_frame_unref(filtered);
            if (write_err < 0) {
                av_frame_free(&filtered);
                return write_err;
            }
        }
        av_frame_free(&filtered);
        if (err != AVERROR(EAGAIN) && err != AVERROR_EOF && err < 0) {
            return err;
        }
    }

    err = write_audio_frame(audio, out_ctx, NULL);
    if (err < 0) {
        return err;
    }

    return 0;
}

static int transcode_video_packet(AFFVideoTranscoder *video, AVPacket *packet, AVFormatContext *out_ctx) {
    int err = avcodec_send_packet(video->dec_ctx, packet);
    if (err < 0) {
        return err;
    }

    AVFrame *decoded = av_frame_alloc();
    if (decoded == NULL) {
        return AVERROR(ENOMEM);
    }

    while ((err = avcodec_receive_frame(video->dec_ctx, decoded)) >= 0) {
        AVFrame *output = decoded;

        if (video->sws != NULL && video->scaled_frame != NULL) {
            int writable_err = av_frame_make_writable(video->scaled_frame);
            if (writable_err < 0) {
                av_frame_free(&decoded);
                return writable_err;
            }
            sws_scale(
                video->sws,
                (const uint8_t *const *)decoded->data,
                decoded->linesize,
                0,
                video->dec_ctx->height,
                video->scaled_frame->data,
                video->scaled_frame->linesize
            );
            output = video->scaled_frame;
        }

        int64_t source_pts = decoded->best_effort_timestamp;
        if (source_pts == AV_NOPTS_VALUE) {
            source_pts = decoded->pts;
        }
        if (source_pts != AV_NOPTS_VALUE) {
            source_pts = av_rescale_q(source_pts, video->in_time_base, video->enc_ctx->time_base);
        }
        if (source_pts < 0) {
            source_pts = AV_NOPTS_VALUE;
        }
        source_pts = normalize_video_pts(video, source_pts);

        output->pts = source_pts;

        if (video->filter_graph != NULL) {
            err = av_buffersrc_add_frame_flags(video->buffersrc_ctx, output, AV_BUFFERSRC_FLAG_KEEP_REF);
            av_frame_unref(decoded);
            if (err < 0) {
                av_frame_free(&decoded);
                return err;
            }

            AVFrame *filtered = av_frame_alloc();
            if (filtered == NULL) {
                av_frame_free(&decoded);
                return AVERROR(ENOMEM);
            }
            while ((err = av_buffersink_get_frame(video->buffersink_ctx, filtered)) >= 0) {
                if (filtered->pts == AV_NOPTS_VALUE) filtered->pts = AV_NOPTS_VALUE;
                if (filtered->pts != AV_NOPTS_VALUE && video->filter_sink_time_base.num > 0 && video->filter_sink_time_base.den > 0) {
                    filtered->pts = av_rescale_q(filtered->pts, video->filter_sink_time_base, video->enc_ctx->time_base);
                }
                filtered->pts = normalize_video_pts(video, filtered->pts);
                int write_err = write_video_frame(video, out_ctx, filtered);
                av_frame_unref(filtered);
                if (write_err < 0) {
                    av_frame_free(&filtered);
                    av_frame_free(&decoded);
                    return write_err;
                }
            }
            av_frame_free(&filtered);
            if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
                err = 0;
            }
            if (err < 0) {
                av_frame_free(&decoded);
                return err;
            }
            continue;
        }

        err = write_video_frame(video, out_ctx, output);
        av_frame_unref(decoded);
        if (err < 0) {
            av_frame_free(&decoded);
            return err;
        }
    }

    av_frame_free(&decoded);
    if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
        return 0;
    }
    return err;
}

static int flush_video(AFFVideoTranscoder *video, AVFormatContext *out_ctx) {
    int err = avcodec_send_packet(video->dec_ctx, NULL);
    if (err < 0) {
        return err;
    }

    AVFrame *decoded = av_frame_alloc();
    if (decoded == NULL) {
        return AVERROR(ENOMEM);
    }
    while ((err = avcodec_receive_frame(video->dec_ctx, decoded)) >= 0) {
        AVFrame *output = decoded;
        if (video->sws != NULL && video->scaled_frame != NULL) {
            int writable_err = av_frame_make_writable(video->scaled_frame);
            if (writable_err < 0) {
                av_frame_free(&decoded);
                return writable_err;
            }
            sws_scale(
                video->sws,
                (const uint8_t *const *)decoded->data,
                decoded->linesize,
                0,
                video->dec_ctx->height,
                video->scaled_frame->data,
                video->scaled_frame->linesize
            );
            output = video->scaled_frame;
        }

        int64_t source_pts = decoded->best_effort_timestamp;
        if (source_pts == AV_NOPTS_VALUE) source_pts = decoded->pts;
        if (source_pts != AV_NOPTS_VALUE) {
            source_pts = av_rescale_q(source_pts, video->in_time_base, video->enc_ctx->time_base);
        }
        if (source_pts < 0) source_pts = AV_NOPTS_VALUE;
        source_pts = normalize_video_pts(video, source_pts);
        output->pts = source_pts;

        if (video->filter_graph != NULL) {
            err = av_buffersrc_add_frame_flags(video->buffersrc_ctx, output, AV_BUFFERSRC_FLAG_KEEP_REF);
            av_frame_unref(decoded);
            if (err < 0) {
                av_frame_free(&decoded);
                return err;
            }

            AVFrame *filtered = av_frame_alloc();
            if (filtered == NULL) {
                av_frame_free(&decoded);
                return AVERROR(ENOMEM);
            }
            while ((err = av_buffersink_get_frame(video->buffersink_ctx, filtered)) >= 0) {
                if (filtered->pts == AV_NOPTS_VALUE) filtered->pts = AV_NOPTS_VALUE;
                if (filtered->pts != AV_NOPTS_VALUE && video->filter_sink_time_base.num > 0 && video->filter_sink_time_base.den > 0) {
                    filtered->pts = av_rescale_q(filtered->pts, video->filter_sink_time_base, video->enc_ctx->time_base);
                }
                filtered->pts = normalize_video_pts(video, filtered->pts);
                int write_err = write_video_frame(video, out_ctx, filtered);
                av_frame_unref(filtered);
                if (write_err < 0) {
                    av_frame_free(&filtered);
                    av_frame_free(&decoded);
                    return write_err;
                }
            }
            av_frame_free(&filtered);
            if (err == AVERROR(EAGAIN) || err == AVERROR_EOF) {
                err = 0;
            }
            if (err < 0) {
                av_frame_free(&decoded);
                return err;
            }
            continue;
        }

        err = write_video_frame(video, out_ctx, output);
        av_frame_unref(decoded);
        if (err < 0) {
            av_frame_free(&decoded);
            return err;
        }
    }
    av_frame_free(&decoded);

    if (video->filter_graph != NULL) {
        err = av_buffersrc_add_frame_flags(video->buffersrc_ctx, NULL, 0);
        if (err < 0 && err != AVERROR_EOF) {
            return err;
        }
        AVFrame *filtered = av_frame_alloc();
        if (filtered == NULL) {
            return AVERROR(ENOMEM);
        }
        while ((err = av_buffersink_get_frame(video->buffersink_ctx, filtered)) >= 0) {
            if (filtered->pts == AV_NOPTS_VALUE) filtered->pts = AV_NOPTS_VALUE;
            if (filtered->pts != AV_NOPTS_VALUE && video->filter_sink_time_base.num > 0 && video->filter_sink_time_base.den > 0) {
                filtered->pts = av_rescale_q(filtered->pts, video->filter_sink_time_base, video->enc_ctx->time_base);
            }
            filtered->pts = normalize_video_pts(video, filtered->pts);
            int write_err = write_video_frame(video, out_ctx, filtered);
            av_frame_unref(filtered);
            if (write_err < 0) {
                av_frame_free(&filtered);
                return write_err;
            }
        }
        av_frame_free(&filtered);
        if (err != AVERROR(EAGAIN) && err != AVERROR_EOF && err < 0) {
            return err;
        }
    }

    err = write_video_frame(video, out_ctx, NULL);
    if (err < 0) {
        return err;
    }
    return 0;
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
    free_media_edit_config(job);
    free(job);
}

int aff_set_input_output(AFFOpaqueJob *job, const char *input_path, const char *output_path, int overwrite_existing) {
    if (job == NULL || input_path == NULL || output_path == NULL) {
        return set_errorf("invalid arguments for aff_set_input_output");
    }

    char *input_copy = dup_string(input_path);
    char *output_copy = dup_string(output_path);
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
    job->cancelled = false;
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
        copies[i] = dup_string(arguments[i]);
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

int aff_set_media_edit_inputs(
    AFFOpaqueJob *job,
    const char *additional_audio_input,
    const char *subtitle_input,
    const char *subtitle_codec
) {
    if (job == NULL) {
        return set_errorf("invalid job in aff_set_media_edit_inputs");
    }

    free(job->additional_audio_input);
    free(job->subtitle_input);
    free(job->subtitle_codec);
    job->additional_audio_input = dup_string(additional_audio_input);
    job->subtitle_input = dup_string(subtitle_input);
    job->subtitle_codec = dup_string(subtitle_codec);
    job->media_edit_mode = true;
    clear_error();
    return 0;
}

int aff_add_metadata(AFFOpaqueJob *job, const char *key, const char *value) {
    if (job == NULL || key == NULL || value == NULL) {
        return set_errorf("invalid arguments in aff_add_metadata");
    }
    av_dict_set(&job->media_edit_metadata, key, value, 0);
    job->media_edit_mode = true;
    clear_error();
    return 0;
}

int aff_clear_chapters(AFFOpaqueJob *job) {
    if (job == NULL) {
        return set_errorf("invalid job in aff_clear_chapters");
    }

    for (int i = 0; i < job->chapter_count; i++) {
        free(job->chapters[i].title);
    }
    free(job->chapters);
    job->chapters = NULL;
    job->chapter_count = 0;
    job->chapter_capacity = 0;
    job->media_edit_mode = true;
    clear_error();
    return 0;
}

int aff_add_chapter(AFFOpaqueJob *job, int64_t start_milliseconds, int64_t end_milliseconds, const char *title) {
    if (job == NULL || title == NULL) {
        return set_errorf("invalid arguments in aff_add_chapter");
    }
    if (end_milliseconds <= start_milliseconds || start_milliseconds < 0) {
        return set_errorf("invalid chapter range");
    }
    if (job->chapter_count == job->chapter_capacity) {
        int next_capacity = job->chapter_capacity == 0 ? 8 : job->chapter_capacity * 2;
        AFFChapterEntry *next = (AFFChapterEntry *)realloc(job->chapters, sizeof(AFFChapterEntry) * (size_t)next_capacity);
        if (next == NULL) {
            return set_errorf("failed to grow chapter buffer");
        }
        job->chapters = next;
        job->chapter_capacity = next_capacity;
    }

    AFFChapterEntry *entry = &job->chapters[job->chapter_count];
    entry->start_milliseconds = start_milliseconds;
    entry->end_milliseconds = end_milliseconds;
    entry->title = dup_string(title);
    if (entry->title == NULL) {
        return set_errorf("failed to copy chapter title");
    }

    job->chapter_count += 1;
    job->media_edit_mode = true;
    clear_error();
    return 0;
}

int aff_run_job_async(
    AFFOpaqueJob *job,
    AFFLogCallback log_callback,
    AFFProgressCallback progress_callback,
    void *context
) {
    if (job == NULL || job->input_path == NULL || job->output_path == NULL) {
        return set_errorf("job is not fully configured");
    }

    if (job->media_edit_mode) {
        return run_media_edit_job(job, progress_callback, context);
    }

    AFFParsedOptions opts;
    if (parse_options(job, &opts, log_callback, context) != 0) {
        return -1;
    }

    AVFormatContext *input_ctx = NULL;
    AVFormatContext *output_ctx = NULL;
    AVPacket *packet = NULL;
    int *stream_map = NULL;
    int stream_map_size = 0;
    AFFAudioTranscoder audio = {0};
    AFFVideoTranscoder video = {0};
    audio.in_stream_index = -1;
    audio.out_stream_index = -1;
    video.in_stream_index = -1;
    video.out_stream_index = -1;

    int err = avformat_open_input(&input_ctx, job->input_path, NULL, NULL);
    if (err < 0) {
        free_options(&opts);
        return set_error_av("failed to open input", err);
    }

    err = avformat_find_stream_info(input_ctx, NULL);
    if (err < 0) {
        avformat_close_input(&input_ctx);
        free_options(&opts);
        return set_error_av("failed to read stream info", err);
    }

    if (opts.start_seconds > 0) {
        int64_t seek_ts = (int64_t)(opts.start_seconds * AV_TIME_BASE);
        av_seek_frame(input_ctx, -1, seek_ts, AVSEEK_FLAG_BACKWARD);
    }

    err = avformat_alloc_output_context2(&output_ctx, NULL, opts.output_format, job->output_path);
    if (err < 0 || output_ctx == NULL) {
        avformat_close_input(&input_ctx);
        free_options(&opts);
        return set_error_av("failed to allocate output context", err < 0 ? err : AVERROR_UNKNOWN);
    }

    stream_map_size = (int)input_ctx->nb_streams;
    stream_map = (int *)malloc(sizeof(int) * (size_t)stream_map_size);
    if (stream_map == NULL) {
        avformat_free_context(output_ctx);
        avformat_close_input(&input_ctx);
        free_options(&opts);
        return set_errorf("failed to allocate stream map");
    }
    for (int i = 0; i < stream_map_size; i++) {
        stream_map[i] = -1;
    }

    bool audio_transcode_used = false;
    bool video_transcode_used = false;
    int audio_ordinal = -1;

    for (unsigned int i = 0; i < input_ctx->nb_streams; i++) {
        AVStream *in_stream = input_ctx->streams[i];
        enum AVMediaType type = in_stream->codecpar->codec_type;
        if (type == AVMEDIA_TYPE_AUDIO) {
            audio_ordinal += 1;
        }

        if ((type == AVMEDIA_TYPE_VIDEO && opts.disable_video) ||
            (type == AVMEDIA_TYPE_AUDIO && opts.disable_audio) ||
            (type == AVMEDIA_TYPE_SUBTITLE && opts.disable_subtitle)) {
            continue;
        }
        if (opts.has_explicit_map) {
            if (type == AVMEDIA_TYPE_VIDEO && !opts.map_video) {
                continue;
            }
            if (type == AVMEDIA_TYPE_AUDIO && !opts.map_audio) {
                continue;
            }
            if (type == AVMEDIA_TYPE_SUBTITLE && !opts.map_subtitle) {
                continue;
            }
            if (type == AVMEDIA_TYPE_AUDIO && opts.map_audio_index >= 0 && audio_ordinal != opts.map_audio_index) {
                continue;
            }
        }

        if (!(type == AVMEDIA_TYPE_AUDIO || type == AVMEDIA_TYPE_VIDEO || type == AVMEDIA_TYPE_SUBTITLE)) {
            continue;
        }

        AVStream *out_stream = avformat_new_stream(output_ctx, NULL);
        if (out_stream == NULL) {
            err = AVERROR(ENOMEM);
            goto cleanup;
        }

        stream_map[i] = out_stream->index;

        if (type == AVMEDIA_TYPE_AUDIO && !opts.copy_audio && !audio_transcode_used) {
            audio.in_stream_index = (int)i;
            audio.out_stream_index = out_stream->index;
            err = configure_audio_encoder(&audio, output_ctx, in_stream, out_stream, &opts);
            if (err < 0) {
                goto cleanup;
            }
            err = configure_audio_filter_graph(&audio, in_stream, &opts);
            if (err < 0) {
                goto cleanup;
            }
            audio_transcode_used = true;
            continue;
        }

        if (type == AVMEDIA_TYPE_VIDEO && !opts.copy_video && !video_transcode_used) {
            video.in_stream_index = (int)i;
            video.out_stream_index = out_stream->index;
            err = configure_video_encoder(&video, input_ctx, output_ctx, in_stream, out_stream, &opts);
            if (err < 0) {
                goto cleanup;
            }
            err = configure_video_filter_graph(&video, in_stream, &opts);
            if (err < 0) {
                goto cleanup;
            }
            video_transcode_used = true;
            continue;
        }

        err = avcodec_parameters_copy(out_stream->codecpar, in_stream->codecpar);
        if (err < 0) {
            err = set_error_av("failed to copy stream parameters", err);
            goto cleanup;
        }
        out_stream->codecpar->codec_tag = 0;
        out_stream->time_base = in_stream->time_base;
    }

    if (opts.keep_metadata) {
        av_dict_copy(&output_ctx->metadata, input_ctx->metadata, 0);
    }

    AVDictionaryEntry *entry = NULL;
    while ((entry = av_dict_get(opts.metadata, "", entry, AV_DICT_IGNORE_SUFFIX)) != NULL) {
        av_dict_set(&output_ctx->metadata, entry->key, entry->value, 0);
    }

    if (!(output_ctx->oformat->flags & AVFMT_NOFILE)) {
        if (!job->overwrite_existing) {
            FILE *f = fopen(job->output_path, "rb");
            if (f != NULL) {
                fclose(f);
                err = set_errorf("output exists and overwrite is disabled");
                goto cleanup;
            }
        }

        err = avio_open(&output_ctx->pb, job->output_path, AVIO_FLAG_WRITE);
        if (err < 0) {
            err = set_error_av("failed to open output", err);
            goto cleanup;
        }
    }

    AVDictionary *muxer_opts = NULL;
    if (opts.faststart) {
        av_dict_set(&muxer_opts, "movflags", "+faststart", 0);
    }
    err = avformat_write_header(output_ctx, muxer_opts ? &muxer_opts : NULL);
    av_dict_free(&muxer_opts);
    if (err < 0) {
        err = set_error_av("failed to write header", err);
        goto cleanup;
    }

    packet = av_packet_alloc();
    if (packet == NULL) {
        err = set_errorf("failed to allocate packet");
        goto cleanup;
    }

    int64_t input_duration = input_ctx->duration;
    int64_t begin_us = opts.start_seconds > 0 ? (int64_t)(opts.start_seconds * AV_TIME_BASE) : 0;
    int64_t end_us = opts.duration_seconds > 0 ? (begin_us + (int64_t)(opts.duration_seconds * AV_TIME_BASE)) : INT64_MAX;

    while ((err = av_read_frame(input_ctx, packet)) >= 0) {
        if (job->cancelled) {
            err = set_errorf("job cancelled");
            goto cleanup;
        }

        if (packet->stream_index < 0 || packet->stream_index >= stream_map_size || stream_map[packet->stream_index] < 0) {
            av_packet_unref(packet);
            continue;
        }

        AVStream *in_stream = input_ctx->streams[packet->stream_index];
        int64_t packet_us = av_rescale_q(packet->pts, in_stream->time_base, AV_TIME_BASE_Q);
        if (packet_us < begin_us) {
            av_packet_unref(packet);
            continue;
        }
        if (packet_us > end_us) {
            av_packet_unref(packet);
            break;
        }

        if (progress_callback != NULL) {
            AFFProgress progress = {0};
            progress.processed_time_seconds = packet_us > 0 ? ((double)packet_us / (double)AV_TIME_BASE) : 0;
            if (input_duration > 0) {
                double ratio = (double)packet_us / (double)input_duration;
                if (ratio < 0) ratio = 0;
                if (ratio > 1) ratio = 1;
                progress.estimated_ratio = ratio;
            }
            progress_callback(progress, context);
        }

        if (packet->stream_index == audio.in_stream_index && audio_transcode_used) {
            err = transcode_audio_packet(&audio, packet, output_ctx);
            av_packet_unref(packet);
            if (err < 0) {
                err = set_error_av("audio transcode failed", err);
                goto cleanup;
            }
            continue;
        }
        if (packet->stream_index == video.in_stream_index && video_transcode_used) {
            err = transcode_video_packet(&video, packet, output_ctx);
            av_packet_unref(packet);
            if (err < 0) {
                err = set_error_av("video transcode failed", err);
                goto cleanup;
            }
            continue;
        }

        AVStream *out_stream = output_ctx->streams[stream_map[packet->stream_index]];
        err = copy_packet(output_ctx, packet, in_stream, out_stream);
        av_packet_unref(packet);
        if (err < 0) {
            err = set_error_av("failed to write packet", err);
            goto cleanup;
        }
    }

    if (audio_transcode_used) {
        err = flush_audio(&audio, output_ctx);
        if (err < 0) {
            err = set_error_av("failed to flush audio", err);
            goto cleanup;
        }
    }
    if (video_transcode_used) {
        err = flush_video(&video, output_ctx);
        if (err < 0) {
            err = set_error_av("failed to flush video", err);
            goto cleanup;
        }
    }

    err = av_write_trailer(output_ctx);
    if (err < 0) {
        err = set_error_av("failed to write trailer", err);
        goto cleanup;
    }

    err = 0;

cleanup:
    if (packet != NULL) {
        av_packet_free(&packet);
    }

    if (audio.swr != NULL) {
        swr_free(&audio.swr);
    }

    if (audio.dec_ctx != NULL) {
        avcodec_free_context(&audio.dec_ctx);
    }

    if (audio.enc_ctx != NULL) {
        avcodec_free_context(&audio.enc_ctx);
    }
    if (audio.filter_graph != NULL) {
        avfilter_graph_free(&audio.filter_graph);
    }
    if (video.scaled_frame != NULL) {
        av_frame_free(&video.scaled_frame);
    }
    if (video.sws != NULL) {
        sws_freeContext(video.sws);
    }
    if (video.dec_ctx != NULL) {
        avcodec_free_context(&video.dec_ctx);
    }
    if (video.enc_ctx != NULL) {
        avcodec_free_context(&video.enc_ctx);
    }
    if (video.filter_graph != NULL) {
        avfilter_graph_free(&video.filter_graph);
    }

    if (output_ctx != NULL) {
        if (!(output_ctx->oformat->flags & AVFMT_NOFILE) && output_ctx->pb != NULL) {
            avio_closep(&output_ctx->pb);
        }
        avformat_free_context(output_ctx);
    }

    if (input_ctx != NULL) {
        avformat_close_input(&input_ctx);
    }

    free(stream_map);
    free_options(&opts);

    return err;
}

int aff_cancel_job(AFFOpaqueJob *job) {
    if (job == NULL) {
        return set_errorf("invalid job in aff_cancel_job");
    }
    job->cancelled = true;
    clear_error();
    return 0;
}

const char *aff_copy_last_error(void) {
    return g_last_error;
}

void aff_free_string(char *value) {
    free(value);
}
