#include <stddef.h>
#include <stdio.h>
#include <jpeglib.h>
#include <setjmp.h>
#include <string.h>

typedef struct {
    struct jpeg_error_mgr base;
    jmp_buf jump;
    char message[JMSG_LENGTH_MAX];
} DecodeError;

static void failed(j_common_ptr common) {
    DecodeError *error = (DecodeError *)common->err;
    (*common->err->format_message)(common, error->message);
    longjmp(error->jump, 1);
}

int jpeg_decode_gray(const unsigned char *jpeg, size_t size,
                     unsigned char *output, unsigned width, unsigned height,
                     char *message, size_t message_size) {
    struct jpeg_decompress_struct decoder;
    DecodeError error;
    memset(&decoder, 0, sizeof(decoder));
    decoder.err = jpeg_std_error(&error.base);
    error.base.error_exit = failed;
    if(setjmp(error.jump)) {
        snprintf(message, message_size, "%s", error.message);
        jpeg_destroy_decompress(&decoder);
        return -1;
    }
    jpeg_create_decompress(&decoder);
    jpeg_mem_src(&decoder, jpeg, size);
    jpeg_read_header(&decoder, TRUE);
    if(decoder.image_width != width || decoder.image_height != height) {
        snprintf(message, message_size, "unexpected JPEG dimensions %ux%u",
                 decoder.image_width, decoder.image_height);
        jpeg_destroy_decompress(&decoder);
        return -1;
    }
    decoder.out_color_space = JCS_GRAYSCALE;
    decoder.dct_method = JDCT_IFAST;
    jpeg_start_decompress(&decoder);
    if(decoder.output_width != width || decoder.output_height != height ||
       decoder.output_components != 1) {
        snprintf(message, message_size, "unexpected decoded layout");
        jpeg_destroy_decompress(&decoder);
        return -1;
    }
    while(decoder.output_scanline < height) {
        JSAMPROW row = output + (size_t)decoder.output_scanline * width;
        jpeg_read_scanlines(&decoder, &row, 1);
    }
    jpeg_finish_decompress(&decoder);
    jpeg_destroy_decompress(&decoder);
    return 0;
}
