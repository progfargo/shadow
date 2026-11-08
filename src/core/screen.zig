//! Halftone patterns: whether a point of the pattern plane is clear at a
//! given brightness.

const std = @import("std");
const film = @import("film.zig");
const roundHalfUp = @import("format.zig").roundHalfUp;

pub const Screen = struct {
    kind: film.HtPattern,
    P: f64,
    F: f64,
    ca: f64,
    sa: f64,
    A: f64,
    W: f64,
    dy: f64,

    /// The clear fraction is about t; Fill scales the shape size at full
    /// brightness relative to the pitch.
    pub fn init(p: *const film.Pattern) Screen {
        const ang = p.ht_angle * std.math.pi / 180;
        // same default as the first version when no wavelength is given
        const W = @max(0.1, if (p.wave_len == 0) 1 else p.wave_len);
        return .{
            .kind = p.ht_pattern,
            .P = p.pitch,
            .F = p.fill,
            .ca = @cos(ang),
            .sa = @sin(ang),
            .A = p.wave_amp,
            .W = W,
            .dy = p.pitch * @sqrt(3.0) / 2,
        };
    }

    /// Distance to the nearest line of the grid
    inline fn nearLine(s: *const Screen, v: f64) f64 {
        return @abs(v - roundHalfUp(v / s.P) * s.P);
    }

    inline fn rot(s: *const Screen, a: f64, b: f64) [2]f64 {
        return .{ a * s.ca + b * s.sa, -a * s.sa + b * s.ca };
    }

    /// Is point (a, b) of the pattern plane clear at brightness t (0..1)?
    pub fn clear(s: *const Screen, a: f64, b: f64, t: f64) bool {
        const P = s.P;
        const F = s.F;
        switch (s.kind) {
            .square => { // square grid; 45° gives diamonds
                const q = s.rot(a, b);
                const du = q[0] - roundHalfUp(q[0] / P) * P;
                const dv = q[1] - roundHalfUp(q[1] / P) * P;
                const k = @max(@abs(du), @abs(dv)) / (P / 2);
                return k * k < t * F * F;
            },
            .lines => {
                const q = s.rot(a, b);
                return s.nearLine(q[1]) < (P / 2) * F * t;
            },
            .wavy => {
                const q = s.rot(a, b);
                return s.nearLine(q[1] + s.A * @sin(2 * std.math.pi * q[0] / s.W)) < (P / 2) * F * t;
            },
            .cross => { // lines in two directions: width chosen so the clear area 1-(1-f)² = t
                const q = s.rot(a, b);
                const w = (P / 2) * F * (1 - @sqrt(@max(0, 1 - t)));
                return s.nearLine(q[0]) < w or s.nearLine(q[1]) < w;
            },
            .rings => return s.nearLine(@sqrt(a * a + b * b)) < (P / 2) * F * t,
            .spiral => { // Archimedean spiral: opens by P per turn
                const r = @sqrt(a * a + b * b) - P * std.math.atan2(b, a) / (2 * std.math.pi);
                return s.nearLine(r) < (P / 2) * F * t;
            },
            .dot => { // round dots on a hexagonal grid
                const q = s.rot(a, b);
                const row: i64 = @intFromFloat(roundHalfUp(q[1] / s.dy));
                var best = std.math.inf(f64);
                var rr = row - 1;
                while (rr <= row + 1) : (rr += 1) {
                    const off: f64 = if (@mod(rr, 2) == 1) P / 2 else 0;
                    const cx = roundHalfUp((q[0] - off) / P) * P + off;
                    const cy = @as(f64, @floatFromInt(rr)) * s.dy;
                    const d2 = (q[0] - cx) * (q[0] - cx) + (q[1] - cy) * (q[1] - cy);
                    if (d2 < best) best = d2;
                }
                return best < t * (P / 2) * (P / 2) * F * F;
            },
        }
    }
};
