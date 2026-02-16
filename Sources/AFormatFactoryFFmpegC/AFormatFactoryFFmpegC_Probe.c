#include "AFormatFactoryFFmpegC_Internal.h"

int aff_detect_capabilities(char **muxers_json, char **encoders_json) {
    if (muxers_json == NULL || encoders_json == NULL) {
        return set_errorf("invalid arguments for aff_detect_capabilities");
    }

    size_t mux_cap = 65536;
    size_t enc_cap = 65536;
    char *mux = (char *)malloc(mux_cap);
    char *enc = (char *)malloc(enc_cap);
    if (mux == NULL || enc == NULL) {
        free(mux);
        free(enc);
        return set_errorf("failed to allocate capability buffer");
    }

    mux[0] = '['; mux[1] = '\0';
    enc[0] = '['; enc[1] = '\0';

    void *opaque = NULL;
    const AVOutputFormat *ofmt = NULL;
    bool first = true;
    while ((ofmt = av_muxer_iterate(&opaque)) != NULL) {
        if (ofmt->name == NULL) continue;
        if (!first) strncat(mux, ",", mux_cap - strlen(mux) - 1);
        strncat(mux, "\"", mux_cap - strlen(mux) - 1);
        strncat(mux, ofmt->name, mux_cap - strlen(mux) - 1);
        strncat(mux, "\"", mux_cap - strlen(mux) - 1);
        first = false;
    }
    strncat(mux, "]", mux_cap - strlen(mux) - 1);

    opaque = NULL;
    const AVCodec *codec = NULL;
    first = true;
    while ((codec = av_codec_iterate(&opaque)) != NULL) {
        if (!av_codec_is_encoder(codec) || codec->name == NULL) {
            continue;
        }
        if (codec->type != AVMEDIA_TYPE_VIDEO && codec->type != AVMEDIA_TYPE_AUDIO) {
            continue;
        }
        if (!first) strncat(enc, ",", enc_cap - strlen(enc) - 1);
        strncat(enc, "\"", enc_cap - strlen(enc) - 1);
        strncat(enc, codec->name, enc_cap - strlen(enc) - 1);
        strncat(enc, "\"", enc_cap - strlen(enc) - 1);
        first = false;
    }
    strncat(enc, "]", enc_cap - strlen(enc) - 1);

    *muxers_json = mux;
    *encoders_json = enc;
    clear_error();
    return 0;
}

int aff_probe_media(const char *input_path, char **media_info_json) {
    if (input_path == NULL || media_info_json == NULL) {
        return set_errorf("invalid arguments for aff_probe_media");
    }

    AVFormatContext *ctx = NULL;
    int err = avformat_open_input(&ctx, input_path, NULL, NULL);
    if (err < 0) {
        return set_error_av("failed to open input", err);
    }
    err = avformat_find_stream_info(ctx, NULL);
    if (err < 0) {
        avformat_close_input(&ctx);
        return set_error_av("failed to read stream info", err);
    }

    char buffer[256] = {0};
    double duration = ctx->duration > 0 ? ((double)ctx->duration / (double)AV_TIME_BASE) : 0;
    snprintf(buffer, sizeof(buffer), "{\"duration\":%.6f,\"streams\":%u}", duration, ctx->nb_streams);

    *media_info_json = dup_string(buffer);
    avformat_close_input(&ctx);

    if (*media_info_json == NULL) {
        return set_errorf("failed to allocate probe json");
    }

    clear_error();
    return 0;
}
