#include <stdint.h>
#include <string.h>

void jpeg_weave_1080p(uint8_t *output, const uint8_t *a,
                      const uint8_t *b, const uint8_t *c) {
    const uint8_t *tiles[3] = {a, b, c};
    const size_t stripe_bytes = 1920u * 8u;
    for(size_t stripe = 0; stripe < 135; ++stripe)
        memcpy(output + stripe * stripe_bytes,
               tiles[stripe % 3] + stripe / 3 * stripe_bytes, stripe_bytes);
}
