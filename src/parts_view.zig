//! 4. The parts drawing of the night lamp on screen: the same list of shapes
//! as the SVG file (core/parts.zig), drawn with the styles of its classes.

const std = @import("std");
const lv = @import("lvgl");
const core = @import("core");
const parts = core.parts;
const Class = parts.Class;
const cv = @import("canvas.zig");
const Canvas = cv.Canvas;
const st = @import("style.zig");

/// The look of a class, as in the SVG style sheet. Widths are in mm.
const Style = struct {
    fill: ?u32 = null,
    stroke: ?u32 = null,
    width: f64 = 1, // SVG default
    dash: ?[2]f64 = null,
    opa: u8 = 255,
    wood: bool = false,
    font_mm: f64 = 0,
    bold: bool = false,
};

fn style(c: Class) Style {
    return switch (c) {
        .w => .{ .fill = 0xF3E6CF, .stroke = 0x222222, .width = 0.35, .wood = true },
        .cut => .{ .fill = 0xFFFFFF, .stroke = 0x222222, .width = 0.3 },
        .cap => .{ .fill = 0xE2C79B, .stroke = 0x222222, .width = 0.35 },
        .felt => .{ .fill = 0x8B6F8E },
        .led => .{ .fill = 0xFFD23F, .stroke = 0xA07800, .width = 0.3 },
        .glass => .{ .fill = 0xCFE6DC, .stroke = 0x5C8A78, .width = 0.2 },
        .cable => .{ .stroke = 0x333333, .opa = 217 },
        .plugO => .{ .stroke = 0x222222, .width = 0.3, .dash = .{ 1.5, 0.8 } },
        .chanO => .{ .fill = 0, .stroke = 0x222222 },
        .chanI => .{ .fill = 0, .stroke = 0xFFFFFF },
        .pcb => .{ .fill = 0x2E7D4F, .stroke = 0x14402A, .width = 0.2 },
        .glue => .{ .fill = 0, .stroke = 0x555555, .dash = .{ 1, 0.6 } },
        .scrH => .{ .fill = 0x888888, .stroke = 0x444444, .width = 0.2 },
        .scr => .{ .fill = 0, .stroke = 0x888888 },
        .wire => .{ .fill = 0, .stroke = 0xC0392B },
        .o => .{ .stroke = 0x222222, .width = 0.3 },
        .jack => .{ .fill = 0x3A3A3A, .stroke = 0x000000, .width = 0.2 },
        .hid => .{ .fill = 0xFFFFFF, .stroke = 0x222222, .width = 0.3, .dash = .{ 1, 0.6 } },
        .wh => .{ .fill = 0, .stroke = 0xFFFFFF, .width = 0.5 },
        .ray => .{ .stroke = 0xE0A000, .width = 0.3 },
        .wall => .{ .fill = 0, .stroke = 0x444444, .width = 1.2 },
        .d => .{ .stroke = 0xC0392B, .width = 0.2 },
        .dt => .{ .fill = 0xC0392B, .font_mm = 2.8 },
        .t => .{ .fill = 0x222222, .font_mm = 3.2 },
        .h => .{ .fill = 0x222222, .font_mm = 4, .bold = true },
        .scale => .{ .fill = 0x222222 },
    };
}

/// Smallest scale (pixels per mm) so the labels stay readable; a wider
/// drawing than the view scrolls sideways.
pub const min_scale = 3.5;

/// Draws the parts drawing into the canvas at `sc` pixels per mm.
pub fn draw(c: *Canvas, d: *const parts.Drawing, sc: f64) !void {
    c.fill(0xFFFFFF);
    // One font per text class at this scale
    var fonts: [3]?*lv.lv_font_t = .{ null, null, null };
    defer for (fonts) |f| st.freeFont(f);
    for ([_]Class{ .dt, .t, .h }, 0..) |cls, i| {
        const s = style(cls);
        fonts[i] = st.fontOfSize(@intFromFloat(@round(s.font_mm * sc * 1.1)), s.bold) orelse return error.FontLoadFailed;
    }

    c.begin();
    for (d.items.items) |e| switch (e) {
        .circle => |ci| {
            const s = style(ci.cls);
            if (s.fill) |f| cv.fillCircle(ci.cx * sc, ci.cy * sc, ci.r * sc, f, s.opa);
            if (s.wood) woodCircle(ci.cx, ci.cy, ci.r, sc);
            if (s.stroke) |k| {
                if (s.dash) |ds| {
                    cv.dashedCircle(ci.cx * sc, ci.cy * sc, ci.r * sc, @max(1, s.width * sc), k, ds[0] * sc, ds[1] * sc);
                } else {
                    cv.strokeCircle(ci.cx * sc, ci.cy * sc, ci.r * sc, @max(1, s.width * sc), k, s.opa);
                }
            }
        },
        .rect => |r| {
            const s = style(r.cls);
            if (s.fill) |f| cv.rect(r.x * sc, r.y * sc, r.w * sc, r.h * sc, f, s.opa);
            if (s.wood) woodRect(r.x, r.y, r.w, r.h, sc);
            if (s.stroke) |k| {
                const pts = [_][2]f64{ .{ r.x, r.y }, .{ r.x + r.w, r.y }, .{ r.x + r.w, r.y + r.h }, .{ r.x, r.y + r.h }, .{ r.x, r.y } };
                outline(&pts, k, s, s.width, sc);
            }
        },
        .line => |l| {
            const s = style(l.cls);
            const w = if (l.sw != 0) l.sw else s.width;
            segment(l.x1, l.y1, l.x2, l.y2, s.stroke orelse 0, s, w, sc, false);
        },
        .polygon => |p| {
            const s = style(p.cls);
            if (s.fill) |f| {
                for (1..p.pts.len - 1) |i| cv.triangle(
                    p.pts[0][0] * sc, p.pts[0][1] * sc, p.pts[i][0] * sc, p.pts[i][1] * sc, p.pts[i + 1][0] * sc, p.pts[i + 1][1] * sc, f, 255,
                );
            }
            if (s.stroke) |k| {
                for (0..p.pts.len) |i| {
                    const a = p.pts[i];
                    const b = p.pts[(i + 1) % p.pts.len];
                    segment(a[0], a[1], b[0], b[1], k, s, s.width, sc, false);
                }
            }
        },
        .polyline => |p| {
            const s = style(p.cls);
            for (1..p.pts.len) |i| segment(p.pts[i - 1][0], p.pts[i - 1][1], p.pts[i][0], p.pts[i][1], s.stroke orelse 0, s, p.sw, sc, true);
        },
        .arrow => |a| {
            const s = style(.ray);
            segment(a.x, a.y, a.x - 6, a.y - 4, s.stroke.?, s, s.width, sc, false);
            segment(a.x, a.y, a.x - 6, a.y + 4, s.stroke.?, s, s.width, sc, false);
        },
        .text => |t| {
            const s = style(t.cls);
            const font = fonts[switch (t.cls) {
                .dt => 0,
                .h => 2,
                else => 1,
            }];
            const alignment: cv.Align = switch (t.anchor) {
                .start => .start,
                .middle => .middle,
                .end => .end,
            };
            // turned labels (vertical dimensions) are drawn after the rest
            if (t.rot == 0) cv.text(t.x * sc, t.y * sc, st.zfmt("{s}", .{t.s}), font, s.fill.?, alignment);
        },
    };
    c.end();
    for (d.items.items) |e| switch (e) {
        .text => |t| if (t.rot != 0) {
            // The drawing only turns labels by -90° (upward)
            try cv.textUpward(c, t.x * sc, t.y * sc, st.zfmt("{s}", .{t.s}), fonts[0], style(t.cls).fill.?, .middle);
        },
        else => {},
    };
}

fn segment(x1: f64, y1: f64, x2: f64, y2: f64, color: u32, s: Style, width: f64, sc: f64, round: bool) void {
    const w = @max(1, width * sc);
    if (s.dash) |ds| {
        cv.dashedLine(x1 * sc, y1 * sc, x2 * sc, y2 * sc, w, color, @max(1, @as(i32, @intFromFloat(ds[0] * sc))), @max(1, @as(i32, @intFromFloat(ds[1] * sc))));
    } else if (round) {
        cv.roundLine(x1 * sc, y1 * sc, x2 * sc, y2 * sc, w, color, s.opa);
    } else {
        cv.line(x1 * sc, y1 * sc, x2 * sc, y2 * sc, w, color, s.opa);
    }
}

fn outline(pts: []const [2]f64, color: u32, s: Style, width: f64, sc: f64) void {
    for (1..pts.len) |i| segment(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], color, s, width, sc, false);
}

// Wood: thin lines at 45°, 2.5 mm apart (the SVG pattern, rotated 45°).
const wood_gap = 2.5;
const wood_color = 0xC19A64;
const n = [2]f64{ std.math.sqrt1_2, std.math.sqrt1_2 }; // normal of the lines
const u = [2]f64{ -std.math.sqrt1_2, std.math.sqrt1_2 }; // along the lines

fn woodLine(a: [2]f64, b: [2]f64, sc: f64) void {
    cv.line(a[0] * sc, a[1] * sc, b[0] * sc, b[1] * sc, @max(1, 0.35 * sc), wood_color, 255);
}

fn woodCircle(cx: f64, cy: f64, r: f64, sc: f64) void {
    const cn = cx * n[0] + cy * n[1];
    var k = @ceil((cn - r) / wood_gap);
    while (k * wood_gap < cn + r) : (k += 1) {
        const d = k * wood_gap - cn; // signed distance of the line from the center
        const half = @sqrt(@max(0, r * r - d * d));
        const mx = cx + d * n[0];
        const my = cy + d * n[1];
        woodLine(.{ mx - half * u[0], my - half * u[1] }, .{ mx + half * u[0], my + half * u[1] }, sc);
    }
}

fn woodRect(x: f64, y: f64, w: f64, h: f64, sc: f64) void {
    // The line p·n = c crosses the rectangle between its corners' values of p·n
    const c0 = (x + y) * n[0];
    const c1 = (x + w + y + h) * n[0];
    var k = @ceil(c0 / wood_gap);
    while (k * wood_gap < c1) : (k += 1) {
        const c = k * wood_gap / n[0]; // x + y = c on this line
        // Points of x + y = c inside the rectangle: x from max(x, c - (y+h)) to min(x+w, c - y)
        const xa = @max(x, c - (y + h));
        const xb = @min(x + w, c - y);
        if (xb <= xa) continue;
        woodLine(.{ xa, c - xa }, .{ xb, c - xb }, sc);
    }
}
