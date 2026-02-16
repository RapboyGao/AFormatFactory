#ifndef AFORMATFACTORYFFMPEGC_INTERNAL_H
#define AFORMATFACTORYFFMPEGC_INTERNAL_H

#include "AFormatFactoryFFmpegC.h"

#include <libavcodec/avcodec.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/dict.h>
#include <libavutil/imgutils.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/samplefmt.h>
#include <libavutil/timestamp.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct AFFChapterEntry {
    int64_t start_milliseconds;
    int64_t end_milliseconds;
    char *title;
} AFFChapterEntry;

typedef struct AFFOpaqueJob {
    char *input_path;
    char *output_path;
    char **arguments;
    int argument_count;
    int overwrite_existing;
    bool cancelled;
    bool media_edit_mode;

    char *additional_audio_input;
    char *subtitle_input;
    char *subtitle_codec;
    AVDictionary *media_edit_metadata;
    AFFChapterEntry *chapters;
    int chapter_count;
    int chapter_capacity;
} AFFOpaqueJob;

typedef struct AFFParsedOptions {
    bool keep_metadata;
    bool copy_audio;
    bool copy_video;
    bool copy_subtitle;
    bool disable_audio;
    bool disable_video;
    bool disable_subtitle;

    char *audio_codec;
    char *video_codec;
    char *subtitle_codec;

    int audio_bitrate;
    int audio_sample_rate;
    int audio_channels;
    int video_bitrate;
    bool has_video_bitrate;
    int video_gop;
    int video_maxrate;
    int video_bufsize;
    double video_frame_rate;
    int video_crf;
    double video_qscale;
    double audio_qscale;
    int thread_count;
    bool faststart;
    bool has_explicit_map;
    bool map_video;
    bool map_audio;
    bool map_subtitle;
    int map_audio_index;

    double start_seconds;
    double duration_seconds;

    char *video_preset;
    char *video_profile;
    char *video_level;
    char *video_tune;
    char *video_pix_fmt;
    char *video_filter;
    char *audio_filter;
    char *output_format;
    int output_width;
    int output_height;

    AVDictionary *metadata;
} AFFParsedOptions;

typedef struct AFFAudioTranscoder {
    int in_stream_index;
    int out_stream_index;
    AVCodecContext *dec_ctx;
    AVCodecContext *enc_ctx;
    SwrContext *swr;
    int64_t next_pts;
    AVRational in_time_base;
    AVFilterGraph *filter_graph;
    AVFilterContext *buffersrc_ctx;
    AVFilterContext *buffersink_ctx;
    AVRational filter_sink_time_base;
} AFFAudioTranscoder;

typedef struct AFFVideoTranscoder {
    int in_stream_index;
    int out_stream_index;
    AVCodecContext *dec_ctx;
    AVCodecContext *enc_ctx;
    struct SwsContext *sws;
    AVFrame *scaled_frame;
    int64_t next_pts;
    AVRational in_time_base;
    AVRational out_time_base;
    AVFilterGraph *filter_graph;
    AVFilterContext *buffersrc_ctx;
    AVFilterContext *buffersink_ctx;
    AVRational filter_sink_time_base;
} AFFVideoTranscoder;

int set_errorf(const char *message);
int set_error_av(const char *prefix, int errnum);
void clear_error(void);
char *dup_string(const char *value);
bool str_eq(const char *lhs, const char *rhs);
void free_options(AFFParsedOptions *opts);
void free_media_edit_config(AFFOpaqueJob *job);
int copy_packet(AVFormatContext *out_ctx, AVPacket *packet, AVStream *in_stream, AVStream *out_stream);
int run_media_edit_job(AFFOpaqueJob *job, AFFProgressCallback progress_callback, void *context);

#endif
