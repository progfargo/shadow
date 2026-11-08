//! In-app test (SHADOW_TEST=1). Input goes through the same paths as real
//! use (pointer and keypad indevs); nothing is sent to the X server.
//!
//!   SHADOW_TEST=1 SDL_VIDEO_DRIVER=offscreen SHADOW_TEST_DIR=<tmp> \
//!   [SHADOW_SHOT=<dir>] ./zig-out/bin/shadow
//!
//! Prints "test: ok" at the end. SHADOW_SHOT saves screenshots (BMP).

const std = @import("std");
const Io = std.Io;
const sdl = @import("sdl3");
const lv = @import("lvgl");
const ui = @import("ui");
const main = @import("main.zig");
const core = ui.core;

var gpa: std.mem.Allocator = undefined;
var io: Io = undefined;

fn settle() void {
    _ = lv.lv_timer_handler();
    lv.lv_refr_now(main.display);
}

fn tap(obj: ?*lv.lv_obj_t) !void {
    const o = obj orelse return error.TestObjectMissing;
    lv.lv_obj_scroll_to_view_recursive(o, false);
    lv.lv_obj_update_layout(lv.lv_screen_active());
    var area: lv.lv_area_t = undefined;
    lv.lv_obj_get_coords(o, &area);
    main.mouse_x = @divTrunc(area.x1 + area.x2, 2);
    main.mouse_y = @divTrunc(area.y1 + area.y2, 2);
    main.mouse_down = true;
    lv.lv_indev_read(main.pointer);
    main.mouse_down = false;
    lv.lv_indev_read(main.pointer);
    settle();
}

/// Presses on the middle of an object, moves by (dx, dy) in steps and releases.
fn dragBy(obj: ?*lv.lv_obj_t, dx: i32, dy: i32) !void {
    const o = obj orelse return error.TestObjectMissing;
    var area: lv.lv_area_t = undefined;
    lv.lv_obj_get_coords(o, &area);
    const x0 = @divTrunc(area.x1 + area.x2, 2);
    const y0 = @divTrunc(area.y1 + area.y2, 2);
    main.mouse_x = x0;
    main.mouse_y = y0;
    main.mouse_down = true;
    lv.lv_indev_read(main.pointer);
    for (1..7) |i| {
        main.mouse_x = x0 + @divTrunc(dx * @as(i32, @intCast(i)), 6);
        main.mouse_y = y0 + @divTrunc(dy * @as(i32, @intCast(i)), 6);
        lv.lv_indev_read(main.pointer);
    }
    main.mouse_down = false;
    lv.lv_indev_read(main.pointer);
    settle();
}

/// Waits until the film is computed and drawn.
fn compute() void {
    ui.wb.finishNow();
    settle();
}

fn shot(name: []const u8) void {
    const d = sdl.SDL_getenv("SHADOW_SHOT") orelse return;
    settle();
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&buf, "{s}/{s}.bmp", .{ std.mem.span(d), name }, 0) catch return;
    const surf = sdl.SDL_CreateSurfaceFrom(main.frame_w, main.frame_h, sdl.SDL_PIXELFORMAT_XRGB8888, main.frame.ptr, main.frame_w * 4) orelse return;
    defer sdl.SDL_DestroySurface(surf);
    _ = sdl.SDL_SaveBMP(surf, path.ptr);
}

fn expect(ok: bool, comptime what: []const u8) !void {
    if (!ok) {
        std.debug.print("test: FAILED: {s}\n", .{what});
        return error.TestFailed;
    }
}

/// Replaces a text field's content by typing, then presses Enter.
fn typeInto(ta: ?*lv.lv_obj_t, text: []const u8) !void {
    try tap(ta);
    lv.lv_textarea_set_text(ta, "");
    main.typeText(text);
    main.pushKey(lv.LV_KEY_ENTER);
    main.flushKeys();
    settle();
}

fn choose(dd: ?*lv.lv_obj_t, index: u32) !void {
    if (dd == null) return error.TestObjectMissing;
    lv.lv_dropdown_set_selected(dd, index);
    _ = lv.lv_obj_send_event(dd, lv.LV_EVENT_VALUE_CHANGED, null);
    settle();
}

fn control(id: ui.settings.Id) ?*lv.lv_obj_t {
    return ui.settings.controls.get(id);
}

fn bench() *ui.wb.Bench {
    return ui.wb.cur.?;
}

fn isVisible(obj: ?*lv.lv_obj_t) bool {
    return obj != null and !lv.lv_obj_is_hidden(obj);
}

var dir: []const u8 = "";

/// Saves a file through the workbench (as after the save dialog) and reads it back.
fn saveAndRead(kind: ui.wb.exporter.Kind, name: []const u8) ![]u8 {
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, name });
    ui.wb.saveAs(kind, path);
    if (!std.mem.startsWith(u8, ui.wb.status_text, "Saved")) {
        std.debug.print("test: save failed: {s}\n", .{ui.wb.status_text});
        return error.TestSaveFailed;
    }
    const ext: []const u8 = if (kind == .film_png) ".png" else ".svg";
    var full_buf: [512]u8 = undefined;
    const full = if (std.mem.endsWith(u8, path, ext)) path else try std.fmt.bufPrint(&full_buf, "{s}{s}", .{ path, ext });
    return Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(100 * 1024 * 1024));
}

pub fn run(allocator: std.mem.Allocator, io_: Io) !void {
    gpa = allocator;
    io = io_;
    dir = if (sdl.SDL_getenv("SHADOW_TEST_DIR")) |d| std.mem.span(d) else return error.SetShadowTestDir;
    const cwd = Io.Dir.cwd();
    cwd.deleteTree(io, dir) catch {};
    try cwd.createDirPath(io, dir);

    settle();
    try expect(ui.page == .start, "starts on the start page");
    shot("00_start");

    // --- Every page of both products opens ---
    for (ui.refs.lamp_btns, ui.pagesOf(.lamp)) |b, pg| {
        try tap(b);
        try expect(ui.product == .lamp and ui.page == pg, "lamp page opened from the menu");
        compute();
        try expect(ui.wb.cur.?.lamp_res != null, "lamp film computed");
        var name: [32]u8 = undefined;
        shot(std.fmt.bufPrint(&name, "lamp_{s}", .{@tagName(pg)}) catch "lamp");
    }
    for (ui.refs.candle_btns, ui.pagesOf(.candle)) |b, pg| {
        try tap(b);
        try expect(ui.product == .candle and ui.page == pg, "candle page opened from the menu");
        compute();
        try expect(ui.wb.cur.?.candle_res != null, "candle film computed");
        var name: [32]u8 = undefined;
        shot(std.fmt.bufPrint(&name, "candle_{s}", .{@tagName(pg)}) catch "candle");
    }

    // --- Frames of the whole window with the flickering flame (SHADOW_FRAMES=<dir>),
    // for the README animation ---
    if (sdl.SDL_getenv("SHADOW_FRAMES")) |d| {
        for (0..36) |i| {
            ui.wb.flameFrame(@as(f64, @floatFromInt(i)) / 12);
            settle();
            var buf: [512]u8 = undefined;
            const path = try std.fmt.bufPrintSentinel(&buf, "{s}/frame_{d:0>2}.bmp", .{ std.mem.span(d), i }, 0);
            const surf = sdl.SDL_CreateSurfaceFrom(main.frame_w, main.frame_h, sdl.SDL_PIXELFORMAT_XRGB8888, main.frame.ptr, main.frame_w * 4) orelse return error.TestSurface;
            defer sdl.SDL_DestroySurface(surf);
            _ = sdl.SDL_SaveBMP(surf, path.ptr);
        }
        ui.wb.render(); // the animation runs again
        settle();
    }

    // --- Candle simulation: the flame is animated, the sliders change only the light ---
    try expect(ui.wb.flame.running(), "flame animated on the Light page");
    {
        const film_before = bench().candle_res.?.film.data.ptr;
        const slider = control(.hnow);
        try expect(lv.lv_slider_get_min_value(slider) == 100 * 18 and lv.lv_slider_get_max_value(slider) == 100 * 135, "flame slider fits the glass");
        lv.lv_slider_set_value(slider, 100 * 90, false);
        _ = lv.lv_obj_send_event(slider, lv.LV_EVENT_VALUE_CHANGED, null);
        settle();
        try expect(bench().vals.num(.hnow) == 90 and bench().hnow_touched, "flame height now moved");
        try expect(!ui.wb.busy() and bench().candle_res.?.film.data.ptr == film_before, "the slider does not compute the film again");
        const note = std.mem.span(lv.lv_label_get_text(ui.settings.flame_note));
        try expect(std.mem.startsWith(u8, note, "Flame now 90 mm, design 60 mm.") and std.mem.indexOf(u8, note, "candle still hides") != null, "flame note");
        shot("07_candle_flame_high");
    }
    try choose(control(.source), 1); // LED tealight
    compute();
    try expect(bench().vals.num(.cd) == 38 and bench().vals.num(.hd) == 30 and bench().candle_res.?.p.source == .led, "LED preset applied");
    try expect(!isVisible(ui.settings.rows.get(.hnow).?), "no flame height slider for LED");
    try tap(control(.animate));
    try expect(!ui.wb.flame.running(), "animation off");
    try choose(control(.source), 0);
    try tap(control(.animate));
    compute();
    try expect(ui.wb.flame.running() and bench().vals.num(.hnow) == 60, "real candle again, slider follows the design height");

    // --- Settings change the film ---
    try tap(ui.refs.lamp_btns[0]);
    compute();
    const open0 = bench().lamp_res.?.film.open();
    // The sample picture's suggestion is applied at start; switch to the other mode
    const suggested = bench().lamp_res.?.p.pattern.mode;
    const other: core.film.Mode = if (suggested == .binary) .halftone else .binary;
    try choose(control(.mode), @intFromEnum(other));
    const ht = other == .halftone;
    try expect(isVisible(ui.settings.rows.get(.pitch).?) == ht and isVisible(ui.settings.rows.get(.threshold).?) == !ht, "fields of the mode shown");
    compute();
    try expect(bench().lamp_res.?.p.pattern.mode == other, "other mode computed");
    try expect(bench().lamp_res.?.film.open() != open0, "film changed");
    try expect(ui.wb.refs.apply_suggested_btn != null, "suggestion offered");
    shot("03_other_mode");
    try tap(ui.wb.refs.apply_suggested_btn);
    compute();
    try expect(bench().lamp_res.?.p.pattern.mode == suggested and ui.wb.refs.apply_suggested_btn == null, "suggestion applied");

    try typeInto(control(.iw), "300");
    compute();
    try expect(bench().lamp_res.?.p.placement.iw == 300, "image width typed");
    const invert0 = bench().lamp_res.?.p.pattern.invert;
    try tap(control(.invert));
    compute();
    try expect(bench().lamp_res.?.p.pattern.invert != invert0, "invert toggled");

    // --- A picture from a file; the settings stay ---
    {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrintSentinel(&path_buf, "{s}/picture.bmp", .{dir}, 0);
        const surf = sdl.SDL_CreateSurface(40, 20, sdl.SDL_PIXELFORMAT_XRGB8888) orelse return error.TestSurface;
        defer sdl.SDL_DestroySurface(surf);
        _ = sdl.SDL_FillSurfaceRect(surf, null, 0xFFFFFF);
        var r: sdl.SDL_Rect = .{ .x = 10, .y = 5, .w = 20, .h = 10 };
        _ = sdl.SDL_FillSurfaceRect(surf, &r, 0x000000);
        if (!sdl.SDL_SaveBMP(surf, path.ptr)) return error.TestSaveBmp;
        ui.wb.openPicturePath(path);
        compute();
        try expect(std.mem.eql(u8, bench().picture_name.get(), "picture.bmp") and bench().picture.w == 40, "picture loaded");
        try expect(bench().lamp_res.?.p.placement.aspect == 0.5 and bench().lamp_res.?.p.pattern.invert != invert0, "settings kept, aspect from the picture");
        shot("04_picture");
        ui.wb.openPicturePath("no/such/file.png");
        try expect(std.mem.startsWith(u8, ui.wb.status_text, "Cannot open the picture"), "missing file reported");
    }

    // --- Ctrl + drag moves the glass; the picture center moves the other way ---
    try tap(ui.refs.lamp_btns[0]);
    compute();
    {
        const ix0 = bench().vals.num(.ix);
        const sc = ui.wb.viewScale();
        ui.wb.ctrl_held = true;
        try dragBy(ui.wb.refs.canvas, 60, 0);
        ui.wb.ctrl_held = false;
        compute();
        const want = @floor(ix0 - 60 / sc + 0.5);
        try expect(bench().vals.num(.ix) == want and bench().lamp_res.?.p.placement.ix == want, "Ctrl + drag moved the picture");
        shot("08_dragged");
        // Without Ctrl nothing moves
        try dragBy(ui.wb.refs.canvas, 60, 0);
        try expect(bench().vals.num(.ix) == want and !ui.wb.busy(), "plain drag does nothing");
    }

    // --- Saving: print PNG with its resolution, SVG, laser pattern, parts drawing ---
    try tap(ui.refs.lamp_btns[1]);
    compute();
    try expect(ui.wb.refs.save_png_btn != null and ui.wb.refs.save_svg_btn != null, "save buttons on the Film page");
    shot("05_film_saved");
    {
        const png = try saveAndRead(.film_png, "film.png");
        defer gpa.free(png);
        try expect(std.mem.eql(u8, png[1..4], "PNG") and std.mem.eql(u8, png[37..41], "pHYs"), "print PNG with resolution");
        try expect(png[25] == 2, "print PNG is RGB");
        try expect(std.mem.eql(u8, ui.wb.status_text, "Saved film.png"), "saved message");
    }
    {
        const svg = try saveAndRead(.film_svg, "film");
        defer gpa.free(svg);
        try expect(std.mem.startsWith(u8, svg, "<svg") and std.mem.indexOf(u8, svg, "data:image/png;base64,") != null, "film SVG with the picture (extension added)");
    }
    try choose(control(.surface), 1); // Painted glass + laser ablation
    compute();
    {
        const png = try saveAndRead(.film_png, "laser.png");
        defer gpa.free(png);
        const fl = bench().lamp_res.?.film;
        try expect(png[25] == 0 and std.mem.readInt(u32, png[16..20], .big) == fl.w, "laser PNG: gray, film size, no border");
    }
    try choose(control(.surface), 0);
    compute();
    try tap(ui.refs.lamp_btns[3]);
    compute();
    {
        const svg = try saveAndRead(.parts_svg, "parts.svg");
        defer gpa.free(svg);
        try expect(std.mem.startsWith(u8, svg, "<svg") and std.mem.indexOf(u8, svg, "Parts and notes") != null, "parts SVG");
    }
    shot("06_parts");

    // --- The settings panel opens and closes, and stays so between pages ---
    const was_open = ui.settingsOpen();
    try tap(ui.refs.settings_btn);
    try expect(ui.settingsOpen() != was_open, "Settings button toggles the panel");
    if (!ui.settingsOpen()) try tap(ui.refs.settings_btn);
    try tap(ui.refs.lamp_btns[0]);
    try expect(ui.settingsOpen(), "panel stays open on another page");
    shot("02_lamp_image");
    try expect(ui.back() and !ui.settingsOpen(), "Esc closes the panel");
    try tap(ui.refs.settings_btn);

    try tap(ui.refs.start_btn);
    try expect(ui.page == .start, "back to the start page");

    std.debug.print("test: ok\n", .{});
}
