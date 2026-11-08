/* Picture files: reading any common format with stb_image and writing PNG
 * with stb_image_write. Always built with -O2 (see build.zig): decoding and
 * encoding large pictures is slow at -O0. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#include "stb_image_write.h"

#include <stdlib.h>
#include <string.h>

/* Pictures larger than this (in pixels) are refused */
#define MAX_PIXELS (100u * 1000u * 1000u)

/* Decodes PNG, JPEG, BMP, GIF (first frame), TGA, PSD or PNM data into RGBA
 * (4 bytes per pixel). Returns NULL if the data cannot be decoded. Free the
 * result with shadow_image_free. */
unsigned char * shadow_image_decode(const unsigned char * data, size_t len, int * w, int * h)
{
    int comp;
    if (len > 0x7FFFFFFF) return NULL;
    if (!stbi_info_from_memory(data, (int)len, w, h, &comp)) return NULL;
    if ((unsigned long long)*w * (unsigned long long)*h > MAX_PIXELS) return NULL;
    return stbi_load_from_memory(data, (int)len, w, h, &comp, 4);
}

void shadow_image_free(void * p)
{
    stbi_image_free(p);
}

/* Why the last decode failed (static text) */
const char * shadow_image_error(void)
{
    return stbi_failure_reason();
}

struct buf {
    unsigned char * data;
    size_t len, cap;
};

static void append(void * ctx, void * data, int size)
{
    struct buf * b = ctx;
    if (!b->data && b->cap) return; /* an earlier allocation failed */
    if (b->len + (size_t)size > b->cap) {
        size_t cap = b->cap ? b->cap * 2 : 65536;
        while (cap < b->len + (size_t)size) cap *= 2;
        unsigned char * p = realloc(b->data, cap);
        if (!p) {
            free(b->data);
            b->data = NULL;
            return;
        }
        b->data = p;
        b->cap = cap;
    }
    memcpy(b->data + b->len, data, (size_t)size);
    b->len += (size_t)size;
}

/* Encodes pixels as PNG. comp: 1 = gray, 3 = RGB, 4 = RGBA. Returns NULL on
 * failure; free with shadow_png_free. */
unsigned char * shadow_png_encode(const unsigned char * px, int w, int h, int comp, size_t * out_len)
{
    struct buf b = { 0 };
    stbi_write_png_compression_level = 6;
    if (!stbi_write_png_to_func(append, &b, w, h, comp, px, w * comp) || !b.data) {
        free(b.data);
        return NULL;
    }
    *out_len = b.len;
    return b.data;
}

void shadow_png_free(void * p)
{
    free(p);
}
