/* In-place temporal tone stabilization for 1080p GREY8 on RK3576.
 *
 * The FPGA's framewise histogram equalization alternates between two tone
 * curves under the current illumination. Match each frame's 10th, 50th and
 * 90th percentiles to a slowly moving reference, preserving the broad
 * equalized contrast while removing the rapid curve change. This filter
 * changes pixel values only; it never drops or duplicates frames.
 */
#include <gst/base/gstbasetransform.h>
#include <gst/video/video.h>
#include <string.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#define PACKAGE "rktemporalgray"
#define SAMPLE_X 16
#define SAMPLE_Y 4
#define REFERENCE_DIVISOR 32
#define MAX_ANCHOR_SHIFT 48

typedef struct {
    GstBaseTransform parent;
    GstVideoInfo info;
    gint reference_q8[3];
    gint reference_mean_q8;
    gboolean reference_valid;
    guint64 frames;
    guint64 processing_us;
} GstRkTemporalGray;

typedef struct {
    GstBaseTransformClass parent_class;
} GstRkTemporalGrayClass;

G_DEFINE_TYPE(GstRkTemporalGray, gst_rk_temporal_gray, GST_TYPE_BASE_TRANSFORM)

static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE(
    "sink", GST_PAD_SINK, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)GRAY8"));
static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE(
    "src", GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)GRAY8"));

static gboolean set_caps(GstBaseTransform *base, GstCaps *in, GstCaps *out) {
    (void)out;
    return gst_video_info_from_caps(&((GstRkTemporalGray *)base)->info, in);
}

static gboolean start(GstBaseTransform *base) {
    GstRkTemporalGray *self = (GstRkTemporalGray *)base;
    self->reference_valid = FALSE;
    self->frames = 0;
    self->processing_us = 0;
    memset(self->reference_q8, 0, sizeof(self->reference_q8));
    self->reference_mean_q8 = 0;
    return TRUE;
}

static gint clamp_int(gint value, gint low, gint high) {
    return value < low ? low : (value > high ? high : value);
}

static void percentiles(const guint histogram[256], guint samples, gint p[3]) {
    const guint thresholds[3] = {
        (samples + 9) / 10, (samples + 1) / 2, (samples * 9 + 9) / 10
    };
    guint cumulative = 0;
    gint next = 0;
    for(gint level = 0; level < 256 && next < 3; ++level) {
        cumulative += histogram[level];
        while(next < 3 && cumulative >= thresholds[next]) {
            p[next] = level;
            ++next;
        }
    }
}

static void tone_lut(const gint input[3], const gint target[3], guint8 lut[256]) {
    const gint x[5] = {0, input[0], input[1], input[2], 255};
    const gint y[5] = {0, target[0], target[1], target[2], 255};
    gint segment = 0;
    for(gint level = 0; level < 256; ++level) {
        while(segment < 3 && level > x[segment + 1])
            ++segment;
        gint span = x[segment + 1] - x[segment];
        gint mapped = span ? y[segment] +
            ((level - x[segment]) * (y[segment + 1] - y[segment]) +
             span / 2) / span : y[segment + 1];
        lut[level] = (guint8)clamp_int(mapped, 0, 255);
    }
    lut[0] = 0;
    lut[255] = 255;
}

static void apply_lut(guint8 *data, gint stride, gint width, gint height,
                      const guint8 lut[256]) {
#if defined(__aarch64__)
    uint8x16x4_t tables[4];
    for(gint quarter = 0; quarter < 4; ++quarter) {
        for(gint vector = 0; vector < 4; ++vector)
            tables[quarter].val[vector] =
                vld1q_u8(lut + quarter * 64 + vector * 16);
    }
    const uint8x16_t index_mask = vdupq_n_u8(0x3f);
    const uint8x16_t group_one = vdupq_n_u8(1);
    const uint8x16_t group_two = vdupq_n_u8(2);
    const uint8x16_t group_three = vdupq_n_u8(3);
    for(gint row = 0; row < height; ++row) {
        guint8 *pixels = data + row * stride;
        gint col = 0;
        for(; col + 16 <= width; col += 16) {
            uint8x16_t source = vld1q_u8(pixels + col);
            uint8x16_t index = vandq_u8(source, index_mask);
            uint8x16_t group = vshrq_n_u8(source, 6);
            uint8x16_t mapped = vqtbl4q_u8(tables[0], index);
            mapped = vbslq_u8(vceqq_u8(group, group_one),
                               vqtbl4q_u8(tables[1], index), mapped);
            mapped = vbslq_u8(vceqq_u8(group, group_two),
                               vqtbl4q_u8(tables[2], index), mapped);
            mapped = vbslq_u8(vceqq_u8(group, group_three),
                               vqtbl4q_u8(tables[3], index), mapped);
            vst1q_u8(pixels + col, mapped);
        }
        for(; col < width; ++col)
            pixels[col] = lut[pixels[col]];
    }
#else
    for(gint row = 0; row < height; ++row) {
        guint8 *pixels = data + row * stride;
        for(gint col = 0; col < width; ++col)
            pixels[col] = lut[pixels[col]];
    }
#endif
}

static GstFlowReturn transform_ip(GstBaseTransform *base, GstBuffer *buffer) {
    GstRkTemporalGray *self = (GstRkTemporalGray *)base;
    gint64 work_started = g_get_monotonic_time();
    GstVideoFrame frame;
    if(!gst_video_frame_map(&frame, &self->info, buffer, GST_MAP_READWRITE))
        return GST_FLOW_ERROR;

    guint8 *data = GST_VIDEO_FRAME_PLANE_DATA(&frame, 0);
    const gint stride = GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0);
    const gint width = GST_VIDEO_FRAME_WIDTH(&frame);
    const gint height = GST_VIDEO_FRAME_HEIGHT(&frame);
    guint histogram[256] = {0};
    guint samples = 0;
    for(gint row = 0; row < height; row += SAMPLE_Y) {
        const guint8 *pixels = data + row * stride;
        for(gint col = 0; col < width; col += SAMPLE_X) {
            ++histogram[pixels[col]];
            ++samples;
        }
    }
    if(!samples) {
        gst_video_frame_unmap(&frame);
        return GST_FLOW_OK;
    }

    gint input[3], target[3];
    percentiles(histogram, samples, input);
    guint64 input_sum = 0;
    for(gint level = 0; level < 256; ++level)
        input_sum += (guint64)histogram[level] * level;
    gint input_mean_q8 = (gint)((input_sum << 8) / samples);
    if(!self->reference_valid) {
        for(gint i = 0; i < 3; ++i)
            self->reference_q8[i] = input[i] << 8;
        self->reference_mean_q8 = input_mean_q8;
        self->reference_valid = TRUE;
    } else {
        for(gint i = 0; i < 3; ++i)
            self->reference_q8[i] +=
                ((input[i] << 8) - self->reference_q8[i]) /
                REFERENCE_DIVISOR;
        self->reference_mean_q8 +=
            (input_mean_q8 - self->reference_mean_q8) / REFERENCE_DIVISOR;
    }
    for(gint i = 0; i < 3; ++i) {
        gint reference = (self->reference_q8[i] + 128) >> 8;
        target[i] = clamp_int(reference,
                              input[i] - MAX_ANCHOR_SHIFT,
                              input[i] + MAX_ANCHOR_SHIFT);
    }

    guint8 lut[256];
    tone_lut(input, target, lut);
    guint64 mapped_sum = 0;
    for(gint level = 0; level < 256; ++level)
        mapped_sum += (guint64)histogram[level] * lut[level];
    gint mapped_mean_q8 = (gint)((mapped_sum << 8) / samples);
    gint mean_error_q8 = self->reference_mean_q8 - mapped_mean_q8;
    gint rounded_error = mean_error_q8 >= 0 ?
        (mean_error_q8 + 128) / 256 : -((-mean_error_q8 + 128) / 256);
    gint offset = clamp_int(rounded_error, -24, 24);
    if(offset) {
        for(gint level = 0; level < 256; ++level)
            lut[level] = (guint8)clamp_int((gint)lut[level] + offset, 0, 255);
    }
    lut[0] = 0;
    lut[255] = 255;
    apply_lut(data, stride, width, height, lut);
    ++self->frames;
    self->processing_us += (guint64)(g_get_monotonic_time() - work_started);
    if(self->frames <= 4 || self->frames % 60 == 0) {
        g_print("RK temporal frame %llu: p10/p50/p90 %d/%d/%d -> %d/%d/%d, mean offset %+d, avg %.2f ms\n",
                (unsigned long long)self->frames,
                input[0], input[1], input[2],
                target[0], target[1], target[2], offset,
                (double)self->processing_us / (double)self->frames / 1000.0);
    }
    gst_video_frame_unmap(&frame);
    return GST_FLOW_OK;
}

static void gst_rk_temporal_gray_class_init(GstRkTemporalGrayClass *klass) {
    GstElementClass *element = GST_ELEMENT_CLASS(klass);
    GstBaseTransformClass *transform = GST_BASE_TRANSFORM_CLASS(klass);
    gst_element_class_set_static_metadata(element, "RK temporal GREY stabilizer",
        "Filter/Effect/Video", "Per-frame percentile tone matching", "Codex");
    gst_element_class_add_static_pad_template(element, &sink_template);
    gst_element_class_add_static_pad_template(element, &src_template);
    transform->set_caps = set_caps;
    transform->start = start;
    transform->transform_ip = transform_ip;
}

static void gst_rk_temporal_gray_init(GstRkTemporalGray *self) {
    gst_base_transform_set_in_place(GST_BASE_TRANSFORM(self), TRUE);
}

static gboolean plugin_init(GstPlugin *plugin) {
    return gst_element_register(plugin, "rktemporalgray", GST_RANK_NONE,
                                gst_rk_temporal_gray_get_type());
}

GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, rktemporalgray,
                  "RK GREY temporal tone stabilizer", plugin_init, "1.0",
                  "LGPL", "rktemporalgray", "local")
