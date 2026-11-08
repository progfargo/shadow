//! Suggested settings from the picture: Otsu threshold, mean and median
//! brightness, and whether it is mostly black and white.

const std = @import("std");
const fmt = @import("format.zig");
const film = @import("film.zig");

pub const Analysis = struct {
    otsu: f64,
    mean: f64,
    median: f64,
    two_tone: bool,
    mode: film.Mode, // suggested mode
    invert: bool, // suggested invert
};

/// Analyses an image given as RGBA bytes (the first version used a 200×200
/// copy of the image).
pub fn analyzeRgba(rgba: []const u8) Analysis {
    var hist: [256]f64 = @splat(0);
    var sum: f64 = 0;
    var ext: f64 = 0;
    var i: usize = 0;
    while (i + 3 < rgba.len) : (i += 4) {
        const lum = fmt.jsRound(0.2126 * @as(f64, @floatFromInt(rgba[i])) + 0.7152 * @as(f64, @floatFromInt(rgba[i + 1])) +
            0.0722 * @as(f64, @floatFromInt(rgba[i + 2])));
        const b: usize = @intFromFloat(lum);
        hist[b] += 1;
        sum += lum;
        if (b < 40 or b > 215) ext += 1;
    }
    const N: f64 = @floatFromInt(rgba.len / 4);
    const mean = sum / N / 255;

    // Otsu: the threshold that best separates the dark and light groups
    var wB: f64 = 0;
    var sB: f64 = 0;
    var best: f64 = 0;
    var otsu: usize = 128;
    for (0..256) |t| {
        wB += hist[t];
        if (wB == 0 or wB == N) continue;
        sB += @as(f64, @floatFromInt(t)) * hist[t];
        const mB = sB / wB;
        const mF = (sum - sB) / (N - wB);
        const v = wB * (N - wB) * (mB - mF) * (mB - mF);
        if (v > best) {
            best = v;
            otsu = t;
        }
    }
    var acc: f64 = 0;
    var median: f64 = 0.5;
    for (0..256) |t| {
        acc += hist[t];
        if (acc >= N / 2) {
            median = @as(f64, @floatFromInt(t)) / 255;
            break;
        }
    }
    const two_tone = ext / N > 0.75;
    return .{
        .otsu = (@as(f64, @floatFromInt(otsu)) + 0.5) / 255,
        .mean = mean,
        .median = median,
        .two_tone = two_tone,
        .mode = if (two_tone) .binary else .halftone,
        // A mostly white image with a dark subject (a drawing on paper)
        // projects best inverted: the subject becomes light
        .invert = two_tone and mean > 0.6,
    };
}

/// Rounds like the first version: toFixed, then back to a number.
fn round2(x: f64) f64 {
    var buf: [64]u8 = undefined;
    return std.fmt.parseFloat(f64, fmt.jsFixed(&buf, x, 2)) catch x;
}

/// The Otsu threshold (flipped when the image is inverted), two decimals.
pub fn suggestedThreshold(a: ?*const Analysis, invert: bool) f64 {
    const an = a orelse return 0.5;
    return round2(if (invert) 1 - an.otsu else an.otsu);
}

/// Maps the median tone to half brightness so dark or light photos still use
/// the whole range.
pub fn suggestedGamma(a: ?*const Analysis, invert: bool) f64 {
    var median: f64 = 0.5;
    if (a) |an| median = if (invert) 1 - an.median else an.median;
    const g = @min(2.5, @max(0.4, @log(0.5) / @log(@min(0.98, @max(0.02, median)))));
    return round2(g);
}

/// Keeps the halftone pitch about as small as the light source, so the blur
/// on the lit surface is wider than the dot spacing and the dots merge into
/// smooth tones. `source_size` is the LED size for the night lamp and about a
/// third of the flame width for the candle.
pub fn suggestedPitch(source_size: f64) f64 {
    return @max(1, fmt.jsRound(source_size * 2) / 2);
}

/// Explains the suggested settings in one sentence.
pub fn writeNote(w: *std.Io.Writer, a: *const Analysis, mode: film.Mode, threshold: f64, gamma: f64) !void {
    try w.writeAll("Suggested from the image: ");
    if (a.two_tone) {
        try w.writeAll("mostly black and white, so black & white mode");
    } else {
        try w.writeAll("many mid-tones, so halftone");
    }
    if (mode == .binary) {
        try w.print(", threshold {f} (best split between its dark and light parts)", .{fmt.num(threshold)});
    } else {
        try w.print(", gamma {f} (centers its tones)", .{fmt.num(gamma)});
    }
    if (a.invert) try w.writeAll(", inverted so the dark subject on a light background becomes light");
    try w.writeAll(".");
}

test "a drawing on paper is black & white and inverted" {
    var rgba: [400]u8 = undefined;
    for (0..100) |i| {
        const v: u8 = if (i < 20) 10 else 250;
        rgba[4 * i] = v;
        rgba[4 * i + 1] = v;
        rgba[4 * i + 2] = v;
        rgba[4 * i + 3] = 255;
    }
    const a = analyzeRgba(&rgba);
    try std.testing.expect(a.two_tone and a.mode == .binary and a.invert);
    const th = suggestedThreshold(&a, true);
    try std.testing.expect(th > 0 and th < 1);
    try std.testing.expectEqual(@as(f64, 1.5), suggestedPitch(1.3));
}
