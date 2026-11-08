//! The drawings of the product pages: 1. the picture on the wall or table,
//! 2. the unrolled film, 3. the light on the wall (the candle's light is in
//! flame.zig), 4. the parts drawing (parts_view.zig).
//!
//! Pixels are computed here and written into the canvas; the glass, labels
//! and scale bar are drawn over them.

const std = @import("std");
const lv = @import("lvgl");
const core = @import("core");
const lamp = core.lamp;
const candle = core.candle;
const film = core.film;
const fmt = core.format;
const cv = @import("canvas.zig");
const Canvas = cv.Canvas;
const st = @import("style.zig");
const wb = @import("workbench.zig");
const Bench = wb.Bench;

pub const stage_rgb = 0x2B2722;
const muted_rgb = 0x9A917E;
const amber_rgb = 0xFFCF6B;

/// An area of the lit surface in mm (y up).
pub const Bounds = struct { x0: f64, x1: f64, y0: f64, y1: f64 };

/// Maps the lit surface to canvas pixels.
pub const View = struct {
    sc: f64,
    ox: f64,
    oy: f64,

    pub fn fit(w: f64, h: f64, b: Bounds) View {
        const sc = @min(w / (b.x1 - b.x0), h / (b.y1 - b.y0));
        return .{ .sc = sc, .ox = (w - (b.x1 - b.x0) * sc) / 2 - b.x0 * sc, .oy = (h - (b.y1 - b.y0) * sc) / 2 + b.y1 * sc };
    }

    pub fn X(v: View, x: f64) f64 {
        return v.ox + x * v.sc;
    }

    pub fn Y(v: View, y: f64) f64 {
        return v.oy - y * v.sc;
    }
};

/// The area of the lit surface in view: the wall for the night lamp, the
/// table (seen from above) for the candle glass.
pub fn wallBounds(b: *const Bench) Bounds {
    const pl = b.placement();
    const ih = pl.iw * pl.aspect;
    var r = b.vals.num(.dia) / 2;
    if (b.product == .lamp) {
        if (b.lamp_res) |*res| r = @max(r, lamp.baseDims(&res.p).db / 2);
    }
    const x0 = @min(pl.ix - pl.iw / 2, -r);
    const x1 = @max(pl.ix + pl.iw / 2, r);
    const y0 = @min(pl.iy - ih / 2, -r);
    const y1 = @max(pl.iy + ih / 2, r);
    const m = 0.05 * @max(x1 - x0, y1 - y0);
    return .{ .x0 = x0 - m, .x1 = x1 + m, .y0 = y0 - m, .y1 = y1 + m };
}

pub fn drawScale(c: *const Canvas, v: View) void {
    const w: f64 = @floatFromInt(c.w);
    const h: f64 = @floatFromInt(c.h);
    const x1 = w - st.dpf(12);
    cv.rect(x1 - 100 * v.sc, h - st.dpf(18), 100 * v.sc, st.dpf(3), muted_rgb, 255);
    cv.text(x1, h - st.dpf(26), "100 mm", st.font_small, muted_rgb, .end);
}

/// Candle glass seen from above: glass ring, candle, flame and the dashed
/// circle where the image starts.
pub fn drawGlass(b: *const Bench, v: View, ox: f64, oy: f64, flame_z: f64, flame: [2]f64) void {
    const p = &b.candle_res.?.p;
    const R = p.dia / 2;
    const ri = candle.innerRadius(p, flame_z);
    if (std.math.isFinite(ri)) cv.dashedCircle(v.X(ox), v.Y(oy), ri * v.sc, 1, muted_rgb, st.dpf(6), st.dpf(6));
    cv.circle(v.X(ox), v.Y(oy), (R - p.glass / 2) * v.sc, 0xC8DCD2, 64, 0xCFD8D0, @max(1, p.glass * v.sc));
    cv.fillCircle(v.X(ox), v.Y(oy), p.cd / 2 * v.sc, 0xE8DCC4, 255);
    cv.fillCircle(v.X(ox + flame[0]), v.Y(oy + flame[1]), @max(st.dpf(2), p.fwid / 2 * v.sc), amber_rgb, 255);
}

/// The glass over the drawing; for the lamp seen from the front: back cap,
/// tube, the circle where the light starts and the cable.
pub fn drawBottle(b: *const Bench, v: View, ox: f64, oy: f64) void {
    if (b.product == .candle) {
        drawGlass(b, v, ox, oy, b.candle_res.?.p.hd, .{ 0, 0 });
        return;
    }
    const r = &b.lamp_res.?;
    const p = &r.p;
    cv.circle(v.X(ox), v.Y(oy), r.B.rb * v.sc, 0x6B5238, 255, 0x2A1F14, 2);
    cv.circle(v.X(ox), v.Y(oy), p.dia / 2 * v.sc, 0xC8DCD2, 90, 0xCFD8D0, 2);
    const ri = r.B.innerRadius();
    if (std.math.isFinite(ri)) cv.dashedCircle(v.X(ox), v.Y(oy), ri * v.sc, 1, muted_rgb, st.dpf(6), st.dpf(6));
    cv.circle(v.X(ox + r.B.cable_x), v.Y(oy + r.B.cable_y), @max(st.dpf(2), r.B.cable_a * v.sc), 0xD6B24A, 255, 0x6B5414, 1);
    cv.textMiddle(v.X(ox), v.Y(oy), "bottle", st.font_small, 0xE9E2D2, .middle);
}

/// Pixels of the drawing without the glass, kept so dragging the glass only
/// redraws the glass.
pub var base: std.ArrayList(u32) = .empty;
pub var base_view: ?View = null;

pub fn keepBase(c: *const Canvas, v: View) void {
    const px = c.pixels();
    base.resize(wb.gpa, px.px.len) catch {
        base_view = null;
        return;
    };
    @memcpy(base.items, px.px);
    base_view = v;
}

/// Puts the kept drawing back (before drawing the glass at a new place).
pub fn restoreBase(c: *const Canvas) bool {
    const px = c.pixels();
    if (base_view == null or base.items.len != px.px.len) return false;
    @memcpy(px.px, base.items);
    return true;
}

/// 1. The target on the wall or table (thresholded in black & white mode).
pub fn drawImage(c: *Canvas, b: *const Bench) !void {
    c.fill(stage_rgb);
    const W: f64 = @floatFromInt(c.w);
    const H: f64 = @floatFromInt(c.h);
    const v = View.fit(W, H, wallBounds(b));
    const pt = b.pattern();
    const pl = b.placement();
    const ih = pl.iw * pl.aspect;
    const w: usize = @intFromFloat(@max(1, fmt.roundHalfUp(pl.iw * v.sc)));
    const h: usize = @intFromFloat(@max(1, fmt.roundHalfUp(ih * v.sc)));
    const rgb = try wb.gpa.alloc(f32, 3 * w * h);
    defer wb.gpa.free(rgb);
    b.picture.resample(rgb, w, h);

    const px = c.pixels();
    const x0: i64 = @intFromFloat(@round(v.X(pl.ix - pl.iw / 2)));
    const y0: i64 = @intFromFloat(@round(v.Y(pl.iy + ih / 2)));
    for (0..h) |y| {
        const cy = y0 + @as(i64, @intCast(y));
        if (cy < 0 or cy >= c.h) continue;
        for (0..w) |x| {
            const cx = x0 + @as(i64, @intCast(x));
            if (cx < 0 or cx >= c.w) continue;
            const i = 3 * (y * w + x);
            var t: f64 = (0.2126 * rgb[i] + 0.7152 * rgb[i + 1] + 0.0722 * rgb[i + 2]) / 255;
            if (pt.invert) t = 1 - t;
            t = std.math.pow(f64, @max(0, t), pt.gamma);
            if (pt.mode == .binary) t = if (t >= pt.threshold) 1 else 0;
            const k = 17 + t * 226;
            px.px[@as(usize, @intCast(cy)) * px.stride + @as(usize, @intCast(cx))] = cv.pixel(k, k * 0.96, k * 0.88);
        }
    }
    keepBase(c, v);
    c.begin();
    drawBottle(b, v, 0, 0);
    drawScale(c, v);
    c.end();
}

/// Colors of a pattern method: clear and blocked parts of the film preview.
pub fn filmColors(b: *const Bench) [2]u32 {
    return switch (b.vals.choice(lamp.Surface, .surface, .film)) {
        .film => .{ 0xE8EEF0, 0x0C0B09 },
        .paint => .{ 0xE8EEF0, 0x141414 },
        .frost => .{ 0x3A4846, 0xEEF1F0 },
    };
}

/// 2. The film unrolled, seen from outside. Black = printed, light = clear.
/// The cable shadow (light through here does not reach the wall) is laid over
/// it in red.
pub fn drawFilm(c: *Canvas, b: *const Bench) !void {
    c.fill(stage_rgb);
    base_view = null;
    const fl = b.computedFilm() orelse return;
    const cw: f64 = @floatFromInt(c.w);
    const ch: f64 = @floatFromInt(c.h);
    const m = st.dpf(40);
    const fw: f64 = @floatFromInt(fl.w);
    const fh: f64 = @floatFromInt(fl.h);
    const sc = @min((cw - 2 * m) / fw, (ch - 2 * m) / fh);
    const W = fw * sc;
    const H = fh * sc;
    const X = (cw - W) / 2;
    const Y = (ch - H) / 2;
    const colors = filmColors(b);
    const with_shadow = b.product == .lamp;

    // Each canvas pixel shows the share of clear film pixels it covers
    const px = c.pixels();
    const x0: usize = @intFromFloat(@round(X));
    const y0: usize = @intFromFloat(@round(Y));
    const w: usize = @intFromFloat(@round(W));
    const h: usize = @intFromFloat(@round(H));
    const ca = rgbOf(colors[0]);
    const ck = rgbOf(colors[1]);
    for (0..h) |ty| {
        const sy0: usize = @intFromFloat(@floor(@as(f64, @floatFromInt(ty)) / sc));
        const sy1: usize = @min(fl.h, @max(sy0 + 1, @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(ty + 1)) / sc)))));
        for (0..w) |tx| {
            const sx0: usize = @intFromFloat(@floor(@as(f64, @floatFromInt(tx)) / sc));
            const sx1: usize = @min(fl.w, @max(sx0 + 1, @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(tx + 1)) / sc)))));
            var clear: f64 = 0;
            var shade: f64 = 0;
            var n: f64 = 0;
            for (@min(sy0, fl.h - 1)..sy1) |sy| for (@min(sx0, fl.w - 1)..sx1) |sx| {
                const i = sy * fl.w + sx;
                clear += @floatFromInt(fl.data[i]);
                if (with_shadow) shade += @floatFromInt(fl.shadow[i]);
                n += 1;
            };
            clear /= n;
            shade = shade / n * (150.0 / 255.0);
            var col: [3]f64 = undefined;
            for (0..3) |k| {
                const base_c = ck[k] + (ca[k] - ck[k]) * clear;
                col[k] = base_c * (1 - shade) + @as(f64, switch (k) {
                    0 => 224,
                    1 => 83,
                    else => 60,
                }) * shade;
            }
            px.px[(y0 + ty) * px.stride + x0 + tx] = cv.pixel(col[0], col[1], col[2]);
        }
    }

    c.begin();
    cv.strokeRect(X, Y, W, H, muted_rgb, 1);
    var z1: f64 = undefined;
    var light_z: f64 = undefined;
    if (b.product == .candle) {
        z1 = b.candle_res.?.B.z1;
        light_z = b.candle_res.?.p.hd;
    } else {
        const B = &b.lamp_res.?.B;
        z1 = B.z1;
        light_z = b.lamp_res.?.p.lz;
        const uP = B.cableU() / fl.px * sc;
        cv.triangle(X + uP, Y + H + st.dpf(2), X + uP - st.dpf(5), Y + H + st.dpf(10), X + uP + st.dpf(5), Y + H + st.dpf(10), 0xD6B24A, 255);
        cv.text(X + uP, Y + H + st.dpf(32), "cable", st.font_small, 0xD6B24A, .middle);
    }
    const vL = (z1 - light_z) / fl.px * sc;
    const inside = vL > 0 and vL < H;
    if (inside) cv.dashedLine(X, Y + vL, X + W, Y + vL, st.dpf(1), amber_rgb, @intFromFloat(st.dpf(5)), @intFromFloat(st.dpf(5)));
    const top: [*:0]const u8 = if (b.product == .candle) "top of the glass" else "front plug side";
    const bottom: [*:0]const u8 = if (b.product == .candle) "bottom (table)" else "back cap side (wall)";
    const level: [*:0]const u8 = if (b.product == .candle) "design flame height" else "LED level";
    cv.text(X + W / 2, Y - st.dpf(10), top, st.font_small, muted_rgb, .middle);
    cv.text(X + W / 2, Y + H + st.dpf(18), bottom, st.font_small, muted_rgb, .middle);
    if (inside) cv.text(X + st.dpf(4), Y + vL - st.dpf(4), level, st.font_small, amber_rgb, .start);
    cv.text(X + W, Y + H + st.dpf(18), st.zfmt("{f} × {f} mm", .{ fmt.fixed1(fw * fl.px), fmt.fixed1(fh * fl.px) }), st.font_small, muted_rgb, .end);
    c.end();
}

fn rgbOf(c: u32) [3]f64 {
    return .{ @floatFromInt(c >> 16 & 0xFF), @floatFromInt(c >> 8 & 0xFF), @floatFromInt(c & 0xFF) };
}

/// The LED color seen through the glass color.
pub fn lightColor(b: *const Bench) [3]f64 {
    const t = rgbOf(@import("settings.zig").parseColor(b.vals.get(.tint)));
    const led = [3]f64{ 255, 236, 190 };
    var c: [3]f64 = undefined;
    for (0..3) |k| c[k] = fmt.roundHalfUp(led[k] * t[k] / 255);
    return c;
}

/// Blur levels in pixels (the width of a Gaussian blur is level / 2)
const levels = [_]f64{ 0, 1, 2, 4, 8, 16, 32 };

/// 3. Light on the wall through the film, with glass refraction and blur
/// from the LED size. The sharp light is blurred at a few levels; each pixel
/// mixes the two levels around its own blur.
pub fn drawLampLight(c: *Canvas, b: *const Bench) !void {
    const gpa = wb.gpa;
    const r = &b.lamp_res.?;
    const led = b.vals.num(.led);
    const w: usize = @intCast(c.w);
    const h: usize = @intCast(c.h);
    const v = View.fit(@floatFromInt(w), @floatFromInt(h), wallBounds(b));

    // Blur level per pixel: computed every 4 pixels and interpolated
    const gw = (w + 3) / 4 + 1;
    const gh = (h + 3) / 4 + 1;
    const grid = try gpa.alloc(f32, gw * gh);
    defer gpa.free(grid);
    for (0..gh) |gy| for (0..gw) |gx| {
        const qx = (@as(f64, @floatFromInt(gx * 4)) - v.X(0)) / v.sc;
        const qy = (v.Y(0) - @as(f64, @floatFromInt(gy * 4))) / v.sc;
        const pen = r.penumbraAt(qx, qy, led) * v.sc;
        var li: usize = 0;
        while (li < levels.len - 2 and pen > levels[li + 1]) li += 1;
        const frac = std.math.clamp((pen - levels[li]) / (levels[li + 1] - levels[li]), 0, 1);
        grid[gy * gw + gx] = @floatCast(@min(@as(f64, levels.len - 1), @as(f64, @floatFromInt(li)) + frac));
    };

    // Sharp light: 0..1 per pixel
    const sharp = try gpa.alloc(f32, w * h);
    defer gpa.free(sharp);
    for (0..h) |y| {
        const qy = (v.Y(0) - @as(f64, @floatFromInt(y)) - 0.5) / v.sc;
        for (0..w) |x| {
            const qx = (@as(f64, @floatFromInt(x)) + 0.5 - v.X(0)) / v.sc;
            sharp[y * w + x] = @floatCast(fmt.roundHalfUp(255 * r.litAt(qx, qy)) / 255);
        }
    }

    // Blurred copies, one per level
    var blurred: [levels.len][]f32 = undefined;
    blurred[0] = sharp;
    var made: usize = 1;
    defer for (blurred[1..made]) |s| gpa.free(s);
    const tmp = try gpa.alloc(f32, w * h);
    defer gpa.free(tmp);
    for (levels[1..], 1..) |l, k| {
        blurred[k] = try gpa.alloc(f32, w * h);
        made += 1;
        @memcpy(blurred[k], sharp);
        gaussBlur(blurred[k], tmp, w, h, l / 2);
    }

    const wall = [3]f64{ 43, 39, 34 };
    const light = lightColor(b);
    const px = c.pixels();
    for (0..h) |y| {
        const gy = y / 4;
        const fy: f32 = @as(f32, @floatFromInt(y % 4)) / 4;
        for (0..w) |x| {
            const gx = x / 4;
            const fx: f32 = @as(f32, @floatFromInt(x % 4)) / 4;
            const gi = gy * gw + gx;
            const pick = (grid[gi] * (1 - fx) + grid[gi + 1] * fx) * (1 - fy) + (grid[gi + gw] * (1 - fx) + grid[gi + gw + 1] * fx) * fy;
            const l0: usize = @intFromFloat(pick);
            const l1 = @min(levels.len - 1, l0 + 1);
            const fr = pick - @as(f32, @floatFromInt(l0));
            const i = y * w + x;
            const a: f64 = std.math.clamp(blurred[l0][i] * (1 - fr) + blurred[l1][i] * fr, 0, 1);
            px.px[y * px.stride + x] = cv.pixel(
                wall[0] + (light[0] - wall[0]) * a,
                wall[1] + (light[1] - wall[1]) * a,
                wall[2] + (light[2] - wall[2]) * a,
            );
        }
    }
    keepBase(c, v);
    c.begin();
    drawBottle(b, v, 0, 0);
    drawScale(c, v);
    c.end();
}

/// Gaussian blur of standard deviation sigma (pixels), approximated by three
/// box blurs in each direction. `tmp` is scratch space of the same size.
pub fn gaussBlur(img: []f32, tmp: []f32, w: usize, h: usize, sigma: f64) void {
    if (sigma <= 0.2) return;
    // Box widths for three passes (Kovesi's method)
    const n = 3.0;
    const wIdeal = @sqrt(12 * sigma * sigma / n + 1);
    var wl: i64 = @intFromFloat(@floor(wIdeal));
    if (@mod(wl, 2) == 0) wl -= 1;
    const wu = wl + 2;
    const fwl: f64 = @floatFromInt(wl);
    const mIdeal = (12 * sigma * sigma - n * fwl * fwl - 4 * n * fwl - 3 * n) / (-4 * fwl - 4);
    const m: i64 = @intFromFloat(@round(mIdeal));
    for (0..3) |i| {
        const bw = if (@as(i64, @intCast(i)) < m) wl else wu;
        const radius: usize = @intCast(@divTrunc(@max(bw, 1) - 1, 2));
        if (radius == 0) continue;
        boxH(img, tmp, w, h, radius);
        boxV(tmp, img, w, h, radius);
    }
}

/// Horizontal box blur of radius r from src into dst; outside the image is dark.
fn boxH(src: []const f32, dst: []f32, w: usize, h: usize, r: usize) void {
    const norm: f64 = 1 / @as(f64, @floatFromInt(2 * r + 1));
    for (0..h) |y| {
        const row = src[y * w ..][0..w];
        const out = dst[y * w ..][0..w];
        // f64 sums: f32 running sums drift and leave faint streaks in dark areas
        var acc: f64 = 0;
        for (0..@min(r, w)) |x| acc += row[x];
        for (0..w) |x| {
            if (x + r < w) acc += row[x + r];
            if (x > r) acc -= row[x - r - 1];
            out[x] = @floatCast(@max(0, acc * norm));
        }
    }
}

/// Vertical box blur of radius r from src into dst.
fn boxV(src: []const f32, dst: []f32, w: usize, h: usize, r: usize) void {
    const norm: f64 = 1 / @as(f64, @floatFromInt(2 * r + 1));
    for (0..w) |x| {
        var acc: f64 = 0;
        for (0..@min(r, h)) |y| acc += src[y * w + x];
        for (0..h) |y| {
            if (y + r < h) acc += src[(y + r) * w + x];
            if (y > r) acc -= src[(y - r - 1) * w + x];
            dst[y * w + x] = @floatCast(@max(0, acc * norm));
        }
    }
}
