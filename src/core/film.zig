//! What both products share: the image settings, the film raster and how it
//! is filled from the image. The products (lamp, candle) only differ in where
//! each film pixel sends its light. Units are mm.

const std = @import("std");
const Allocator = std.mem.Allocator;
const jsRound = @import("format.zig").jsRound;
const Screen = @import("screen.zig").Screen;

pub const Mode = enum { binary, halftone };
pub const HtPattern = enum { dot, square, lines, wavy, cross, rings, spiral };
/// Where the halftone pattern is even: on the unrolled film, or on the lit
/// surface (wall or table). The app always uses `wall`; `film` is kept so the
/// results can be compared with the first version.
pub const Grid = enum { film, wall };

/// Settings that turn the image into light and shadow.
pub const Pattern = struct {
    mode: Mode = .binary,
    threshold: f64 = 0.5,
    gamma: f64 = 1,
    invert: bool = false,
    ht_pattern: HtPattern = .dot,
    grid: Grid = .wall,
    pitch: f64 = 2,
    fill: f64 = 0.9,
    ht_angle: f64 = 0, // degrees
    wave_amp: f64 = 1,
    wave_len: f64 = 8,
};

/// Puts the image on the lit surface: width, center and height/width ratio.
pub const Placement = struct {
    iw: f64,
    ix: f64 = 0,
    iy: f64 = 0,
    aspect: f64 = 1,
};

/// Brightness (0..1) of the source image at (u, v), both 0..1 with (0, 0) at
/// the top left.
pub const Sampler = struct {
    ctx: *const anyopaque,
    f: *const fn (ctx: *const anyopaque, u: f64, v: f64) f64,

    pub inline fn sample(s: Sampler, u: f64, v: f64) f64 {
        return s.f(s.ctx, u, v);
    }
};

/// Brightness used for the pattern at a point of the lit surface: 0 outside
/// the image, otherwise the image brightness after invert and gamma.
pub const Tone = struct {
    sampler: Sampler,
    invert: bool,
    gamma: f64,
    iw: f64,
    ih: f64,
    x0: f64,
    y1: f64,

    pub fn init(p: *const Pattern, pl: Placement, sampler: Sampler) Tone {
        const ih = pl.iw * pl.aspect;
        return .{
            .sampler = sampler,
            .invert = p.invert,
            .gamma = p.gamma,
            .iw = pl.iw,
            .ih = ih,
            .x0 = pl.ix - pl.iw / 2,
            .y1 = pl.iy + ih / 2,
        };
    }

    pub fn at(t: *const Tone, x: f64, y: f64) f64 {
        const u = (x - t.x0) / t.iw;
        const v = (t.y1 - y) / t.ih;
        if (u < 0 or u > 1 or v < 0 or v > 1) return 0;
        var b = t.sampler.sample(u, v);
        if (t.invert) b = 1 - b;
        b = std.math.clamp(b, 0, 1);
        if (t.gamma == 1) return b;
        return std.math.pow(f64, b, t.gamma);
    }
};

/// The unrolled pattern around the glass: `data` is 1 where light passes
/// (clear) and 0 where it is printed. `shadow` marks pixels whose light is
/// blocked on the way (the night lamp's cable); it is for display only.
pub const Film = struct {
    w: usize,
    h: usize,
    px: f64, // pixel size in mm
    data: []u8,
    shadow: []u8,

    /// An empty film for a glass of the given circumference and height.
    pub fn init(gpa: Allocator, circ: f64, height: f64, dpi: f64) !Film {
        const px = 25.4 / dpi;
        const w: usize = @intFromFloat(@max(1, jsRound(circ / px)));
        const h: usize = @intFromFloat(@max(1, jsRound(height / px)));
        const data = try gpa.alloc(u8, w * h);
        errdefer gpa.free(data);
        const shadow = try gpa.alloc(u8, w * h);
        @memset(data, 0);
        @memset(shadow, 0);
        return .{ .w = w, .h = h, .px = px, .data = data, .shadow = shadow };
    }

    pub fn deinit(f: *Film, gpa: Allocator) void {
        gpa.free(f.data);
        gpa.free(f.shadow);
        f.* = undefined;
    }

    /// Number of clear pixels
    pub fn open(f: *const Film) usize {
        var n: usize = 0;
        for (f.data) |v| n += v;
        return n;
    }
};

/// Where each film pixel lands on the lit surface. Points are stored as f32
/// like the first version.
pub const Mapping = struct {
    qx: []f32,
    qy: []f32,
    ok: []u8,

    pub fn deinit(m: *Mapping, gpa: Allocator) void {
        gpa.free(m.qx);
        gpa.free(m.qy);
        gpa.free(m.ok);
        m.* = undefined;
    }
};

/// Finds where each film pixel lands on the lit surface. `proj.project(u, v)`
/// maps a film point (mm) to a surface point. The mapping is smooth, so it is
/// computed exactly every few pixels and interpolated in between; where a
/// corner is invalid (edge, blocked, going the wrong way) the pixel is
/// computed exactly.
pub fn mapFilm(gpa: Allocator, f: *const Film, proj: anytype) !Mapping {
    const S = 4;
    const fw = f.w;
    const fh = f.h;
    const px = f.px;
    const n = fw * fh;
    const qx = try gpa.alloc(f32, n);
    errdefer gpa.free(qx);
    const qy = try gpa.alloc(f32, n);
    errdefer gpa.free(qy);
    const ok = try gpa.alloc(u8, n);
    errdefer gpa.free(ok);
    @memset(qx, 0);
    @memset(qy, 0);
    @memset(ok, 0);

    const gw = (fw + S - 1) / S + 1;
    const gh = (fh + S - 1) / S + 1;
    const gx = try gpa.alloc(f64, gw * gh);
    defer gpa.free(gx);
    const gy = try gpa.alloc(f64, gw * gh);
    defer gpa.free(gy);
    const gok = try gpa.alloc(u8, gw * gh);
    defer gpa.free(gok);
    @memset(gok, 0);

    for (0..gh) |y| {
        for (0..gw) |x| {
            const u = @as(f64, @floatFromInt(x * S)) * px;
            const v = @as(f64, @floatFromInt(y * S)) * px;
            if (proj.project(u, v)) |q| {
                const i = y * gw + x;
                gx[i] = q[0];
                gy[i] = q[1];
                gok[i] = 1;
            }
        }
    }
    for (0..fh) |y| {
        const yf = (@as(f64, @floatFromInt(y)) + 0.5) / S;
        const cy0 = @floor(yf);
        const fy = yf - cy0;
        for (0..fw) |x| {
            const xf = (@as(f64, @floatFromInt(x)) + 0.5) / S;
            const cx0 = @floor(xf);
            const fx = xf - cx0;
            const a = @as(usize, @intFromFloat(cy0)) * gw + @as(usize, @intFromFloat(cx0));
            const b = a + 1;
            const c = a + gw;
            const d = c + 1;
            const i = y * fw + x;
            if (gok[a] == 1 and gok[b] == 1 and gok[c] == 1 and gok[d] == 1) {
                qx[i] = @floatCast((gx[a] * (1 - fx) + gx[b] * fx) * (1 - fy) + (gx[c] * (1 - fx) + gx[d] * fx) * fy);
                qy[i] = @floatCast((gy[a] * (1 - fx) + gy[b] * fx) * (1 - fy) + (gy[c] * (1 - fx) + gy[d] * fx) * fy);
                ok[i] = 1;
            } else if (gok[a] == 1 or gok[b] == 1 or gok[c] == 1 or gok[d] == 1) {
                const u = (@as(f64, @floatFromInt(x)) + 0.5) * px;
                const v = (@as(f64, @floatFromInt(y)) + 0.5) * px;
                if (proj.project(u, v)) |q| {
                    qx[i] = @floatCast(q[0]);
                    qy[i] = @floatCast(q[1]);
                    ok[i] = 1;
                }
            }
        }
    }
    return .{ .qx = qx, .qy = qy, .ok = ok };
}

/// Sets the clear pixels from the image. Black & white compares the
/// brightness with the threshold. Halftone compares it with the screen: with
/// the `wall` grid the pattern lives on the lit surface (origin at the glass
/// center), otherwise on the unrolled film (origin at the film center).
pub fn fillFilm(f: *Film, m: *const Mapping, p: *const Pattern, tone: *const Tone, circ: f64) void {
    if (p.mode == .binary) {
        for (f.data, 0..) |*d, i| {
            if (m.ok[i] == 1 and tone.at(m.qx[i], m.qy[i]) >= p.threshold) d.* = 1;
        }
        return;
    }
    const screen = Screen.init(p);
    const wall = p.grid == .wall;
    const px = f.px;
    const fh: f64 = @floatFromInt(f.h);
    for (0..f.h) |y| {
        for (0..f.w) |x| {
            const i = y * f.w + x;
            if (m.ok[i] == 0) continue;
            const t = tone.at(m.qx[i], m.qy[i]);
            if (t <= 0.004) continue;
            var pa: f64 = undefined;
            var pb: f64 = undefined;
            if (wall) {
                pa = m.qx[i];
                pb = m.qy[i];
            } else {
                pa = (@as(f64, @floatFromInt(x)) + 0.5) * px - circ / 2;
                pb = fh * px / 2 - (@as(f64, @floatFromInt(y)) + 0.5) * px;
            }
            if (screen.clear(pa, pb, t)) f.data[i] = 1;
        }
    }
}
