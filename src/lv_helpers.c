/* Small helpers for LVGL fields Zig cannot reach.
 * lv_font_t and lv_image_header_t contain bit fields, so translate-c turns
 * them into opaque types. */
#include "lvgl.h"

/* Fallback font for characters missing from a TTF font (LV_SYMBOL_* icons) */
void shadow_font_set_fallback(lv_font_t * font, const lv_font_t * fallback)
{
    font->fallback = fallback;
}

/* Is the object a text area? (to start/stop SDL text input) */
bool shadow_is_textarea(const lv_obj_t * obj)
{
    return obj != NULL && lv_obj_check_type(obj, &lv_textarea_class);
}

/* Size and stride of a draw buffer */
void shadow_draw_buf_size(const lv_draw_buf_t * buf, int32_t * w, int32_t * h, uint32_t * stride)
{
    *w = buf->header.w;
    *h = buf->header.h;
    *stride = buf->header.stride;
}
