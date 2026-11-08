//! The files the user saves: the film for printing, the pattern for the
//! rotary laser (PNG that prints at actual size, or the same inside an SVG
//! with its size in mm) and the parts drawing (SVG, 1:1).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const lv = @import("lvgl");
const core = @import("core");
const fmt = core.format;
const lamp = core.lamp;
const cv = @import("canvas.zig");
const st = @import("style.zig");
const wb = @import("workbench.zig");
const Bench = wb.Bench;

// src/image.c
extern fn shadow_png_encode(px: [*]const u8, w: c_int, h: c_int, comp: c_int, out_len: *usize) ?[*]u8;
extern fn shadow_png_free(p: ?*anyopaque) void;

pub const Kind = enum {
    /// the film as PNG: print file, or the plain pattern for the laser
    film_png,
    /// the same picture inside an SVG with its size in mm
    film_svg,
    parts_svg,
};

/// File name offered in the save dialog
pub fn fileName(b: *const Bench, kind: Kind) []const u8 {
    if (kind == .parts_svg) return "shadow-bottle-parts.svg";
    const png = kind == .film_png;
    return switch (b.vals.choice(lamp.Surface, .surface, .film)) {
        .film => if (png) "shadow-bottle-film.png" else "shadow-bottle-film.svg",
        .paint => if (png) "shadow-bottle-laser-paint.png" else "shadow-bottle-laser-paint.svg",
        .frost => if (png) "shadow-bottle-laser-frost.png" else "shadow-bottle-laser-frost.svg",
    };
}

/// Label of the PNG button for the pattern method
pub fn pngButtonLabel(b: *const Bench) [*:0]const u8 {
    return if (b.vals.is(.surface, "film")) lv.LV_SYMBOL_SAVE ++ "  Save PNG (print)" else lv.LV_SYMBOL_SAVE ++ "  Save PNG (rotary laser)";
}

/// Pixels of an output picture: gray (1 byte per pixel) or RGB (3 bytes).
const Image = struct {
    w: usize,
    h: usize,
    comp: u8,
    px: []u8,

    fn deinit(im: *Image, gpa: Allocator) void {
        gpa.free(im.px);
    }

    /// Encodes as PNG with the film's resolution, so it prints at actual size.
    fn png(im: *const Image, gpa: Allocator, dpi: f64) ![]u8 {
        var len: usize = 0;
        const data = shadow_png_encode(im.px.ptr, @intCast(im.w), @intCast(im.h), im.comp, &len) orelse return error.PngEncodeFailed;
        defer shadow_png_free(data);
        return core.png.withDpi(gpa, data[0..len], dpi);
    }
};

/// The plain pattern for the rotary laser: no border, text or scale bar
/// (they would be engraved too). Black = the laser fires: on painted glass
/// where light should pass, for frosting where light should be blocked.
fn laserImage(gpa: Allocator, b: *const Bench) !Image {
    const fl = b.computedFilm().?;
    const px = try gpa.alloc(u8, fl.w * fl.h);
    const paint = b.vals.is(.surface, "paint");
    for (fl.data, px) |d, *o| {
        const clear = d == 1;
        o.* = if (clear == paint) 0 else 255;
    }
    return .{ .w = fl.w, .h = fl.h, .comp = 1, .px = px };
}

/// The print file: actual-size film (black = printed) with the cut border,
/// edge labels, a 50 mm scale bar and, for the lamp, the cable mark.
fn printImage(gpa: Allocator, b: *const Bench) !Image {
    const fl = b.computedFilm().?;
    const mm = 1 / fl.px; // pixels per mm
    const m = fmt.jsRound(12 * mm);
    const W: f64 = @floatFromInt(fl.w);
    const H: f64 = @floatFromInt(fl.h);
    const cw: usize = @intFromFloat(W + 2 * m);
    const ch: usize = @intFromFloat(H + 2 * m);

    var c = try cv.Canvas.create(lv.lv_layer_sys(), @intCast(cw), @intCast(ch));
    defer c.destroy();
    lv.lv_obj_set_hidden(c.obj, true);
    c.fill(0xFFFFFF);
    {
        const out = c.pixels();
        const mi: usize = @intFromFloat(m);
        for (0..fl.h) |y| {
            const row = out.px[(mi + y) * out.stride + mi ..][0..fl.w];
            for (row, fl.data[y * fl.w ..][0..fl.w]) |*p, d| p.* = if (d == 1) 0xFFFFFFFF else 0xFF000000;
        }
    }
    const font = st.fontOfSize(@intFromFloat(fmt.jsRound(3 * mm)), false) orelse return error.FontLoadFailed;
    defer st.freeFont(font);
    const gray = 0x777777;
    const top: [*:0]const u8 = if (b.product == .candle) "top of the glass" else "front plug side";
    const bottom: [*:0]const u8 = if (b.product == .candle) "bottom (table)" else "back cap side (wall)";
    c.begin();
    cv.strokeRect(m, m, W, H, 0x999999, @max(1, 0.2 * mm));
    cv.text(m + W / 2, m - 1.5 * mm, top, font, gray, .middle);
    cv.text(m + W / 2, m + H + 4.5 * mm, bottom, font, gray, .middle);
    cv.rect(m, m + H + 7 * mm, 50 * mm, @max(1, 0.4 * mm), gray, 255);
    cv.text(m + 52 * mm, m + H + 8.5 * mm, "50 mm (scale check)", font, gray, .start);
    cv.text(m + W, m + H + 8.5 * mm, st.zfmt("{f} × {f} mm · seen from outside", .{ fmt.fixed1(W * fl.px), fmt.fixed1(H * fl.px) }), font, gray, .end);
    if (b.lamp_res) |*r| if (b.product == .lamp) {
        const uP = m + r.B.cableU() / fl.px;
        cv.triangle(uP, m + H + 0.5 * mm, uP - 1.5 * mm, m + H + 3 * mm, uP + 1.5 * mm, m + H + 3 * mm, gray, 255);
        cv.text(uP + 2 * mm, m + H + 3 * mm, "cable", font, gray, .start);
    };
    c.end();

    const px = try gpa.alloc(u8, 3 * cw * ch);
    const src = c.pixels();
    for (0..ch) |y| for (0..cw) |x| {
        const p = src.px[y * src.stride + x];
        const i = 3 * (y * cw + x);
        px[i] = @truncate(p >> 16);
        px[i + 1] = @truncate(p >> 8);
        px[i + 2] = @truncate(p);
    };
    return .{ .w = cw, .h = ch, .comp = 3, .px = px };
}

/// The output picture for the pattern method: print file or laser pattern
fn outputImage(gpa: Allocator, b: *const Bench) !Image {
    return if (b.vals.is(.surface, "film")) printImage(gpa, b) else laserImage(gpa, b);
}

/// Makes the file's content. Caller owns it.
pub fn content(gpa: Allocator, b: *const Bench, kind: Kind) ![]u8 {
    switch (kind) {
        .parts_svg => {
            const p = b.lampParams();
            var d = try core.parts.partsDrawing(gpa, &p);
            defer d.deinit();
            return d.svgAlloc(gpa);
        },
        .film_png => {
            var im = try outputImage(gpa, b);
            defer im.deinit(gpa);
            return im.png(gpa, b.vals.num(.dpi));
        },
        .film_svg => {
            var im = try outputImage(gpa, b);
            defer im.deinit(gpa);
            const png = try im.png(gpa, b.vals.num(.dpi));
            defer gpa.free(png);
            const px = b.computedFilm().?.px;
            const W = @as(f64, @floatFromInt(im.w)) * px;
            const H = @as(f64, @floatFromInt(im.h)) * px;
            var out: std.Io.Writer.Allocating = .init(gpa);
            errdefer out.deinit();
            const w = &out.writer;
            try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{f}mm\" height=\"{f}mm\" viewBox=\"0 0 {f} {f}\">", .{
                fmt.fixed(W, 2), fmt.fixed(H, 2), fmt.fixed(W, 3), fmt.fixed(H, 3),
            });
            try w.print("<image width=\"{f}\" height=\"{f}\" href=\"data:image/png;base64,", .{ fmt.fixed(W, 3), fmt.fixed(H, 3) });
            try std.base64.standard.Encoder.encodeWriter(w, png);
            try w.writeAll("\" style=\"image-rendering:pixelated\"/></svg>");
            return out.toOwnedSlice();
        },
    }
}

/// Writes the file. The extension is added if the name has none.
pub fn save(gpa: Allocator, io: Io, b: *const Bench, kind: Kind, path: []const u8) !void {
    const ext: []const u8 = if (kind == .film_png) ".png" else ".svg";
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const full = if (std.ascii.endsWithIgnoreCase(path, ext)) path else try std.fmt.bufPrint(&buf, "{s}{s}", .{ path, ext });
    const data = try content(gpa, b, kind);
    defer gpa.free(data);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = full, .data = data });
}
