/* Small in-place RGBx OSD for the RK HDMI viewer. */
#include <gst/base/gstbasetransform.h>
#include <gst/video/video.h>
#include <stdio.h>
#include <string.h>

#define PACKAGE "rkfastosd"

typedef struct {
    GstBaseTransform parent;
    GstVideoInfo info;
    gint64 second_start;
    guint frames_this_second;
    double fps;
} GstRkFastOsd;

typedef struct {
    GstBaseTransformClass parent_class;
} GstRkFastOsdClass;

G_DEFINE_TYPE(GstRkFastOsd, gst_rk_fast_osd, GST_TYPE_BASE_TRANSFORM)

static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE(
    "sink", GST_PAD_SINK, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)RGBx"));
static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE(
    "src", GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=(string)RGBx"));

/* Five columns, seven rows. Only characters used by the status line. */
static void glyph(char c, unsigned char out[7]) {
    static const unsigned char digits[10][7] = {
        {14,17,19,21,25,17,14}, {4,12,4,4,4,4,14},
        {14,17,1,2,4,8,31}, {30,1,1,14,1,1,30},
        {2,6,10,18,31,2,2}, {31,16,16,30,1,1,30},
        {14,16,16,30,17,17,14}, {31,1,2,4,8,8,8},
        {14,17,17,14,17,17,14}, {14,17,17,15,1,1,14}
    };
    if(c >= '0' && c <= '9') {
        memcpy(out, digits[c-'0'], 7);
        return;
    }
    static const unsigned char h[7] = {17,17,17,31,17,17,17};
    static const unsigned char d[7] = {30,17,17,17,17,17,30};
    static const unsigned char m[7] = {17,27,21,21,17,17,17};
    static const unsigned char i[7] = {31,4,4,4,4,4,31};
    static const unsigned char f[7] = {31,16,16,30,16,16,16};
    static const unsigned char p[7] = {30,17,17,30,16,16,16};
    static const unsigned char s[7] = {15,16,16,14,1,1,30};
    static const unsigned char x[7] = {0,17,10,4,10,17,0};
    static const unsigned char colon[7] = {0,4,4,0,4,4,0};
    static const unsigned char point[7] = {0,0,0,0,0,4,4};
    const unsigned char *rows = NULL;
    switch(c) {
    case 'H': rows=h; break; case 'D': rows=d; break;
    case 'M': rows=m; break; case 'I': rows=i; break;
    case 'F': rows=f; break; case 'P': rows=p; break;
    case 'S': rows=s; break; case 'x': rows=x; break;
    case ':': rows=colon; break; case '.': rows=point; break;
    default: memset(out, 0, 7); return;
    }
    memcpy(out, rows, 7);
}

static gboolean set_caps(GstBaseTransform *base, GstCaps *in, GstCaps *out) {
    (void)out;
    return gst_video_info_from_caps(&((GstRkFastOsd *)base)->info, in);
}

static GstFlowReturn transform_ip(GstBaseTransform *base, GstBuffer *buffer) {
    GstRkFastOsd *self = (GstRkFastOsd *)base;
    gint64 now = g_get_monotonic_time();
    if(self->second_start == 0) self->second_start = now;
    self->frames_this_second++;
    if(now - self->second_start >= G_USEC_PER_SEC) {
        self->fps = (double)self->frames_this_second * G_USEC_PER_SEC /
                    (double)(now - self->second_start);
        self->frames_this_second = 0;
        self->second_start = now;
        g_print("HDMI 1920x1080 FPS:%.1f\n", self->fps);
    }

    GstVideoFrame frame;
    if(!gst_video_frame_map(&frame, &self->info, buffer, GST_MAP_READWRITE))
        return GST_FLOW_ERROR;
    unsigned char *data = GST_VIDEO_FRAME_PLANE_DATA(&frame, 0);
    int stride = GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0);
    int width = GST_VIDEO_FRAME_WIDTH(&frame);
    int height = GST_VIDEO_FRAME_HEIGHT(&frame);
    if(width >= 380 && height >= 60) {
        char label[80];
        snprintf(label, sizeof(label), "HDMI 1920x1080 FPS:%.1f", self->fps);
        /* Draw a small opaque panel and 2x white bitmap glyphs. */
        for(int y=16; y<48; ++y) {
            unsigned char *row = data + y*stride + 16*4;
            for(int x=16; x<360; ++x, row+=4) {
                row[0]=16; row[1]=40; row[2]=64; row[3]=255;
            }
        }
        int x0=24;
        for(const char *p=label; *p && x0<350; ++p, x0+=12) {
            unsigned char rows[7];
            glyph(*p, rows);
            for(int gy=0; gy<7; ++gy)
                for(int gx=0; gx<5; ++gx)
                    if(rows[gy] & (1u << (4-gx)))
                        for(int sy=0; sy<2; ++sy)
                            for(int sx=0; sx<2; ++sx) {
                                unsigned char *pixel = data + (24+gy*2+sy)*stride +
                                                       (x0+gx*2+sx)*4;
                                pixel[0]=255; pixel[1]=255; pixel[2]=255;
                                pixel[3]=255;
                            }
        }
    }
    gst_video_frame_unmap(&frame);
    return GST_FLOW_OK;
}

static void gst_rk_fast_osd_class_init(GstRkFastOsdClass *klass) {
    GstElementClass *element = GST_ELEMENT_CLASS(klass);
    GstBaseTransformClass *transform = GST_BASE_TRANSFORM_CLASS(klass);
    gst_element_class_set_static_metadata(element, "RK fast HDMI OSD",
        "Filter/Effect/Video", "In-place 1080p grayscale status overlay", "Codex");
    gst_element_class_add_static_pad_template(element, &sink_template);
    gst_element_class_add_static_pad_template(element, &src_template);
    transform->set_caps = set_caps;
    transform->transform_ip = transform_ip;
}

static void gst_rk_fast_osd_init(GstRkFastOsd *self) {
    self->second_start = 0;
    self->frames_this_second = 0;
    self->fps = 0;
    gst_base_transform_set_in_place(GST_BASE_TRANSFORM(self), TRUE);
}

static gboolean plugin_init(GstPlugin *plugin) {
    return gst_element_register(plugin, "rkfastosd", GST_RANK_NONE,
                                gst_rk_fast_osd_get_type());
}

GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, rkfastosd,
                  "Lightweight RK HDMI status overlay", plugin_init, "1.0",
                  "LGPL", "rkfastosd", "local")
