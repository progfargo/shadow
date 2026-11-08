//! The night lamp: a glass tube on the wall with an LED inside, drawing the
//! picture on the wall.
//!
//! Units are mm. Coordinates: x right, y up, z from the wall toward the
//! viewer; the wall is the z=0 plane.
//! A bottle is cut in two places to make a glass tube. Its back end sits gd mm
//! deep in a groove on the front face of a wooden back cap that hangs on the
//! wall and is glued there; the back cap is s thick. The front end is closed
//! by a removable plug made of two parts: a front disc and a hollow cup that
//! goes into the tube. The cup is screwed to the disc from below with two wood
//! screws through its wall (not glued); the circuit sits inside the cup. The
//! LED is glued to the center of the outside of the cup's bottom and faces the
//! wall. Power comes from a USB-C receptacle module on the bottom edge of the
//! back cap; the cable runs through a channel on the back to the rim slot,
//! along the outside of the glass (bare, not in a tube), through a channel on
//! the front of the plug to the center and in through the middle hole. The
//! cable is always at the bottom (so its weight does not tilt the lamp) and
//! casts a narrow shadow downward. The film is wrapped around the visible
//! outer surface of the tube: printed (black) areas block the light.
//!
//! Light through the glass is shifted sideways (glassShift); going back from
//! the wall this is the same as light leaving a virtual source shifted from
//! the LED.

const std = @import("std");
const Allocator = std.mem.Allocator;
const film = @import("film.zig");
const optics = @import("optics.zig");
const dims_ = @import("lamp_dims.zig");
const Vec = optics.Vec;

pub const Dims = dims_.Dims;
pub const baseDims = dims_.baseDims;
pub const baseWarnings = dims_.baseWarnings;
pub const Warnings = dims_.Warnings;

pub const Surface = enum { film, paint, frost };
/// The band of film in front of the LED: black (light only on the wall) or
/// clear (the lamp also lights the room).
pub const Front = enum { black, clear };

/// The night lamp settings.
pub const Params = struct {
    pattern: film.Pattern = .{},
    placement: film.Placement = .{ .iw = 400 },

    // glass tube: outer diameter, length between the cuts, glass thickness, refractive index
    dia: f64 = 70,
    len: f64 = 120,
    glass: f64 = 3,
    n: f64 = 1.52,
    // back cap: thickness (wall to tube), groove depth, groove outer wall
    s: f64 = 20,
    gd: f64 = 6,
    rim_w: f64 = 4,
    // front plug: disc thickness, cup depth
    front_t: f64 = 12,
    plug_depth: f64 = 16,
    // cable outside the glass: diameter, angle (270 = bottom)
    cable_d: f64 = 3,
    cable_angle: f64 = 270,
    // LED position; lz follows from the plug (ledZ)
    lx: f64 = 0,
    ly: f64 = 0,
    lz: f64 = 0,
    dpi: f64 = 300,
    seam: f64 = 270, // seam position (degrees)
    front: Front = .black,
    surface: Surface = .film,
};

/// Share of direct, image-forming light left by laser-frosted glass, which
/// scatters rather than blocks light (an estimate).
pub const frost_direct = 0.15;

/// The LED's distance from the wall: it sits on the plug, so it follows from
/// the tube and plug sizes (LED height ~2 mm).
pub fn ledZ(p: *const Params) f64 {
    return p.s - p.gd + p.len - p.plug_depth - 2;
}

/// The geometry the light passes through.
pub const Bottle = struct {
    R: f64,
    G: f64,
    N: f64,
    L: Vec,
    z0: f64, // visible glass from the back cap to the plug
    z1: f64,
    rb: f64, // back cap radius
    s: f64, // back cap thickness
    circ: f64,
    phi0: f64, // seam angle
    cable_x: f64,
    cable_y: f64,
    cable_a: f64, // cable radius
    cable_z0: f64,
    cable_z1: f64,

    pub fn init(p: *const Params) Bottle {
        const d = baseDims(p);
        const R = p.dia / 2;
        return .{
            .R = R,
            .G = p.glass,
            .N = p.n,
            .L = .{ p.lx, p.ly, p.lz },
            .z0 = p.s,
            .z1 = p.s + p.len - p.gd,
            .rb = d.db / 2,
            .s = p.s,
            .circ = 2 * std.math.pi * R,
            .phi0 = p.seam * std.math.pi / 180,
            .cable_x = d.cable.x,
            .cable_y = d.cable.y,
            .cable_a = p.cable_d / 2,
            .cable_z0 = p.s,
            .cable_z1 = d.tube_end,
        };
    }

    /// Does the ray leaving the glass at P and reaching the wall at (qx, qy)
    /// hit the cable outside the glass? The cable is parallel to the axis:
    /// check the distance in the xy plane, then the height at that point.
    pub fn cableBlocks(B: *const Bottle, P: Vec, qx: f64, qy: f64) bool {
        const dx = qx - P[0];
        const dy = qy - P[1];
        const l2 = dx * dx + dy * dy;
        if (l2 < 1e-12) return false;
        const t = std.math.clamp(((B.cable_x - P[0]) * dx + (B.cable_y - P[1]) * dy) / l2, 0, 1);
        const ex = P[0] + t * dx - B.cable_x;
        const ey = P[1] + t * dy - B.cable_y;
        if (ex * ex + ey * ey >= B.cable_a * B.cable_a) return false;
        const z = P[2] * (1 - t);
        return z >= B.cable_z0 and z <= B.cable_z1;
    }

    /// Where the ray from exit point P in direction d hits the wall; null if
    /// it goes away from the wall, leaves outside the tube, or hits the back cap.
    fn toWall(B: *const Bottle, P: Vec, d: Vec) ?[2]f64 {
        if (d[2] >= -1e-9 or P[2] < B.z0 or P[2] > B.z1) return null;
        const k = (B.s - P[2]) / d[2];
        const xs = P[0] + k * d[0];
        const ys = P[1] + k * d[1];
        if (@sqrt(xs * xs + ys * ys) < B.rb) return null;
        const kw = -P[2] / d[2];
        return .{ P[0] + kw * d[0], P[1] + kw * d[1] };
    }

    /// Point of the outer glass surface at film coordinates (u around, v from the front).
    pub fn filmPoint(B: *const Bottle, u: f64, v: f64) Vec {
        return optics.cylPoint(B.R, B.phi0, B.z1, u, v);
    }

    /// Maps a film point to the wall, with glass refraction.
    pub fn filmToWall(B: *const Bottle, P: Vec) ?[2]f64 {
        const L = B.L;
        var d = optics.norm(optics.sub(P, L));
        for (0..3) |_| {
            const sh = optics.glassShift(B.R, B.G, B.N, P, d);
            d = optics.norm(optics.sub(optics.sub(P, sh), L));
        }
        return B.toWall(P, d);
    }

    /// Maps a wall point back to the point on the outer glass surface its
    /// light comes through.
    pub fn wallToFilm(B: *const Bottle, qx: f64, qy: f64) ?Vec {
        const L = B.L;
        var Lv = B.L;
        var d: Vec = undefined;
        var P: Vec = undefined;
        for (0..4) |_| {
            d = optics.norm(.{ qx - Lv[0], qy - Lv[1], -Lv[2] });
            const Ps = optics.sideHit(B.R, L, d) orelse return null;
            const sh = optics.glassShift(B.R, B.G, B.N, Ps, d);
            P = optics.add(Ps, sh);
            Lv = optics.add(L, sh);
        }
        if (B.toWall(P, d) == null) return null;
        return P;
    }

    /// Smallest radius on the wall where light starts (with the LED on the
    /// axis; for information). Infinity if there is none.
    pub fn innerRadius(B: *const Bottle) f64 {
        const Rr = @max(B.R, B.rb);
        const z = B.s;
        if (B.L[2] > z) return Rr * B.L[2] / (B.L[2] - z);
        return std.math.inf(f64);
    }

    /// Horizontal position of the cable on the film (mm): align this mark
    /// with the cable when wrapping.
    pub fn cableU(B: *const Bottle) f64 {
        const a = std.math.atan2(B.cable_y, B.cable_x) - B.phi0;
        return @mod(a, 2 * std.math.pi) * B.R;
    }
};

const Projector = struct {
    B: *const Bottle,
    pub fn project(self: Projector, u: f64, v: f64) ?[2]f64 {
        return self.B.filmToWall(self.B.filmPoint(u, v));
    }
};

/// A computed lamp: the settings, the geometry and the film.
pub const Result = struct {
    p: Params,
    B: Bottle,
    film: film.Film,

    pub fn deinit(r: *Result, gpa: Allocator) void {
        r.film.deinit(gpa);
    }

    /// Light on the wall at (qx, qy): 1 through a clear film pixel, 0 when
    /// blocked (frost_direct for frosted glass).
    pub fn litAt(r: *const Result, qx: f64, qy: f64) f64 {
        const B = &r.B;
        const f = &r.film;
        const P = B.wallToFilm(qx, qy) orelse return 0;
        if (B.cableBlocks(P, qx, qy)) return 0;
        const uv = optics.cylUV(B.R, B.phi0, B.z1, P);
        const x = @floor(uv[0] / f.px);
        const y = @floor(uv[1] / f.px);
        if (x < 0 or y < 0 or x >= @as(f64, @floatFromInt(f.w)) or y >= @as(f64, @floatFromInt(f.h))) return 0;
        const i = @as(usize, @intFromFloat(y)) * f.w + @as(usize, @intFromFloat(x));
        if (f.data[i] == 1) return 1;
        if (r.p.surface == .frost) return frost_direct;
        return 0;
    }

    /// Blur on the wall (mm) from the LED size.
    pub fn penumbraAt(r: *const Result, qx: f64, qy: f64, led: f64) f64 {
        const L = r.B.L;
        const P = r.B.wallToFilm(qx, qy) orelse return 0;
        const a = @sqrt((qx - P[0]) * (qx - P[0]) + (qy - P[1]) * (qy - P[1]) + P[2] * P[2]);
        const b = @sqrt((P[0] - L[0]) * (P[0] - L[0]) + (P[1] - L[1]) * (P[1] - L[1]) + (P[2] - L[2]) * (P[2] - L[2]));
        return led * a / b;
    }
};

/// Makes the film for the lamp from the image.
pub fn compute(gpa: Allocator, p: *const Params, sampler: film.Sampler) !Result {
    const B = Bottle.init(p);
    var f = try film.Film.init(gpa, B.circ, B.z1 - B.z0, p.dpi);
    errdefer f.deinit(gpa);
    var m = try film.mapFilm(gpa, &f, Projector{ .B = &B });
    defer m.deinit(gpa);
    const tone = film.Tone.init(&p.pattern, p.placement, sampler);
    film.fillFilm(&f, &m, &p.pattern, &tone, B.circ);

    // Cable shadow (for information; shown on the film). The film point's x
    // and y only depend on the column, so they are computed once per column.
    const cols = try gpa.alloc(Vec, f.w);
    defer gpa.free(cols);
    for (cols, 0..) |*c, x| c.* = B.filmPoint((@as(f64, @floatFromInt(x)) + 0.5) * f.px, 0);
    for (0..f.h) |y| {
        const z = B.z1 - (@as(f64, @floatFromInt(y)) + 0.5) * f.px;
        for (0..f.w) |x| {
            const i = y * f.w + x;
            if (m.ok[i] == 1 and B.cableBlocks(.{ cols[x][0], cols[x][1], z }, m.qx[i], m.qy[i])) f.shadow[i] = 1;
        }
    }

    // The band in front of the LED sends no light to the wall; leave it clear
    // if it should light the room like a lamp.
    if (p.front == .clear) {
        const vl = @floor((B.z1 - B.L[2]) / f.px);
        const rows: usize = if (vl <= 0) 0 else @min(f.h, @as(usize, @intFromFloat(vl)));
        @memset(f.data[0 .. rows * f.w], 1);
    }
    return .{ .p = p.*, .B = B, .film = f };
}
