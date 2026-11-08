//! The sample pictures shown before the user chooses one, drawn once on a
//! hidden canvas.

const std = @import("std");
const Allocator = std.mem.Allocator;
const lv = @import("lvgl");
const cv = @import("canvas.zig");
const st = @import("style.zig");
const Picture = @import("picture.zig").Picture;
const Product = @import("pages.zig").Product;

const white = 0xFFFFFF;

pub fn picture(gpa: Allocator, product: Product) !Picture {
    const size: i32 = if (product == .lamp) 600 else 800;
    var c = try cv.Canvas.create(lv.lv_layer_sys(), size, size);
    defer c.destroy();
    lv.lv_obj_set_hidden(c.obj, true);
    c.fill(0x000000);
    switch (product) {
        .lamp => try drawLamp(&c),
        .candle => drawCandle(&c),
    }
    // Copy out as RGBA
    const px = c.pixels();
    const n: usize = @intCast(size);
    const rgba = try gpa.alloc(u8, 4 * n * n);
    for (0..n) |y| for (0..n) |x| {
        const p = px.px[y * px.stride + x];
        const i = 4 * (y * n + x);
        rgba[i] = @truncate(p >> 16);
        rgba[i + 1] = @truncate(p >> 8);
        rgba[i + 2] = @truncate(p);
        rgba[i + 3] = 255;
    };
    return .{ .w = n, .h = n, .rgba = rgba };
}

/// For the night lamp: words and two rings.
fn drawLamp(c: *cv.Canvas) !void {
    const font = st.fontOfSize(110, true) orelse return error.FontLoadFailed;
    defer st.freeFont(font);
    c.begin();
    cv.textMiddle(300, 95, "SHADOW", font, white, .middle);
    cv.textMiddle(300, 510, "PLAY", font, white, .middle);
    for ([_]f64{ 85, 515 }) |x| cv.strokeCircle(x, 300, 55, 24, white, 255);
    c.end();
}

/// For the candle glass (seen from above, glass at the center): fish swimming
/// and gulls flying around the glass, with a wave ring. Large soft
/// silhouettes suit the blur of a flame.
fn drawCandle(c: *cv.Canvas) void {
    c.begin();
    // Fish swimming along a circle
    for (0..5) |k| {
        const a = 0.3 + @as(f64, @floatFromInt(k)) * 2.0 * std.math.pi / 5.0;
        const T = Turn.at(400 + 165 * @cos(a), 400 + 165 * @sin(a), a + std.math.pi / 2.0);
        // body: an ellipse 45 × 20 as a fan of triangles
        const n = 48;
        for (0..n) |i| {
            const t0 = @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f64, n);
            const t1 = @as(f64, @floatFromInt(i + 1)) * 2.0 * std.math.pi / @as(f64, n);
            const p0 = T.map(45 * @cos(t0), 20 * @sin(t0));
            const p1 = T.map(45 * @cos(t1), 20 * @sin(t1));
            const o = T.map(0, 0);
            cv.triangle(o[0], o[1], p0[0], p0[1], p1[0], p1[1], white, 255);
        }
        const t0 = T.map(-38, 0);
        const t1 = T.map(-75, -24);
        const t2 = T.map(-75, 24);
        cv.triangle(t0[0], t0[1], t1[0], t1[1], t2[0], t2[1], white, 255);
    }
    // Wave ring
    var prev: ?[2]f64 = null;
    var a: f64 = 0;
    while (a <= 2 * std.math.pi + 0.01) : (a += 0.02) {
        const r = 250 + 12 * @sin(a * 14);
        const p = [2]f64{ 400 + r * @cos(a), 400 + r * @sin(a) };
        if (prev) |q| cv.roundLine(q[0], q[1], p[0], p[1], 12, white, 255);
        prev = p;
    }
    // Gulls: two curved wing strokes
    for (0..6) |k| {
        const ga = @as(f64, @floatFromInt(k)) * 2.0 * std.math.pi / 6.0;
        const T = Turn.at(400 + 330 * @cos(ga), 400 + 330 * @sin(ga), ga + std.math.pi / 2.0);
        wing(T, .{ -50, 0 }, .{ -25, -30 }, .{ 0, 5 });
        wing(T, .{ 0, 5 }, .{ 25, -30 }, .{ 50, 0 });
    }
    c.end();
}

/// A quadratic curve from p0 to p2 with control point p1, as round-capped strokes
fn wing(T: Turn, p0: [2]f64, p1: [2]f64, p2: [2]f64) void {
    var prev = T.map(p0[0], p0[1]);
    for (1..17) |i| {
        const t = @as(f64, @floatFromInt(i)) / 16;
        const x = (1 - t) * (1 - t) * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0];
        const y = (1 - t) * (1 - t) * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1];
        const p = T.map(x, y);
        cv.roundLine(prev[0], prev[1], p[0], p[1], 14, white, 255);
        prev = p;
    }
}

/// Moves to (x, y) and turns by angle a (canvas translate + rotate).
const Turn = struct {
    x: f64,
    y: f64,
    c: f64,
    s: f64,

    fn at(x: f64, y: f64, a: f64) Turn {
        return .{ .x = x, .y = y, .c = @cos(a), .s = @sin(a) };
    }

    fn map(t: Turn, u: f64, v: f64) [2]f64 {
        return .{ t.x + u * t.c - v * t.s, t.y + u * t.s + v * t.c };
    }
};
