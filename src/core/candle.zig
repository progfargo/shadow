//! The candle glass.
//!
//! Units are mm. Frame: z points up from the table (z=0) and the glass axis
//! is the z axis. Seen from above, the table has x to the right and y up, with
//! the glass at the origin.
//! A cut bottle stands on the table (its film starts gb above the table) with
//! a candle inside. Light going down from the flame through the glass draws
//! the pattern on the table around the glass. The film is computed for a
//! design flame height: while the candle is taller the image is distorted,
//! and as it burns down to that height it comes into focus. The candle itself
//! blocks the steepest rays, so the image on the table starts some distance
//! away from the glass.

const std = @import("std");
const Allocator = std.mem.Allocator;
const film = @import("film.zig");
const optics = @import("optics.zig");
const Warnings = @import("lamp_dims.zig").Warnings;
const Vec = optics.Vec;

pub const Source = enum { real, led, ledmove };
/// Film areas that send no light to the table: black for a clean image, or
/// clear so the glass glows like a lantern.
pub const Unused = enum { black, clear };

/// The candle glass settings.
pub const Params = struct {
    pattern: film.Pattern = .{},
    placement: film.Placement = .{ .iw = 500 },

    // glass: outer diameter, thickness, refractive index
    dia: f64 = 70,
    glass: f64 = 3,
    n: f64 = 1.52,
    // film: bottom above the table, height
    gb: f64 = 0,
    gh: f64 = 150,
    cd: f64 = 34, // candle diameter
    hd: f64 = 60, // design flame height (flame center above the table)
    fwid: f64 = 10, // flame width
    fhei: f64 = 30, // flame height
    seam: f64 = 0,
    dpi: f64 = 300,
    source: Source = .real,
    unused: Unused = .black,
};

/// The geometry the light passes through.
pub const Glass = struct {
    R: f64,
    G: f64,
    N: f64,
    z0: f64, // film from the bottom up
    z1: f64,
    rc: f64, // candle radius
    circ: f64,
    phi0: f64, // seam angle
    wax_gap: f64, // flame center above the melted wax surface
    L: Vec, // flame at the design height

    pub fn init(p: *const Params) Glass {
        const R = p.dia / 2;
        return .{
            .R = R,
            .G = p.glass,
            .N = p.n,
            .z0 = p.gb,
            .z1 = p.gb + p.gh,
            .rc = p.cd / 2,
            .circ = 2 * std.math.pi * R,
            .phi0 = p.seam * std.math.pi / 180,
            .wax_gap = p.fhei / 2 + 3,
            .L = .{ 0, 0, p.hd },
        };
    }

    /// Does the candle (its wax top, radius rc) block the ray from flame L to
    /// glass point P?
    fn candleBlocks(B: *const Glass, L: Vec, P: Vec) bool {
        const top = L[2] - B.wax_gap;
        if (P[2] >= top) return false;
        const s = (L[2] - top) / (L[2] - P[2]);
        const x = L[0] + s * (P[0] - L[0]);
        const y = L[1] + s * (P[1] - L[1]);
        return @sqrt(x * x + y * y) < B.rc;
    }

    /// Where the ray leaving the glass at P in direction d meets the table;
    /// null if it goes up or leaves outside the film.
    fn toTable(B: *const Glass, P: Vec, d: Vec) ?[2]f64 {
        if (d[2] >= -1e-9 or P[2] < B.z0 or P[2] > B.z1) return null;
        const k = -P[2] / d[2];
        return .{ P[0] + k * d[0], P[1] + k * d[1] };
    }

    /// Point of the outer glass surface at film coordinates (u around, v down from the top).
    pub fn filmPoint(B: *const Glass, u: f64, v: f64) Vec {
        return optics.cylPoint(B.R, B.phi0, B.z1, u, v);
    }

    /// Maps a film point to the table for a flame at L, with glass refraction.
    pub fn filmToTable(B: *const Glass, P: Vec, L: Vec) ?[2]f64 {
        if (B.candleBlocks(L, P)) return null;
        var d = optics.norm(optics.sub(P, L));
        for (0..3) |_| {
            const sh = optics.glassShift(B.R, B.G, B.N, P, d);
            d = optics.norm(optics.sub(optics.sub(P, sh), L));
        }
        return B.toTable(P, d);
    }
};

/// Radius on the table where the image starts at flame height h: inside it
/// the candle (or the glass bottom) blocks the light.
pub fn innerRadius(p: *const Params, h: f64) f64 {
    const R = p.dia / 2;
    const wax_gap = p.fhei / 2 + 3;
    const by_candle = h * (p.cd / 2) / wax_gap;
    var by_bottom = std.math.inf(f64);
    if (h > p.gb) by_bottom = R * h / (h - p.gb);
    return @max(by_candle, by_bottom);
}

const Projector = struct {
    B: *const Glass,
    pub fn project(self: Projector, u: f64, v: f64) ?[2]f64 {
        return self.B.filmToTable(self.B.filmPoint(u, v), self.B.L);
    }
};

/// A computed candle glass: the settings, the geometry and the film.
pub const Result = struct {
    p: Params,
    B: Glass,
    film: film.Film,

    pub fn deinit(r: *Result, gpa: Allocator) void {
        r.film.deinit(gpa);
    }

    /// Light on the table at (tx, ty) from a point flame at L: 1 if it passes
    /// a clear film pixel. Refraction is ignored here; its shift (~2 mm) is
    /// small next to the blur of a candle flame. Used for the animated
    /// simulation.
    pub fn litAt(r: *const Result, tx: f64, ty: f64, L: Vec) f64 {
        const B = &r.B;
        const f = &r.film;
        const P = optics.sideHit(B.R, L, .{ tx - L[0], ty - L[1], -L[2] }) orelse return 0;
        if (P[2] < B.z0 or P[2] > B.z1 or B.candleBlocks(L, P)) return 0;
        const uv = optics.cylUV(B.R, B.phi0, B.z1, P);
        const x = @floor(uv[0] / f.px);
        const y = @floor(uv[1] / f.px);
        if (x < 0 or y < 0 or x >= @as(f64, @floatFromInt(f.w)) or y >= @as(f64, @floatFromInt(f.h))) return 0;
        return @floatFromInt(f.data[@as(usize, @intFromFloat(y)) * f.w + @as(usize, @intFromFloat(x))]);
    }

    /// Blur on the table from the flame size: flame size × (glass-to-table
    /// distance) / (flame-to-glass distance).
    pub fn blurAt(r: *const Result, tx: f64, ty: f64, flame_size: f64) f64 {
        const L = r.B.L;
        const P = optics.sideHit(r.B.R, L, .{ tx - L[0], ty - L[1], -L[2] }) orelse return 0;
        const a = @sqrt((tx - P[0]) * (tx - P[0]) + (ty - P[1]) * (ty - P[1]) + P[2] * P[2]);
        const b = @sqrt((P[0] - L[0]) * (P[0] - L[0]) + (P[1] - L[1]) * (P[1] - L[1]) + (P[2] - L[2]) * (P[2] - L[2]));
        return flame_size * a / b;
    }
};

/// Makes the film for the design flame height from the image.
pub fn compute(gpa: Allocator, p: *const Params, sampler: film.Sampler) !Result {
    const B = Glass.init(p);
    var f = try film.Film.init(gpa, B.circ, B.z1 - B.z0, p.dpi);
    errdefer f.deinit(gpa);
    var m = try film.mapFilm(gpa, &f, Projector{ .B = &B });
    defer m.deinit(gpa);
    // With the "wall" grid the pattern lives on the table centered on the
    // glass, so rings and spirals circle it.
    const tone = film.Tone.init(&p.pattern, p.placement, sampler);
    film.fillFilm(&f, &m, &p.pattern, &tone, B.circ);

    if (p.unused == .clear) {
        for (f.data, m.ok) |*d, ok| {
            if (ok == 0) d.* = 1;
        }
    }
    return .{ .p = p.*, .B = B, .film = f };
}

pub fn warnings(p: *const Params) Warnings {
    var w: Warnings = .{};
    const R = p.dia / 2 - p.glass;
    if (p.source == .real) {
        if (p.cd / 2 > R - 15) w.add("The candle is too close to the glass: keep at least 15 mm between candle and glass.");
    } else if (p.cd / 2 > R - 2) {
        w.add("The LED candle does not fit inside the glass.");
    }
    if (p.hd <= p.gb + p.fhei / 2 + 3) w.add("Design flame height is below the bottom of the glass.");
    if (p.hd + p.fhei > p.gb + p.gh) w.add("The flame reaches above the glass: use a taller glass or a lower design height.");
    return w;
}
