/* Small ARGB DRM status plane: avoids mapping the 1920x1080 video buffer. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>
#include <drm_mode.h>
#include "rk_font5x7.h"

#define WIDTH 600
#define HEIGHT 124
#define CONNECTOR_ID 188
#define PLANE_ID 165
#define BOX_MAGIC 0x52414942u
#define CONTROL_ABI 0x4a435431u

typedef struct {
    uint32_t magic, seq;
    uint64_t updated_us;
    uint32_t count, reserved;
} AiHeader;
_Static_assert(sizeof(AiHeader) == 24, "AI status ABI mismatch");

typedef struct {
    uint32_t handle, pitch, fb_id;
    uint64_t size;
    uint32_t *pixels;
} Buffer;

static volatile sig_atomic_t stopping;
static void stop_now(int sig) { (void)sig; stopping = 1; }

static uint64_t monotonic_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}

static int create_buffer(int fd, Buffer *b) {
    struct drm_mode_create_dumb create = {0};
    create.width = WIDTH;
    create.height = HEIGHT;
    create.bpp = 32;
    if(ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0) return -1;
    b->handle = create.handle;
    b->pitch = create.pitch;
    b->size = create.size;
    uint32_t handles[4] = {b->handle, 0, 0, 0};
    uint32_t pitches[4] = {b->pitch, 0, 0, 0};
    uint32_t offsets[4] = {0, 0, 0, 0};
    if(drmModeAddFB2(fd, WIDTH, HEIGHT, DRM_FORMAT_ARGB8888, handles,
                     pitches, offsets, &b->fb_id, 0) < 0) return -1;
    struct drm_mode_map_dumb map = {0};
    map.handle = b->handle;
    if(ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) return -1;
    b->pixels = mmap(NULL, b->size, PROT_READ | PROT_WRITE, MAP_SHARED,
                     fd, map.offset);
    return b->pixels == MAP_FAILED ? -1 : 0;
}

static void destroy_buffer(int fd, Buffer *b) {
    if(b->pixels && b->pixels != MAP_FAILED) munmap(b->pixels, b->size);
    if(b->fb_id) drmModeRmFB(fd, b->fb_id);
    if(b->handle) {
        struct drm_mode_destroy_dumb destroy = {.handle = b->handle};
        ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
    }
}

static void draw_text(Buffer *b, int x0, int y0, const char *label) {
    const int scale = 3;
    int stride = (int)b->pitch / 4;
    for(const char *p = label; *p && x0 + 15 <= WIDTH; ++p, x0 += 18) {
        unsigned char rows[7];
        rk_glyph5x7(*p, rows);
        for(int gy = 0; gy < 7; ++gy) {
            for(int gx = 0; gx < 5; ++gx) {
                if(!(rows[gy] & (1u << (4-gx)))) continue;
                for(int sy = 0; sy < scale; ++sy) {
                    int y = y0 + gy*scale + sy;
                    if(y >= HEIGHT) continue;
                    for(int sx = 0; sx < scale; ++sx) {
                        int x = x0 + gx*scale + sx;
                        if(x < WIDTH) b->pixels[y*stride+x] = 0xffffffffu;
                    }
                }
            }
        }
    }
}

static void draw_status(Buffer *b, unsigned quality, int quality_valid,
                        double yolo_fps, unsigned mode, int mode_valid) {
    memset(b->pixels, 0, b->size);
    static const char *names[] = {"GRAY", "GAUSS", "CLAHE", "GAUSS+CLAHE",
        "SOBEL", "BLACKHAT", "SOBEL+CLAHE", "BLACKHAT+CLAHE"};
    char line1[80], line2[40], line3[48];
    if(quality_valid)
        snprintf(line1, sizeof(line1), "HDMI 1920x1080 FPS:60 QF:%u", quality);
    else
        snprintf(line1, sizeof(line1), "HDMI 1920x1080 FPS:60");
    snprintf(line2, sizeof(line2), "YOLO FPS:%.1f", yolo_fps);
    snprintf(line3, sizeof(line3), "PREPROC: %s", mode_valid ? names[mode] : "UNKNOWN");
    int right = 36 + (int)strlen(line1) * 18;
    int right3 = 36 + (int)strlen(line3) * 18;
    if(right3 > right) right = right3;
    if(right > WIDTH) right = WIDTH;
    /* ARGB premultiplied blue at 25% opacity, transparent outside the panel. */
    const uint32_t shade = 0x40041018u;
    int stride = (int)b->pitch / 4;
    for(int y = 16; y < 118; ++y)
        for(int x = 16; x < right; ++x)
            b->pixels[y*stride+x] = shade;
    draw_text(b, 26, 24, line1);
    draw_text(b, 26, 55, line2);
    draw_text(b, 26, 86, line3);
}

/* Optional diagnostic export of the actual status buffer, composited on black.
   Disabled in normal deployment; mode changes only, never per video frame. */
static void dump_status(const Buffer *b, const char *path) {
    char temporary[512];
    if(!path || !*path || strlen(path) > 490) return;
    snprintf(temporary, sizeof(temporary), "%s.tmp", path);
    FILE *out = fopen(temporary, "wb");
    if(!out) return;
    fprintf(out, "P6\n%d %d\n255\n", WIDTH, HEIGHT);
    unsigned char row[WIDTH*3];
    int stride = (int)b->pitch / 4;
    for(int y = 0; y < HEIGHT; ++y) {
        for(int x = 0; x < WIDTH; ++x) {
            uint32_t p = b->pixels[y*stride+x];
            row[x*3] = (p >> 16) & 255;
            row[x*3+1] = (p >> 8) & 255;
            row[x*3+2] = p & 255;
        }
        if(fwrite(row, 1, sizeof(row), out) != sizeof(row)) {
            fclose(out); unlink(temporary); return;
        }
    }
    if(fclose(out) == 0) rename(temporary, path);
}

static void update_yolo_fps(const AiHeader *shared, uint32_t *last_seq,
                            uint64_t *last_us, double *fps) {
    uint64_t now = monotonic_us();
    if(shared) {
        uint32_t before = __atomic_load_n(&shared->seq, __ATOMIC_ACQUIRE);
        if(!(before & 1u)) {
            AiHeader snap;
            memcpy(&snap, shared, sizeof(snap));
            __atomic_thread_fence(__ATOMIC_ACQUIRE);
            uint32_t after = __atomic_load_n(&shared->seq, __ATOMIC_ACQUIRE);
            if(before == after && snap.magic == BOX_MAGIC &&
               snap.updated_us <= now && now - snap.updated_us <= 1000000u &&
               snap.seq != *last_seq) {
                uint32_t steps = (snap.seq - *last_seq) / 2u;
                if(*last_us && snap.updated_us > *last_us &&
                   steps > 0 && steps < 100) {
                    double instant = (double)steps * 1000000.0 /
                                     (double)(snap.updated_us - *last_us);
                    if(instant <= 100.0)
                        *fps = *fps == 0.0 ? instant : *fps * 0.7 + instant * 0.3;
                }
                *last_seq = snap.seq;
                *last_us = snap.updated_us;
            }
        }
    }
    if(*last_us && now - *last_us > 1000000u) *fps = 0.0;
}

int main(int argc, char **argv) {
    unsigned seconds = argc > 1 ? (unsigned)strtoul(argv[1], NULL, 10) : 0;
    signal(SIGINT, stop_now);
    signal(SIGTERM, stop_now);
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if(fd < 0) { perror("open DRM card"); return 1; }
    drmModeConnector *connector = drmModeGetConnector(fd, CONNECTOR_ID);
    if(!connector || connector->connection != DRM_MODE_CONNECTED) {
        fprintf(stderr, "HDMI connector %d unavailable\n", CONNECTOR_ID);
        if(connector) drmModeFreeConnector(connector);
        close(fd);
        return 1;
    }
    drmModeEncoder *encoder = drmModeGetEncoder(fd, connector->encoder_id);
    uint32_t crtc_id = encoder ? encoder->crtc_id : 0;
    drmModeFreeConnector(connector);
    if(encoder) drmModeFreeEncoder(encoder);
    if(!crtc_id) { fprintf(stderr, "No active HDMI CRTC\n"); close(fd); return 1; }

    Buffer buffers[2] = {{0}, {0}};
    if(create_buffer(fd, &buffers[0]) || create_buffer(fd, &buffers[1])) {
        perror("create ARGB DRM buffer");
        destroy_buffer(fd, &buffers[0]);
        destroy_buffer(fd, &buffers[1]);
        close(fd);
        return 1;
    }
    int state_fd = open("/run/road_ai_boxes.bin", O_RDONLY);
    const AiHeader *state = state_fd < 0 ? NULL :
        mmap(NULL, sizeof(AiHeader), PROT_READ, MAP_SHARED, state_fd, 0);
    if(state == MAP_FAILED) state = NULL;
    int bar_fd = open("/sys/bus/pci/devices/0000:21:00.0/resource0",
                      O_RDWR | O_SYNC);
    volatile const uint32_t *bar = bar_fd < 0 ? NULL :
        mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, bar_fd, 0);
    if(bar == MAP_FAILED) bar = NULL;

    uint64_t began = monotonic_us();
    uint32_t last_seq = 0;
    uint64_t last_ai_us = 0;
    double yolo_fps = 0;
    int index = 0, frames = 0, failed = 0;
    unsigned previous_mode = UINT32_MAX;
    int previous_valid = -1;
    const char *snapshot = getenv("RK_STATUS_SNAPSHOT");
    while(!stopping && (!seconds || monotonic_us() - began < (uint64_t)seconds*1000000u)) {
        update_yolo_fps(state, &last_seq, &last_ai_us, &yolo_fps);
        unsigned quality = 0;
        int valid = 0;
        unsigned mode = 0;
        int mode_valid = 0;
        if(bar) {
            uint32_t applied = bar[0xf8 / 4];
            valid = bar[0xfc / 4] == CONTROL_ABI && (applied & 0x80u);
            quality = applied & 0x7fu;
            uint32_t tag = bar[0xac / 4];
            mode = bar[0x100 / 4];
            mode_valid = (tag == 0x45485032u && mode < 8) ||
                         (tag == 0x45485031u && mode < 6) ||
                         (tag == 0x434c4831u && mode < 4);
        }
        draw_status(&buffers[index], quality, valid, yolo_fps, mode, mode_valid);
        if(drmModeSetPlane(fd, PLANE_ID, crtc_id, buffers[index].fb_id, 0,
                           0, 0, WIDTH, HEIGHT, 0, 0,
                           WIDTH << 16, HEIGHT << 16) < 0) {
            perror("set status plane");
            failed = 1;
            break;
        }
        frames++;
        if(mode != previous_mode || mode_valid != previous_valid) {
            printf("DRM status PREPROC applied=%u valid=%d\n", mode, mode_valid);
            dump_status(&buffers[index], snapshot);
            previous_mode = mode;
            previous_valid = mode_valid;
        }
        if(frames % 5 == 0)
            printf("DRM status plane frames=%d YOLO FPS:%.1f QF:%u PREPROC:%u valid:%d\n",
                   frames, yolo_fps, quality, mode, mode_valid);
        fflush(stdout);
        index ^= 1;
        /* One legacy plane commit can displace one video commit. A 1 Hz status
           refresh keeps the counters useful while preserving video cadence. */
        struct timespec delay = {.tv_sec=1, .tv_nsec=0};
        nanosleep(&delay, NULL);
    }
    drmModeSetPlane(fd, PLANE_ID, crtc_id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    if(bar) munmap((void *)bar, 4096);
    if(bar_fd >= 0) close(bar_fd);
    if(state) munmap((void *)state, sizeof(AiHeader));
    if(state_fd >= 0) close(state_fd);
    destroy_buffer(fd, &buffers[0]);
    destroy_buffer(fd, &buffers[1]);
    close(fd);
    return failed;
}
