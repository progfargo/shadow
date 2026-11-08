//! A canvas widget with its own pixel buffer: pixels computed in Zig are
//! written straight into it, shapes and labels are drawn over them with the
//! functions of src/draw.c.

const std = @import("std");
const lv = @import("lvgl");

// src/lv_helpers.c and src/draw.c
extern fn shadow_draw_buf_pixels(buf: ?*lv.lv_draw_buf_t, w: *i32, h: *i32, stride: *u32) [*]u8;
extern fn shadow_layer_begin(canvas: ?*lv.lv_obj_t) void;
extern fn shadow_layer_end() void;
extern fn shadow_line(x1: f32, y1: f32, x2: f32, y2: f32, width: f32, rgb: u32, opa: u8, dash: i32, gap: i32, round: bool) void;
extern fn shadow_circle(cx: f32, cy: f32, r: f32, fill: u32, fill_opa: u8, border: u32, border_opa: u8, border_w: f32) void;
extern fn shadow_arc(cx: f32, cy: f32, r: f32, width: f32, start: f32, end: f32, rgb: u32, opa: u8) void;
extern fn shadow_rect(x: f32, y: f32, w: f32, h: f32, fill: u32, fill_opa: u8, border: u32, border_opa: u8, border_w: f32) void;
extern fn shadow_triangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, rgb: u32, opa: u8) void;
extern fn shadow_text(x: f32, y: f32, text: [*:0]const u8, font: ?*const lv.lv_font_t, rgb: u32, opa: u8, alignment: c_int, valign: c_int) void;
extern fn shadow_text_metrics(text: [*:0]const u8, font: ?*const lv.lv_font_t, width: *i32, line_h: *i32, ascent: *i32) void;
extern fn shadow_canvas_fill(canvas: ?*lv.lv_obj_t, rgb: u32) void;
extern fn shadow_canvas_detach(canvas: ?*lv.lv_obj_t) void;

pub const Canvas = struct {
    obj: ?*lv.lv_obj_t = null,
    buf: ?*lv.lv_draw_buf_t = null,
    w: i32 = 0,
    h: i32 = 0,

    /// A canvas of w x h pixels under `parent`.
    pub fn create(parent: ?*lv.lv_obj_t, w: i32, h: i32) !Canvas {
        var c: Canvas = .{ .obj = lv.lv_canvas_create(parent) };
        errdefer lv.lv_obj_delete(c.obj);
        try c.resize(w, h);
        return c;
    }

    /// Gives the canvas a new buffer of w x h pixels (the content is lost).
    pub fn resize(c: *Canvas, w: i32, h: i32) !void {
        const ww = @max(1, w);
        const hh = @max(1, h);
        if (c.buf != null and ww == c.w and hh == c.h) return;
        const nb = lv.lv_draw_buf_create(@intCast(ww), @intCast(hh), lv.LV_COLOR_FORMAT_XRGB8888, lv.LV_STRIDE_AUTO) orelse return error.OutOfMemory;
        lv.lv_canvas_set_draw_buf(c.obj, nb);
        if (c.buf) |old| lv.lv_draw_buf_destroy(old);
        c.buf = nb;
        c.w = ww;
        c.h = hh;
    }

    /// Deletes the widget and its buffer.
    pub fn destroy(c: *Canvas) void {
        if (c.obj) |o| {
            shadow_canvas_detach(o);
            lv.lv_obj_delete(o);
        }
        if (c.buf) |b| lv.lv_draw_buf_destroy(b);
        c.* = .{};
    }

    /// Frees only the buffer (the widget was deleted with its parent).
    pub fn forget(c: *Canvas) void {
        if (c.buf) |b| lv.lv_draw_buf_destroy(b);
        c.* = .{};
    }

    /// The pixels as 0xXXRRGGBB, row by row; `stride` is in pixels.
    pub fn pixels(c: *const Canvas) struct { px: []u32, stride: usize } {
        var w: i32 = 0;
        var h: i32 = 0;
        var stride: u32 = 0;
        const p = shadow_draw_buf_pixels(c.buf, &w, &h, &stride);
        const s = stride / 4;
        const px: [*]u32 = @ptrCast(@alignCast(p));
        return .{ .px = px[0 .. s * @as(usize, @intCast(h))], .stride = s };
    }

    /// Tells LVGL the pixels changed.
    pub fn invalidate(c: *const Canvas) void {
        _ = lv.lv_obj_invalidate(c.obj);
    }

    pub fn fill(c: *const Canvas, color: u32) void {
        shadow_canvas_fill(c.obj, color);
    }

    /// Draws shapes over the pixels: call the drawing functions below, then `end`.
    pub fn begin(c: *const Canvas) void {
        shadow_layer_begin(c.obj);
    }

    pub fn end(_: *const Canvas) void {
        shadow_layer_end();
    }
};

pub fn rgb(r: u8, g: u8, b: u8) u32 {
    return @as(u32, r) << 16 | @as(u32, g) << 8 | b;
}

pub fn pixel(r: f64, g: f64, b: f64) u32 {
    const R: u32 = @intFromFloat(std.math.clamp(r, 0, 255));
    const G: u32 = @intFromFloat(std.math.clamp(g, 0, 255));
    const B: u32 = @intFromFloat(std.math.clamp(b, 0, 255));
    return 0xFF000000 | R << 16 | G << 8 | B;
}

fn f(v: f64) f32 {
    return @floatCast(v);
}

pub fn line(x1: f64, y1: f64, x2: f64, y2: f64, width: f64, color: u32, opa: u8) void {
    shadow_line(f(x1), f(y1), f(x2), f(y2), f(width), color, opa, 0, 0, false);
}

pub fn roundLine(x1: f64, y1: f64, x2: f64, y2: f64, width: f64, color: u32, opa: u8) void {
    shadow_line(f(x1), f(y1), f(x2), f(y2), f(width), color, opa, 0, 0, true);
}

pub fn dashedLine(x1: f64, y1: f64, x2: f64, y2: f64, width: f64, color: u32, dash: i32, gap: i32) void {
    shadow_line(f(x1), f(y1), f(x2), f(y2), f(width), color, 255, dash, gap, false);
}

pub fn fillCircle(cx: f64, cy: f64, r: f64, color: u32, opa: u8) void {
    shadow_circle(f(cx), f(cy), f(r), color, opa, 0, 0, 0);
}

/// A circle outline centered on radius r
pub fn strokeCircle(cx: f64, cy: f64, r: f64, width: f64, color: u32, opa: u8) void {
    shadow_arc(f(cx), f(cy), f(r), f(width), 0, 360, color, opa);
}

/// A filled circle with an outline centered on its edge (like a canvas fill + stroke)
pub fn circle(cx: f64, cy: f64, r: f64, fill_color: u32, fill_opa: u8, stroke: u32, width: f64) void {
    shadow_circle(f(cx), f(cy), f(r), fill_color, fill_opa, 0, 0, 0);
    if (width > 0) strokeCircle(cx, cy, r, width, stroke, 255);
}

/// A dashed circle outline (dash and gap in pixels along the circle)
pub fn dashedCircle(cx: f64, cy: f64, r: f64, width: f64, color: u32, dash: f64, gap: f64) void {
    if (r <= 0 or !std.math.isFinite(r)) return;
    const circ = 2 * std.math.pi * r;
    const n = @max(4, @floor(circ / (dash + gap)));
    const step = 360 / n;
    const on = step * dash / (dash + gap);
    var a: f64 = 0;
    while (a < 360 - 1e-6) : (a += step) {
        shadow_arc(f(cx), f(cy), f(r), f(width), f(a), f(a + on), color, 255);
    }
}

pub fn rect(x: f64, y: f64, w: f64, h: f64, color: u32, opa: u8) void {
    shadow_rect(f(x), f(y), f(w), f(h), color, opa, 0, 0, 0);
}

pub fn strokeRect(x: f64, y: f64, w: f64, h: f64, color: u32, width: f64) void {
    shadow_rect(f(x), f(y), f(w), f(h), 0, 0, color, 255, f(width));
}

pub fn triangle(x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64, color: u32, opa: u8) void {
    shadow_triangle(f(x1), f(y1), f(x2), f(y2), f(x3), f(y3), color, opa);
}

pub const Align = enum(c_int) { start = 0, middle = 1, end = 2 };

/// Text with its baseline at y
pub fn text(x: f64, y: f64, s: [*:0]const u8, font: ?*const lv.lv_font_t, color: u32, alignment: Align) void {
    shadow_text(f(x), f(y), s, font, color, 255, @intFromEnum(alignment), 0);
}

/// Text centered vertically on y
pub fn textMiddle(x: f64, y: f64, s: [*:0]const u8, font: ?*const lv.lv_font_t, color: u32, alignment: Align) void {
    shadow_text(f(x), f(y), s, font, color, 255, @intFromEnum(alignment), 1);
}

/// Text with its baseline at y, turned a quarter turn counterclockwise
/// around (x, y) so it reads upward (SVG rotate(-90)). Call outside
/// begin/end: it draws the text flat on a small canvas and blends the turned
/// pixels into `c`.
pub fn textUpward(c: *const Canvas, x: f64, y: f64, s: [*:0]const u8, font: ?*const lv.lv_font_t, color: u32, alignment: Align) !void {
    var tw: i32 = 0;
    var lh: i32 = 0;
    var asc: i32 = 0;
    shadow_text_metrics(s, font, &tw, &lh, &asc);
    var tmp = try Canvas.create(lv.lv_layer_sys(), tw + 2, lh);
    defer tmp.destroy();
    lv.lv_obj_set_hidden(tmp.obj, true);
    tmp.fill(0xFFFFFF);
    tmp.begin();
    text(1, @floatFromInt(asc), s, font, 0x000000, .start);
    tmp.end();

    const anchor: f64 = switch (alignment) {
        .start => 1,
        .middle => @as(f64, @floatFromInt(tw)) / 2 + 1,
        .end => @as(f64, @floatFromInt(tw)) + 1,
    };
    const src = tmp.pixels();
    const dst = c.pixels();
    const cr: f64 = @floatFromInt(color >> 16 & 0xFF);
    const cg: f64 = @floatFromInt(color >> 8 & 0xFF);
    const cb: f64 = @floatFromInt(color & 0xFF);
    for (0..@intCast(lh)) |v| for (0..@intCast(tmp.w)) |u| {
        const cover = 255 - (src.px[v * src.stride + u] & 0xFF); // black text on white
        if (cover == 0) continue;
        // flat (u, v) -> turned: along the text goes up, above the baseline goes left
        const tx: i64 = @intFromFloat(@round(x + @as(f64, @floatFromInt(v)) - @as(f64, @floatFromInt(asc))));
        const ty: i64 = @intFromFloat(@round(y - (@as(f64, @floatFromInt(u)) - anchor)));
        if (tx < 0 or ty < 0 or tx >= c.w or ty >= c.h) continue;
        const p = &dst.px[@as(usize, @intCast(ty)) * dst.stride + @as(usize, @intCast(tx))];
        const a = @as(f64, @floatFromInt(cover)) / 255;
        const r: f64 = @floatFromInt(p.* >> 16 & 0xFF);
        const g: f64 = @floatFromInt(p.* >> 8 & 0xFF);
        const b: f64 = @floatFromInt(p.* & 0xFF);
        p.* = pixel(r + (cr - r) * a, g + (cg - g) * a, b + (cb - b) * a);
    };
}
