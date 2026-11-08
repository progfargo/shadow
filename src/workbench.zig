//! The working area of the product pages: the settings, the picture, the
//! computed film and the drawings. Each product keeps its own settings and
//! picture while the user moves between its pages.
//!
//! The film is computed on a worker thread so the window stays responsive;
//! a timer picks up the result and redraws.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const lv = @import("lvgl");
const sdl = @import("sdl3");
const core = @import("core");
const lamp = core.lamp;
const candle = core.candle;
const film = core.film;
const fmt = core.format;
const suggest = core.suggest;
const pages = @import("pages.zig");
const Product = pages.Product;
const Page = pages.Page;
const settings = @import("settings.zig");
const Id = settings.Id;
const Values = settings.Values;
const st = @import("style.zig");
const dp = st.dp;
const cv = @import("canvas.zig");
const views = @import("views.zig");
const parts_view = @import("parts_view.zig");
pub const flame = @import("flame.zig");
pub const exporter = @import("export.zig");
const demo = @import("demo.zig");
const dialogs = @import("dialogs.zig");
const pic = @import("picture.zig");
const Picture = pic.Picture;

pub var gpa: Allocator = undefined;
pub var io: Io = undefined;

/// The state of one product.
pub const Bench = struct {
    product: Product,
    /// settings as the fields show them
    vals: Values,
    picture: Picture,
    /// file name of the picture the user chose (empty: sample picture)
    picture_name: settings.Text = .{},
    analysis: ?suggest.Analysis = null,
    lamp_res: ?lamp.Result = null,
    candle_res: ?candle.Result = null,
    /// the "flame now" slider follows the design height until the user moves it
    hnow_touched: bool = false,
    /// the settings changed while the film was being computed
    dirty: bool = false,

    fn deinit(b: *Bench) void {
        b.picture.deinit(gpa);
        if (b.lamp_res) |*r| r.deinit(gpa);
        if (b.candle_res) |*r| r.deinit(gpa);
    }

    pub fn pattern(b: *const Bench) film.Pattern {
        const v = &b.vals;
        return .{
            .mode = v.choice(film.Mode, .mode, .binary),
            .threshold = v.num(.threshold),
            .gamma = v.num(.gamma),
            .invert = v.flag(.invert),
            .ht_pattern = v.choice(film.HtPattern, .ht_pattern, .dot),
            .grid = .wall, // the pattern is even on the lit surface (wall or table)
            .pitch = v.num(.pitch),
            .fill = v.num(.fill),
            .ht_angle = v.num(.ht_angle),
            .wave_amp = v.num(.wave_amp),
            .wave_len = v.num(.wave_len),
        };
    }

    pub fn placement(b: *const Bench) film.Placement {
        return .{ .iw = b.vals.num(.iw), .ix = b.vals.num(.ix), .iy = b.vals.num(.iy), .aspect = b.picture.aspect() };
    }

    pub fn lampParams(b: *const Bench) lamp.Params {
        const v = &b.vals;
        var p: lamp.Params = .{
            .pattern = b.pattern(),
            .placement = b.placement(),
            .dia = v.num(.dia),
            .len = v.num(.len),
            .glass = v.num(.glass),
            .n = v.num(.n),
            .s = v.num(.s),
            .gd = v.num(.gd),
            .rim_w = v.num(.rim_w),
            .front_t = v.num(.front_t),
            .plug_depth = v.num(.plug_depth),
            .cable_d = v.num(.cable_d),
            .cable_angle = 270, // always at the bottom so the cable's weight does not tilt the lamp
            .lx = v.num(.lx),
            .ly = v.num(.ly),
            .dpi = v.num(.dpi),
            .seam = v.num(.seam),
            .front = v.choice(lamp.Front, .front, .black),
            .surface = v.choice(lamp.Surface, .surface, .film),
        };
        p.lz = lamp.ledZ(&p); // the LED sits on the plug
        return p;
    }

    pub fn candleParams(b: *const Bench) candle.Params {
        const v = &b.vals;
        return .{
            .pattern = b.pattern(),
            .placement = b.placement(),
            .dia = v.num(.dia),
            .glass = v.num(.glass),
            .n = v.num(.n),
            .gb = v.num(.gb),
            .gh = v.num(.gh),
            .cd = v.num(.cd),
            .hd = v.num(.hd),
            .fwid = v.num(.fwid),
            .fhei = v.num(.fhei),
            .seam = v.num(.seam),
            .dpi = v.num(.dpi),
            .source = v.choice(candle.Source, .source, .real),
            .unused = v.choice(candle.Unused, .unused, .black),
        };
    }

    pub fn computedFilm(b: *const Bench) ?*const film.Film {
        return switch (b.product) {
            .lamp => if (b.lamp_res) |*r| &r.film else null,
            .candle => if (b.candle_res) |*r| &r.film else null,
        };
    }

    /// Reads the picture and keeps what it suggests; the settings are not
    /// changed until the user applies it.
    fn analyze(b: *Bench) void {
        const small = b.picture.smallRgba(gpa, 200, 200) catch {
            b.analysis = null;
            return;
        };
        defer gpa.free(small);
        b.analysis = suggest.analyzeRgba(small);
    }

    /// The cleanest settings for the picture. Threshold and gamma follow the
    /// picture; for halftone the pattern pitch is kept about as small as the
    /// light source, so the blur on the wall/table is wider than the dot
    /// spacing and the dots merge into smooth tones.
    pub fn suggestion(b: *const Bench) Suggestion {
        var s: Suggestion = .{};
        const a = &(b.analysis orelse return s);
        var buf: [64]u8 = undefined;
        s.add(.mode, @tagName(a.mode));
        s.add(.invert, if (a.invert) "true" else "false");
        if (a.mode == .binary) {
            s.add(.threshold, fmt.jsNum(&buf, suggest.suggestedThreshold(a, a.invert)));
            s.add(.gamma, "1");
        } else {
            const size = if (b.product == .candle) b.vals.num(.fwid) * 0.35 else b.vals.num(.led);
            s.add(.gamma, fmt.jsNum(&buf, suggest.suggestedGamma(a, a.invert)));
            s.add(.ht_pattern, "dot");
            s.add(.fill, "1");
            s.add(.ht_angle, "0");
            s.add(.pitch, fmt.jsNum(&buf, suggest.suggestedPitch(size)));
        }
        return s;
    }

    /// Explains the suggestion, or is empty when the settings already follow it.
    fn suggestionNote(b: *const Bench, w: *std.Io.Writer) !bool {
        const s = b.suggestion();
        const a = &(b.analysis orelse return false);
        for (s.items[0..s.len]) |*it| {
            if (!std.mem.eql(u8, b.vals.get(it.id), it.text.get())) {
                const th = fmt.parseNum(s.get(.threshold) orelse "0");
                const gamma = fmt.parseNum(s.get(.gamma) orelse "1");
                try suggest.writeNote(w, a, a.mode, th, gamma);
                return true;
            }
        }
        return false;
    }

    fn applySuggestions(b: *Bench) void {
        const s = b.suggestion();
        for (s.items[0..s.len]) |*it| b.vals.set(it.id, it.text.get());
    }
};

pub const Suggestion = struct {
    items: [8]struct { id: Id, text: settings.Text } = undefined,
    len: usize = 0,

    fn add(s: *Suggestion, id: Id, text: []const u8) void {
        s.items[s.len] = .{ .id = id, .text = .{} };
        s.items[s.len].text.set(text);
        s.len += 1;
    }

    fn get(s: *const Suggestion, id: Id) ?[]const u8 {
        for (s.items[0..s.len]) |*it| if (it.id == id) return it.text.get();
        return null;
    }
};

var benches: [2]?*Bench = .{ null, null };
pub var cur: ?*Bench = null;
pub var page: Page = .start;

/// Widgets of the current page (null when not on screen)
var view_box: ?*lv.lv_obj_t = null;
var info_box: ?*lv.lv_obj_t = null;
var status_label: ?*lv.lv_obj_t = null;
var canvas: cv.Canvas = .{};
var timer: ?*lv.lv_timer_t = null;

/// Objects the in-app test drives
pub const Refs = struct {
    apply_suggested_btn: ?*lv.lv_obj_t = null,
    canvas: ?*lv.lv_obj_t = null,
    save_png_btn: ?*lv.lv_obj_t = null,
    save_svg_btn: ?*lv.lv_obj_t = null,
    save_parts_btn: ?*lv.lv_obj_t = null,
};
/// Ctrl (Cmd on macOS) was held when the mouse button went down (main.zig)
pub var ctrl_held = false;

/// Ctrl + drag moves the glass over the picture; on release the picture
/// center moves the other way and the film is computed again.
pub const Drag = struct {
    on: bool = false,
    start: lv.lv_point_t = .{ .x = 0, .y = 0 },
    ix: f64 = 0, // picture center at the start
    iy: f64 = 0,
    ox: f64 = 0, // glass offset (mm)
    oy: f64 = 0,
};
pub var drag: Drag = .{};

/// Pixels per mm of the current drawing (for the in-app test)
pub fn viewScale() f64 {
    return if (views.base_view) |v| v.sc else 1;
}

/// Size of the drawing area the canvas was last drawn for
var drawn_for: [2]i32 = .{ 0, 0 };
/// What the open save dialog is for
var pending_save: exporter.Kind = .film_png;
pub var refs: Refs = .{};
/// Last status text (for the in-app test)
pub var status_buf: [256]u8 = undefined;
pub var status_text: []const u8 = "";

pub fn init(allocator: Allocator, io_: Io, window: ?*sdl.SDL_Window) void {
    gpa = allocator;
    io = io_;
    dialogs.init(gpa, window);
    flame.init(window);
    timer = lv.lv_timer_create(onTimer, 30, null);
}

pub fn deinit() void {
    flame.stop();
    waitForWorker();
    if (timer) |t| lv.lv_timer_delete(t);
    canvas.destroy();
    views.base.deinit(gpa);
    dialogs.deinit();
    for (&benches) |*b| {
        if (b.*) |bb| {
            bb.deinit();
            gpa.destroy(bb);
        }
        b.* = null;
    }
}

fn benchOf(product: Product) !*Bench {
    const slot = &benches[@intFromEnum(product)];
    if (slot.*) |b| return b;
    const b = try gpa.create(Bench);
    errdefer gpa.destroy(b);
    b.* = .{ .product = product, .vals = settings.defaultValues(product), .picture = try demo.picture(gpa, product) };
    b.analyze();
    // Only on the first start the sample picture's suggestion is applied
    b.applySuggestions();
    slot.* = b;
    return b;
}

// ---------------------------------------------------------------------------
// Pages

/// Containers of a product page, made by ui.zig.
pub const Frame = struct {
    toolbar: ?*lv.lv_obj_t,
    view: ?*lv.lv_obj_t,
    info: ?*lv.lv_obj_t,
    panel: ?*lv.lv_obj_t,
};

/// Builds the working area of a page into the frame.
pub fn show(product: Product, pg: Page, frame: Frame) !void {
    leave();
    const b = try benchOf(product);
    cur = b;
    page = pg;
    view_box = frame.view;
    info_box = frame.info;
    refs = .{};

    // Toolbar: page buttons on the left, status on the right
    switch (pg) {
        .image, .light => {
            const hint = st.muted(frame.toolbar, "Ctrl + drag: move the glass over the image");
            lv.lv_obj_set_width(hint, lv.LV_SIZE_CONTENT);
            lv.lv_obj_move_to_index(hint, 0);
        },
        .film => {
            refs.save_png_btn = st.button(frame.toolbar, exporter.pngButtonLabel(b), onSave, @ptrFromInt(1 + @as(usize, @intFromEnum(exporter.Kind.film_png))));
            refs.save_svg_btn = st.outlineButton(frame.toolbar, lv.LV_SYMBOL_SAVE ++ "  Save SVG (actual size)", onSave, @ptrFromInt(1 + @as(usize, @intFromEnum(exporter.Kind.film_svg))));
            lv.lv_obj_move_to_index(refs.save_png_btn, 0);
            lv.lv_obj_move_to_index(refs.save_svg_btn, 1);
        },
        .parts => {
            refs.save_parts_btn = st.button(frame.toolbar, lv.LV_SYMBOL_SAVE ++ "  Save parts drawing (SVG, 1:1)", onSave, @ptrFromInt(1 + @as(usize, @intFromEnum(exporter.Kind.parts_svg))));
            lv.lv_obj_move_to_index(refs.save_parts_btn, 0);
            // The drawing is white paper and scrolls when it is taller than the view
            lv.lv_obj_set_style_bg_color(frame.view, lv.lv_color_white(), 0);
            lv.lv_obj_set_scrollable(frame.view, true);
        },
        else => {},
    }
    status_label = lv.lv_label_create(frame.toolbar);
    lv.lv_obj_set_width(status_label, 1);
    lv.lv_obj_set_flex_grow(status_label, 1);
    lv.lv_obj_set_style_text_align(status_label, lv.LV_TEXT_ALIGN_RIGHT, 0);
    lv.lv_obj_set_style_text_font(status_label, st.font_small, 0);
    lv.lv_label_set_text(status_label, "");
    // before the Settings button, which ui.zig made first
    lv.lv_obj_move_to_index(status_label, @intCast(lv.lv_obj_get_child_count(frame.toolbar) - 2));

    settings.build(frame.panel, product, &b.vals);
    updatePictureLabel();

    canvas = try cv.Canvas.create(frame.view, 1, 1);
    refs.canvas = canvas.obj;
    lv.lv_obj_center(canvas.obj);
    drag = .{};
    if (pg == .image or pg == .light) {
        lv.lv_obj_set_clickable(canvas.obj, true);
        _ = lv.lv_obj_add_event_cb(canvas.obj, onDrag, lv.LV_EVENT_PRESSED, null);
        _ = lv.lv_obj_add_event_cb(canvas.obj, onDrag, lv.LV_EVENT_PRESSING, null);
        _ = lv.lv_obj_add_event_cb(canvas.obj, onDrag, lv.LV_EVENT_RELEASED, null);
        _ = lv.lv_obj_add_event_cb(canvas.obj, onDrag, lv.LV_EVENT_PRESS_LOST, null);
    }

    if (b.computedFilm() == null or b.dirty) {
        requestCompute(b);
        drawEmpty();
    } else {
        refresh();
    }
}

/// Removes the page's drawing (before ui.zig deletes the page widgets).
pub fn leave() void {
    flame.stop();
    canvas.destroy();
    views.base_view = null;
    view_box = null;
    info_box = null;
    status_label = null;
    settings.rows = .initFill(null);
    settings.controls = .initFill(null);
    settings.flame_note = null;
    settings.picture_label = null;
    refs = .{};
    cur = null;
}

/// The window size changed: draw again at the new size.
pub fn onResize() void {
    if (cur != null and canvas.obj != null) render();
}

/// Size of the drawing area in pixels
fn viewSize() [2]i32 {
    // Twice: wrapped labels in the information area get their height only
    // after their width is known, which changes the drawing area once more.
    lv.lv_obj_update_layout(lv.lv_screen_active());
    lv.lv_obj_update_layout(lv.lv_screen_active());
    return .{ lv.lv_obj_get_content_width(view_box), lv.lv_obj_get_content_height(view_box) };
}

fn drawEmpty() void {
    const sz = viewSize();
    canvas.resize(sz[0], sz[1]) catch return;
    canvas.fill(views.stage_rgb);
}

/// Draws the page and its information.
fn refresh() void {
    updateInfo() catch {};
    if (cur) |b| settings.sync(&b.vals); // the info sets the LED distance
    render();
}

/// Draws the page's view into the canvas.
pub fn render() void {
    const b = cur orelse return;
    if (b.computedFilm() == null) return;
    const sz = viewSize();
    drawn_for = sz;
    if (page == .parts) return renderParts(b, sz);
    canvas.resize(sz[0], sz[1]) catch return;
    lv.lv_obj_center(canvas.obj);
    const result = switch (page) {
        .image => views.drawImage(&canvas, b),
        .film => views.drawFilm(&canvas, b),
        .light => if (b.product == .lamp) views.drawLampLight(&canvas, b) else flame.start(&canvas),
        .parts, .start => drawEmpty(),
    };
    result catch |e| setStatus("Cannot draw: {s}", .{@errorName(e)});
    canvas.invalidate();
}

/// The parts drawing fills the width (at least readable size) and scrolls.
fn renderParts(b: *const Bench, sz: [2]i32) void {
    const p = b.lampParams();
    var d = core.parts.partsDrawing(gpa, &p) catch |e| return setStatus("Cannot draw: {s}", .{@errorName(e)});
    defer d.deinit();
    // leave room for the vertical scrollbar
    const avail: f64 = @floatFromInt(@max(100, sz[0] - dp(12)));
    const sc = @max(avail / d.w, parts_view.min_scale);
    canvas.resize(@intFromFloat(@ceil(d.w * sc)), @intFromFloat(@ceil(d.h * sc))) catch return;
    parts_view.draw(&canvas, &d, sc) catch |e| setStatus("Cannot draw: {s}", .{@errorName(e)});
    canvas.invalidate();
}

pub fn setStatus(comptime f: []const u8, args: anytype) void {
    status_text = std.fmt.bufPrint(&status_buf, f, args) catch status_buf[0..0];
    if (status_label) |l| {
        var z: [260]u8 = undefined;
        const s = std.fmt.bufPrintSentinel(&z, "{s}", .{status_text}, 0) catch return;
        lv.lv_label_set_text(l, s.ptr);
    }
}

// ---------------------------------------------------------------------------
// Settings changes

/// Takes a new value from a settings field. Number fields send it on Enter
/// or when left, the others on change; sliders on every move.
pub fn changed(id: Id, text: []const u8) void {
    const b = cur orelse return;
    if (std.mem.eql(u8, text, b.vals.get(id))) return;
    b.vals.set(id, text);
    switch (id) {
        .source => {
            settings.applySourcePreset(&b.vals);
            b.hnow_touched = false;
        },
        .hnow => b.hnow_touched = true,
        else => {},
    }
    settings.sync(&b.vals);
    if (id == .surface) {
        if (refs.save_png_btn) |btn| lv.lv_label_set_text(lv.lv_obj_get_child(btn, 0), exporter.pngButtonLabel(b));
    }
    const f = settings.field(id);
    if (f.live) {
        // the simulation: only the candle's light and the note change
        updateFlameNote(b);
        if (page == .light and b.product == .candle and b.candle_res != null) render();
        return;
    }
    if (id == .tint) {
        // only the drawing changes, not the film
        refresh();
        return;
    }
    requestCompute(b);
}

/// Writes the settings suggested by the picture into the fields and computes again.
pub fn applySuggested() void {
    const b = cur orelse return;
    b.applySuggestions();
    settings.sync(&b.vals);
    requestCompute(b);
}

// ---------------------------------------------------------------------------
// Ctrl + drag

fn onDrag(e: ?*lv.lv_event_t) callconv(.c) void {
    const b = cur orelse return;
    const code = lv.lv_event_get_code(e);
    var pt: lv.lv_point_t = undefined;
    lv.lv_indev_get_point(lv.lv_indev_active(), &pt);
    switch (code) {
        lv.LV_EVENT_PRESSED => {
            if (!ctrl_held or views.base_view == null or b.computedFilm() == null or job != null) return;
            drag = .{ .on = true, .start = pt, .ix = b.vals.num(.ix), .iy = b.vals.num(.iy) };
        },
        lv.LV_EVENT_PRESSING => {
            if (!drag.on) return;
            const v = views.base_view.?;
            drag.ox = @as(f64, @floatFromInt(pt.x - drag.start.x)) / v.sc;
            drag.oy = -@as(f64, @floatFromInt(pt.y - drag.start.y)) / v.sc;
            if (!views.restoreBase(&canvas)) return;
            canvas.begin();
            views.drawBottle(b, v, drag.ox, drag.oy);
            views.drawScale(&canvas, v);
            canvas.end();
            canvas.invalidate();
        },
        else => { // released or lost
            if (!drag.on) return;
            drag.on = false;
            if (@abs(drag.ox) < 0.5 and @abs(drag.oy) < 0.5) return;
            b.vals.setNum(.ix, fmt.jsRound(drag.ix - drag.ox));
            b.vals.setNum(.iy, fmt.jsRound(drag.iy - drag.oy));
            settings.sync(&b.vals);
            requestCompute(b);
        },
    }
}

// ---------------------------------------------------------------------------
// Saving files

fn onSave(e: ?*lv.lv_event_t) callconv(.c) void {
    const kind: exporter.Kind = @enumFromInt(@intFromPtr(lv.lv_event_get_user_data(e)) - 1);
    startSave(kind);
}

/// Asks where to save, then writes the file (saveTo).
pub fn startSave(kind: exporter.Kind) void {
    const b = cur orelse return;
    if (b.computedFilm() == null or job != null) return setStatus("Wait until the film is computed.", .{});
    pending_save = kind;
    dialogs.start(if (kind == .film_png) .save_png else .save_svg, exporter.fileName(b, kind));
}

/// Writes the pending file to `path`.
pub fn saveTo(path: []const u8) void {
    const b = cur orelse return;
    exporter.save(gpa, io, b, pending_save, path) catch |e| return setStatus("Cannot save: {s}", .{@errorName(e)});
    setStatus("Saved {s}", .{std.fs.path.basename(path)});
}

/// Saves a file without the dialog (for the in-app test).
pub fn saveAs(kind: exporter.Kind, path: []const u8) void {
    pending_save = kind;
    saveTo(path);
}

fn onApplySuggested(_: ?*lv.lv_event_t) callconv(.c) void {
    applySuggested();
}

// ---------------------------------------------------------------------------
// Picture

pub fn choosePicture() void {
    if (cur == null) return;
    dialogs.start(.open_picture, null);
}

/// Loads a picture for the current product; the settings stay as they are.
pub fn openPicturePath(path: []const u8) void {
    const b = cur orelse return;
    var p = Picture.load(gpa, io, path) catch |e| {
        setStatus("Cannot open the picture: {s}", .{switch (e) {
            error.CannotDecode => "not a supported picture",
            error.FileNotFound => "file not found",
            else => @errorName(e),
        }});
        return;
    };
    b.picture.deinit(gpa);
    b.picture = p;
    p = undefined;
    b.picture_name.set(std.fs.path.basename(path));
    b.analyze();
    updatePictureLabel();
    setStatus("", .{});
    requestCompute(b);
}

fn updatePictureLabel() void {
    const b = cur orelse return;
    const l = settings.picture_label orelse return;
    const name = b.picture_name.get();
    lv.lv_label_set_text(l, st.zfmt("{s} ({d} × {d} px)", .{ if (name.len == 0) "Sample picture" else name, b.picture.w, b.picture.h }));
}

// ---------------------------------------------------------------------------
// Computing on a worker thread

const Job = struct {
    product: Product,
    lamp_p: lamp.Params = .{},
    candle_p: candle.Params = .{},
    grid: pic.LumGrid,
    lamp_res: ?lamp.Result = null,
    candle_res: ?candle.Result = null,
    err: ?anyerror = null,
};

var job: ?*Job = null;
var worker: ?std.Thread = null;
var job_done: std.atomic.Value(bool) = .init(false);

fn runJob(j: *Job) void {

    const sampler: film.Sampler = .{ .ctx = &j.grid, .f = pic.LumGrid.sample };
    switch (j.product) {
        .lamp => j.lamp_res = lamp.compute(gpa, &j.lamp_p, sampler) catch |e| blk: {
            j.err = e;
            break :blk null;
        },
        .candle => j.candle_res = candle.compute(gpa, &j.candle_p, sampler) catch |e| blk: {
            j.err = e;
            break :blk null;
        },
    }
    job_done.store(true, .release);
}

/// Computes the film again from the current settings; if a computation is
/// running, it runs again when that one is done.
pub fn requestCompute(b: *Bench) void {
    b.dirty = true;
    if (job != null) return;
    startJob(b) catch |e| setStatus("Cannot compute: {s}", .{@errorName(e)});
}

fn startJob(b: *Bench) !void {
    b.dirty = false;
    const j = try gpa.create(Job);
    errdefer gpa.destroy(j);
    const pl = b.placement();
    j.* = .{ .product = b.product, .grid = try pic.lumGrid(gpa, &b.picture, pl.iw) };
    errdefer j.grid.deinit(gpa);
    switch (b.product) {
        .lamp => j.lamp_p = b.lampParams(),
        .candle => j.candle_p = b.candleParams(),
    }
    job_done.store(false, .release);
    job = j;
    worker = try std.Thread.spawn(.{}, runJob, .{j});
    if (cur == b) setStatus("computing…", .{});
}

/// Waits for a running computation (when quitting).
fn waitForWorker() void {
    if (worker) |t| t.join();
    worker = null;
    if (job) |j| {
        if (j.lamp_res) |*r| r.deinit(gpa);
        if (j.candle_res) |*r| r.deinit(gpa);
        j.grid.deinit(gpa);
        gpa.destroy(j);
    }
    job = null;
}

/// Takes a finished computation and starts the next one if needed.
fn finishJob() void {
    if (worker) |t| t.join();
    worker = null;
    const j = job orelse return;
    job = null;
    defer {
        j.grid.deinit(gpa);
        gpa.destroy(j);
    }
    const b = benches[@intFromEnum(j.product)].?;
    if (j.err) |e| {
        if (cur == b) setStatus("Cannot compute: {s}", .{@errorName(e)});
    } else switch (j.product) {
        .lamp => {
            if (b.lamp_res) |*r| r.deinit(gpa);
            b.lamp_res = j.lamp_res;
        },
        .candle => {
            if (b.candle_res) |*r| r.deinit(gpa);
            b.candle_res = j.candle_res;
        },
    }
    // Settings changed meanwhile: compute again (the current product first)
    if (cur) |c| {
        if (c.dirty) return startJob(c) catch {};
    }
    for (benches) |ob| {
        if (ob) |o| if (o.dirty) return startJob(o) catch {};
    }
    if (cur == b and j.err == null) {
        setStatus("", .{});
        refresh();
    }
}

fn onTimer(_: ?*lv.lv_timer_t) callconv(.c) void {
    if (job != null and job_done.load(.acquire)) finishJob();
    // The drawing area changed size (window, settings panel, information): draw again
    if (cur) |b| if (view_box != null and canvas.obj != null and b.computedFilm() != null) {
        const w = lv.lv_obj_get_content_width(view_box);
        const h = lv.lv_obj_get_content_height(view_box);
        if (w > 0 and h > 0 and (w != drawn_for[0] or h != drawn_for[1])) render();
    };
    if (dialogs.poll()) |r| {
        defer if (r.path) |p| gpa.free(p);
        if (r.err) |e| {
            setStatus("Cannot show the file dialog: {s}", .{e});
        } else if (r.path) |p| switch (r.kind) {
            .open_picture => openPicturePath(p),
            .save_png, .save_svg => saveTo(p),
        };
    }
}

/// Is a computation running? (for the in-app test)
pub fn busy() bool {
    return job != null;
}

/// Runs the timer until the computation is done (for the in-app test).
pub fn finishNow() void {
    while (job != null) {
        if (worker) |t| {
            t.join();
            worker = null;
        }
        finishJob();
    }
}

// ---------------------------------------------------------------------------
// Information under the drawing

fn addLine(parent: ?*lv.lv_obj_t, s: []const u8, small: bool) ?*lv.lv_obj_t {
    const l = if (small) st.muted(parent, st.zfmt("{s}", .{s})) else st.label(parent, st.zfmt("{s}", .{s}));
    return l;
}

/// Writes warnings, sizes and notes under the drawing.
fn updateInfo() !void {
    const b = cur orelse return;
    const box = info_box orelse return;
    const fl = b.computedFilm() orelse return;
    _ = st.frame_arena.reset(.retain_capacity);
    lv.lv_obj_clean(box);
    refs.apply_suggested_btn = null;
    const a = st.frame_arena.allocator();

    var warn: lamp.Warnings = .{};
    var stats: std.ArrayList([]const u8) = .empty;
    const open = @as(f64, @floatFromInt(fl.open())) / @as(f64, @floatFromInt(fl.w * fl.h));
    try stats.append(a, try std.fmt.allocPrint(a, "Film: {f} × {f} mm ({d} × {d} px)", .{
        fmt.fixed1(@as(f64, @floatFromInt(fl.w)) * fl.px), fmt.fixed1(@as(f64, @floatFromInt(fl.h)) * fl.px), fl.w, fl.h,
    }));
    try stats.append(a, try std.fmt.allocPrint(a, "Clear area: {f}%", .{fmt.fixed1(open * 100)}));

    switch (b.product) {
        .candle => {
            const r = &b.candle_res.?;
            const p = &r.p;
            warn = candle.warnings(p);
            const ri = candle.innerRadius(p, p.hd);
            try stats.append(a, try std.fmt.allocPrint(a, "Image on table: {f} × {f} mm", .{ fmt.num(fmt.jsRound(p.placement.iw)), fmt.num(fmt.jsRound(p.placement.iw * p.placement.aspect)) }));
            try stats.append(a, try std.fmt.allocPrint(a, "Image starts {f} mm from the glass center (dashed circle; the candle blocks the light inside)", .{fmt.num(fmt.jsRound(ri))}));
            try stats.append(a, try std.fmt.allocPrint(a, "Blur from the flame: ~{f} mm near the glass, ~{f} mm at the image edge", .{
                fmt.num(fmt.jsRound(r.blurAt(ri + 20, 0, p.fwid))), fmt.num(fmt.jsRound(r.blurAt(p.placement.iw / 2 * 0.9, 0, p.fwid))),
            }));
            syncFlameSlider(b);
            updateFlameNote(b);
        },
        .lamp => {
            const r = &b.lamp_res.?;
            const p = &r.p;
            if (p.lz <= p.s or p.lz >= r.B.z1)
                warn.add(try std.fmt.allocPrint(a, "LED is not inside the tube: z must be between {f} and {f}.", .{ fmt.num(p.s), fmt.num(r.B.z1) }));
            if (std.math.hypot(p.lx, p.ly) >= p.dia / 2 - p.glass) warn.add("LED is outside the tube.");
            const d = lamp.baseDims(p);
            for (lamp.baseWarnings(p, &d).slice()) |w| warn.add(w);
            try stats.append(a, try std.fmt.allocPrint(a, "Image on wall: {f} × {f} mm", .{ fmt.num(fmt.jsRound(p.placement.iw)), fmt.num(fmt.jsRound(p.placement.iw * p.placement.aspect)) }));
            try stats.append(a, try std.fmt.allocPrint(a, "Back cap and plug: Ø {f} mm", .{fmt.fixed1(d.db)}));
            try stats.append(a, try std.fmt.allocPrint(a, "Cable shadow: ~{f}° wide, below the bottle", .{fmt.fixed1(d.cable.shadow_deg)}));
            const ri = r.B.innerRadius();
            if (std.math.isFinite(ri)) try stats.append(a, try std.fmt.allocPrint(a, "Light starts {f} mm from the bottle center (dashed circle)", .{fmt.num(fmt.jsRound(ri))}));
            var buf: [64]u8 = undefined;
            b.vals.set(.lz, fmt.jsFixed(&buf, p.lz, 1));
        },
    }

    if (warn.len > 0) {
        const wbox = lv.lv_obj_create(box);
        lv.lv_obj_set_size(wbox, lv.lv_pct(100), lv.LV_SIZE_CONTENT);
        lv.lv_obj_set_flex_flow(wbox, lv.LV_FLEX_FLOW_COLUMN);
        lv.lv_obj_set_style_bg_color(wbox, lv.lv_color_hex(st.color_warning_bg), 0);
        lv.lv_obj_set_style_border_width(wbox, 0, 0);
        lv.lv_obj_set_style_radius(wbox, dp(8), 0);
        lv.lv_obj_set_style_pad_all(wbox, dp(10), 0);
        lv.lv_obj_set_style_pad_row(wbox, dp(4), 0);
        lv.lv_obj_set_scrollable(wbox, false);
        for (warn.slice()) |w| {
            const l = addLine(wbox, w, false);
            lv.lv_obj_set_style_text_color(l, lv.lv_color_hex(st.color_warning), 0);
        }
    }
    for (stats.items) |s| _ = addLine(box, s, false);

    var note: std.Io.Writer.Allocating = .init(a);
    if (try b.suggestionNote(&note.writer)) {
        const row = st.box(box, lv.LV_FLEX_FLOW_ROW_WRAP);
        // full width so the note wraps; the button goes below it
        _ = st.muted(row, st.zfmt("{s}", .{note.written()}));
        refs.apply_suggested_btn = st.smallButton(row, "Apply suggested", onApplySuggested, null);
    }
    _ = addLine(box, surfaceNote(b), true);
    if (page == .film and b.vals.is(.surface, "film")) {
        const how = st.bold(box, "How to apply:");
        lv.lv_obj_set_style_text_font(how, st.font_small, 0);
        if (b.product == .candle) {
            _ = addLine(box, "1. Apply the film starting from the bottom edge of the glass.", true);
            _ = addLine(box, "2. Place the LED candle in the center of the glass.", true);
            _ = addLine(box, "3. The LED's light must be as high above the table as the \"Design flame height\".", true);
            _ = addLine(box, "4. If the LED is not that high, put a pedestal under it. The pedestal must not be wider than the candle.", true);
        } else {
            _ = addLine(box, "Bottom edge against the back cap, cable mark under the cable, ends meet without overlap, trim extra at the front.", true);
        }
    }
    _ = addLine(box, "The test print includes a 50 mm scale bar: check it with a ruler.", true);
}

/// Fits the "Flame height now" slider to the glass; the slider follows the
/// design height until the user moves it.
fn syncFlameSlider(b: *Bench) void {
    const p = &b.candle_res.?.p;
    const lo = fmt.jsRound(p.gb + p.fhei / 2 + 3);
    const hi = @max(lo, fmt.jsRound(p.gb + p.gh - p.fhei / 2));
    settings.setRange(.hnow, lo, hi);
    if (!b.hnow_touched or p.source != .real) b.vals.setNum(.hnow, p.hd);
    b.vals.setNum(.hnow, std.math.clamp(fmt.jsRound(b.vals.num(.hnow)), lo, hi));
}

/// The note under the simulation sliders.
fn updateFlameNote(b: *const Bench) void {
    const l = settings.flame_note orelse return;
    const p = &(b.candle_res orelse return).p;
    const h = b.vals.num(.hnow);
    const ri = candle.innerRadius(p, h);
    var note: std.Io.Writer.Allocating = .init(gpa);
    defer note.deinit();
    const w = &note.writer;
    writeFlameNote(w, p, h, ri) catch return;
    w.writeByte(0) catch return;
    lv.lv_label_set_text(l, @ptrCast(note.written().ptr));
}

fn writeFlameNote(w: *std.Io.Writer, p: *const candle.Params, h: f64, ri: f64) !void {
    if (p.source != .real) {
        try w.print("LED candles do not burn down: the light stays at {f} mm and the image stays sharp. " ++
            "Light on the table starts {f} mm from the glass center.", .{ fmt.num(p.hd), fmt.num(fmt.jsRound(ri)) });
        return;
    }
    try w.print("Flame now {f} mm, design {f} mm. The image is sharpest when they match.", .{ fmt.num(h), fmt.num(p.hd) });
    // Pattern band: from where the candle stops blocking up to the flame (for the design height)
    const band_bottom = p.hd - (p.dia / 2) * (p.fhei / 2 + 3) / (p.cd / 2);
    if (h - (p.fhei / 2 + 3) > p.hd) {
        try w.writeAll(" The candle still hides the pattern at this height: the image appears as the flame comes down.");
    } else if (h < band_bottom) {
        try w.writeAll(" The flame is below the pattern: most of its light goes up, not to the table.");
    } else {
        try w.print(" Light on the table starts {f} mm from the glass center.", .{fmt.num(fmt.jsRound(ri))});
    }
}

/// What the pattern method means for the file and the result.
pub fn surfaceNote(b: *const Bench) []const u8 {
    return switch (b.vals.choice(lamp.Surface, .surface, .film)) {
        .film => "Print on clear adhesive film: printed black blocks the light.",
        .paint => "Paint the glass matte black first; the rotary laser removes the paint where light should pass. " ++
            "In the file black = remove. Set the rotary diameter to the outer diameter of the bottle.",
        .frost => "The laser frosts the places that should block light. Frosted glass scatters light rather than blocking it, " ++
            "so the image on the wall is faint and low in contrast (the ratio in the simulation is an estimate). In the file black = frost.",
    };
}
