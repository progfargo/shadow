//! PNG resolution chunk, so a film prints at actual size.

const std = @import("std");
const roundHalfUp = @import("format.zig").roundHalfUp;

/// Returns `src` (a PNG) with a resolution chunk (pHYs) right after the
/// header. Caller owns the result.
pub fn withDpi(gpa: std.mem.Allocator, src: []const u8, dpi: f64) ![]u8 {
    if (src.len < 33) return error.NotPng;
    const ppm: u32 = @intFromFloat(roundHalfUp(dpi / 0.0254));
    var chunk: [21]u8 = undefined;
    std.mem.writeInt(u32, chunk[0..4], 9, .big);
    @memcpy(chunk[4..8], "pHYs");
    std.mem.writeInt(u32, chunk[8..12], ppm, .big);
    std.mem.writeInt(u32, chunk[12..16], ppm, .big);
    chunk[16] = 1; // unit: meter
    std.mem.writeInt(u32, chunk[17..21], std.hash.Crc32.hash(chunk[4..17]), .big);

    const out = try gpa.alloc(u8, src.len + chunk.len);
    @memcpy(out[0..33], src[0..33]); // signature + IHDR
    @memcpy(out[33..54], &chunk);
    @memcpy(out[54..], src[33..]);
    return out;
}
