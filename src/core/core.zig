//! The calculation of shadow, without UI: the film for a picture, where its
//! light lands, the sizes of the parts and the parts drawing. Units are mm.
//!
//! The results follow the first version of the tool (JavaScript); the tests
//! compare them with that version (test/reference/reference.json).

pub const format = @import("format.zig");
pub const optics = @import("optics.zig");
pub const film = @import("film.zig");
pub const screen = @import("screen.zig");
pub const suggest = @import("suggest.zig");
pub const png = @import("png.zig");
pub const lamp = @import("lamp.zig");
pub const candle = @import("candle.zig");
pub const parts = @import("parts.zig");

test {
    _ = format;
    _ = suggest;
    _ = @import("reference_test.zig");
}
