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

fn isVisible(obj: ?*lv.lv_obj_t) bool {
    return obj != null and !lv.lv_obj_is_hidden(obj);
}

pub fn run(allocator: std.mem.Allocator, io_: Io) !void {
    gpa = allocator;
    io = io_;

    settle();
    try expect(ui.page == .start, "starts on the start page");
    shot("00_start");

    // --- Every page of both products opens ---
    for (ui.refs.lamp_btns, ui.pagesOf(.lamp)) |b, pg| {
        try tap(b);
        try expect(ui.product == .lamp and ui.page == pg, "lamp page opened from the menu");
    }
    for (ui.refs.candle_btns, ui.pagesOf(.candle)) |b, pg| {
        try tap(b);
        try expect(ui.product == .candle and ui.page == pg, "candle page opened from the menu");
    }
    shot("01_candle_light");

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
