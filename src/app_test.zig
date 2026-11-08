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
    }
    shot("01_candle_light");

    // --- Settings change the film ---
    try tap(ui.refs.lamp_btns[0]);
    compute();
    const open0 = bench().lamp_res.?.film.open();
    try choose(control(.mode), 1); // Halftone
    try expect(isVisible(ui.settings.rows.get(.pitch).?) and !isVisible(ui.settings.rows.get(.threshold).?), "halftone fields shown");
    compute();
    try expect(bench().lamp_res.?.p.pattern.mode == .halftone, "halftone computed");
    try expect(bench().lamp_res.?.film.open() != open0, "film changed");
    try expect(ui.wb.refs.apply_suggested_btn != null, "suggestion offered");
    shot("03_halftone");
    try tap(ui.wb.refs.apply_suggested_btn);
    compute();
    try expect(bench().lamp_res.?.p.pattern.mode == .binary and ui.wb.refs.apply_suggested_btn == null, "suggestion applied");

    try typeInto(control(.iw), "300");
    compute();
    try expect(bench().lamp_res.?.p.placement.iw == 300, "image width typed");
    try tap(control(.invert));
    compute();
    try expect(bench().lamp_res.?.p.pattern.invert, "invert checked");

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
        try expect(bench().lamp_res.?.p.placement.aspect == 0.5 and bench().lamp_res.?.p.pattern.invert, "settings kept, aspect from the picture");
        shot("04_picture");
        ui.wb.openPicturePath("no/such/file.png");
        try expect(std.mem.startsWith(u8, ui.wb.status_text, "Cannot open the picture"), "missing file reported");
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
