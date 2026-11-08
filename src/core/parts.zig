//! Technical drawing of the night lamp (1:1, mm): back cap, front plug,
//! section and parts list.
//!
//! The drawing is a list of simple shapes. The same list is written as SVG
//! (byte for byte the same text as the first version) and drawn on screen.

const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = @import("format.zig");
const lamp = @import("lamp.zig");
const dims_ = @import("lamp_dims.zig");

/// Style classes of the SVG (the names are the class names).
pub const Class = enum { w, cut, cap, felt, led, glass, cable, plugO, chanO, chanI, pcb, glue, scrH, scr, wire, o, jack, hid, wh, ray, wall, d, dt, t, h, scale };
pub const Anchor = enum { start, middle, end };

pub const Elem = union(enum) {
    circle: struct { cx: f64, cy: f64, r: f64, cls: Class },
    rect: struct { x: f64, y: f64, w: f64, h: f64, cls: Class },
    /// sw: stroke width, 0 = from the class
    line: struct { x1: f64, y1: f64, x2: f64, y2: f64, cls: Class, sw: f64 },
    text: struct { x: f64, y: f64, s: []const u8, cls: Class, anchor: Anchor, rot: f64 },
    polygon: struct { pts: []const [2]f64, cls: Class },
    polyline: struct { pts: []const [2]f64, cls: Class, sw: f64 },
    /// The LED's light: two short strokes pointing at (x, y)
    arrow: struct { x: f64, y: f64 },
};

pub const Drawing = struct {
    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(Elem) = .empty,
    /// Size in mm
    w: f64 = 0,
    h: f64 = 0,

    pub fn deinit(d: *Drawing) void {
        d.arena.deinit();
    }

    /// Writes the drawing as SVG with its size in mm.
    pub fn writeSvg(d: *const Drawing, w: *std.Io.Writer) !void {
        try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{f}mm\" height=\"{f}mm\" viewBox=\"0 0 {f} {f}\">", .{
            fmt.fixed1(d.w), fmt.fixed1(d.h), fmt.fixed1(d.w), fmt.fixed1(d.h),
        });
        try w.writeAll(svg_head);
        for (d.items.items) |e| try writeElem(w, e);
        try w.writeAll("</svg>");
    }

    /// The SVG as one string (owned by the caller).
    pub fn svgAlloc(d: *const Drawing, gpa: Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        try d.writeSvg(&out.writer);
        return out.toOwnedSlice();
    }
};

const svg_head =
    "<defs><pattern id=\"wood\" patternUnits=\"userSpaceOnUse\" width=\"2.5\" height=\"2.5\" patternTransform=\"rotate(45)\">" ++
    "<rect width=\"2.5\" height=\"2.5\" fill=\"#f3e6cf\"/><line x1=\"0\" y1=\"0\" x2=\"0\" y2=\"2.5\" stroke=\"#c19a64\" stroke-width=\"0.35\"/></pattern></defs>" ++
    "<style>.w{fill:url(#wood);stroke:#222;stroke-width:0.35}.cut{fill:#fff;stroke:#222;stroke-width:0.3}" ++
    ".cap{fill:#e2c79b;stroke:#222;stroke-width:0.35}.felt{fill:#8b6f8e;stroke:none}" ++
    ".led{fill:#ffd23f;stroke:#a07800;stroke-width:0.3}.glass{fill:#cfe6dc;stroke:#5c8a78;stroke-width:0.2}" ++
    ".cable{fill:none;stroke:#333;stroke-linejoin:round;stroke-linecap:round;opacity:0.85}" ++
    ".plugO{fill:none;stroke:#222;stroke-width:0.3;stroke-dasharray:1.5 0.8}.chanO{stroke:#222}.chanI{stroke:#fff}" ++
    ".pcb{fill:#2e7d4f;stroke:#14402a;stroke-width:0.2}.glue{stroke:#555;stroke-dasharray:1 0.6}.scrH{fill:#888;stroke:#444;stroke-width:0.2}.scr{stroke:#888}.wire{stroke:#c0392b}.o{fill:none;stroke:#222;stroke-width:0.3}" ++
    ".jack{fill:#3a3a3a;stroke:#000;stroke-width:0.2}.hid{fill:#fff;stroke:#222;stroke-width:0.3;stroke-dasharray:1 0.6}" ++
    ".wh{stroke:#fff;stroke-width:0.5}.ray{fill:none;stroke:#e0a000;stroke-width:0.3}" ++
    ".wall{stroke:#444;stroke-width:1.2}.d{stroke:#c0392b;stroke-width:0.2;fill:none}.dt{fill:#c0392b;font:2.8px sans-serif}" ++
    ".t{fill:#222;font:3.2px sans-serif}.h{fill:#222;font:bold 4px sans-serif}.scale{fill:#222}</style>" ++
    "<rect width=\"100%\" height=\"100%\" fill=\"#fff\"/>";

fn f1(x: f64) fmt.Fixed {
    return fmt.fixed1(x);
}

fn writePoints(w: *std.Io.Writer, pts: []const [2]f64) !void {
    for (pts, 0..) |q, i| {
        if (i > 0) try w.writeByte(' ');
        try w.print("{f},{f}", .{ f1(q[0]), f1(q[1]) });
    }
}

fn writeElem(w: *std.Io.Writer, e: Elem) !void {
    switch (e) {
        .circle => |c| try w.print("<circle cx=\"{f}\" cy=\"{f}\" r=\"{f}\" class=\"{s}\"/>", .{ f1(c.cx), f1(c.cy), f1(c.r), @tagName(c.cls) }),
        .rect => |r| try w.print("<rect x=\"{f}\" y=\"{f}\" width=\"{f}\" height=\"{f}\" class=\"{s}\"/>", .{ f1(r.x), f1(r.y), f1(r.w), f1(r.h), @tagName(r.cls) }),
        .line => |l| {
            try w.print("<line x1=\"{f}\" y1=\"{f}\" x2=\"{f}\" y2=\"{f}\" class=\"{s}\"", .{ f1(l.x1), f1(l.y1), f1(l.x2), f1(l.y2), @tagName(l.cls) });
            if (l.sw != 0) try w.print(" stroke-width=\"{f}\"", .{f1(l.sw)});
            try w.writeAll("/>");
        },
        .text => |t| {
            try w.print("<text x=\"{f}\" y=\"{f}\" class=\"{s}\" text-anchor=\"{s}\"", .{ f1(t.x), f1(t.y), @tagName(t.cls), @tagName(t.anchor) });
            if (t.rot != 0) try w.print(" transform=\"rotate({f} {f} {f})\"", .{ fmt.num(t.rot), f1(t.x), f1(t.y) });
            // The texts are fixed labels and numbers: nothing to escape
            try w.print(">{s}</text>", .{t.s});
        },
        .polygon => |p| {
            try w.writeAll("<polygon points=\"");
            try writePoints(w, p.pts);
            try w.print("\" class=\"{s}\"/>", .{@tagName(p.cls)});
        },
        .polyline => |p| {
            try w.writeAll("<polyline points=\"");
            try writePoints(w, p.pts);
            try w.print("\" class=\"{s}\" stroke-width=\"{f}\"/>", .{ @tagName(p.cls), f1(p.sw) });
        },
        .arrow => |a| try w.print("<path d=\"M{f} {f} l-6 -4 m6 4 l-6 4\" class=\"ray\"/>", .{ f1(a.x), f1(a.y) }),
    }
}

/// Collects the shapes while the drawing is made.
const Builder = struct {
    d: *Drawing,
    dims: *const dims_.Dims,

    fn alloc(b: *Builder) Allocator {
        return b.d.arena.allocator();
    }

    fn add(b: *Builder, e: Elem) !void {
        try b.d.items.append(b.alloc(), e);
    }

    fn str(b: *Builder, comptime f: []const u8, args: anytype) ![]const u8 {
        return std.fmt.allocPrint(b.alloc(), f, args);
    }

    fn circle(b: *Builder, cx: f64, cy: f64, r: f64, cls: Class) !void {
        try b.add(.{ .circle = .{ .cx = cx, .cy = cy, .r = r, .cls = cls } });
    }

    fn rect(b: *Builder, x0: f64, y0: f64, x1: f64, y1: f64, cls: Class) !void {
        try b.add(.{ .rect = .{ .x = @min(x0, x1), .y = @min(y0, y1), .w = @abs(x1 - x0), .h = @abs(y1 - y0), .cls = cls } });
    }

    fn line(b: *Builder, x1: f64, y1: f64, x2: f64, y2: f64, cls: Class, sw: f64) !void {
        try b.add(.{ .line = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .cls = cls, .sw = sw } });
    }

    /// A label; rot 0 is no rotation.
    fn text(b: *Builder, x: f64, y: f64, s: []const u8, cls: Class, anchor: Anchor, rot: f64) !void {
        try b.add(.{ .text = .{ .x = x, .y = y, .s = s, .cls = cls, .anchor = anchor, .rot = rot } });
    }

    fn dimH(b: *Builder, x1: f64, x2: f64, y: f64, lbl: []const u8) !void {
        try b.line(x1, y, x2, y, .d, 0);
        for ([_]f64{ x1, x2 }) |x| try b.line(x - 1, y + 1, x + 1, y - 1, .d, 0);
        try b.text((x1 + x2) / 2, y - 1.2, lbl, .dt, .middle, 0);
    }

    fn dimV(b: *Builder, x: f64, y1: f64, y2: f64, lbl: []const u8) !void {
        try b.line(x, y1, x, y2, .d, 0);
        for ([_]f64{ y1, y2 }) |y| try b.line(x - 1, y + 1, x + 1, y - 1, .d, 0);
        try b.text(x - 1.2, (y1 + y2) / 2, lbl, .dt, .middle, -90);
    }

    fn points(b: *Builder, pts: []const [2]f64) ![]const [2]f64 {
        return b.alloc().dupe([2]f64, pts);
    }

    /// A rim slot: from the edge of the disc to where the cable sits, as wide
    /// as the cable.
    fn slot(b: *Builder, cx: f64, cy: f64, ang: f64, r_in: f64, r_out: f64) !void {
        const ux = @cos(ang);
        const uy = -@sin(ang);
        const vx = -uy;
        const vy = ux;
        const h = b.dims.cable.d / 2;
        var pts = [4][2]f64{ .{ r_in, -h }, .{ r_out + 0.5, -h }, .{ r_out + 0.5, h }, .{ r_in, h } };
        for (&pts) |*q| {
            // copy first: assigning an array literal writes q[0] before q[1] is computed
            const a = q.*;
            q.* = .{ cx + a[0] * ux + a[1] * vx, cy + a[0] * uy + a[1] * vy };
        }
        try b.add(.{ .polygon = .{ .pts = try b.points(&pts), .cls = .cut } });
    }

    /// Keyhole: head hole at the bottom, slot upward (y points down in SVG).
    fn keyhole(b: *Builder, cx: f64, cy: f64) !void {
        const k = b.dims.key;
        try b.circle(cx, cy, k.r, .cut);
        try b.rect(cx - k.w / 2, cy, cx + k.w / 2, cy - k.slot, .cut);
        try b.circle(cx, cy - k.slot, k.w / 2, .cut);
        try b.line(cx - k.w / 2 + 0.2, cy, cx + k.w / 2 - 0.2, cy, .wh, 0);
    }
};

const num = fmt.num;

/// Makes the technical drawing. Free with `Drawing.deinit`.
pub fn partsDrawing(gpa: Allocator, p: *const lamp.Params) !Drawing {
    var drawing: Drawing = .{ .arena = .init(gpa) };
    errdefer drawing.deinit();
    const d = dims_.baseDims(p);
    var s: Builder = .{ .d = &drawing, .dims = &d };

    const R = d.db / 2;
    const cb = d.cable;
    const fr = d.front;
    const lz = lamp.ledZ(p);
    const ang = d.cable.angle * std.math.pi / 180;
    const top = 22.0;
    const cy = top + R + 8;

    // 1. Back cap, front face (tube side; seen from the front)
    const ax = 15 + R;
    try s.text(ax - R, top, "Back cap — front face (tube side)", .h, .start, 0);
    try s.circle(ax, cy, R, .w);
    try s.circle(ax, cy, d.gout / 2, .cut);
    try s.circle(ax, cy, d.gin / 2, .w);
    try s.slot(ax, cy, ang, d.gout / 2 - 0.5, R);
    try s.dimH(ax - R, ax + R, cy + R + 6, try s.str("Ø {f} × {f}", .{ f1(d.db), f1(d.s) }));
    try s.dimH(ax - d.gout / 2, ax + d.gout / 2, cy - R - 3, try s.str("groove outer Ø {f}", .{f1(d.gout)}));
    try s.dimH(ax - d.gin / 2, ax + d.gin / 2, cy + 3, try s.str("groove inner Ø {f}, depth {f}", .{ f1(d.gin), f1(d.gd) }));
    try s.text(ax, cy - 6, try s.str("cable slot: {f} wide, through", .{f1(cb.d)}), .dt, .middle, 0);
    try s.text(ax, cy - 2.5, "at the very bottom (cable weight must not tilt the lamp)", .dt, .middle, 0);

    // 2. Back cap, back face (wall side; seen from behind, x mirrored)
    const bx = ax + d.db + 26;
    try s.text(bx - R, top, "Back cap — back face (wall side)", .h, .start, 0);
    try s.circle(bx, cy, R, .w);
    const ub = d.usb;
    const ux = bx - ub.x;
    const sxb = bx - (d.gout / 2) * @cos(ang);
    const syb = cy - (d.gout / 2) * @sin(ang);
    try s.line(ux, cy + ub.top + 1, sxb, syb, .chanO, d.chan.w + 0.6);
    try s.line(ux, cy + ub.top + 1, sxb, syb, .chanI, d.chan.w);
    try s.rect(ux - ub.w / 2, cy + ub.top, ux + ub.w / 2, cy + ub.rim - ub.wall, .cut);
    try s.rect(ux - ub.port[0] / 2, cy + ub.rim - ub.wall, ux + ub.port[0] / 2, cy + R, .hid);
    try s.rect(ux - 4.5, cy + ub.rim - ub.wall - 7.5, ux + 4.5, cy + ub.rim - ub.wall, .jack);
    try s.rect(ux - ub.w / 2 + 0.5, cy + ub.top + 0.5, ux + ub.w / 2 - 0.5, cy + ub.rim - ub.wall - 7.5, .pcb);
    try s.slot(bx, cy, std.math.pi - ang, d.gout / 2 - 0.5, R);
    try s.keyhole(bx, cy - d.key.y);
    try s.text(ux + ub.w / 2 + 2, cy + ub.top + 3, try s.str("USB-C pocket {f}×{f}, depth {f}", .{ num(ub.w), num(ub.len), num(ub.depth) }), .dt, .start, 0);
    try s.text(ux + ub.w / 2 + 2, cy + ub.top + 6.5, try s.str("{f} mm from center (left when seen from the front)", .{f1(@abs(ub.x))}), .dt, .start, 0);
    try s.text(ux + ub.w / 2 + 2, cy + ub.top + 10, try s.str("{f}×{f} window in the bottom edge (plug from below)", .{ num(ub.port[0]), num(ub.port[1]) }), .dt, .start, 0);
    try s.text(bx - R, cy + R + 7, try s.str("cable channel {f}×{f}: from the USB-C pocket to the rim slot", .{ f1(d.chan.w), f1(d.chan.d) }), .dt, .start, 0);
    try s.text(bx + 7, cy - d.key.y - 2, try s.str("keyhole: head Ø{f}, slot {f}, depth {f}", .{ f1(2 * d.key.r), num(d.key.w), num(d.key.depth) }), .dt, .start, 0);
    try s.text(bx + 7, cy - d.key.y + 1.5, try s.str("{f} mm above center", .{f1(d.key.y)}), .dt, .start, 0);

    // 3. Section through the cable's plane; z to the right (wall on the left), cable on top
    const sx = bx + R + 30;
    const Z = struct {
        sx: f64,
        fn at(z: @This(), v: f64) f64 {
            return z.sx + v;
        }
    }{ .sx = sx };
    const Y = struct {
        cy: f64,
        fn at(y: @This(), v: f64) f64 {
            return y.cy - v;
        }
    }{ .cy = cy };
    const zF = d.tube_end;
    const zEnd = zF + fr.t;
    const cr = cb.R;
    try s.text(sx, top, "Section (through the cable)", .h, .start, 0);
    try s.line(Z.at(0), Y.at(R + 10), Z.at(0), Y.at(-R - 10), .wall, 0);
    try s.text(Z.at(-1.5), Y.at(R + 7), "wall", .t, .end, 0);
    try s.rect(Z.at(0), Y.at(R), Z.at(d.s), Y.at(-R), .w);
    for ([_]f64{ -1, 1 }) |sg| try s.rect(Z.at(d.s - d.gd), Y.at(sg * d.gin / 2), Z.at(d.s), Y.at(sg * d.gout / 2), .cut);
    try s.rect(Z.at(0), Y.at(R + 0.5), Z.at(d.s), Y.at(d.gout / 2 - 0.5), .cut);
    for ([_]f64{ -1, 1 }) |sg| try s.rect(Z.at(d.s - d.gd), Y.at(sg * d.rin), Z.at(zF), Y.at(sg * p.dia / 2), .glass);
    try s.rect(Z.at(zF), Y.at(R), Z.at(zEnd), Y.at(-R), .cap);
    try s.rect(Z.at(zF - fr.plug_depth), Y.at(fr.plug_d / 2), Z.at(zF), Y.at(-fr.plug_d / 2), .cap);
    for ([_]f64{ -1, 1 }) |sg| try s.rect(Z.at(zF - fr.plug_depth), Y.at(sg * fr.plug_d / 2), Z.at(zF), Y.at(sg * (fr.plug_d / 2 + fr.felt)), .felt);
    try s.rect(Z.at(zF), Y.at(R + 0.5), Z.at(zEnd), Y.at(d.gout / 2 - 0.5), .cut);
    try s.rect(Z.at(zEnd - cb.d - 0.5), Y.at(R + 0.5), Z.at(zEnd), Y.at(0), .cut);
    try s.rect(Z.at(zF - fr.cav_depth), Y.at(fr.cav_d / 2), Z.at(zF), Y.at(-fr.cav_d / 2), .cut);
    try s.rect(Z.at(zF - fr.cav_depth + 0.5), Y.at(fr.cav_d / 2 - 6), Z.at(zF - fr.cav_depth + 2.1), Y.at(-fr.cav_d / 2 + 6), .pcb);
    try s.rect(Z.at(zF), Y.at(fr.hole / 2), Z.at(zEnd), Y.at(-fr.hole / 2), .cut);
    try s.rect(Z.at(zF - fr.plug_depth), Y.at(fr.led_hole / 2), Z.at(zF - fr.cav_depth), Y.at(-fr.led_hole / 2), .cut);
    for ([_]f64{ -1, 1 }) |sg| {
        try s.line(Z.at(zF - fr.plug_depth), Y.at(sg * fr.screw_r), Z.at(zF - fr.plug_depth + fr.screw.len), Y.at(sg * fr.screw_r), .scr, fr.screw.d);
        try s.rect(Z.at(zF - fr.plug_depth), Y.at(sg * fr.screw_r - fr.screw.head / 2), Z.at(zF - fr.plug_depth + 1.5), Y.at(sg * fr.screw_r + fr.screw.head / 2), .scrH);
    }
    try s.line(Z.at(zF), Y.at(fr.plug_d / 2), Z.at(zF), Y.at(-fr.plug_d / 2), .glue, 0.6);
    // cable: from the back cap slot along the glass, over the front of the plug to the center and in
    try s.add(.{ .polyline = .{ .pts = try s.points(&.{
        .{ Z.at(0), Y.at(cr) },
        .{ Z.at(zEnd - cb.d / 2 - 0.25), Y.at(cr) },
        .{ Z.at(zEnd - cb.d / 2 - 0.25), Y.at(0) },
        .{ Z.at(zF - fr.cav_depth + 2.5), Y.at(0) },
    }), .cls = .cable, .sw = cb.d } });
    try s.line(Z.at(zF - fr.cav_depth + 0.5), Y.at(0), Z.at(lz + 2), Y.at(0), .wire, 0.6);
    try s.rect(Z.at(0), Y.at(cr - cb.d), Z.at(d.chan.d), Y.at(cr - cb.d - 10), .cut);
    try s.add(.{ .polyline = .{ .pts = try s.points(&.{
        .{ Z.at(d.chan.d / 2), Y.at(cr - cb.d - 10) },
        .{ Z.at(d.chan.d / 2), Y.at(cr) },
        .{ Z.at(1), Y.at(cr) },
    }), .cls = .cable, .sw = cb.d } });
    try s.rect(Z.at(lz), Y.at(2), Z.at(lz + 2), Y.at(-2), .led);
    try s.add(.{ .arrow = .{ .x = Z.at(lz), .y = Y.at(0) } });
    try s.dimV(Z.at(-7), Y.at(R), Y.at(-R), try s.str("Ø {f}", .{f1(d.db)}));
    try s.dimH(Z.at(0), Z.at(d.s), Y.at(-R - 5), try s.str("{f}", .{f1(d.s)}));
    try s.dimH(Z.at(0), Z.at(lz), Y.at(-R - 11), try s.str("LED from wall {f}", .{f1(lz)}));
    try s.dimH(Z.at(0), Z.at(zF), Y.at(-R - 17), try s.str("back of plug {f}", .{f1(zF)}));
    try s.dimH(Z.at(zF), Z.at(zEnd), Y.at(R + 4), try s.str("{f}", .{f1(fr.t)}));
    try s.dimH(Z.at(zF - fr.plug_depth), Z.at(zF), Y.at(-fr.plug_d / 2 - 4), try s.str("{f}", .{f1(fr.plug_depth)}));
    try s.text(Z.at(zF - fr.cav_depth / 2), Y.at(fr.cav_d / 2 - 9), "circuit", .dt, .middle, 0);
    try s.text(Z.at(lz - 7), Y.at(-6), "LED on the cup bottom, facing the wall", .dt, .end, 0);
    try s.text(Z.at(zF - fr.plug_depth - 1), Y.at(-fr.screw_r - 3), "screw from below (through the cup wall into the disc)", .dt, .end, 0);
    try s.text(Z.at((d.s + zF) / 2), Y.at(cr + 3), "cable on the outside of the glass", .dt, .middle, 0);
    try s.text(Z.at(d.chan.d + 1), Y.at(cr - cb.d - 8), "← from the USB-C module (back channel)", .dt, .start, 0);

    // 4. Front plug, front face (viewer side)
    const y2 = cy + R + 34;
    const rx = 15 + R;
    const ry = y2 + R + 6;
    try s.text(15, y2, "Front plug — front face (viewer side)", .h, .start, 0);
    try s.circle(rx, ry, R, .cap);
    try s.circle(rx, ry, fr.plug_d / 2, .plugO);
    try s.slot(rx, ry, ang, d.gout / 2 - 0.5, R);
    try s.slot(rx, ry, ang, 0, d.gout / 2);
    try s.circle(rx, ry, fr.hole / 2, .cut);
    try s.dimH(rx - R, rx + R, ry + R + 6, try s.str("Ø {f}, thickness {f}", .{ f1(d.db), f1(fr.t) }));
    try s.dimH(rx - fr.plug_d / 2, rx + fr.plug_d / 2, ry - 6, try s.str("cup behind: Ø {f} × {f}", .{ f1(fr.plug_d), f1(fr.plug_depth) }));
    try s.text(rx, ry + 8, try s.str("center hole Ø{f} through", .{f1(fr.hole)}), .dt, .middle, 0);
    try s.text(rx, ry + 11.5, try s.str("cable channel {f} × {f} (rim to center)", .{ f1(cb.d), f1(cb.d + 0.5) }), .dt, .middle, 0);

    // 5. Cup: from above (separated from the disc, circuit space) and from below (LED side)
    const gx = rx + R + 22 + fr.plug_d / 2;
    const hx = gx + fr.plug_d + 14;
    const rr = fr.plug_d / 2;
    try s.text(gx - rr, y2, "Cup — from above (off the disc)", .h, .start, 0);
    try s.circle(gx, ry, rr, .cap);
    try s.circle(gx, ry, fr.cav_d / 2, .cut);
    try s.circle(gx, ry, fr.led_hole / 2, .o);
    for ([_]f64{ -1, 1 }) |sg| try s.circle(gx + sg * fr.screw_r, ry, fr.screw.hole / 2, .cut);
    try s.dimH(gx - rr, gx + rr, ry + rr + 6, try s.str("Ø {f} × {f}", .{ f1(fr.plug_d), f1(fr.plug_depth) }));
    try s.dimH(gx - fr.cav_d / 2, gx + fr.cav_d / 2, ry - 5, try s.str("circuit space Ø {f} × {f}", .{ f1(fr.cav_d), f1(fr.cav_depth) }));
    try s.text(gx, ry + 5, try s.str("cavity: Ø{f} Forstner, {f} deep; bottom {f}", .{ num(fr.cav_d), f1(fr.cav_depth), num(fr.bottom) }), .dt, .middle, 0);
    try s.text(gx, ry + 8.5, try s.str("screw hole Ø{f} through", .{num(fr.screw.hole)}), .dt, .middle, 0);
    try s.text(hx - rr, y2, "Cup — from below (LED side)", .h, .start, 0);
    try s.circle(hx, ry, rr, .cap);
    try s.circle(hx, ry, fr.led_hole / 2, .cut);
    for ([_]f64{ -1, 1 }) |sg| {
        try s.circle(hx + sg * fr.screw_r, ry, fr.screw.head / 2, .o);
        try s.circle(hx + sg * fr.screw_r, ry, fr.screw.hole / 2, .cut);
    }
    try s.rect(hx - 1.5, ry - 1, hx + 1.5, ry + 1, .led);
    try s.dimH(hx - rr, hx + rr, ry + rr + 6, try s.str("Ø {f}", .{f1(fr.plug_d)}));
    try s.text(hx, ry - 4, try s.str("LED + wire hole Ø{f}", .{num(fr.led_hole)}), .dt, .middle, 0);
    try s.text(hx, ry + 6, try s.str("countersink Ø{f}; pilot in disc Ø{f}", .{ num(fr.screw.head), num(fr.screw.pilot) }), .dt, .middle, 0);

    // 6. Parts list
    const lx = rx - R;
    const ly = ry + R + 18;
    try s.text(lx, ly, "Parts and notes", .h, .start, 0);
    const notes = [_][]const u8{
        try s.str("Glass tube: bottle cut in two places, length {f} mm (outer Ø {f}, glass {f})", .{ f1(p.len), f1(p.dia), f1(p.glass) }),
        try s.str("Back cap: wood, Ø {f} × {f} mm; tube glued into the groove with clear silicone/epoxy", .{ f1(d.db), f1(d.s) }),
        try s.str("Front plug disc: wood, Ø {f} × {f} mm; cable enters at the center", .{ f1(d.db), f1(fr.t) }),
        try s.str("Cup: wood, Ø {f} × {f} mm; Ø {f} × {f} mm Forstner cavity in the middle (circuit goes here)", .{ f1(fr.plug_d), f1(fr.plug_depth), f1(fr.cav_d), f1(fr.cav_depth) }),
        try s.str("Cup wall {f} mm; screws in the middle of the wall, ~{f} mm of wood on each side", .{ f1(fr.wall), f1(fr.screw_wood) }),
        try s.str("Cup screwed to the disc from below with 2 × {f} × {f} mm countersunk wood screws (not glued)", .{ num(fr.screw.d), num(fr.screw.len) }),
        try s.str("{f} mm felt or cork strip around the cup: tight fit, pull forward to remove", .{num(fr.felt)}),
        "Power input: USB-C receptacle module on the bottom edge of the back cap; any 5 V USB charger",
        "The USB-C module needs 5.1 kΩ CC resistors (\"Type-C 6P\" / \"5.1k\"); otherwise chargers supply no power",
        "Fix the module in its pocket with hot glue or epoxy (so it does not move when plugging in)",
        try s.str("Cable: Ø {f} mm, from the socket via the back channel to the rim slot, along the glass (bare) to the plug, through its channel to the center", .{f1(cb.d)}),
        "Fix the cable in the slots and on the glass with a few drops of clear silicone",
        try s.str("LED: 1–2 mm SMD, glued to the center of the outside of the cup bottom, facing the wall; {f} mm from the wall", .{f1(lz)}),
        try s.str("Circuit inside the cup: a resistor or a small module (up to Ø {f} × {f} mm)", .{ f1(fr.cav_d), f1(fr.cav_depth) }),
        "For a plain light no circuit is needed: a 100–150 Ω series resistor for 5 V and a white LED",
        "Service: pull the plug forward, remove the 2 screws under the cup, separate the cup from the disc",
        try s.str("Wall mount: 1 screw, head Ø ≤ {f} mm; hang the lamp on it and slide down", .{f1(2 * d.key.r - 1)}),
        try s.str("The cable casts a ~{f}° wide radial shadow on the wall", .{f1(cb.shadow_deg)}),
        "Scale 1:1, dimensions in mm. Print at 100%; the line below must measure 50 mm.",
    };
    for (notes, 0..) |t, i| try s.text(lx, ly + 7 + @as(f64, @floatFromInt(i)) * 5.2, t, .t, .start, 0);
    const sy = ly + 7 + @as(f64, @floatFromInt(notes.len)) * 5.2 + 3;
    try s.rect(lx, sy, lx + 50, sy + 1, .scale);
    try s.text(lx + 52, sy + 1.2, "50 mm", .dt, .start, 0);

    drawing.w = @max(sx + zEnd + 12, lx + 170);
    drawing.h = @max(@max(ry + R + 14, sy + 10), cy + R + 32);
    return drawing;
}
