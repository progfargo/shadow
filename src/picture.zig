//! The picture the user chooses: decoded to RGBA, then resampled for the
//! calculation (brightness grid) and for the Image view.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

// src/image.c
extern fn shadow_image_decode(data: [*]const u8, len: usize, w: *c_int, h: *c_int) ?[*]u8;
extern fn shadow_image_free(p: ?*anyopaque) void;
extern fn shadow_image_error() ?[*:0]const u8;

/// Largest picture file read
const max_file_size = 200 * 1024 * 1024;

pub const Picture = struct {
    w: usize,
    h: usize,
    /// 4 bytes per pixel, row by row
    rgba: []u8,

    pub fn deinit(p: *Picture, gpa: Allocator) void {
        gpa.free(p.rgba);
        p.* = undefined;
    }

    /// Height / width
    pub fn aspect(p: *const Picture) f64 {
        if (p.w == 0) return 1;
        return @as(f64, @floatFromInt(p.h)) / @as(f64, @floatFromInt(p.w));
    }

    /// Decodes a picture file (PNG, JPEG, BMP, GIF, ...).
    pub fn decode(gpa: Allocator, data: []const u8) !Picture {
        var w: c_int = 0;
        var h: c_int = 0;
        const px = shadow_image_decode(data.ptr, data.len, &w, &h) orelse return error.CannotDecode;
        defer shadow_image_free(px);
        const n: usize = @intCast(w * h * 4);
        return .{ .w = @intCast(w), .h = @intCast(h), .rgba = try gpa.dupe(u8, px[0..n]) };
    }

    pub fn load(gpa: Allocator, io: Io, path: []const u8) !Picture {
        const data = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_size));
        defer gpa.free(data);
        return decode(gpa, data);
    }

    /// RGB of pixel (x, y) composited over black (transparent parts are dark)
    inline fn rgbAt(p: *const Picture, x: usize, y: usize) [3]f32 {
        const i = 4 * (y * p.w + x);
        const a: f32 = @as(f32, @floatFromInt(p.rgba[i + 3])) / 255;
        return .{
            @as(f32, @floatFromInt(p.rgba[i])) * a,
            @as(f32, @floatFromInt(p.rgba[i + 1])) * a,
            @as(f32, @floatFromInt(p.rgba[i + 2])) * a,
        };
    }

    /// Resamples the picture to w x h pixels (RGB 0..255 over black):
    /// averaging when it shrinks, bilinear when it grows. `out` has 3 floats
    /// per pixel.
    pub fn resample(p: *const Picture, out: []f32, w: usize, h: usize) void {
        const sw: f64 = @floatFromInt(p.w);
        const sh: f64 = @floatFromInt(p.h);
        const fw: f64 = @floatFromInt(w);
        const fh: f64 = @floatFromInt(h);
        for (0..h) |ty| {
            const fy0 = @as(f64, @floatFromInt(ty)) * sh / fh;
            const fy1 = @as(f64, @floatFromInt(ty + 1)) * sh / fh;
            for (0..w) |tx| {
                const fx0 = @as(f64, @floatFromInt(tx)) * sw / fw;
                const fx1 = @as(f64, @floatFromInt(tx + 1)) * sw / fw;
                var c: [3]f32 = undefined;
                if (fx1 - fx0 >= 1 and fy1 - fy0 >= 1) {
                    // box: average the source pixels the target pixel covers
                    const x0: usize = @intFromFloat(fx0);
                    const y0: usize = @intFromFloat(fy0);
                    const x1: usize = @min(p.w, @max(x0 + 1, @as(usize, @intFromFloat(fx1))));
                    const y1: usize = @min(p.h, @max(y0 + 1, @as(usize, @intFromFloat(fy1))));
                    var acc: [3]f32 = .{ 0, 0, 0 };
                    for (y0..y1) |y| for (x0..x1) |x| {
                        const v = p.rgbAt(x, y);
                        acc[0] += v[0];
                        acc[1] += v[1];
                        acc[2] += v[2];
                    };
                    const n: f32 = @floatFromInt((y1 - y0) * (x1 - x0));
                    c = .{ acc[0] / n, acc[1] / n, acc[2] / n };
                } else {
                    // bilinear around the target pixel's center
                    const cx = std.math.clamp((fx0 + fx1) / 2 - 0.5, 0, sw - 1);
                    const cy = std.math.clamp((fy0 + fy1) / 2 - 0.5, 0, sh - 1);
                    const x0: usize = @intFromFloat(cx);
                    const y0: usize = @intFromFloat(cy);
                    const x1 = @min(x0 + 1, p.w - 1);
                    const y1 = @min(y0 + 1, p.h - 1);
                    const ax: f32 = @floatCast(cx - @as(f64, @floatFromInt(x0)));
                    const ay: f32 = @floatCast(cy - @as(f64, @floatFromInt(y0)));
                    const a = p.rgbAt(x0, y0);
                    const b = p.rgbAt(x1, y0);
                    const cc = p.rgbAt(x0, y1);
                    const d = p.rgbAt(x1, y1);
                    for (0..3) |k| c[k] = (a[k] * (1 - ax) + b[k] * ax) * (1 - ay) + (cc[k] * (1 - ax) + d[k] * ax) * ay;
                }
                const o = 3 * (ty * w + tx);
                out[o] = c[0];
                out[o + 1] = c[1];
                out[o + 2] = c[2];
            }
        }
    }

    /// Brightness 0..1 of the picture resampled to cols x rows.
    pub fn luminance(p: *const Picture, gpa: Allocator, cols: usize, rows: usize) ![]f32 {
        const rgb = try gpa.alloc(f32, 3 * cols * rows);
        defer gpa.free(rgb);
        p.resample(rgb, cols, rows);
        const lum = try gpa.alloc(f32, cols * rows);
        for (lum, 0..) |*l, i| l.* = (0.2126 * rgb[3 * i] + 0.7152 * rgb[3 * i + 1] + 0.0722 * rgb[3 * i + 2]) / 255;
        return lum;
    }

    /// A w x h RGBA copy (for the picture analysis).
    pub fn smallRgba(p: *const Picture, gpa: Allocator, w: usize, h: usize) ![]u8 {
        const rgb = try gpa.alloc(f32, 3 * w * h);
        defer gpa.free(rgb);
        p.resample(rgb, w, h);
        const out = try gpa.alloc(u8, 4 * w * h);
        for (0..w * h) |i| {
            for (0..3) |k| out[4 * i + k] = @intFromFloat(@round(std.math.clamp(rgb[3 * i + k], 0, 255)));
            out[4 * i + 3] = 255;
        }
        return out;
    }
};

/// Brightness grid read by the calculation (`core.film.Sampler`).
pub const LumGrid = struct {
    cols: usize,
    rows: usize,
    lum: []f32,

    pub fn deinit(g: *LumGrid, gpa: Allocator) void {
        gpa.free(g.lum);
        g.* = undefined;
    }

    pub fn sample(ctx: *const anyopaque, u: f64, v: f64) f64 {
        const g: *const LumGrid = @ptrCast(@alignCast(ctx));
        const fc: f64 = @floatFromInt(g.cols);
        const fr: f64 = @floatFromInt(g.rows);
        const x: usize = @intFromFloat(std.math.clamp(@floor(u * fc), 0, fc - 1));
        const y: usize = @intFromFloat(std.math.clamp(@floor(v * fr), 0, fr - 1));
        return g.lum[y * g.cols + x];
    }
};

/// The picture at about 0.5 mm per pixel of the lit surface, for an image
/// `iw` mm wide.
pub fn lumGrid(gpa: Allocator, p: *const Picture, iw: f64) !LumGrid {
    const roundHalfUp = @import("core").format.roundHalfUp;
    const cols: usize = @intFromFloat(@max(1, @min(2400, roundHalfUp(iw / 0.5))));
    const rows: usize = @intFromFloat(@max(1, @min(2400, roundHalfUp(iw * p.aspect() / 0.5))));
    return .{ .cols = cols, .rows = rows, .lum = try p.luminance(gpa, cols, rows) };
}
