//! Native file dialogs through SDL3 (Windows and macOS system dialogs; on
//! Linux the desktop portal or zenity). SDL may call back from another
//! thread, so the result is handed over through an atomic flag and the UI
//! polls for it from a timer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sdl = @import("sdl3");

pub const Kind = enum { open_picture, save_png, save_svg };

pub const Result = struct {
    kind: Kind,
    /// Selected path, or null if the dialog was cancelled or failed.
    path: ?[:0]u8,
    /// Error text if the dialog could not be shown.
    err: ?[]const u8 = null,
};

var gpa: Allocator = undefined;
var window: ?*sdl.SDL_Window = null;
var open = false;
var done: std.atomic.Value(bool) = .init(false);
var result: Result = undefined;
var location_buf: [std.fs.max_path_bytes:0]u8 = undefined;
var err_buf: [256]u8 = undefined;

const picture_filters = [_]sdl.SDL_DialogFileFilter{
    .{ .name = "Pictures", .pattern = "png;jpg;jpeg;bmp;gif;tga;psd;pnm;ppm;pgm;PNG;JPG;JPEG;BMP;GIF" },
    .{ .name = "All files", .pattern = "*" },
};
const png_filters = [_]sdl.SDL_DialogFileFilter{.{ .name = "PNG image", .pattern = "png" }};
const svg_filters = [_]sdl.SDL_DialogFileFilter{.{ .name = "SVG drawing", .pattern = "svg" }};

pub fn init(allocator: Allocator, win: ?*sdl.SDL_Window) void {
    gpa = allocator;
    window = win;
}

pub fn deinit() void {
    if (done.load(.acquire)) {
        if (result.path) |p| gpa.free(p);
    }
}

pub fn busy() bool {
    return open;
}

/// Opens a dialog unless one is already open. `location` is the folder (open)
/// or the suggested file (save).
pub fn start(kind: Kind, location: ?[]const u8) void {
    if (open) return;
    open = true;
    done.store(false, .release);
    result = .{ .kind = kind, .path = null };
    const loc: ?[*:0]const u8 = if (location) |d|
        (std.fmt.bufPrintSentinel(&location_buf, "{s}", .{d}, 0) catch null)
    else
        null;
    switch (kind) {
        .open_picture => sdl.SDL_ShowOpenFileDialog(onResult, null, window, &picture_filters, picture_filters.len, loc, false),
        .save_png => sdl.SDL_ShowSaveFileDialog(onResult, null, window, &png_filters, png_filters.len, loc),
        .save_svg => sdl.SDL_ShowSaveFileDialog(onResult, null, window, &svg_filters, svg_filters.len, loc),
    }
}

/// Returns the result once the dialog is closed. Caller owns `path`.
pub fn poll() ?Result {
    if (!done.load(.acquire)) return null;
    done.store(false, .release);
    open = false;
    return result;
}

/// filelist: null on error, empty (first item null) when cancelled.
fn onResult(_: ?*anyopaque, filelist: [*c]const [*c]const u8, _: c_int) callconv(.c) void {
    if (filelist == null) {
        result.err = std.fmt.bufPrint(&err_buf, "{s}", .{std.mem.span(sdl.SDL_GetError())}) catch "unknown error";
    } else if (filelist[0] != null) {
        result.path = gpa.dupeSentinel(u8, std.mem.span(filelist[0]), 0) catch null;
    }
    done.store(true, .release);
}
