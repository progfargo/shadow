//! Sizes of the night lamp's wooden parts (back cap, front plug) and the
//! cable, and the warnings about them.

const std = @import("std");
const Params = @import("lamp.zig").Params;
const ledZ = @import("lamp.zig").ledZ;

/// The USB-C receptacle module (power only, small board): a pocket on the
/// back face, the plug window on the bottom edge. The cable slot is at the
/// very bottom, so the module is moved beside it.
pub const Usb = struct {
    w: f64,
    len: f64,
    depth: f64,
    port: [2]f64,
    wall: f64,
    x: f64 = 0, // offset from the center seen from the front, minus = left
    rim: f64 = 0, // y of the rim at the pocket's outer corner
    top: f64 = 0, // pocket edge nearest the center
};

pub const Channel = struct {
    w: f64,
    d: f64,
};

/// The keyhole for the wall screw on the back face.
pub const Key = struct {
    r: f64,
    slot: f64,
    w: f64,
    depth: f64,
    y: f64,
};

/// The cable rests on the outside of the glass and passes through rim slots
/// in the back cap and plug.
pub const Cable = struct {
    d: f64,
    R: f64,
    x: f64,
    y: f64,
    angle: f64,
    shadow_deg: f64,
};

pub const Screw = struct {
    d: f64,
    len: f64,
    hole: f64,
    pilot: f64,
    head: f64,
    bite: f64,
};

/// The front plug: a front disc and a hollow cup that goes into the tube
/// (tight fit with a 1 mm felt/cork strip). The cup is screwed to the disc
/// from below with 2 wood screws through its wall; the circuit is inside the
/// cup, the LED outside its bottom.
pub const Front = struct {
    t: f64,
    plug_d: f64,
    plug_depth: f64,
    felt: f64,
    hole: f64,
    bottom: f64,
    led_hole: f64,
    screw: Screw = undefined,
    cav_d: f64 = 0,
    wall: f64 = 0,
    cav_depth: f64 = 0,
    screw_r: f64 = 0,
    screw_wood: f64 = 0, // wood left on each side of the screw hole
};

/// Sizes of the back cap, front plug and cable.
pub const Dims = struct {
    c: f64, // clearance around the glass in the groove
    gin: f64,
    gout: f64,
    db: f64,
    usb: Usb,
    chan: Channel,
    gd: f64,
    s: f64,
    rin: f64,
    tube_end: f64,
    key: Key,
    cable: Cable,
    front: Front,
};

/// The largest of the sizes not above max, or def if none is.
fn lastUpTo(sizes: []const f64, max: f64, def: f64) f64 {
    var v = def;
    for (sizes) |s| {
        if (s <= max) v = s;
    }
    return v;
}

pub fn baseDims(p: *const Params) Dims {
    const c = 0.5;
    const gin = p.dia - 2 * p.glass - 2 * c;
    const gout = p.dia + 2 * c;
    const rin = p.dia / 2 - p.glass;
    const R = p.dia / 2;
    const ca = p.cable_angle * std.math.pi / 180;
    const a = p.cable_d / 2;
    const cR = R + a;
    const db = gout + 2 * p.rim_w;

    var usb: Usb = .{ .w = 12.5, .len = 13, .depth = 5.5, .port = .{ 9.5, 3.8 }, .wall = 1.5 };
    usb.x = -(usb.w / 2 + p.cable_d / 2 + 2);
    usb.rim = @sqrt(db * db / 4 - std.math.pow(f64, @abs(usb.x) + usb.w / 2, 2));
    usb.top = usb.rim - usb.wall - usb.len;

    var fr: Front = .{ .t = p.front_t, .plug_d = 2 * rin - 2, .plug_depth = p.plug_depth, .felt = 1, .hole = p.cable_d + 1, .bottom = 3, .led_hole = 3 };
    // Screw length: goes through the cup into the disc at least 5 mm and stops
    // 2 mm before its front (standard lengths)
    const l = lastUpTo(&.{ 12, 16, 20, 25, 30, 35, 40 }, p.plug_depth + p.front_t - 2, 12);
    fr.screw = .{ .d = 3, .len = l, .hole = 3.3, .pilot = 2, .head = 6, .bite = l - p.plug_depth };
    // The cavity is a single Forstner hole: keep the wall at least 12 mm so
    // there is solid wood on both sides of the screw
    fr.cav_d = lastUpTo(&.{ 20, 25, 30, 35, 40, 45, 50 }, fr.plug_d - 24, 20);
    fr.wall = (fr.plug_d - fr.cav_d) / 2;
    fr.cav_depth = fr.plug_depth - fr.bottom;
    fr.screw_r = (fr.cav_d / 2 + fr.plug_d / 2) / 2;
    fr.screw_wood = fr.wall / 2 - fr.screw.hole / 2;

    return .{
        .c = c,
        .gin = gin,
        .gout = gout,
        .db = db,
        .usb = usb,
        .chan = .{ .w = p.cable_d + 1, .d = p.cable_d + 1 },
        .gd = p.gd,
        .s = p.s,
        .rin = rin,
        .tube_end = p.s - p.gd + p.len,
        .key = .{ .r = 4.5, .slot = 5, .w = 5, .depth = 8, .y = 6 },
        .cable = .{
            .d = p.cable_d,
            .R = cR,
            .x = cR * @cos(ca),
            .y = cR * @sin(ca),
            .angle = p.cable_angle,
            .shadow_deg = 2 * std.math.asin(@min(1, a / cR)) * 180 / std.math.pi,
        },
        .front = fr,
    };
}

/// Up to 8 warning texts (static strings).
pub const Warnings = struct {
    items: [8][]const u8 = undefined,
    len: usize = 0,

    pub fn add(w: *Warnings, s: []const u8) void {
        if (w.len < w.items.len) {
            w.items[w.len] = s;
            w.len += 1;
        }
    }

    pub fn slice(w: *const Warnings) []const []const u8 {
        return w.items[0..w.len];
    }
};

pub fn baseWarnings(p: *const Params, d: *const Dims) Warnings {
    var w: Warnings = .{};
    if (d.s - d.gd < d.key.depth + 3)
        w.add("Back cap too thin: less than 3 mm of wood between the front groove and the keyhole.");
    if (d.front.t < d.cable.d + 4)
        w.add("Front plug too thin: keep at least 4 mm of wood under the cable channel on its front.");
    if (ledZ(p) <= d.s + 10)
        w.add("LED too close to the back cap: use a longer tube.");
    if (d.usb.depth > d.s - d.gd - 2)
        w.add("Back cap too thin: less than 2 mm of wood between the USB-C pocket and the front groove.");
    if (d.front.cav_depth < 6)
        w.add("Cup too shallow: the circuit needs at least 6 mm inside (increase the cup depth).");
    if (d.front.screw.bite < 5)
        w.add("Cup screws do not bite enough into the disc: make the front disc thicker.");
    if (d.front.screw_wood < 3)
        w.add("Too little wood beside the screw holes in the cup: the tube is too narrow.");
    return w;
}
