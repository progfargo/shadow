//! Look of the app: colors, scale, fonts and small widget helpers shared by
//! the screens.

const std = @import("std");
const lv = @import("lvgl");

// src/lv_helpers.c
extern fn shadow_font_set_fallback(font: ?*lv.lv_font_t, fallback: ?*const lv.lv_font_t) void;

pub const color_primary = 0x5B6EF5;
pub const color_danger = 0xD84315;
pub const color_warning_bg = 0xFFF4E0;
pub const color_warning = 0x8A5300;
pub const color_text = 0x212121;
pub const color_muted = 0x6B6B6B;
pub const color_bg = 0xF2F4F7;
pub const color_menu_active = 0xE8EBFE;
/// Dark background of the drawings (wall, table)
pub const color_stage = 0x2B2722;

pub var scale: f32 = 1.0;

/// 1x pixels -> screen pixels
pub fn dp(v: i32) i32 {
    if (v == 0) return 0;
    const s: i32 = @max(1, @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(@abs(v))) * scale))));
    return if (v < 0) -s else s;
}

pub fn dpf(v: f32) f32 {
    return v * scale;
}

const font_regular_data = @embedFile("font_regular");
const font_semibold_data = @embedFile("font_semibold");
const font_icons_data = @embedFile("font_icons");

pub var font_normal: ?*lv.lv_font_t = null;
pub var font_small: ?*lv.lv_font_t = null;
pub var font_bold: ?*lv.lv_font_t = null;
pub var font_title: ?*lv.lv_font_t = null;
var icon_fonts: [4]?*lv.lv_font_t = @splat(null);

fn makeFont(data: []const u8, size: i32, icon_slot: usize) ?*lv.lv_font_t {
    const px = dp(size);
    const f = lv.lv_tiny_ttf_create_data(data.ptr, data.len, px);
    const icons = lv.lv_tiny_ttf_create_data(font_icons_data.ptr, font_icons_data.len, px);
    icon_fonts[icon_slot] = icons;
    shadow_font_set_fallback(f, icons);
    return f;
}

pub fn createFonts() !void {
    font_normal = makeFont(font_regular_data, 15, 0);
    font_small = makeFont(font_regular_data, 13, 1);
    font_bold = makeFont(font_semibold_data, 15, 2);
    font_title = makeFont(font_semibold_data, 19, 3);
    if (font_normal == null or font_small == null or font_bold == null or font_title == null)
        return error.FontLoadFailed;
}

pub fn destroyFonts() void {
    for ([_]*?*lv.lv_font_t{ &font_normal, &font_small, &font_bold, &font_title }) |f| {
        if (f.*) |ff| lv.lv_tiny_ttf_destroy(ff);
        f.* = null;
    }
    for (&icon_fonts) |*f| {
        if (f.*) |ff| lv.lv_tiny_ttf_destroy(ff);
        f.* = null;
    }
}

/// A font of any pixel size (drawing labels); free with `freeFont`.
pub fn fontOfSize(px: i32, bold_face: bool) ?*lv.lv_font_t {
    const data = if (bold_face) font_semibold_data else font_regular_data;
    return lv.lv_tiny_ttf_create_data(data.ptr, data.len, @max(4, px));
}

pub fn freeFont(f: ?*lv.lv_font_t) void {
    if (f) |ff| lv.lv_tiny_ttf_destroy(ff);
}

// ---------------------------------------------------------------------------
// Temporary strings for one screen build

pub var frame_arena: std.heap.ArenaAllocator = undefined;

/// Formats into the frame arena as a C string.
pub fn zfmt(comptime fmt: []const u8, args: anytype) [*:0]const u8 {
    return (std.fmt.allocPrintSentinel(frame_arena.allocator(), fmt, args, 0) catch return "").ptr;
}

// ---------------------------------------------------------------------------
// Widget helpers

pub fn box(parent: ?*lv.lv_obj_t, flow: lv.lv_flex_flow_t) ?*lv.lv_obj_t {
    const b = lv.lv_obj_create(parent);
    lv.lv_obj_remove_style_all(b);
    lv.lv_obj_set_size(b, lv.lv_pct(100), lv.LV_SIZE_CONTENT);
    lv.lv_obj_set_flex_flow(b, flow);
    lv.lv_obj_set_flex_align(b, lv.LV_FLEX_ALIGN_START, lv.LV_FLEX_ALIGN_CENTER, lv.LV_FLEX_ALIGN_CENTER);
    lv.lv_obj_set_style_pad_column(b, dp(8), 0);
    lv.lv_obj_set_style_pad_row(b, dp(6), 0);
    lv.lv_obj_set_scrollable(b, false);
    return b;
}

pub fn spacer(parent: ?*lv.lv_obj_t) void {
    const s = lv.lv_obj_create(parent);
    lv.lv_obj_remove_style_all(s);
    lv.lv_obj_set_size(s, 1, 1);
    lv.lv_obj_set_flex_grow(s, 1);
}

pub fn card(parent: ?*lv.lv_obj_t) ?*lv.lv_obj_t {
    const c = lv.lv_obj_create(parent);
    lv.lv_obj_set_flex_flow(c, lv.LV_FLEX_FLOW_COLUMN);
    lv.lv_obj_set_style_pad_all(c, dp(14), 0);
    lv.lv_obj_set_style_pad_row(c, dp(10), 0);
    lv.lv_obj_set_style_radius(c, dp(10), 0);
    lv.lv_obj_set_style_border_width(c, 0, 0);
    lv.lv_obj_set_style_shadow_width(c, dp(14), 0);
    lv.lv_obj_set_style_shadow_offset_y(c, dp(2), 0);
    lv.lv_obj_set_style_shadow_opa(c, lv.LV_OPA_10, 0);
    lv.lv_obj_set_scrollable(c, false);
    return c;
}

pub fn label(parent: ?*lv.lv_obj_t, s: [*:0]const u8) ?*lv.lv_obj_t {
    const l = lv.lv_label_create(parent);
    lv.lv_label_set_text(l, s);
    lv.lv_label_set_long_mode(l, lv.LV_LABEL_LONG_MODE_WRAP);
    lv.lv_obj_set_width(l, lv.lv_pct(100));
    return l;
}

pub fn title(parent: ?*lv.lv_obj_t, s: [*:0]const u8) ?*lv.lv_obj_t {
    const l = label(parent, s);
    lv.lv_obj_set_style_text_font(l, font_title, 0);
    lv.lv_obj_set_style_text_color(l, lv.lv_color_hex(color_text), 0);
    return l;
}

pub fn bold(parent: ?*lv.lv_obj_t, s: [*:0]const u8) ?*lv.lv_obj_t {
    const l = label(parent, s);
    lv.lv_obj_set_style_text_font(l, font_bold, 0);
    return l;
}

pub fn muted(parent: ?*lv.lv_obj_t, s: [*:0]const u8) ?*lv.lv_obj_t {
    const l = label(parent, s);
    lv.lv_obj_set_style_text_font(l, font_small, 0);
    lv.lv_obj_set_style_text_color(l, lv.lv_color_hex(color_muted), 0);
    return l;
}

pub fn button(parent: ?*lv.lv_obj_t, s: [*:0]const u8, cb: lv.lv_event_cb_t, user_data: ?*anyopaque) ?*lv.lv_obj_t {
    const b = lv.lv_button_create(parent);
    const l = lv.lv_label_create(b);
    lv.lv_label_set_text(l, s);
    lv.lv_obj_center(l);
    lv.lv_obj_set_style_radius(b, dp(8), 0);
    lv.lv_obj_set_style_pad_hor(b, dp(14), 0);
    lv.lv_obj_set_style_pad_ver(b, dp(8), 0);
    lv.lv_obj_set_style_shadow_width(b, 0, 0);
    _ = lv.lv_obj_add_event_cb(b, cb, lv.LV_EVENT_CLICKED, user_data);
    return b;
}

pub fn outlineButton(parent: ?*lv.lv_obj_t, s: [*:0]const u8, cb: lv.lv_event_cb_t, user_data: ?*anyopaque) ?*lv.lv_obj_t {
    const b = button(parent, s, cb, user_data);
    const color = lv.lv_color_hex(color_primary);
    lv.lv_obj_set_style_bg_color(b, lv.lv_color_white(), 0);
    lv.lv_obj_set_style_border_color(b, color, 0);
    lv.lv_obj_set_style_border_width(b, dp(1), 0);
    lv.lv_obj_set_style_text_color(b, color, 0);
    return b;
}

/// Small button inside text (e.g. "Apply suggested")
pub fn smallButton(parent: ?*lv.lv_obj_t, s: [*:0]const u8, cb: lv.lv_event_cb_t, user_data: ?*anyopaque) ?*lv.lv_obj_t {
    const b = outlineButton(parent, s, cb, user_data);
    lv.lv_obj_set_style_pad_hor(b, dp(10), 0);
    lv.lv_obj_set_style_pad_ver(b, dp(4), 0);
    lv.lv_obj_set_style_text_font(b, font_small, 0);
    return b;
}

pub fn setEnabled(obj: ?*lv.lv_obj_t, on: bool) void {
    if (on) lv.lv_obj_remove_state(obj, lv.LV_STATE_DISABLED) else lv.lv_obj_add_state(obj, lv.LV_STATE_DISABLED);
}
