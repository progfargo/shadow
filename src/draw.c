/* Drawing on an LVGL canvas: lines, circles, rectangles, triangles and text.
 * The LVGL draw descriptors contain bit fields, which translate-c turns into
 * opaque types, so the drawing goes through these small C functions.
 * Coordinates are canvas pixels (floats); colors are 0xRRGGBB. */
#include "lvgl.h"
#include "src/widgets/canvas/lv_canvas_private.h"

static lv_layer_t layer;
static lv_obj_t * layer_canvas;

/* Starts drawing on a canvas; end with shadow_layer_end. */
void shadow_layer_begin(lv_obj_t * canvas)
{
    layer_canvas = canvas;
    lv_canvas_init_layer(canvas, &layer);
}

/* Finishes the drawing (waits until it is done). */
void shadow_layer_end(void)
{
    lv_canvas_finish_layer(layer_canvas, &layer);
    layer_canvas = NULL;
}

void shadow_line(float x1, float y1, float x2, float y2, float width, uint32_t rgb, uint8_t opa,
                 int32_t dash, int32_t gap, bool round)
{
    lv_draw_line_dsc_t d;
    lv_draw_line_dsc_init(&d);
    d.p1.x = x1;
    d.p1.y = y1;
    d.p2.x = x2;
    d.p2.y = y2;
    d.width = width < 1 ? 1 : (int32_t)(width + 0.5f);
    d.color = lv_color_hex(rgb);
    d.opa = opa;
    d.dash_width = dash;
    d.dash_gap = gap;
    d.round_start = round;
    d.round_end = round;
    lv_draw_line(&layer, &d);
}

/* A circle: filled (fill_opa > 0) and/or outlined (border_w > 0). */
void shadow_circle(float cx, float cy, float r, uint32_t fill, uint8_t fill_opa, uint32_t border, uint8_t border_opa,
                   float border_w)
{
    if (r < 0.5f) r = 0.5f;
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.radius = LV_RADIUS_CIRCLE;
    d.bg_color = lv_color_hex(fill);
    d.bg_opa = fill_opa;
    d.border_color = lv_color_hex(border);
    d.border_opa = border_w > 0 ? border_opa : LV_OPA_TRANSP;
    d.border_width = border_w > 0 && border_w < 1 ? 1 : (int32_t)(border_w + 0.5f);
    lv_area_t a = { (int32_t)(cx - r + 0.5f), (int32_t)(cy - r + 0.5f), (int32_t)(cx + r + 0.5f) - 1,
                    (int32_t)(cy + r + 0.5f) - 1 };
    lv_draw_rect(&layer, &d, &a);
}

/* An arc of a circle outline from start to end degrees (0 = right, clockwise). */
void shadow_arc(float cx, float cy, float r, float width, float start, float end, uint32_t rgb, uint8_t opa)
{
    lv_draw_arc_dsc_t d;
    lv_draw_arc_dsc_init(&d);
    d.center.x = (int32_t)(cx + 0.5f);
    d.center.y = (int32_t)(cy + 0.5f);
    d.radius = (uint16_t)(r + width / 2 + 0.5f);
    d.width = width < 1 ? 1 : (int32_t)(width + 0.5f);
    d.start_angle = start;
    d.end_angle = end;
    d.color = lv_color_hex(rgb);
    d.opa = opa;
    lv_draw_arc(&layer, &d);
}

void shadow_rect(float x, float y, float w, float h, uint32_t fill, uint8_t fill_opa, uint32_t border, uint8_t border_opa,
                 float border_w)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.radius = 0;
    d.bg_color = lv_color_hex(fill);
    d.bg_opa = fill_opa;
    d.border_color = lv_color_hex(border);
    d.border_opa = border_w > 0 ? border_opa : LV_OPA_TRANSP;
    d.border_width = border_w > 0 && border_w < 1 ? 1 : (int32_t)(border_w + 0.5f);
    lv_area_t a = { (int32_t)(x + 0.5f), (int32_t)(y + 0.5f), (int32_t)(x + w + 0.5f) - 1, (int32_t)(y + h + 0.5f) - 1 };
    if (a.x2 < a.x1) a.x2 = a.x1;
    if (a.y2 < a.y1) a.y2 = a.y1;
    lv_draw_rect(&layer, &d, &a);
}

void shadow_triangle(float x1, float y1, float x2, float y2, float x3, float y3, uint32_t rgb, uint8_t opa)
{
    lv_draw_triangle_dsc_t d;
    lv_draw_triangle_dsc_init(&d);
    d.p[0].x = x1;
    d.p[0].y = y1;
    d.p[1].x = x2;
    d.p[1].y = y2;
    d.p[2].x = x3;
    d.p[2].y = y3;
    d.color = lv_color_hex(rgb);
    d.opa = opa;
    lv_draw_triangle(&layer, &d);
}

/* Text with its anchor at (x, y): align 0 = start, 1 = middle, 2 = end;
 * valign 0 = y is the baseline, 1 = y is the middle of the line.
 * rot is degrees clockwise around the anchor (only 0 and ±90 are used). */
void shadow_text(float x, float y, const char * text, const lv_font_t * font, uint32_t rgb, uint8_t opa, int align,
                 int valign, float rot)
{
    lv_draw_label_dsc_t d;
    lv_draw_label_dsc_init(&d);
    d.text = text;
    d.font = font;
    d.color = lv_color_hex(rgb);
    d.opa = opa;
    d.align = align == 1 ? LV_TEXT_ALIGN_CENTER : align == 2 ? LV_TEXT_ALIGN_RIGHT : LV_TEXT_ALIGN_LEFT;

    int32_t line_h = lv_font_get_line_height(font);
    int32_t ascent = line_h - font->base_line;
    int32_t top = valign == 1 ? (int32_t)(y - line_h / 2.0f + 0.5f) : (int32_t)(y - ascent + 0.5f);
    lv_point_t size;
    lv_text_get_size(&size, text, font, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
    int32_t left = (int32_t)(x + 0.5f);
    if (align == 1) left = (int32_t)(x - size.x / 2.0f + 0.5f);
    if (align == 2) left = (int32_t)(x - size.x + 0.5f);
    lv_area_t a = { left, top, left + size.x, top + line_h - 1 };
    if (rot != 0) d.rotation = (int32_t)(rot * 10);
    lv_draw_label(&layer, &d, &a);
}

/* Fills the whole canvas with one color. */
void shadow_canvas_fill(lv_obj_t * canvas, uint32_t rgb)
{
    lv_canvas_fill_bg(canvas, lv_color_hex(rgb), LV_OPA_COVER);
}

/* Detaches the buffer before the canvas is deleted. LVGL 9.6's canvas
 * destructor passes the address of its buffer pointer to the image cache,
 * which logs "invalid magic"; with no buffer it skips that. */
void shadow_canvas_detach(lv_obj_t * canvas)
{
    ((lv_canvas_t *)canvas)->draw_buf = NULL;
}
