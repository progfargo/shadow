//! The settings: the table of fields (label, kind, defaults, when each one
//! is shown), the values of one product, and the settings panel built from
//! the table.
//!
//! Values are kept as the text the fields show, so a field shows exactly what
//! the user typed; the calculation reads them as numbers.

const std = @import("std");
const lv = @import("lvgl");
const core = @import("core");
const film = core.film;
const Product = @import("pages.zig").Product;
const st = @import("style.zig");
const dp = st.dp;
const workbench = @import("workbench.zig");

pub const Id = enum {
    file,
    mode,
    threshold,
    ht_pattern,
    pitch,
    fill,
    ht_angle,
    wave_amp,
    wave_len,
    gamma,
    invert,
    iw,
    ix,
    iy,
    dia,
    len,
    gh,
    gb,
    glass,
    n,
    lz,
    lx,
    ly,
    led,
    source,
    cd,
    hd,
    fwid,
    fhei,
    hnow,
    flick,
    animate,
    tint,
    s,
    gd,
    rim_w,
    front_t,
    plug_depth,
    cable_d,
    surface,
    dpi,
    seam,
    unused,
    front,
};

pub const Kind = enum {
    num,
    select,
    check,
    color,
    /// simulation slider: changes only the picture, not the film
    range,
    file,
    /// computed value, shown read-only
    info,
};

pub const Opt = struct { value: []const u8, label: [:0]const u8 };

/// One setting. `mode`, `pats` and `source` limit when it is shown (null or
/// empty: always).
pub const Field = struct {
    id: Id,
    label: [:0]const u8,
    kind: Kind = .num,
    min: ?f64 = null,
    max: ?f64 = null,
    opts: []const Opt = &.{},
    mode: ?film.Mode = null,
    pats: []const film.HtPattern = &.{},
    source: ?core.candle.Source = null,
    product: ?Product = null,
    /// redraws the simulation without computing the film again
    live: bool = false,
};

/// A box of settings in the panel.
pub const Group = struct {
    title: [:0]const u8,
    product: ?Product = null,
    fields: []const Field,
};

const tilted: []const film.HtPattern = &.{ .dot, .square, .lines, .wavy, .cross };

pub const groups = [_]Group{
    .{ .title = "Image", .fields = &.{
        .{ .id = .file, .label = "Picture", .kind = .file },
        .{ .id = .mode, .label = "Mode", .kind = .select, .opts = &.{ .{ .value = "binary", .label = "Black & white" }, .{ .value = "halftone", .label = "Halftone" } } },
        .{ .id = .threshold, .label = "Threshold", .min = 0, .max = 1, .mode = .binary },
        .{ .id = .ht_pattern, .label = "Pattern", .kind = .select, .mode = .halftone, .opts = &.{
            .{ .value = "dot", .label = "Dots (round)" },
            .{ .value = "square", .label = "Squares / diamonds" },
            .{ .value = "lines", .label = "Straight lines" },
            .{ .value = "wavy", .label = "Wavy lines" },
            .{ .value = "cross", .label = "Crosshatch" },
            .{ .value = "rings", .label = "Concentric rings" },
            .{ .value = "spiral", .label = "Spiral" },
        } },
        .{ .id = .pitch, .label = "Pitch (mm)", .min = 0.5, .mode = .halftone },
        .{ .id = .fill, .label = "Fill", .min = 0.1, .max = 1.2, .mode = .halftone },
        .{ .id = .ht_angle, .label = "Angle (degrees)", .mode = .halftone, .pats = tilted },
        .{ .id = .wave_amp, .label = "Wave amplitude (mm)", .min = 0, .mode = .halftone, .pats = &.{.wavy} },
        .{ .id = .wave_len, .label = "Wavelength (mm)", .min = 1, .mode = .halftone, .pats = &.{.wavy} },
        .{ .id = .gamma, .label = "Gamma", .min = 0.2 },
        .{ .id = .invert, .label = "Invert (light background, shadow image)", .kind = .check },
    } },
    .{ .title = "Image placement", .fields = &.{
        .{ .id = .iw, .label = "Image width (mm)" },
        .{ .id = .ix, .label = "Center x (mm)" },
        .{ .id = .iy, .label = "Center y (mm)" },
    } },
    .{ .title = "Glass (cut bottle)", .fields = &.{
        .{ .id = .dia, .label = "Outer diameter (mm)" },
        .{ .id = .len, .label = "Tube length (between cuts, mm)", .product = .lamp },
        .{ .id = .gh, .label = "Glass height (mm)", .product = .candle },
        .{ .id = .gb, .label = "Glass bottom above table (mm)", .min = 0, .product = .candle },
        .{ .id = .glass, .label = "Glass thickness (mm)", .min = 0 },
        .{ .id = .n, .label = "Refractive index", .min = 1 },
    } },
    .{ .title = "LED", .product = .lamp, .fields = &.{
        .{ .id = .lz, .label = "Distance from wall (from plug, mm)", .kind = .info },
        .{ .id = .lx, .label = "x (mm)" },
        .{ .id = .ly, .label = "y (mm)" },
        .{ .id = .led, .label = "LED size (mm)", .min = 0 },
    } },
    .{ .title = "Candle", .product = .candle, .fields = &.{
        .{ .id = .source, .label = "Light source", .kind = .select, .opts = &.{
            .{ .value = "real", .label = "Real candle" },
            .{ .value = "led", .label = "LED tealight (brightness flicker)" },
            .{ .value = "ledmove", .label = "LED candle, moving flame" },
        } },
        .{ .id = .cd, .label = "Candle diameter (mm)", .min = 5 },
        .{ .id = .hd, .label = "Design flame height (mm above table)" },
        .{ .id = .fwid, .label = "Flame width (mm)", .min = 1 },
        .{ .id = .fhei, .label = "Flame height (mm)", .min = 5 },
    } },
    .{ .title = "Simulation", .product = .candle, .fields = &.{
        .{ .id = .hnow, .label = "Flame height now (mm)", .kind = .range, .min = 20, .max = 140, .source = .real, .live = true },
        .{ .id = .flick, .label = "Flicker", .kind = .range, .min = 0, .max = 1, .live = true },
        .{ .id = .animate, .label = "Animate the flame", .kind = .check, .live = true },
    } },
    .{ .title = "Light", .fields = &.{
        .{ .id = .tint, .label = "Glass color", .kind = .color },
    } },
    .{ .title = "Back cap (wood, on wall)", .product = .lamp, .fields = &.{
        .{ .id = .s, .label = "Thickness (wall to tube, mm)", .min = 0 },
        .{ .id = .gd, .label = "Groove depth (mm)", .min = 2 },
        .{ .id = .rim_w, .label = "Groove outer wall (mm)", .min = 2 },
    } },
    .{ .title = "Front plug (removable)", .product = .lamp, .fields = &.{
        .{ .id = .front_t, .label = "Disc thickness (mm)", .min = 6 },
        .{ .id = .plug_depth, .label = "Cup depth (goes into tube, holds circuit; mm)", .min = 6 },
    } },
    .{ .title = "Cable (outside the glass)", .product = .lamp, .fields = &.{
        .{ .id = .cable_d, .label = "Diameter (mm)", .min = 1 },
    } },
    .{ .title = "Pattern method", .fields = &.{
        .{ .id = .surface, .label = "Method", .kind = .select, .opts = &.{
            .{ .value = "film", .label = "Printed clear film" },
            .{ .value = "paint", .label = "Painted glass + laser ablation" },
            .{ .value = "frost", .label = "Laser frosting on bare glass" },
        } },
        .{ .id = .dpi, .label = "Resolution (dpi)", .min = 72 },
        .{ .id = .seam, .label = "Seam position (degrees)" },
        .{ .id = .unused, .label = "Unused areas", .kind = .select, .product = .candle, .opts = &.{
            .{ .value = "black", .label = "Black (clean image)" },
            .{ .value = "clear", .label = "Clear (glass glows like a lantern)" },
        } },
        .{ .id = .front, .label = "Band in front of LED", .kind = .select, .product = .lamp, .opts = &.{
            .{ .value = "black", .label = "Black (wall only)" },
            .{ .value = "clear", .label = "Clear (glows like a lamp)" },
        } },
    } },
};

pub fn field(id: Id) *const Field {
    inline for (&groups) |*g| {
        for (g.fields) |*f| if (f.id == id) return f;
    }
    unreachable;
}

pub fn forProduct(product: ?Product, p: Product) bool {
    return product == null or product.? == p;
}

// ---------------------------------------------------------------------------
// Values

/// The text of one field
pub const Text = struct {
    buf: [32]u8 = undefined,
    len: u8 = 0,

    pub fn get(t: *const Text) []const u8 {
        return t.buf[0..t.len];
    }

    pub fn set(t: *Text, s: []const u8) void {
        const n = @min(s.len, t.buf.len);
        @memcpy(t.buf[0..n], s[0..n]);
        t.len = @intCast(n);
    }
};

pub const Values = struct {
    texts: std.EnumArray(Id, Text) = .initFill(.{}),

    pub fn get(v: *const Values, id: Id) []const u8 {
        return v.texts.getPtrConst(id).get();
    }

    pub fn set(v: *Values, id: Id, s: []const u8) void {
        v.texts.getPtr(id).set(s);
    }

    pub fn setNum(v: *Values, id: Id, x: f64) void {
        var buf: [64]u8 = undefined;
        v.set(id, core.format.jsNum(&buf, x));
    }

    pub fn num(v: *const Values, id: Id) f64 {
        return core.format.parseNum(v.get(id));
    }

    pub fn flag(v: *const Values, id: Id) bool {
        return std.mem.eql(u8, v.get(id), "true");
    }

    pub fn is(v: *const Values, id: Id, s: []const u8) bool {
        return std.mem.eql(u8, v.get(id), s);
    }

    /// An option field as its enum (the default if the text is not one of them)
    pub fn choice(v: *const Values, comptime E: type, id: Id, def: E) E {
        return std.meta.stringToEnum(E, v.get(id)) orelse def;
    }
};

const Pair = struct { Id, []const u8 };

const defaults = [_]Pair{
    .{ .mode, "binary" },   .{ .threshold, "0.5" },  .{ .ht_pattern, "dot" }, .{ .pitch, "2" },     .{ .fill, "0.9" },
    .{ .ht_angle, "0" },    .{ .wave_amp, "1" },     .{ .wave_len, "8" },     .{ .gamma, "1" },     .{ .invert, "false" },
    .{ .ix, "0" },          .{ .iy, "0" },           .{ .dia, "70" },         .{ .len, "120" },     .{ .gh, "150" },
    .{ .gb, "0" },          .{ .glass, "3" },        .{ .n, "1.52" },         .{ .surface, "film" }, .{ .dpi, "300" },
    .{ .unused, "black" },  .{ .front, "black" },    .{ .lx, "0" },           .{ .ly, "0" },        .{ .led, "2" },
    .{ .source, "real" },   .{ .cd, "34" },          .{ .hd, "60" },          .{ .fwid, "10" },     .{ .fhei, "30" },
    .{ .hnow, "60" },       .{ .flick, "0.6" },      .{ .animate, "true" },   .{ .tint, "#ffffff" }, .{ .s, "20" },
    .{ .gd, "6" },          .{ .rim_w, "4" },        .{ .front_t, "12" },     .{ .plug_depth, "16" }, .{ .cable_d, "3" },
};

/// Each product has its own placement and seam. The candle image is centered
/// on the glass, seen from above; the night lamp's seam is at the bottom,
/// behind the cable.
fn productDefaults(p: Product) []const Pair {
    return switch (p) {
        .lamp => &.{ .{ .iw, "400" }, .{ .seam, "270" } },
        .candle => &.{ .{ .iw, "500" }, .{ .seam, "0" } },
    };
}

pub fn defaultValues(p: Product) Values {
    var v: Values = .{};
    for (defaults) |d| v.set(d[0], d[1]);
    for (productDefaults(p)) |d| v.set(d[0], d[1]);
    return v;
}

/// Light source presets (all still editable). LED candles do not burn down,
/// so the flame stays at the design height.
pub fn applySourcePreset(v: *Values) void {
    const preset: []const Pair = switch (v.choice(core.candle.Source, .source, .real)) {
        .real => &.{ .{ .cd, "34" }, .{ .hd, "60" }, .{ .fwid, "10" }, .{ .fhei, "30" } },
        .led => &.{ .{ .cd, "38" }, .{ .hd, "30" }, .{ .fwid, "10" }, .{ .fhei, "15" } },
        .ledmove => &.{ .{ .cd, "38" }, .{ .hd, "35" }, .{ .fwid, "12" }, .{ .fhei, "20" } },
    };
    for (preset) |d| v.set(d[0], d[1]);
}

/// Is the field shown for the selected mode, pattern and light source?
pub fn visible(f: *const Field, v: *const Values) bool {
    if (f.mode) |m| {
        if (v.choice(film.Mode, .mode, .binary) != m) return false;
    }
    if (f.pats.len > 0) {
        const p = v.choice(film.HtPattern, .ht_pattern, .dot);
        if (std.mem.indexOfScalar(film.HtPattern, f.pats, p) == null) return false;
    }
    if (f.source) |s| {
        if (v.choice(core.candle.Source, .source, .real) != s) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// The panel

/// Widgets of the panel (null when not on screen)
pub var rows: std.EnumArray(Id, ?*lv.lv_obj_t) = .initFill(null);
pub var controls: std.EnumArray(Id, ?*lv.lv_obj_t) = .initFill(null);
/// Text under the Simulation group (candle)
pub var flame_note: ?*lv.lv_obj_t = null;
/// Name of the picture file next to the "Choose…" button
pub var picture_label: ?*lv.lv_obj_t = null;
pub var picture_btn: ?*lv.lv_obj_t = null;
/// Color swatch next to the glass color field
var tint_swatch: ?*lv.lv_obj_t = null;

/// Glass color presets: clear, amber, green, blue, rose
const tints = [_][]const u8{ "#ffffff", "#ffb347", "#7fc97f", "#7fa7e0", "#f4a7b9" };

fn idData(id: Id) ?*anyopaque {
    return @ptrFromInt(@as(usize, @intFromEnum(id)) + 1);
}

fn dataId(e: ?*lv.lv_event_t) Id {
    return @enumFromInt(@intFromPtr(lv.lv_event_get_user_data(e)) - 1);
}

/// Builds the settings of a product into the panel.
pub fn build(panel: ?*lv.lv_obj_t, product: Product, v: *const Values) void {
    rows = .initFill(null);
    controls = .initFill(null);
    flame_note = null;
    picture_label = null;
    picture_btn = null;
    tint_swatch = null;
    for (&groups) |*g| {
        if (!forProduct(g.product, product)) continue;
        const box = lv.lv_obj_create(panel);
        lv.lv_obj_set_size(box, lv.lv_pct(100), lv.LV_SIZE_CONTENT);
        lv.lv_obj_set_flex_flow(box, lv.LV_FLEX_FLOW_COLUMN);
        lv.lv_obj_set_style_pad_all(box, dp(10), 0);
        lv.lv_obj_set_style_pad_row(box, dp(6), 0);
        lv.lv_obj_set_style_radius(box, dp(8), 0);
        lv.lv_obj_set_style_border_width(box, dp(1), 0);
        lv.lv_obj_set_style_border_color(box, lv.lv_color_hex(0xE2E5EA), 0);
        lv.lv_obj_set_scrollable(box, false);
        _ = st.bold(box, g.title.ptr);
        for (g.fields) |*f| {
            if (forProduct(f.product, product)) buildField(box, f, v);
        }
        if (std.mem.eql(u8, g.title, "Simulation")) {
            flame_note = st.muted(box, "");
        }
    }
    sync(v);
}

fn row(parent: ?*lv.lv_obj_t, f: *const Field) ?*lv.lv_obj_t {
    const r = st.box(parent, lv.LV_FLEX_FLOW_ROW);
    const l = lv.lv_label_create(r);
    lv.lv_label_set_text(l, f.label.ptr);
    lv.lv_label_set_long_mode(l, lv.LV_LABEL_LONG_MODE_WRAP);
    lv.lv_obj_set_width(l, 1);
    lv.lv_obj_set_flex_grow(l, 1);
    rows.set(f.id, r);
    return r;
}

fn buildField(parent: ?*lv.lv_obj_t, f: *const Field, v: *const Values) void {
    _ = v;
    switch (f.kind) {
        .check => {
            // The checkbox draws its own text on one line; a separate label wraps long texts
            const r = st.box(parent, lv.LV_FLEX_FLOW_ROW);
            lv.lv_obj_set_flex_align(r, lv.LV_FLEX_ALIGN_START, lv.LV_FLEX_ALIGN_START, lv.LV_FLEX_ALIGN_START);
            const cb = lv.lv_checkbox_create(r);
            lv.lv_checkbox_set_text(cb, "");
            _ = lv.lv_obj_add_event_cb(cb, onValueChanged, lv.LV_EVENT_VALUE_CHANGED, idData(f.id));
            const l = lv.lv_label_create(r);
            lv.lv_label_set_text(l, f.label.ptr);
            lv.lv_label_set_long_mode(l, lv.LV_LABEL_LONG_MODE_WRAP);
            lv.lv_obj_set_width(l, 1);
            lv.lv_obj_set_flex_grow(l, 1);
            lv.lv_obj_set_clickable(l, true);
            _ = lv.lv_obj_add_event_cb(l, onCheckLabel, lv.LV_EVENT_CLICKED, idData(f.id));
            rows.set(f.id, r);
            controls.set(f.id, cb);
        },
        .file => {
            const r = row(parent, f);
            picture_btn = st.smallButton(r, lv.LV_SYMBOL_DIRECTORY ++ "  Choose…", onChoosePicture, null);
            controls.set(f.id, picture_btn);
            picture_label = st.muted(parent, "");
        },
        .select => {
            const r = st.box(parent, lv.LV_FLEX_FLOW_COLUMN);
            lv.lv_obj_set_style_pad_row(r, dp(4), 0);
            const l = st.label(r, f.label.ptr);
            _ = l;
            var buf: [512]u8 = undefined;
            var n: usize = 0;
            for (f.opts, 0..) |o, i| {
                if (i > 0) {
                    buf[n] = '\n';
                    n += 1;
                }
                @memcpy(buf[n .. n + o.label.len], o.label);
                n += o.label.len;
            }
            buf[n] = 0;
            const dd = lv.lv_dropdown_create(r);
            lv.lv_dropdown_set_options(dd, @ptrCast(&buf));
            lv.lv_obj_set_width(dd, lv.lv_pct(100));
            lv.lv_obj_set_style_radius(dd, dp(6), 0);
            _ = lv.lv_obj_add_event_cb(dd, onValueChanged, lv.LV_EVENT_VALUE_CHANGED, idData(f.id));
            rows.set(f.id, r);
            controls.set(f.id, dd);
        },
        .range => {
            const r = st.box(parent, lv.LV_FLEX_FLOW_COLUMN);
            lv.lv_obj_set_style_pad_row(r, dp(8), 0);
            _ = st.label(r, f.label.ptr);
            const s = lv.lv_slider_create(r);
            lv.lv_obj_set_width(s, lv.lv_pct(92));
            lv.lv_obj_set_style_margin_left(s, dp(8), 0);
            // sliders work in hundredths so fractional ranges (Flicker 0..1) move smoothly
            lv.lv_slider_set_range(s, @intFromFloat(f.min.? * 100), @intFromFloat(f.max.? * 100));
            _ = lv.lv_obj_add_event_cb(s, onValueChanged, lv.LV_EVENT_VALUE_CHANGED, idData(f.id));
            rows.set(f.id, r);
            controls.set(f.id, s);
        },
        .info => {
            const r = row(parent, f);
            const l = lv.lv_label_create(r);
            lv.lv_obj_set_width(l, dp(96));
            lv.lv_obj_set_style_text_align(l, lv.LV_TEXT_ALIGN_RIGHT, 0);
            controls.set(f.id, l);
        },
        .num, .color => {
            const r = row(parent, f);
            if (f.kind == .color) {
                tint_swatch = lv.lv_obj_create(r);
                lv.lv_obj_remove_style_all(tint_swatch);
                lv.lv_obj_set_size(tint_swatch, dp(22), dp(22));
                lv.lv_obj_set_style_radius(tint_swatch, dp(4), 0);
                lv.lv_obj_set_style_bg_opa(tint_swatch, lv.LV_OPA_COVER, 0);
                lv.lv_obj_set_style_border_width(tint_swatch, dp(1), 0);
                lv.lv_obj_set_style_border_color(tint_swatch, lv.lv_color_hex(0x999999), 0);
            }
            const ta = lv.lv_textarea_create(r);
            lv.lv_textarea_set_one_line(ta, true);
            lv.lv_textarea_set_max_length(ta, 24);
            lv.lv_textarea_set_accepted_chars(ta, if (f.kind == .color) "#0123456789abcdefABCDEF" else "0123456789.-");
            lv.lv_obj_set_width(ta, dp(96));
            lv.lv_obj_set_style_radius(ta, dp(6), 0);
            lv.lv_obj_set_style_pad_ver(ta, dp(5), 0);
            lv.lv_obj_set_style_pad_hor(ta, dp(8), 0);
            // Numbers are taken on Enter or when the field is left
            _ = lv.lv_obj_add_event_cb(ta, onValueChanged, lv.LV_EVENT_READY, idData(f.id));
            _ = lv.lv_obj_add_event_cb(ta, onValueChanged, lv.LV_EVENT_DEFOCUSED, idData(f.id));
            controls.set(f.id, ta);
            if (f.kind == .color) {
                const presets = st.box(parent, lv.LV_FLEX_FLOW_ROW);
                lv.lv_obj_set_flex_align(presets, lv.LV_FLEX_ALIGN_END, lv.LV_FLEX_ALIGN_CENTER, lv.LV_FLEX_ALIGN_CENTER);
                for (tints, 0..) |t, i| {
                    const b = lv.lv_button_create(presets);
                    lv.lv_obj_remove_style_all(b);
                    lv.lv_obj_set_size(b, dp(22), dp(22));
                    lv.lv_obj_set_style_radius(b, dp(11), 0);
                    lv.lv_obj_set_style_bg_opa(b, lv.LV_OPA_COVER, 0);
                    lv.lv_obj_set_style_bg_color(b, lv.lv_color_hex(parseColor(t)), 0);
                    lv.lv_obj_set_style_border_width(b, dp(1), 0);
                    lv.lv_obj_set_style_border_color(b, lv.lv_color_hex(0x999999), 0);
                    _ = lv.lv_obj_add_event_cb(b, onTintPreset, lv.LV_EVENT_CLICKED, @ptrFromInt(i + 1));
                }
            }
        },
    }
}

/// "#rrggbb" as 0xRRGGBB (white if it cannot be read)
pub fn parseColor(s: []const u8) u32 {
    if (s.len != 7 or s[0] != '#') return 0xFFFFFF;
    return std.fmt.parseInt(u32, s[1..], 16) catch 0xFFFFFF;
}

fn optionIndex(f: *const Field, value: []const u8) u32 {
    for (f.opts, 0..) |o, i| if (std.mem.eql(u8, o.value, value)) return @intCast(i);
    return 0;
}

/// Writes the values into the fields and shows only the fields that apply.
pub fn sync(v: *const Values) void {
    var it = controls.iterator();
    while (it.next()) |e| {
        const c = e.value.* orelse continue;
        const f = field(e.key);
        const text = v.get(e.key);
        switch (f.kind) {
            .check => if (std.mem.eql(u8, text, "true")) lv.lv_obj_add_state(c, lv.LV_STATE_CHECKED) else lv.lv_obj_remove_state(c, lv.LV_STATE_CHECKED),
            .select => lv.lv_dropdown_set_selected(c, optionIndex(f, text)),
            .range => lv.lv_slider_set_value(c, @intFromFloat(@round(v.num(e.key) * 100)), false),
            .num, .color => {
                var buf: [40]u8 = undefined;
                const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{text}, 0) catch continue;
                if (!std.mem.eql(u8, std.mem.span(lv.lv_textarea_get_text(c)), z)) lv.lv_textarea_set_text(c, z.ptr);
            },
            .info => {
                var buf: [40]u8 = undefined;
                const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{if (text.len == 0) "–" else text}, 0) catch continue;
                lv.lv_label_set_text(c, z.ptr);
            },
            .file => {},
        }
        if (rows.get(e.key)) |r| lv.lv_obj_set_hidden(r, !visible(f, v));
    }
    if (tint_swatch) |sw| lv.lv_obj_set_style_bg_color(sw, lv.lv_color_hex(parseColor(v.get(.tint))), 0);
}

/// Sets the slider range of a field (the "flame now" slider follows the glass).
pub fn setRange(id: Id, min: f64, max: f64) void {
    const c = controls.get(id) orelse return;
    lv.lv_slider_set_range(c, @intFromFloat(@round(min * 100)), @intFromFloat(@round(@max(min, max) * 100)));
}

fn onValueChanged(e: ?*lv.lv_event_t) callconv(.c) void {
    const id = dataId(e);
    const c = controls.get(id) orelse return;
    const f = field(id);
    var buf: [64]u8 = undefined;
    const text: []const u8 = switch (f.kind) {
        .check => if (lv.lv_obj_has_state(c, lv.LV_STATE_CHECKED)) "true" else "false",
        .select => f.opts[lv.lv_dropdown_get_selected(c)].value,
        .range => core.format.jsNum(&buf, @as(f64, @floatFromInt(lv.lv_slider_get_value(c))) / 100),
        .num, .color => std.mem.trim(u8, std.mem.span(lv.lv_textarea_get_text(c)), " "),
        else => return,
    };
    workbench.changed(id, text);
}

/// Clicking the text of a checkbox toggles it
fn onCheckLabel(e: ?*lv.lv_event_t) callconv(.c) void {
    const c = controls.get(dataId(e)) orelse return;
    if (lv.lv_obj_has_state(c, lv.LV_STATE_CHECKED)) lv.lv_obj_remove_state(c, lv.LV_STATE_CHECKED) else lv.lv_obj_add_state(c, lv.LV_STATE_CHECKED);
    _ = lv.lv_obj_send_event(c, lv.LV_EVENT_VALUE_CHANGED, null);
}

fn onTintPreset(e: ?*lv.lv_event_t) callconv(.c) void {
    const i = @intFromPtr(lv.lv_event_get_user_data(e)) - 1;
    workbench.changed(.tint, tints[i]);
}

fn onChoosePicture(_: ?*lv.lv_event_t) callconv(.c) void {
    workbench.choosePicture();
}
