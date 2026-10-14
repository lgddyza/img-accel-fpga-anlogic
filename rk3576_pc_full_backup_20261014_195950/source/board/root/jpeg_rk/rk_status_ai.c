/* Draw status in GRAY8 before conversion to avoid mapping a DRM RGB buffer. */
#include <gst/base/gstbasetransform.h>
#include <gst/video/video.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>
#include "rk_font5x7.h"

#define BAR_PATH "/sys/bus/pci/devices/0000:21:00.0/resource0"
#define CONTROL_ABI 0x4a435431u
#define BOX_PATH "/run/road_ai_boxes.bin"
#define BOX_MAGIC 0x52414942u

#define PACKAGE "rkstatusai"

typedef struct {
    uint32_t magic, seq;
    uint64_t updated_us;
    uint32_t count, reserved;
} AiHeader;
_Static_assert(sizeof(AiHeader) == 24, "AI state ABI size mismatch");

typedef struct {
    GstBaseTransform parent;
    GstVideoInfo info;
    gint64 second_start;
    guint frames_this_second;
    double fps;
    GMutex display_lock;
    double display_fps;
    void *bar;
    int bar_fd;
    unsigned int quality;
    gboolean quality_valid;
    int boxes_fd;
    const AiHeader *boxes_shared;
    uint32_t last_ai_seq;
    uint64_t last_ai_us;
    double yolo_fps;
    uint64_t frames, map_us, panel_us, unmap_us, shade_us, text_us;
} GstRkStatusAi;

typedef struct {
    GstBaseTransformClass parent_class;
} GstRkStatusAiClass;

G_DEFINE_TYPE(GstRkStatusAi, gst_rk_status_ai, GST_TYPE_BASE_TRANSFORM)

enum { PROP_0, PROP_DISPLAY_FPS };

static void set_property(GObject *object, guint property_id,
                         const GValue *value, GParamSpec *spec) {
    GstRkStatusAi *self = (GstRkStatusAi *)object;
    if(property_id == PROP_DISPLAY_FPS) {
        g_mutex_lock(&self->display_lock);
        self->display_fps = g_value_get_double(value);
        g_mutex_unlock(&self->display_lock);
    } else {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
    }
}

static void get_property(GObject *object, guint property_id,
                         GValue *value, GParamSpec *spec) {
    GstRkStatusAi *self = (GstRkStatusAi *)object;
    if(property_id == PROP_DISPLAY_FPS) {
        g_mutex_lock(&self->display_lock);
        g_value_set_double(value, self->display_fps);
        g_mutex_unlock(&self->display_lock);
    } else {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
    }
}

static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE(
    "sink", GST_PAD_SINK, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)GRAY8"));
static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE(
    "src", GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)GRAY8"));

/* Five columns, seven rows. Only characters used by the status line. */
static void glyph(char c, unsigned char out[7]) {
    rk_glyph5x7(c, out);
}

static gboolean set_caps(GstBaseTransform *base, GstCaps *in, GstCaps *out) {
    (void)out;
    return gst_video_info_from_caps(&((GstRkStatusAi *)base)->info, in);
}

static void update_ai_fps(GstRkStatusAi *self, gint64 now) {
    if(self->boxes_shared) {
        uint32_t before = __atomic_load_n(&self->boxes_shared->seq,
                                           __ATOMIC_ACQUIRE);
        if(!(before & 1u)) {
            AiHeader state;
            memcpy(&state, self->boxes_shared, sizeof(state));
            __atomic_thread_fence(__ATOMIC_ACQUIRE);
            uint32_t after = __atomic_load_n(&self->boxes_shared->seq,
                                              __ATOMIC_ACQUIRE);
            if(before == after && state.magic == BOX_MAGIC &&
               state.updated_us <= (uint64_t)now &&
               (uint64_t)now - state.updated_us <= 1000000u &&
               state.seq != self->last_ai_seq) {
                uint32_t steps = (state.seq - self->last_ai_seq) / 2u;
                if(self->last_ai_us && state.updated_us > self->last_ai_us &&
                   steps > 0 && steps < 100) {
                    double instant = (double)steps * G_USEC_PER_SEC /
                                     (double)(state.updated_us - self->last_ai_us);
                    if(instant <= 100.0)
                        self->yolo_fps = self->yolo_fps == 0.0 ? instant :
                            self->yolo_fps * 0.7 + instant * 0.3;
                }
                self->last_ai_seq = state.seq;
                self->last_ai_us = state.updated_us;
            }
        }
    }
    if(self->last_ai_us && (uint64_t)now - self->last_ai_us > 1000000u)
        self->yolo_fps = 0.0;
}

static void draw_text(unsigned char *data, int stride, int width, int height,
                      int x0, int y0, const char *label) {
    const int scale = 3;
    for(const char *p = label; *p && x0 + 15 <= width; ++p, x0 += 18) {
        unsigned char rows[7];
        glyph(*p, rows);
        for(int gy = 0; gy < 7; ++gy) {
            if(!rows[gy]) continue;
            for(int sy = 0; sy < scale; ++sy) {
                int y = y0 + gy*scale + sy;
                if(y >= height) continue;
                unsigned char *pixel = data + y*stride + x0;
                for(int gx = 0; gx < 5; ++gx)
                    if(rows[gy] & (1u << (4-gx))) {
                        int x = gx*scale;
                        pixel[x] = pixel[x+1] = pixel[x+2] = 255;
                    }
            }
        }
    }
}

static void shade_panel(unsigned char *data, int stride,
                        int x1, int x2, int y1, int y2) {
    for(int y = y1; y < y2; ++y) {
        unsigned char *row = data + y*stride;
        for(int x = x1; x < x2; ++x)
            row[x] = (unsigned char)((row[x] + 24u) / 2u);
    }
}

static GstFlowReturn transform_ip(GstBaseTransform *base, GstBuffer *buffer) {
    GstRkStatusAi *self = (GstRkStatusAi *)base;
    gint64 now = g_get_monotonic_time();
    g_mutex_lock(&self->display_lock);
    double display_fps = self->display_fps;
    g_mutex_unlock(&self->display_lock);
    update_ai_fps(self, now);
    if(self->second_start == 0) self->second_start = now;
    self->frames_this_second++;
    if(now - self->second_start >= G_USEC_PER_SEC) {
        self->fps = (double)self->frames_this_second * G_USEC_PER_SEC /
                    (double)(now - self->second_start);
        self->frames_this_second = 0;
        self->second_start = now;
        if(self->bar != MAP_FAILED) {
            volatile const uint32_t *regs = (volatile const uint32_t *)self->bar;
            uint32_t applied = regs[0xf8 / 4];
            self->quality_valid = (regs[0xfc / 4] == CONTROL_ABI) &&
                                  ((applied & 0x80u) != 0);
            self->quality = applied & 0x7fu;
        }
        if(self->quality_valid)
            g_print("HDMI stage FPS:%.1f display FPS:%.1f QF:%u YOLO FPS:%.1f\n",
                    self->fps, display_fps, self->quality, self->yolo_fps);
        else
            g_print("HDMI stage FPS:%.1f display FPS:%.1f YOLO FPS:%.1f\n",
                    self->fps, display_fps, self->yolo_fps);
    }

    GstVideoFrame frame;
    gint64 map_started = g_get_monotonic_time();
    if(!gst_video_frame_map(&frame, &self->info, buffer, GST_MAP_READWRITE))
        return GST_FLOW_ERROR;
    gint64 panel_started = g_get_monotonic_time();
    unsigned char *data = GST_VIDEO_FRAME_PLANE_DATA(&frame, 0);
    int stride = GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0);
    int width = GST_VIDEO_FRAME_WIDTH(&frame);
    int height = GST_VIDEO_FRAME_HEIGHT(&frame);
    if(width >= 600 && height >= 120) {
        char line1[80], line2[40], line3[64];
        char fps_text[16];
        if(display_fps >= 0)
            snprintf(fps_text, sizeof(fps_text), "%.1f", display_fps);
        else
            snprintf(fps_text, sizeof(fps_text), "--.-");
        static const char *modes[] = {"GRAY", "GAUSS", "CLAHE", "GAUSS+CLAHE",
                                     "SOBEL", "BLACKHAT", "SOBEL+CLAHE", "BLACKHAT+CLAHE"};
        unsigned mode = 0;
        int mode_valid = 0;
        if(self->bar != MAP_FAILED) {
            volatile const uint32_t *regs = self->bar;
            uint32_t tag = regs[0xac / 4];
            mode = regs[0x100 / 4];
            mode_valid = (tag == 0x45485032u && mode < 8) ||
                         (tag == 0x45485031u && mode < 6) ||
                         (tag == 0x434c4831u && mode < 4);
        }
        if(self->quality_valid)
            snprintf(line1, sizeof(line1), "HDMI 1920x1080 FPS:%s QF:%u",
                     fps_text, self->quality);
        else
            snprintf(line1, sizeof(line1), "HDMI 1920x1080 FPS:%s", fps_text);
        snprintf(line2, sizeof(line2), "YOLO FPS:%.1f", self->yolo_fps);
        snprintf(line3, sizeof(line3), "PREPROC:%s", mode_valid ? modes[mode] : "UNKNOWN");
        int panel_right = 36 + (int)strlen(line1) * 18;
        if(panel_right > width - 16) panel_right = width - 16;
        /* Blend only the small status region with a dark background. */
        gint64 blend_started = g_get_monotonic_time();
        shade_panel(data, stride, 16, panel_right, 16, 117);
        gint64 text_started = g_get_monotonic_time();
        draw_text(data, stride, width, height, 26, 24, line1);
        draw_text(data, stride, width, height, 26, 55, line2);
        draw_text(data, stride, width, height, 26, 86, line3);
        self->shade_us += (uint64_t)(text_started - blend_started);
        self->text_us += (uint64_t)(g_get_monotonic_time() - text_started);
    }
    gint64 unmap_started = g_get_monotonic_time();
    gst_video_frame_unmap(&frame);
    gint64 unmap_finished = g_get_monotonic_time();
    self->frames++;
    self->map_us += (uint64_t)(panel_started - map_started);
    self->panel_us += (uint64_t)(unmap_started - panel_started);
    self->unmap_us += (uint64_t)(unmap_finished - unmap_started);
    if(self->frames % 300 == 0)
        g_print("AI status OSD frames=%lu map=%.1f panel=%.1f shade=%.1f text=%.1f unmap=%.1f us\n",
                (unsigned long)self->frames,
                (double)self->map_us / self->frames,
                (double)self->panel_us / self->frames,
                (double)self->shade_us / self->frames,
                (double)self->text_us / self->frames,
                (double)self->unmap_us / self->frames);
    return GST_FLOW_OK;
}

static void gst_rk_status_ai_finalize(GObject *object);

static void gst_rk_status_ai_class_init(GstRkStatusAiClass *klass) {
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    GstElementClass *element = GST_ELEMENT_CLASS(klass);
    GstBaseTransformClass *transform = GST_BASE_TRANSFORM_CLASS(klass);
    gst_element_class_set_static_metadata(element, "RK HDMI and YOLO status OSD",
        "Filter/Effect/Video", "Semi-transparent GRAY8 status overlay", "Codex");
    gst_element_class_add_static_pad_template(element, &sink_template);
    gst_element_class_add_static_pad_template(element, &src_template);
    transform->set_caps = set_caps;
    transform->transform_ip = transform_ip;
    object_class->set_property = set_property;
    object_class->get_property = get_property;
    g_object_class_install_property(object_class, PROP_DISPLAY_FPS,
        g_param_spec_double("display-fps", "Displayed FPS",
            "Latest one-second frame rate measured at the presentation sink",
            -1.0, 1000.0, -1.0, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
    object_class->finalize = gst_rk_status_ai_finalize;
}

static void gst_rk_status_ai_init(GstRkStatusAi *self) {
    self->second_start = 0;
    self->frames_this_second = 0;
    self->fps = 0;
    g_mutex_init(&self->display_lock);
    self->display_fps = -1;
    self->bar_fd = open(BAR_PATH, O_RDWR | O_SYNC);
    self->bar = self->bar_fd >= 0 ? mmap(NULL, 4096, PROT_READ | PROT_WRITE,
                                         MAP_SHARED, self->bar_fd, 0) : MAP_FAILED;
    self->quality_valid = FALSE;
    const char *boxes_path = g_getenv("RK_AI_BOX_PATH");
    if(!boxes_path || !*boxes_path) boxes_path = BOX_PATH;
    self->boxes_fd = open(boxes_path, O_RDONLY);
    self->boxes_shared = self->boxes_fd >= 0 ?
        mmap(NULL, sizeof(AiHeader), PROT_READ, MAP_SHARED, self->boxes_fd, 0) :
        MAP_FAILED;
    if(self->boxes_shared == MAP_FAILED) self->boxes_shared = NULL;
    self->last_ai_seq = 0;
    self->last_ai_us = 0;
    self->yolo_fps = 0.0;
    gst_base_transform_set_in_place(GST_BASE_TRANSFORM(self), TRUE);
}

static void gst_rk_status_ai_finalize(GObject *object) {
    GstRkStatusAi *self = (GstRkStatusAi *)object;
    g_mutex_clear(&self->display_lock);
    if(self->bar != MAP_FAILED) munmap(self->bar, 4096);
    if(self->bar_fd >= 0) close(self->bar_fd);
    if(self->boxes_shared) munmap((void *)self->boxes_shared, sizeof(AiHeader));
    if(self->boxes_fd >= 0) close(self->boxes_fd);
    G_OBJECT_CLASS(gst_rk_status_ai_parent_class)->finalize(object);
}

static gboolean plugin_init(GstPlugin *plugin) {
    return gst_element_register(plugin, "rkstatusai", GST_RANK_NONE,
                                gst_rk_status_ai_get_type());
}

GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, rkstatusai,
                  "RK HDMI and YOLO status overlay", plugin_init, "1.0",
                  "LGPL", "rkstatusai", "local")
