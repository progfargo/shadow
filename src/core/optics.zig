//! Geometry of light through a glass cylinder. Units are mm; the cylinder
//! axis is the z axis.

const std = @import("std");

/// A point or direction in mm.
pub const Vec = [3]f64;

pub fn norm(v: Vec) Vec {
    const l = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return .{ v[0] / l, v[1] / l, v[2] / l };
}

pub fn sub(a: Vec, b: Vec) Vec {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

pub fn add(a: Vec, b: Vec) Vec {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}

/// Where the ray from L (inside) in direction d leaves a cylinder of radius R.
pub fn sideHit(R: f64, L: Vec, d: Vec) ?Vec {
    const a = d[0] * d[0] + d[1] * d[1];
    if (a < 1e-12) return null;
    const b = 2 * (L[0] * d[0] + L[1] * d[1]);
    const c = L[0] * L[0] + L[1] * L[1] - R * R;
    const t = (-b + @sqrt(b * b - 4 * a * c)) / (2 * a);
    return .{ L[0] + t * d[0], L[1] + t * d[1], L[2] + t * d[2] };
}

/// The sideways shift (−δ·t̂) of a ray in direction d passing through glass of
/// thickness g and refractive index n at outer point P of a cylinder of
/// radius R. The glass is treated locally as a flat slab: the ray keeps its
/// direction and only moves sideways, δ = g·(tanθ − tanθ').
pub fn glassShift(R: f64, g: f64, n: f64, P: Vec, d: Vec) Vec {
    if (g == 0) return .{ 0, 0, 0 };
    const nx = P[0] / R;
    const ny = P[1] / R;
    const c = d[0] * nx + d[1] * ny;
    const tx = d[0] - c * nx;
    const ty = d[1] - c * ny;
    const tz = d[2];
    const tl = @sqrt(tx * tx + ty * ty + tz * tz);
    if (tl < 1e-12) return .{ 0, 0, 0 };
    const s2 = tl / n;
    const cc = @max(c, 1e-6);
    const delta = g * (tl / cc - s2 / @sqrt(1 - s2 * s2));
    return .{ -delta * tx / tl, -delta * ty / tl, -delta * tz / tl };
}

/// Point of a cylinder of radius R at film coordinates: u around from angle
/// phi0, v down from z1.
pub fn cylPoint(R: f64, phi0: f64, z1: f64, u: f64, v: f64) Vec {
    const phi = phi0 + u / R;
    return .{ R * @cos(phi), R * @sin(phi), z1 - v };
}

/// Film coordinates of point P on a cylinder of radius R (inverse of cylPoint).
pub fn cylUV(R: f64, phi0: f64, z1: f64, P: Vec) [2]f64 {
    var phi = std.math.atan2(P[1], P[0]) - phi0;
    phi -= 2 * std.math.pi * @floor(phi / (2 * std.math.pi)); // into 0..2π
    return .{ phi * R, z1 - P[2] };
}
