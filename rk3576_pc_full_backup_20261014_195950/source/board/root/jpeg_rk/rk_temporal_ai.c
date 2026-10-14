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
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <math.h>
#include "rk_font5x7.h"
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#define PACKAGE "rktemporalai"
#define SAMPLE_X 16
#define SAMPLE_Y 4
#define REFERENCE_DIVISOR 32
#define MAX_ANCHOR_SHIFT 48
#define BOX_PATH "/run/road_ai_boxes.bin"
#define BOX_MAGIC 0x52414942u
#define MAX_BOXES 64
#define MAX_AGE_US 500000

typedef struct {
    float x1, y1, x2, y2, score;
    uint32_t cls;
} AiBox;
typedef struct {
    uint32_t magic, seq;
    uint64_t updated_us;
    uint32_t count, reserved;
    AiBox boxes[MAX_BOXES];
} AiSnapshot;
_Static_assert(sizeof(AiSnapshot) == 1560, "overlay ABI size mismatch");

typedef struct {
    GstBaseTransform parent;
    GstVideoInfo info;
    gint reference_q8[3];
    gint reference_mean_q8;
    gboolean reference_valid;
    gboolean fast_blend;
    gboolean affine_blend;
    gboolean mix_previous;
    gboolean previous_valid;
    guint8 *previous;
    gsize previous_size;
    guint64 frames;
    guint64 processing_us;
    int boxes_fd;
    const AiSnapshot *boxes_shared;
    guint64 boxes_frames, boxes_drawn, boxes_draw_us;
} GstRkTemporalAi;

typedef struct {
    GstBaseTransformClass parent_class;
} GstRkTemporalAiClass;

G_DEFINE_TYPE(GstRkTemporalAi, gst_rk_temporal_ai, GST_TYPE_BASE_TRANSFORM)

enum {
    PROP_0,
    PROP_FAST_BLEND,
    PROP_AFFINE_BLEND,
    PROP_MIX_PREVIOUS,
};

static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE(
    "sink", GST_PAD_SINK, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)GRAY8"));
static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE(
    "src", GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)GRAY8"));

static gboolean set_caps(GstBaseTransform *base, GstCaps *in, GstCaps *out) {
    (void)out;
    GstRkTemporalAi *self = (GstRkTemporalAi *)base;
    if(!gst_video_info_from_caps(&self->info, in))
        return FALSE;
    gsize needed = (gsize)GST_VIDEO_INFO_WIDTH(&self->info) *
                   GST_VIDEO_INFO_HEIGHT(&self->info);
    if(self->previous_size != needed) {
        self->previous = g_realloc(self->previous, needed);
        self->previous_size = needed;
    }
    self->previous_valid = FALSE;
    return TRUE;
}

static gboolean start(GstBaseTransform *base) {
    GstRkTemporalAi *self = (GstRkTemporalAi *)base;
    self->reference_valid = FALSE;
    self->previous_valid = FALSE;
    self->frames = 0;
    self->processing_us = 0;
    memset(self->reference_q8, 0, sizeof(self->reference_q8));
    self->reference_mean_q8 = 0;
    return TRUE;
}

static void set_property(GObject *object, guint property_id,
                         const GValue *value, GParamSpec *spec) {
    GstRkTemporalAi *self = (GstRkTemporalAi *)object;
    switch(property_id) {
    case PROP_FAST_BLEND:
        self->fast_blend = g_value_get_boolean(value);
        break;
    case PROP_AFFINE_BLEND:
        self->affine_blend = g_value_get_boolean(value);
        break;
    case PROP_MIX_PREVIOUS:
        self->mix_previous = g_value_get_boolean(value);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
    }
}

static void get_property(GObject *object, guint property_id,
                         GValue *value, GParamSpec *spec) {
    GstRkTemporalAi *self = (GstRkTemporalAi *)object;
    switch(property_id) {
    case PROP_FAST_BLEND:
        g_value_set_boolean(value, self->fast_blend);
        break;
    case PROP_AFFINE_BLEND:
        g_value_set_boolean(value, self->affine_blend);
        break;
    case PROP_MIX_PREVIOUS:
        g_value_set_boolean(value, self->mix_previous);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
    }
}

static void finalize(GObject *object) {
    GstRkTemporalAi *self = (GstRkTemporalAi *)object;
    g_free(self->previous);
    self->previous = NULL;
    self->previous_size = 0;
    if(self->boxes_shared) munmap((void *)self->boxes_shared, sizeof(AiSnapshot));
    if(self->boxes_fd >= 0) close(self->boxes_fd);
    G_OBJECT_CLASS(gst_rk_temporal_ai_parent_class)->finalize(object);
}

static gint clamp_int(gint value, gint low, gint high) {
    return value < low ? low : (value > high ? high : value);
}

static gboolean read_boxes(GstRkTemporalAi *self, AiSnapshot *snapshot,
                           gint64 now_us) {
    if(!self->boxes_shared) return FALSE;
    uint32_t before = __atomic_load_n(&self->boxes_shared->seq, __ATOMIC_ACQUIRE);
    if(before & 1u) return FALSE;
    memcpy(snapshot, self->boxes_shared, sizeof(*snapshot));
    __atomic_thread_fence(__ATOMIC_ACQUIRE);
    uint32_t after = __atomic_load_n(&self->boxes_shared->seq, __ATOMIC_ACQUIRE);
    return before == after && !(after & 1u) && snapshot->magic == BOX_MAGIC &&
           snapshot->count <= MAX_BOXES &&
           snapshot->updated_us <= (uint64_t)now_us &&
           (uint64_t)now_us - snapshot->updated_us <= MAX_AGE_US;
}

static void gray_rect(guint8 *data, int stride, int width, int height,
                      int x1, int y1, int x2, int y2, guint8 value) {
    if(x1 < 0) x1 = 0;
    if(y1 < 0) y1 = 0;
    if(x2 > width) x2 = width;
    if(y2 > height) y2 = height;
    if(x1 >= x2 || y1 >= y2) return;
    for(int y = y1; y < y2; ++y)
        memset(data + (gsize)y * stride + x1, value, (size_t)(x2 - x1));
}

static void glyph(char c, guint8 rows[7]) {
    rk_glyph5x7(c, rows);
}

static void draw_boxes(GstRkTemporalAi *self, guint8 *data,
                       int stride, int width, int height,
                       const AiSnapshot *snapshot) {
    static const char *class_names[6] = {
        "Alligator crack", "Longitudinal crack", "Oblique crack",
        "Pothole", "Repair", "Transverse crack"
    };
    for(uint32_t i = 0; i < snapshot->count; ++i) {
        const AiBox *box = &snapshot->boxes[i];
        if(!isfinite(box->x1) || !isfinite(box->y1) ||
           !isfinite(box->x2) || !isfinite(box->y2) ||
           !isfinite(box->score) || box->score < 0 || box->score > 1 ||
           box->x1 < -width || box->x2 > width * 2 ||
           box->y1 < -height || box->y2 > height * 2)
            continue;
        int x1 = (int)box->x1, y1 = (int)box->y1;
        int x2 = (int)box->x2, y2 = (int)box->y2;
        if(x1 >= x2 || y1 >= y2) continue;
        gray_rect(data, stride, width, height, x1, y1, x2+1, y1+4, 255);
        gray_rect(data, stride, width, height, x1, y2-3, x2+1, y2+1, 255);
        gray_rect(data, stride, width, height, x1, y1, x1+4, y2+1, 255);
        gray_rect(data, stride, width, height, x2-3, y1, x2+1, y2+1, 255);
        char label[64];
        const char *name = box->cls < 6 ? class_names[box->cls] : "Unknown";
        snprintf(label, sizeof(label), "%s %.2f", name, box->score);
        int label_width = (int)strlen(label) * 12 + 8;
        int lx = x1 < 0 ? 0 : x1;
        if(lx + label_width > width) lx = width - label_width;
        if(lx < 0) lx = 0;
        int ly = y1 >= 22 ? y1 - 22 : y1 + 3;
        if(ly + 18 > height) ly = height - 18;
        gray_rect(data, stride, width, height, lx, ly,
                  lx + label_width, ly + 18, 0);
        int tx = lx + 4;
        for(const char *p = label; *p; ++p, tx += 12) {
            guint8 rows[7];
            glyph(*p, rows);
            for(int gy = 0; gy < 7; ++gy)
                for(int gx = 0; gx < 5; ++gx)
                    if(rows[gy] & (1u << (4-gx)))
                        gray_rect(data, stride, width, height,
                                  tx + gx*2, ly + 2 + gy*2,
                                  tx + gx*2 + 2, ly + 4 + gy*2, 255);
        }
        self->boxes_drawn++;
    }
}

static void overlay_boxes(GstRkTemporalAi *self, guint8 *data,
                          int stride, int width, int height) {
    AiSnapshot snapshot;
    if(!read_boxes(self, &snapshot, g_get_monotonic_time()) || !snapshot.count)
        return;
    gint64 started = g_get_monotonic_time();
    draw_boxes(self, data, stride, width, height, &snapshot);
    self->boxes_frames++;
    self->boxes_draw_us += g_get_monotonic_time() - started;
    if(self->boxes_frames % 300 == 0)
        g_print("AI temporal OSD frames=%llu boxes=%llu avg_draw_us=%.1f\n",
                (unsigned long long)self->boxes_frames,
                (unsigned long long)self->boxes_drawn,
                (double)self->boxes_draw_us / self->boxes_frames);
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

static void blend_previous(GstRkTemporalAi *self, guint8 *data, gint stride,
                           gint width, gint height) {
    if(!self->previous_valid) {
        for(gint row = 0; row < height; ++row)
            memcpy(self->previous + (gsize)row * width,
                   data + (gsize)row * stride, width);
        self->previous_valid = TRUE;
        return;
    }
    for(gint row = 0; row < height; ++row) {
        guint8 *pixels = data + (gsize)row * stride;
        guint8 *previous = self->previous + (gsize)row * width;
        gint col = 0;
#if defined(__aarch64__)
        for(; col + 16 <= width; col += 16) {
            uint8x16_t current_pixels = vld1q_u8(pixels + col);
            uint8x16_t previous_pixels = vld1q_u8(previous + col);
            vst1q_u8(previous + col, current_pixels);
            vst1q_u8(pixels + col,
                     vrhaddq_u8(current_pixels, previous_pixels));
        }
#endif
        for(; col < width; ++col) {
            guint8 current = pixels[col];
            pixels[col] = (guint8)(((guint)current + previous[col] + 1) >> 1);
            previous[col] = current;
        }
    }
}

/* A dropped display frame can defeat pairwise blending when the FPGA's HE
 * alternates between two frame brightness levels. Normalize each frame
 * independently before mixing with the previous frame. */
static gint sampled_mean(const guint8 *data, gint stride,
                         gint width, gint height) {
    guint64 sum = 0;
    guint count = 0;
    for(gint row = 0; row < height; row += 8) {
        const guint8 *pixels = data + (gsize)row * stride;
        for(gint col = 0; col < width; col += 32) {
            sum += pixels[col];
            ++count;
        }
    }
    return count ? (gint)((sum + count / 2) / count) : 0;
}

static void shift_brightness(guint8 *data, gint stride,
                             gint width, gint height, gint offset) {
    if(!offset) return;
#if defined(__aarch64__)
    const uint8x16_t amount = vdupq_n_u8((guint8)(offset < 0 ? -offset : offset));
#endif
    for(gint row = 0; row < height; ++row) {
        guint8 *pixels = data + (gsize)row * stride;
        gint col = 0;
#if defined(__aarch64__)
        if(offset > 0) {
            for(; col + 16 <= width; col += 16)
                vst1q_u8(pixels + col,
                         vqaddq_u8(vld1q_u8(pixels + col), amount));
        } else {
            for(; col + 16 <= width; col += 16)
                vst1q_u8(pixels + col,
                         vqsubq_u8(vld1q_u8(pixels + col), amount));
        }
#endif
        for(; col < width; ++col)
            pixels[col] = (guint8)clamp_int((gint)pixels[col] + offset, 0, 255);
    }
}

static void sampled_anchors(const guint8 *data, gint stride,
                            gint width, gint height, gint anchors[3],
                            gint *mean) {
    guint histogram[256] = {0};
    guint64 sum = 0;
    guint samples = 0;
    for(gint row = 0; row < height; row += 8) {
        const guint8 *pixels = data + (gsize)row * stride;
        for(gint col = 0; col < width; col += 32) {
            guint8 value = pixels[col];
            ++histogram[value];
            sum += value;
            ++samples;
        }
    }
    percentiles(histogram, samples, anchors);
    *mean = samples ? (gint)((sum + samples / 2) / samples) : 0;
}

/* Fused contrast normalization and two-frame blend. Q6 keeps every
 * multiplication in signed 16 bits, so 1080p costs only one image pass. */
static void affine_blend_previous(GstRkTemporalAi *self, guint8 *data,
                                  gint stride, gint width, gint height,
                                  gint gain_q6, gint offset_q6) {
#if defined(__aarch64__)
    const int16x8_t offset_vec = vdupq_n_s16((gint16)offset_q6);
#endif
    for(gint row = 0; row < height; ++row) {
        guint8 *pixels = data + (gsize)row * stride;
        guint8 *previous = self->previous + (gsize)row * width;
        gint col = 0;
#if defined(__aarch64__)
        for(; col + 16 <= width; col += 16) {
            uint8x16_t input = vld1q_u8(pixels + col);
            int16x8_t low = vreinterpretq_s16_u16(vmovl_u8(vget_low_u8(input)));
            int16x8_t high = vreinterpretq_s16_u16(vmovl_u8(vget_high_u8(input)));
            low = vqaddq_s16(vmulq_n_s16(low, gain_q6), offset_vec);
            high = vqaddq_s16(vmulq_n_s16(high, gain_q6), offset_vec);
            uint8x16_t normalized = vcombine_u8(vqrshrun_n_s16(low, 6),
                                                 vqrshrun_n_s16(high, 6));
            if(self->mix_previous && self->previous_valid) {
                uint8x16_t old = vld1q_u8(previous + col);
                vst1q_u8(pixels + col, vrhaddq_u8(normalized, old));
            } else {
                vst1q_u8(pixels + col, normalized);
            }
            if(self->mix_previous) vst1q_u8(previous + col, normalized);
        }
#endif
        for(; col < width; ++col) {
            guint8 normalized = (guint8)clamp_int(
                ((gint)pixels[col] * gain_q6 + offset_q6 + 32) >> 6, 0, 255);
            pixels[col] = self->mix_previous && self->previous_valid ?
                (guint8)(((guint)normalized + previous[col] + 1) >> 1) :
                normalized;
            if(self->mix_previous) previous[col] = normalized;
        }
    }
    self->previous_valid = TRUE;
}

static GstFlowReturn transform_ip(GstBaseTransform *base, GstBuffer *buffer) {
    GstRkTemporalAi *self = (GstRkTemporalAi *)base;
    gint64 work_started = g_get_monotonic_time();
    GstVideoFrame frame;
    if(!gst_video_frame_map(&frame, &self->info, buffer, GST_MAP_READWRITE))
        return GST_FLOW_ERROR;

    guint8 *data = GST_VIDEO_FRAME_PLANE_DATA(&frame, 0);
    const gint stride = GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0);
    const gint width = GST_VIDEO_FRAME_WIDTH(&frame);
    const gint height = GST_VIDEO_FRAME_HEIGHT(&frame);
    if(self->fast_blend) {
        if(self->previous_size < (gsize)width * height) {
            gst_video_frame_unmap(&frame);
            return GST_FLOW_ERROR;
        }
        gint input_mean;
        gint reference_mean;
        gint offset;
        gint gain_q6 = 64;
        if(self->affine_blend) {
            gint anchors[3];
            sampled_anchors(data, stride, width, height, anchors, &input_mean);
            if(!self->reference_valid) {
                self->reference_q8[0] = anchors[0] << 8;
                self->reference_q8[2] = anchors[2] << 8;
                self->reference_mean_q8 = input_mean << 8;
                self->reference_valid = TRUE;
            } else {
                self->reference_q8[0] +=
                    ((anchors[0] << 8) - self->reference_q8[0]) /
                    REFERENCE_DIVISOR;
                self->reference_q8[2] +=
                    ((anchors[2] << 8) - self->reference_q8[2]) /
                    REFERENCE_DIVISOR;
                self->reference_mean_q8 +=
                    ((input_mean << 8) - self->reference_mean_q8) /
                    REFERENCE_DIVISOR;
            }
            gint target_span =
                (self->reference_q8[2] - self->reference_q8[0] + 128) >> 8;
            gint input_span = clamp_int(anchors[2] - anchors[0], 16, 255);
            gain_q6 = clamp_int((target_span * 64 + input_span / 2) /
                                input_span, 48, 80);
            reference_mean = (self->reference_mean_q8 + 128) >> 8;
            gint offset_q6 = clamp_int(reference_mean * 64 -
                                        input_mean * gain_q6, -48 * 64, 48 * 64);
            offset = (offset_q6 + (offset_q6 >= 0 ? 32 : -32)) / 64;
            affine_blend_previous(self, data, stride, width, height,
                                  gain_q6, offset_q6);
        } else {
            input_mean = sampled_mean(data, stride, width, height);
            if(!self->reference_valid) {
                self->reference_mean_q8 = input_mean << 8;
                self->reference_valid = TRUE;
            } else {
                self->reference_mean_q8 +=
                    ((input_mean << 8) - self->reference_mean_q8) /
                    REFERENCE_DIVISOR;
            }
            reference_mean = (self->reference_mean_q8 + 128) >> 8;
            offset = clamp_int(reference_mean - input_mean, -48, 48);
            shift_brightness(data, stride, width, height, offset);
            blend_previous(self, data, stride, width, height);
        }
        ++self->frames;
        self->processing_us +=
            (guint64)(g_get_monotonic_time() - work_started);
        if(self->frames <= 4 || self->frames % 60 == 0)
            g_print("RK temporal %s frame %llu: input=%d ref=%d gain=%d/64 offset=%+d "
                    "output=%d avg %.2f ms\n",
                    self->affine_blend ? "affine" : "blend",
                    (unsigned long long)self->frames,
                    input_mean, reference_mean, gain_q6, offset,
                    sampled_mean(data, stride, width, height),
                    (double)self->processing_us /
                    (double)self->frames / 1000.0);
        overlay_boxes(self, data, stride, width, height);
        gst_video_frame_unmap(&frame);
        return GST_FLOW_OK;
    }
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
    overlay_boxes(self, data, stride, width, height);
    gst_video_frame_unmap(&frame);
    return GST_FLOW_OK;
}

static void gst_rk_temporal_ai_class_init(GstRkTemporalAiClass *klass) {
    GObjectClass *object = G_OBJECT_CLASS(klass);
    GstElementClass *element = GST_ELEMENT_CLASS(klass);
    GstBaseTransformClass *transform = GST_BASE_TRANSFORM_CLASS(klass);
    object->set_property = set_property;
    object->get_property = get_property;
    object->finalize = finalize;
    g_object_class_install_property(object, PROP_FAST_BLEND,
        g_param_spec_boolean("fast-blend", "Fast two-frame blend",
            "Average adjacent source frames with ARM SIMD",
            FALSE, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
    g_object_class_install_property(object, PROP_AFFINE_BLEND,
        g_param_spec_boolean("affine-blend", "Contrast-normalized blend",
            "Normalize mean and contrast before adjacent-frame blending",
            FALSE, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
    g_object_class_install_property(object, PROP_MIX_PREVIOUS,
        g_param_spec_boolean("mix-previous", "Mix previous frame",
            "Blend previous pixels after normalization; disable for motion",
            TRUE, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
    gst_element_class_set_static_metadata(element, "RK temporal GREY stabilizer",
        "Filter/Effect/Video", "Per-frame percentile tone matching", "Codex");
    gst_element_class_add_static_pad_template(element, &sink_template);
    gst_element_class_add_static_pad_template(element, &src_template);
    transform->set_caps = set_caps;
    transform->start = start;
    transform->transform_ip = transform_ip;
}

static void gst_rk_temporal_ai_init(GstRkTemporalAi *self) {
    self->fast_blend = FALSE;
    self->affine_blend = FALSE;
    self->mix_previous = TRUE;
    self->previous = NULL;
    self->previous_size = 0;
    const char *boxes_path = g_getenv("RK_AI_BOX_PATH");
    if(!boxes_path || !*boxes_path) boxes_path = BOX_PATH;
    self->boxes_fd = open(boxes_path, O_RDONLY);
    self->boxes_shared = self->boxes_fd >= 0 ?
        mmap(NULL, sizeof(AiSnapshot), PROT_READ, MAP_SHARED, self->boxes_fd, 0) :
        MAP_FAILED;
    if(self->boxes_shared == MAP_FAILED) self->boxes_shared = NULL;
    gst_base_transform_set_in_place(GST_BASE_TRANSFORM(self), TRUE);
}

static gboolean plugin_init(GstPlugin *plugin) {
    return gst_element_register(plugin, "rktemporalai", GST_RANK_NONE,
                                gst_rk_temporal_ai_get_type());
}

GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, rktemporalai,
                  "RK GREY temporal tone stabilizer", plugin_init, "1.0",
                  "LGPL", "rktemporalai", "local")
