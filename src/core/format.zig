//! Number formatting with fixed rules, so labels, drawings and the parts SVG
//! come out exactly as in the first version of the tool.

const std = @import("std");

/// Rounds to the nearest integer; halves go toward +infinity (2.5 -> 3, -2.5 -> -2).
pub fn roundHalfUp(x: f64) f64 {
    return @floor(x + 0.5);
}

/// Fixed number of decimals: the exact binary value is rounded to `digits`
/// decimals with halves going away from zero (6.25 -> "6.3"; most
/// formatters round halves to even and would print "6.2").
/// `digits` is at most 6. Writes into `buf` and returns the text.
pub fn fixedText(buf: []u8, x: f64, digits: u3) []const u8 {
    if (std.math.isNan(x)) return "NaN";
    if (std.math.isInf(x)) return if (x > 0) "Infinity" else "-Infinity";
    const neg = x < 0;
    const a = @abs(x);

    var pow10: u128 = 1;
    for (0..digits) |_| pow10 *= 10;

    // a = m * 2^e exactly; q = round(a * 10^digits), halves up
    var q: u128 = 0;
    if (a != 0) {
        const bits: u64 = @bitCast(a);
        const exp_bits: i32 = @intCast((bits >> 52) & 0x7FF);
        var m: u128 = bits & ((1 << 52) - 1);
        var e: i32 = undefined;
        if (exp_bits == 0) {
            e = -1074;
        } else {
            m |= 1 << 52;
            e = exp_bits - 1075;
        }
        if (e >= 0) {
            // Integers: our values stay far below 2^64
            if (e > 60) return std.fmt.bufPrint(buf, "{d:.0}", .{x}) catch "?";
            q = (m << @intCast(e)) * pow10;
        } else {
            const k: u32 = @intCast(-e);
            const n = m * pow10; // < 2^53 * 10^6 < 2^73
            if (k < 100) {
                q = n >> @intCast(k);
                const r = n - (q << @intCast(k));
                if (r >= (@as(u128, 1) << @intCast(k - 1))) q += 1;
            }
            // k >= 100: the value is far below the last digit and rounds to 0
        }
    }

    // Digits of q with the decimal point placed `digits` from the right
    var tmp: [48]u8 = undefined;
    var len: usize = 0;
    var v = q;
    while (v > 0 or len <= digits) : (len += 1) {
        tmp[len] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    var out: usize = 0;
    // The sign of small negatives is kept: -0.04 with one decimal is "-0.0"
    if (neg) {
        buf[out] = '-';
        out += 1;
    }
    var i = len;
    while (i > 0) {
        i -= 1;
        buf[out] = tmp[i];
        out += 1;
        if (i == digits and digits > 0) {
            buf[out] = '.';
            out += 1;
        }
    }
    return buf[0..out];
}

/// The shortest text that reads back as the same number (shortest form
/// that reads back the same; no exponent for the sizes used here).
pub fn numText(buf: []u8, x: f64) []const u8 {
    if (x == 0) return "0"; // also -0
    return std.fmt.bufPrint(buf, "{d}", .{x}) catch "?";
}

/// Writer helpers: the same as above, written to a writer.
pub fn writeFixed(w: *std.Io.Writer, x: f64, digits: u3) !void {
    var buf: [64]u8 = undefined;
    try w.writeAll(fixedText(&buf, x, digits));
}

pub fn writeNum(w: *std.Io.Writer, x: f64) !void {
    var buf: [64]u8 = undefined;
    try w.writeAll(numText(&buf, x));
}

/// Formatting wrappers for "{f}" in format strings: `fixed1(x)`, `num(x)`.
pub const Fixed = struct {
    x: f64,
    digits: u3,
    pub fn format(self: Fixed, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [64]u8 = undefined;
        try w.writeAll(fixedText(&buf, self.x, self.digits));
    }
};

pub const Num = struct {
    x: f64,
    pub fn format(self: Num, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [64]u8 = undefined;
        try w.writeAll(numText(&buf, self.x));
    }
};

pub fn fixed(x: f64, digits: u3) Fixed {
    return .{ .x = x, .digits = digits };
}

pub fn fixed1(x: f64) Fixed {
    return .{ .x = x, .digits = 1 };
}

pub fn num(x: f64) Num {
    return .{ .x = x };
}

/// Parses a number like the settings fields do: empty or invalid text is 0.
pub fn parseNum(s: []const u8) f64 {
    const v = std.fmt.parseFloat(f64, std.mem.trim(u8, s, " \t")) catch return 0;
    return if (std.math.isNan(v)) 0 else v;
}

test "fixedText rounds the exact value, halves away from zero" {
    const cases = [_]struct { x: f64, d: u3, want: []const u8 }{
        .{ .x = 6.25, .d = 1, .want = "6.3" },     .{ .x = 1.005, .d = 2, .want = "1.00" },
        .{ .x = 0.05, .d = 1, .want = "0.1" },     .{ .x = -0.04, .d = 1, .want = "-0.0" },
        .{ .x = -2.35, .d = 1, .want = "-2.4" },   .{ .x = 0, .d = 1, .want = "0.0" },
        .{ .x = 123.456, .d = 0, .want = "123" },  .{ .x = 0.5, .d = 0, .want = "1" },
        .{ .x = 2.5, .d = 0, .want = "3" },        .{ .x = 1e-7, .d = 2, .want = "0.00" },
        .{ .x = 39.95, .d = 1, .want = "40.0" },   .{ .x = 219.9114857512855, .d = 1, .want = "219.9" },
        .{ .x = 1234567.25, .d = 1, .want = "1234567.3" },
    };
    for (cases) |c| {
        var buf: [64]u8 = undefined;
        try std.testing.expectEqualStrings(c.want, fixedText(&buf, c.x, c.d));
    }
}

test "numText prints the shortest form" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("116", numText(&buf, 116));
    try std.testing.expectEqualStrings("0.1", numText(&buf, 0.1));
    try std.testing.expectEqualStrings("12.5", numText(&buf, 12.5));
    try std.testing.expectEqualStrings("-90", numText(&buf, -90));
    try std.testing.expectEqualStrings("0", numText(&buf, -0.0));
}
