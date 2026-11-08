//! Compares the calculation with the first version of the tool.
//! test/reference/reference.json holds that version's results for a set of
//! parameters and test images; this test repeats the same cases.

const std = @import("std");
const testing = std.testing;
const json = std.json;
const film = @import("film.zig");
const screen = @import("screen.zig");
const lamp = @import("lamp.zig");
const candle = @import("candle.zig");
const parts = @import("parts.zig");
const png = @import("png.zig");

const reference = @embedFile("reference_json");

// --- Analytic test images: smooth tones, hard edges and rings --------------

fn smooth(_: *const anyopaque, u: f64, v: f64) f64 {
    return 0.5 + 0.5 * @sin(9 * u) * @cos(7 * v);
}

fn edges(_: *const anyopaque, u: f64, v: f64) f64 {
    const k: i64 = @intFromFloat(@floor(u * 7) + @floor(v * 5));
    return if (@rem(k, 2) != 0) 0.9 else 0.1;
}

fn rings(_: *const anyopaque, u: f64, v: f64) f64 {
    const d = std.math.hypot(u - 0.5, v - 0.5);
    return if ((d > 0.18 and d < 0.3) or (d > 0.38 and d < 0.46)) 1 else 0;
}

fn sampler(name: []const u8) film.Sampler {
    const f = if (std.mem.eql(u8, name, "smooth")) &smooth else if (std.mem.eql(u8, name, "edges")) &edges else &rings;
    return .{ .ctx = undefined, .f = f };
}

// --- Reading the parameter sets ---------------------------------------------

const Obj = json.ObjectMap;

fn num(o: Obj, k: []const u8) f64 {
    const v = o.get(k) orelse return 0;
    return switch (v) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => 0,
    };
}

fn str(o: Obj, k: []const u8) []const u8 {
    const v = o.get(k) orelse return "";
    return if (v == .string) v.string else "";
}

fn enumOf(comptime E: type, o: Obj, k: []const u8, def: E) E {
    return std.meta.stringToEnum(E, str(o, k)) orelse def;
}

fn numOf(v: json.Value) f64 {
    return switch (v) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => std.math.nan(f64),
    };
}

fn pattern(o: Obj) film.Pattern {
    return .{
        .mode = enumOf(film.Mode, o, "mode", .binary),
        .threshold = num(o, "threshold"),
        .gamma = num(o, "gamma"),
        .invert = if (o.get("invert")) |v| v == .bool and v.bool else false,
        .ht_pattern = enumOf(film.HtPattern, o, "htPattern", .dot),
        .grid = enumOf(film.Grid, o, "grid", .film),
        .pitch = num(o, "pitch"),
        .fill = num(o, "fill"),
        .ht_angle = num(o, "htAngle"),
        .wave_amp = num(o, "waveAmp"),
        .wave_len = num(o, "waveLen"),
    };
}

fn placement(o: Obj) film.Placement {
    return .{ .iw = num(o, "iw"), .ix = num(o, "ix"), .iy = num(o, "iy"), .aspect = num(o, "aspect") };
}

fn lampParams(o: Obj) lamp.Params {
    return .{
        .pattern = pattern(o),
        .placement = placement(o),
        .dia = num(o, "dia"),
        .len = num(o, "len"),
        .glass = num(o, "glass"),
        .n = num(o, "n"),
        .s = num(o, "s"),
        .gd = num(o, "gd"),
        .rim_w = num(o, "rimW"),
        .front_t = num(o, "frontT"),
        .plug_depth = num(o, "plugDepth"),
        .cable_d = num(o, "cableD"),
        .cable_angle = num(o, "cableAngle"),
        .lx = num(o, "lx"),
        .ly = num(o, "ly"),
        .lz = num(o, "lz"),
        .dpi = num(o, "dpi"),
        .seam = num(o, "seam"),
        .front = enumOf(lamp.Front, o, "front", .black),
        .surface = enumOf(lamp.Surface, o, "surface", .film),
    };
}

fn candleParams(o: Obj) candle.Params {
    return .{
        .pattern = pattern(o),
        .placement = placement(o),
        .dia = num(o, "dia"),
        .glass = num(o, "glass"),
        .n = num(o, "n"),
        .gb = num(o, "gb"),
        .gh = num(o, "gh"),
        .cd = num(o, "cd"),
        .hd = num(o, "hd"),
        .fwid = num(o, "fwid"),
        .fhei = num(o, "fhei"),
        .seam = num(o, "seam"),
        .dpi = num(o, "dpi"),
        .source = enumOf(candle.Source, o, "source", .real),
        .unused = enumOf(candle.Unused, o, "unused", .black),
    };
}

/// a and b agree to a relative/absolute tolerance
fn close(a: f64, b: f64, tol: f64) bool {
    return @abs(a - b) <= tol * @max(1, @max(@abs(a), @abs(b)));
}

fn fail(comptime f: []const u8, args: anytype) error{TestUnexpectedResult} {
    std.debug.print(f ++ "\n", args);
    return error.TestUnexpectedResult;
}

/// "tube_end" -> "tubeEnd"
fn camel(buf: []u8, name: []const u8) []const u8 {
    var n: usize = 0;
    var up = false;
    for (name) |c| {
        if (c == '_') {
            up = true;
            continue;
        }
        buf[n] = if (up) std.ascii.toUpper(c) else c;
        up = false;
        n += 1;
    }
    return buf[0..n];
}

/// Compares a struct of numbers with its JSON from the first version. JSON
/// names are the camelCase field names; case is ignored ("Db" is `db`).
fn expectSameAsJson(value: anytype, j: json.Value, path: []const u8) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (j != .object) return fail("{s}: not an object", .{path});
            if (j.object.count() != s.field_names.len) return fail("{s}: {d} fields, want {d}", .{ path, s.field_names.len, j.object.count() });
            inline for (s.field_names) |name| {
                var buf: [64]u8 = undefined;
                const key = camel(&buf, name);
                var found: ?json.Value = null;
                var it = j.object.iterator();
                while (it.next()) |e| {
                    if (std.ascii.eqlIgnoreCase(e.key_ptr.*, key)) found = e.value_ptr.*;
                }
                const jv = found orelse return fail("{s}.{s}: missing in the reference", .{ path, key });
                try expectSameAsJson(@field(value, name), jv, key);
            }
        },
        .array => {
            if (j != .array or j.array.items.len != value.len) return fail("{s}: array differs", .{path});
            for (value, j.array.items) |v, jv| try expectSameAsJson(v, jv, path);
        },
        .float => if (!close(value, numOf(j), 1e-12)) return fail("{s}: {d}, want {d}", .{ path, value, numOf(j) }),
        else => @compileError("unexpected type"),
    }
}

fn expectWarnings(got: []const []const u8, want: json.Value) !void {
    const items = want.array.items;
    if (got.len != items.len) return fail("{d} warnings, want {d}", .{ got.len, items.len });
    for (got, items) |g, w| try testing.expectEqualStrings(w.string, g);
}

fn expectSampledPixels(f: *const film.Film, pixels: json.Value) !void {
    var bad: usize = 0;
    for (pixels.array.items) |px| {
        const i: usize = @intCast(px.array.items[0].integer);
        if (f.data[i] != px.array.items[1].integer) bad += 1;
    }
    if (bad > pixels.array.items.len / 200) return fail("{d} of {d} sampled pixels differ", .{ bad, pixels.array.items.len });
}

fn expectFilm(f: *const film.Film, c: Obj) !void {
    const w: usize = @intCast(c.get("w").?.integer);
    const h: usize = @intCast(c.get("h").?.integer);
    if (f.w != w or f.h != h or f.px != num(c, "px")) return fail("film {d}x{d} px {d}, want {d}x{d} px {d}", .{ f.w, f.h, f.px, w, h, num(c, "px") });
    // Interpolated wall points are stored as f32 like the first version; a
    // pixel right on a pattern edge may still fall on the other side, so
    // allow a few.
    const open: f64 = @floatFromInt(f.open());
    if (@abs(open - num(c, "open")) > 0.001 * @as(f64, @floatFromInt(f.w * f.h)))
        return fail("open {d}, want {d}", .{ open, num(c, "open") });
    try expectSampledPixels(f, c.get("pixels").?);
}

test "night lamp matches the first version" {
    const gpa = testing.allocator;
    var parsed = try json.parseFromSlice(json.Value, gpa, reference, .{});
    defer parsed.deinit();

    for (parsed.value.object.get("lamp").?.array.items) |cv| {
        const c = cv.object;
        errdefer std.debug.print("lamp case {s}\n", .{str(c, "name")});
        const p = lampParams(c.get("p").?.object);
        try testing.expectEqual(p.lz, lamp.ledZ(&p));

        var r = try lamp.compute(gpa, &p, sampler(str(c, "sampler")));
        defer r.deinit(gpa);
        try expectFilm(&r.film, c);
        var shadow: usize = 0;
        for (r.film.shadow) |v| shadow += v;
        try testing.expectEqual(@as(usize, @intCast(c.get("shadow").?.integer)), shadow);

        for (c.get("filmToWall").?.array.items) |qv| {
            const q = qv.array.items;
            const got = r.B.filmToWall(r.B.filmPoint(numOf(q[0]), numOf(q[1])));
            if ((got != null) != (q[2] != .null)) return fail("filmToWall({d}, {d}) ok differs", .{ numOf(q[0]), numOf(q[1]) });
            if (got) |g| {
                if (!close(g[0], numOf(q[2]), 1e-9) or !close(g[1], numOf(q[3]), 1e-9))
                    return fail("filmToWall = {d}, {d}, want {d}, {d}", .{ g[0], g[1], numOf(q[2]), numOf(q[3]) });
            }
        }

        var lit_bad: usize = 0;
        const lit = c.get("lit").?.array.items;
        for (lit) |lv| {
            const l = lv.array.items;
            const qx = numOf(l[0]);
            const qy = numOf(l[1]);
            const hit = r.B.wallToFilm(qx, qy);
            if ((hit != null) != (l[4] != .null)) return fail("wallToFilm({d}, {d}) ok differs", .{ qx, qy });
            if (hit) |P| {
                for (0..3) |k| {
                    if (!close(P[k], numOf(l[4].array.items[k]), 1e-9)) return fail("wallToFilm({d}, {d}) differs", .{ qx, qy });
                }
            }
            if (r.litAt(qx, qy) != numOf(l[2])) lit_bad += 1;
            const pen = r.penumbraAt(qx, qy, 2);
            if (!close(pen, numOf(l[3]), 1e-9)) return fail("penumbraAt({d}, {d}) = {d}, want {d}", .{ qx, qy, pen, numOf(l[3]) });
        }
        if (lit_bad > lit.len / 100) return fail("litAt differs at {d} of {d} points", .{ lit_bad, lit.len });
        if (!close(r.B.innerRadius(), num(c, "innerRadius"), 1e-12)) return fail("innerRadius {d}", .{r.B.innerRadius()});

        const d = lamp.baseDims(&p);
        try expectSameAsJson(d, c.get("dims").?, "dims");
        const w = lamp.baseWarnings(&p, &d);
        try expectWarnings(w.slice(), c.get("warnings").?);

        var drawing = try parts.partsDrawing(gpa, &p);
        defer drawing.deinit();
        const svg = try drawing.svgAlloc(gpa);
        defer gpa.free(svg);
        const want = str(c, "svg");
        if (!std.mem.eql(u8, svg, want)) {
            const i = std.mem.indexOfDiff(u8, svg, want) orelse 0;
            return fail("parts SVG differs at byte {d}:\n got …{s}\nwant …{s}", .{
                i, svg[i -| 60..@min(svg.len, i + 60)], want[i -| 60..@min(want.len, i + 60)],
            });
        }
    }
}

test "candle glass matches the first version" {
    const gpa = testing.allocator;
    var parsed = try json.parseFromSlice(json.Value, gpa, reference, .{});
    defer parsed.deinit();

    for (parsed.value.object.get("candle").?.array.items) |cv| {
        const c = cv.object;
        errdefer std.debug.print("candle case {s}\n", .{str(c, "name")});
        const p = candleParams(c.get("p").?.object);
        var r = try candle.compute(gpa, &p, sampler(str(c, "sampler")));
        defer r.deinit(gpa);
        try expectFilm(&r.film, c);

        var lit_bad: usize = 0;
        const lit = c.get("lit").?.array.items;
        for (lit) |lv| {
            const l = lv.array.items;
            const tx = numOf(l[0]);
            const ty = numOf(l[1]);
            const La = l[2].array.items;
            const L = [3]f64{ numOf(La[0]), numOf(La[1]), numOf(La[2]) };
            if (r.litAt(tx, ty, L) != numOf(l[3])) lit_bad += 1;
            const blur = r.blurAt(tx, ty, p.fwid);
            if (!close(blur, numOf(l[4]), 1e-9)) return fail("blurAt({d}, {d}) = {d}, want {d}", .{ tx, ty, blur, numOf(l[4]) });
        }
        if (lit_bad > lit.len / 100) return fail("litAt differs at {d} of {d} points", .{ lit_bad, lit.len });
        const ri = candle.innerRadius(&p, p.hd);
        if (!close(ri, num(c, "innerRadius"), 1e-12)) return fail("innerRadius {d}, want {d}", .{ ri, num(c, "innerRadius") });
        const w = candle.warnings(&p);
        try expectWarnings(w.slice(), c.get("warnings").?);
    }
}

test "halftone screens match the first version" {
    const gpa = testing.allocator;
    var parsed = try json.parseFromSlice(json.Value, gpa, reference, .{});
    defer parsed.deinit();

    for (parsed.value.object.get("screens").?.array.items) |sv| {
        const p = pattern(sv.object.get("p").?.object);
        const s = screen.Screen.init(&p);
        var bad: usize = 0;
        const pts = sv.object.get("pts").?.array.items;
        for (pts) |qv| {
            const q = qv.array.items;
            if (s.clear(numOf(q[0]), numOf(q[1]), numOf(q[2])) != (numOf(q[3]) == 1)) bad += 1;
        }
        if (bad > 0) return fail("{s}: {d} of {d} points differ", .{ @tagName(p.ht_pattern), bad, pts.len });
    }
}

test "PNG resolution chunk matches the first version" {
    const gpa = testing.allocator;
    var parsed = try json.parseFromSlice(json.Value, gpa, reference, .{});
    defer parsed.deinit();

    const o = parsed.value.object.get("png").?.object;
    const in_hex = str(o, "input");
    const in = try gpa.alloc(u8, in_hex.len / 2);
    defer gpa.free(in);
    _ = try std.fmt.hexToBytes(in, in_hex);
    const out = try png.withDpi(gpa, in, num(o, "dpi"));
    defer gpa.free(out);
    const got = try gpa.alloc(u8, out.len * 2);
    defer gpa.free(got);
    _ = std.fmt.bufPrint(got, "{x}", .{out}) catch unreachable;
    try testing.expectEqualStrings(str(o, "output"), got);
}
