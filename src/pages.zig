//! The products and their pages.

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
