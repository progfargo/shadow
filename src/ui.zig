//! Screens (LVGL).
//!
//! Layout: a menu on the left (Start, Night Lamp and Candle Glass pages);
//! the page in the middle (title, toolbar, drawing, information below it);
//! the settings panel on the right, which the "Settings" button opens and
//! closes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const lv = @import("lvgl");
const sdl = @import("sdl3");
const st = @import("style.zig");
const dp = st.dp;

pub const Product = enum {
    lamp,
    candle,

    pub fn label(p: Product) [*:0]const u8 {
        return switch (p) {
            .lamp => "Night Lamp",
            .candle => "Candle Glass",
        };
    }
};

pub const Page = enum {
    start,
    image,
    film,
    light,
    parts,

    pub fn label(p: Page) [*:0]const u8 {
        return switch (p) {
            .start => "Start",
            .image => "Image",
            .film => "Film",
            .light => "Light",
            .parts => "Parts",
        };
    }
};

/// Pages of each product, in menu order
pub fn pagesOf(p: Product) []const Page {
    return switch (p) {
        .lamp => &.{ .image, .film, .light, .parts },
        .candle => &.{ .image, .film, .light },
    };
}

// ---------------------------------------------------------------------------
// State

var gpa: Allocator = undefined;
var io: Io = undefined;
var quit_requested = false;

pub var product: Product = .lamp;
pub var page: Page = .start;
/// Ctrl (Cmd on macOS) was held when the mouse button went down
pub var ctrl_held = false;
/// The settings panel is open (kept between pages)
var settings_open = true;

// Widgets
var menu: ?*lv.lv_obj_t = null;
var main_area: ?*lv.lv_obj_t = null;
var settings_panel: ?*lv.lv_obj_t = null;

/// Objects the in-app test drives (null when not on screen)
pub const Refs = struct {
    start_btn: ?*lv.lv_obj_t = null,
    lamp_btns: [4]?*lv.lv_obj_t = @splat(null),
    candle_btns: [3]?*lv.lv_obj_t = @splat(null),
    settings_btn: ?*lv.lv_obj_t = null,
    page_title: ?*lv.lv_obj_t = null,
};
pub var refs: Refs = .{};

// ---------------------------------------------------------------------------
// Setup

pub fn init(allocator: Allocator, io_: Io, window: ?*sdl.SDL_Window, ui_scale: f32) !void {
    _ = window;
    gpa = allocator;
    io = io_;
    st.frame_arena = .init(gpa);
    // Wide windows start with the settings panel open
    settings_open = lv.lv_display_get_horizontal_resolution(lv.lv_display_get_default()) >= @as(i32, @intFromFloat(1100 * ui_scale));
    try build(ui_scale);
}

pub fn deinit() void {
    // Delete widgets before the fonts they use
    lv.lv_obj_clean(lv.lv_layer_top());
    lv.lv_obj_clean(lv.lv_screen_active());
    st.destroyFonts();
    st.frame_arena.deinit();
}

/// Rebuilds the UI for a new scale; the current page is kept.
pub fn setScale(ui_scale: f32) !void {
    if (@abs(ui_scale - st.scale) < 0.01) return;
    lv.lv_obj_clean(lv.lv_layer_top());
    lv.lv_obj_clean(lv.lv_screen_active());
    st.destroyFonts();
    try build(ui_scale);
}

pub fn onResize() void {
    lv.lv_obj_update_layout(lv.lv_screen_active());
}

pub fn shouldQuit() bool {
    return quit_requested;
}

pub fn requestQuit() void {
    quit_requested = true;
}

/// Esc: closes the settings panel. Returns true if it did something.
pub fn back() bool {
    if (page != .start and settings_open) {
        toggleSettings();
        return true;
    }
    return false;
}

pub fn openPictureShortcut() void {}

pub fn openPicturePath(path: []const u8) void {
    _ = path;
}

fn build(ui_scale: f32) !void {
    st.scale = ui_scale;
    try st.createFonts();
    refs = .{};

    const disp = lv.lv_display_get_default();
    const theme = lv.lv_theme_default_init(disp, lv.lv_color_hex(st.color_primary), lv.lv_color_hex(st.color_danger), false, st.font_normal);
    lv.lv_display_set_theme(disp, theme);

    const scr = lv.lv_screen_active();
    lv.lv_obj_set_style_text_font(scr, st.font_normal, 0);
    lv.lv_obj_set_style_text_font(lv.lv_layer_top(), st.font_normal, 0);
    lv.lv_obj_set_style_text_color(scr, lv.lv_color_hex(st.color_text), 0);
    lv.lv_obj_set_style_bg_color(scr, lv.lv_color_hex(st.color_bg), 0);
    lv.lv_obj_set_flex_flow(scr, lv.LV_FLEX_FLOW_ROW);
    lv.lv_obj_set_style_pad_all(scr, 0, 0);
    lv.lv_obj_set_style_pad_column(scr, 0, 0);
    lv.lv_obj_set_scrollable(scr, false);

    buildMenu(scr);

    main_area = lv.lv_obj_create(scr);
    lv.lv_obj_remove_style_all(main_area);
    lv.lv_obj_set_height(main_area, lv.lv_pct(100));
    lv.lv_obj_set_width(main_area, 1);
    lv.lv_obj_set_flex_grow(main_area, 1);
    lv.lv_obj_set_flex_flow(main_area, lv.LV_FLEX_FLOW_COLUMN);
    lv.lv_obj_set_style_pad_all(main_area, dp(16), 0);
    lv.lv_obj_set_style_pad_row(main_area, dp(12), 0);
    lv.lv_obj_set_scrollable(main_area, false);

    settings_panel = lv.lv_obj_create(scr);
    lv.lv_obj_set_size(settings_panel, dp(340), lv.lv_pct(100));
    lv.lv_obj_set_flex_flow(settings_panel, lv.LV_FLEX_FLOW_COLUMN);
    lv.lv_obj_set_style_radius(settings_panel, 0, 0);
    lv.lv_obj_set_style_border_width(settings_panel, 0, 0);
    lv.lv_obj_set_style_pad_all(settings_panel, dp(14), 0);
    lv.lv_obj_set_style_pad_row(settings_panel, dp(10), 0);
    lv.lv_obj_set_style_shadow_width(settings_panel, dp(14), 0);
    lv.lv_obj_set_style_shadow_opa(settings_panel, lv.LV_OPA_10, 0);
    lv.lv_obj_set_scroll_dir(settings_panel, lv.LV_DIR_VER);

    showPage();
}

// ---------------------------------------------------------------------------
// Menu

/// Menu button user data: product and page packed into a pointer
fn navData(p: Product, pg: Page) ?*anyopaque {
    return @ptrFromInt(1 + @as(usize, @intFromEnum(p)) * 16 + @intFromEnum(pg));
}

fn onNav(e: ?*lv.lv_event_t) callconv(.c) void {
    const v = @intFromPtr(lv.lv_event_get_user_data(e)) - 1;
    navigate(@enumFromInt(v / 16), @enumFromInt(v % 16));
}

fn menuItem(parent: ?*lv.lv_obj_t, text: [*:0]const u8, p: Product, pg: Page, indent: bool) ?*lv.lv_obj_t {
    const b = lv.lv_button_create(parent);
    lv.lv_obj_remove_style_all(b);
    lv.lv_obj_set_width(b, lv.lv_pct(100));
    lv.lv_obj_set_style_pad_ver(b, dp(8), 0);
    lv.lv_obj_set_style_pad_left(b, dp(if (indent) 34 else 16), 0);
    lv.lv_obj_set_style_radius(b, dp(6), 0);
    lv.lv_obj_set_style_bg_color(b, lv.lv_color_hex(st.color_menu_active), lv.LV_STATE_CHECKED);
    lv.lv_obj_set_style_bg_opa(b, lv.LV_OPA_COVER, lv.LV_STATE_CHECKED);
    lv.lv_obj_set_style_bg_color(b, lv.lv_color_hex(st.color_bg), lv.LV_STATE_PRESSED);
    lv.lv_obj_set_style_bg_opa(b, lv.LV_OPA_COVER, lv.LV_STATE_PRESSED);
    lv.lv_obj_set_style_text_color(b, lv.lv_color_hex(st.color_primary), lv.LV_STATE_CHECKED);
    const l = lv.lv_label_create(b);
    lv.lv_label_set_text(l, text);
    _ = lv.lv_obj_add_event_cb(b, onNav, lv.LV_EVENT_CLICKED, navData(p, pg));
    return b;
}

fn menuHeading(parent: ?*lv.lv_obj_t, text: [*:0]const u8) void {
    const l = st.bold(parent, text);
    lv.lv_obj_set_style_pad_left(l, dp(16), 0);
    lv.lv_obj_set_style_pad_top(l, dp(10), 0);
}

fn buildMenu(scr: ?*lv.lv_obj_t) void {
    menu = lv.lv_obj_create(scr);
    lv.lv_obj_set_size(menu, dp(220), lv.lv_pct(100));
    lv.lv_obj_set_flex_flow(menu, lv.LV_FLEX_FLOW_COLUMN);
    lv.lv_obj_set_style_radius(menu, 0, 0);
    lv.lv_obj_set_style_border_width(menu, 0, 0);
    lv.lv_obj_set_style_pad_all(menu, dp(10), 0);
    lv.lv_obj_set_style_pad_row(menu, dp(2), 0);
    lv.lv_obj_set_scroll_dir(menu, lv.LV_DIR_VER);

    const name = st.title(menu, "shadow");
    lv.lv_obj_set_style_pad_left(name, dp(16), 0);
    lv.lv_obj_set_style_pad_ver(name, dp(10), 0);

    refs.start_btn = menuItem(menu, lv.LV_SYMBOL_HOME ++ "  Start", .lamp, .start, false);
    menuHeading(menu, "Night Lamp");
    for (pagesOf(.lamp), 0..) |pg, i| refs.lamp_btns[i] = menuItem(menu, pg.label(), .lamp, pg, true);
    menuHeading(menu, "Candle Glass");
    for (pagesOf(.candle), 0..) |pg, i| refs.candle_btns[i] = menuItem(menu, pg.label(), .candle, pg, true);
}

fn markMenu() void {
    const items = [_]struct { btn: ?*lv.lv_obj_t, p: ?Product, pg: Page }{
        .{ .btn = refs.start_btn, .p = null, .pg = .start },
        .{ .btn = refs.lamp_btns[0], .p = .lamp, .pg = .image },
        .{ .btn = refs.lamp_btns[1], .p = .lamp, .pg = .film },
        .{ .btn = refs.lamp_btns[2], .p = .lamp, .pg = .light },
        .{ .btn = refs.lamp_btns[3], .p = .lamp, .pg = .parts },
        .{ .btn = refs.candle_btns[0], .p = .candle, .pg = .image },
        .{ .btn = refs.candle_btns[1], .p = .candle, .pg = .film },
        .{ .btn = refs.candle_btns[2], .p = .candle, .pg = .light },
    };
    for (items) |it| {
        const on = it.pg == page and (page == .start or it.p == product);
        if (on) lv.lv_obj_add_state(it.btn, lv.LV_STATE_CHECKED) else lv.lv_obj_remove_state(it.btn, lv.LV_STATE_CHECKED);
    }
}

// ---------------------------------------------------------------------------
// Pages

/// Opens a page.
pub fn navigate(p: Product, pg: Page) void {
    if (pg != .start) product = p;
    page = pg;
    showPage();
}

fn onStartProduct(e: ?*lv.lv_event_t) callconv(.c) void {
    const v = @intFromPtr(lv.lv_event_get_user_data(e)) - 1;
    navigate(@enumFromInt(v), .image);
}

pub fn settingsOpen() bool {
    return settings_open;
}

fn onToggleSettings(_: ?*lv.lv_event_t) callconv(.c) void {
    toggleSettings();
}

fn toggleSettings() void {
    settings_open = !settings_open;
    lv.lv_obj_set_hidden(settings_panel, !settings_open or page == .start);
}

/// Builds the current page in the main area.
fn showPage() void {
    _ = st.frame_arena.reset(.retain_capacity);
    lv.lv_obj_clean(main_area);
    refs.settings_btn = null;
    markMenu();
    lv.lv_obj_set_hidden(settings_panel, !settings_open or page == .start);

    if (page == .start) {
        refs.page_title = st.title(main_area, "Shadow Bottle");
        const c = st.card(main_area);
        lv.lv_obj_set_size(c, lv.lv_pct(100), lv.LV_SIZE_CONTENT);
        _ = st.bold(c, "Light through a patterned glass");
        _ = st.label(c, "A cut bottle with a light inside draws a picture: on the wall for the night lamp, " ++
            "on the table for the candle glass. Choose a picture, set the sizes of the glass and the light, " ++
            "and print the computed film to wrap around the glass.");
        const row = st.box(c, lv.LV_FLEX_FLOW_ROW);
        _ = st.button(row, lv.LV_SYMBOL_IMAGE ++ "  Night Lamp", onStartProduct, @ptrFromInt(1 + @as(usize, @intFromEnum(Product.lamp))));
        _ = st.button(row, lv.LV_SYMBOL_IMAGE ++ "  Candle Glass", onStartProduct, @ptrFromInt(1 + @as(usize, @intFromEnum(Product.candle))));
        return;
    }

    refs.page_title = st.title(main_area, st.zfmt("{s}  " ++ lv.LV_SYMBOL_RIGHT ++ "  {s}", .{ product.label(), page.label() }));

    const bar = st.box(main_area, lv.LV_FLEX_FLOW_ROW);
    st.spacer(bar);
    refs.settings_btn = st.outlineButton(bar, lv.LV_SYMBOL_SETTINGS ++ "  Settings", onToggleSettings, null);

    const view = st.card(main_area);
    lv.lv_obj_set_width(view, lv.lv_pct(100));
    lv.lv_obj_set_flex_grow(view, 1);
    lv.lv_obj_set_style_bg_color(view, lv.lv_color_hex(st.color_stage), 0);

    lv.lv_obj_clean(settings_panel);
    _ = st.title(settings_panel, "Settings");
}
