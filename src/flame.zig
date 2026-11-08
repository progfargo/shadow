//! 3. The candle's light on the table, seen from above, with a flickering
//! flame. About 12 frames per second is smooth enough for a flame and keeps
//! the CPU mostly idle; nothing is drawn while the window is hidden.

const std = @import("std");
const lv = @import("lvgl");
const sdl = @import("sdl3");
const core = @import("core");
const candle = core.candle;
const cv = @import("canvas.zig");
const Canvas = cv.Canvas;
const views = @import("views.zig");
const View = views.View;
const wb = @import("workbench.zig");
const Bench = wb.Bench;

/// The flame's offset from its rest position (mm) and its brightness factor.
const Pose = struct { dx: f64 = 0, dy: f64 = 0, dz: f64 = 0, glow: f64 = 1 };

/// The flicker per light source at time t (s) and strength k (0..1): a real
/// flame sways, rises and pulses; a plain LED tealight only pulses in
/// brightness; a moving-flame LED swings like a pendulum at a fixed height.
fn flamePose(t: f64, k: f64, source: candle.Source) Pose {
    const tau = 2 * std.math.pi;
    const a = 3 * k;
    return switch (source) {
        .led => .{ .glow = 1 + 0.3 * k * (0.5 * @sin(tau * 5.3 * t) + 0.3 * @sin(tau * 9.7 * t + 1) + 0.2 * @sin(tau * 2.1 * t + 2)) },
        .ledmove => .{ .dx = 4 * k * @sin(tau * 1.4 * t), .dy = 1.5 * k * @sin(tau * 0.7 * t + 1), .glow = 1 + 0.08 * k * @sin(tau * 3.1 * t) },
        .real => .{
            .dx = a * (0.6 * @sin(tau * 1.1 * t + 0.3) + 0.4 * @sin(tau * 2.9 * t + 1.7)),
            .dy = a * (0.6 * @sin(tau * 0.9 * t + 2.1) + 0.4 * @sin(tau * 3.3 * t + 0.4)),
            .dz = 2 * k * @sin(tau * 1.7 * t + 0.9),
            .glow = 1 + 0.15 * k * (0.6 * @sin(tau * 4.3 * t) + 0.4 * @sin(tau * 7.1 * t + 1)),
        },
    };
}

/// Draws one frame. The flame is an extended, flickering source: each frame
/// samples five points of the flame (center, up, down and two sides) at a
/// quarter of the resolution, then blurs by the rest of the flame width.
pub fn drawFrame(c: *Canvas, b: *const Bench, t: f64) !void {
    const gpa = wb.gpa;
    const r = &b.candle_res.?;
    const p = &r.p;
    const cw: usize = @intCast(c.w);
    const ch: usize = @intCast(c.h);
    const v = View.fit(@floatFromInt(cw), @floatFromInt(ch), views.wallBounds(b));
    const scale = 4;
    const w = (cw + scale - 1) / scale;
    const h = (ch + scale - 1) / scale;
    const k = if (b.vals.flag(.animate)) b.vals.num(.flick) else 0;
    const ps = flamePose(t, k, p.source);
    var hz = if (p.source == .real) b.vals.num(.hnow) else p.hd;
    hz += ps.dz;
    const Sample = struct { L: [3]f64, w: f64 };
    var pts: [5]Sample = undefined;
    for ([_][4]f64{ .{ 0, 0, 0, 0.4 }, .{ 0, 0, p.fhei / 3, 0.15 }, .{ 0, 0, -p.fhei / 3, 0.15 }, .{ p.fwid / 3, 0, 0, 0.15 }, .{ -p.fwid / 3, 0, 0, 0.15 } }, 0..) |q, i| {
        pts[i] = .{ .L = .{ ps.dx + q[0], ps.dy + q[1], hz + q[2] }, .w = q[3] };
    }

    // Light 0..1 at a quarter of the resolution
    const small = try gpa.alloc(f32, w * h);
    defer gpa.free(small);
    for (0..h) |y| {
        const ty = (v.Y(0) - (@as(f64, @floatFromInt(y)) + 0.5) * scale) / v.sc;
        for (0..w) |x| {
            const tx = ((@as(f64, @floatFromInt(x)) + 0.5) * scale - v.X(0)) / v.sc;
            var a: f64 = 0;
            for (pts) |s| a += s.w * r.litAt(tx, ty, s.L);
            small[y * w + x] = @floatCast(@min(1, a * ps.glow));
        }
    }

    // Smooth enlargement to the full size, then the blur of the flame's width
    const full = try gpa.alloc(f32, cw * ch);
    defer gpa.free(full);
    const tmp = try gpa.alloc(f32, cw * ch);
    defer gpa.free(tmp);
    for (0..ch) |y| {
        const fy = std.math.clamp((@as(f64, @floatFromInt(y)) + 0.5) / scale - 0.5, 0, @as(f64, @floatFromInt(h - 1)));
        const y0: usize = @intFromFloat(fy);
        const y1 = @min(y0 + 1, h - 1);
        const ay: f32 = @floatCast(fy - @as(f64, @floatFromInt(y0)));
        for (0..cw) |x| {
            const fx = std.math.clamp((@as(f64, @floatFromInt(x)) + 0.5) / scale - 0.5, 0, @as(f64, @floatFromInt(w - 1)));
            const x0: usize = @intFromFloat(fx);
            const x1 = @min(x0 + 1, w - 1);
            const ax: f32 = @floatCast(fx - @as(f64, @floatFromInt(x0)));
            full[y * cw + x] = (small[y0 * w + x0] * (1 - ax) + small[y0 * w + x1] * ax) * (1 - ay) +
                (small[y1 * w + x0] * (1 - ax) + small[y1 * w + x1] * ax) * ay;
        }
    }
    const blur = @max(0, p.fwid / 6 * r.blurAt(candle.innerRadius(p, p.hd) + 40, 0, 1) * v.sc);
    views.gaussBlur(full, tmp, cw, ch, blur);

    const lc = views.lightColor(b);
    const light = [3]f64{ lc[0], lc[1] * 0.82, lc[2] * 0.6 };
    const px = c.pixels();
    for (0..ch) |y| for (0..cw) |x| {
        const a: f64 = std.math.clamp(full[y * cw + x], 0, 1);
        px.px[y * px.stride + x] = cv.pixel(30 + (light[0] - 30) * a, 30 + (light[1] - 30) * a, 30 + (light[2] - 30) * a);
    };
    views.keepBase(c, v);
    c.begin();
    views.drawGlass(b, v, 0, 0, hz, .{ ps.dx, ps.dy });
    views.drawScale(c, v);
    c.end();
    c.invalidate();
}

// ---------------------------------------------------------------------------
// Animation

const frame_ms = 80;

var timer: ?*lv.lv_timer_t = null;
var t0: u64 = 0;
var window: ?*sdl.SDL_Window = null;
var target: ?*Canvas = null;

pub fn init(win: ?*sdl.SDL_Window) void {
    window = win;
}

/// Draws the first frame now and keeps drawing while "Animate the flame" is on.
pub fn start(c: *Canvas) !void {
    stop();
    target = c;
    t0 = sdl.SDL_GetTicks();
    const b = wb.cur orelse return;
    try drawFrame(c, b, 0);
    if (b.vals.flag(.animate)) timer = lv.lv_timer_create(onFrame, frame_ms, null);
}

pub fn stop() void {
    if (timer) |t| lv.lv_timer_delete(t);
    timer = null;
    target = null;
}

pub fn running() bool {
    return timer != null;
}

fn onFrame(_: ?*lv.lv_timer_t) callconv(.c) void {
    const c = target orelse return;
    const b = wb.cur orelse return stop();
    if (b.candle_res == null) return;
    // Nothing to see while the window is minimized or hidden
    if (window) |w| {
        if (sdl.SDL_GetWindowFlags(w) & (sdl.SDL_WINDOW_MINIMIZED | sdl.SDL_WINDOW_HIDDEN | sdl.SDL_WINDOW_OCCLUDED) != 0) return;
    }
    const t = @as(f64, @floatFromInt(sdl.SDL_GetTicks() - t0)) / 1000;
    drawFrame(c, b, t) catch stop();
}
