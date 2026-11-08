# shadow

Desktop design tool for "shadow bottle" products: Zig 0.17.1 + LVGL 9.6 + SDL3
(allyourcodebase/SDL). The calculation follows the first version of the tool
(JavaScript, `~/project/shadow`), whose results are the test reference. Platform layer
and conventions come from `~/project/github/eexif` (desktop) and `~/project/repeto/repeto`.

## Working with the user

- Talk to the user in Turkish. Everything in the repo is English: code, comments,
  UI text, docs, commit messages.
- In explanations use the on-screen field names ("Design flame height") or plain
  words, not code abbreviations.
- Do not add features that were not asked for; ask in one sentence instead.
- Commits: at the end of each phase and for notable fixes, with a message that
  explains why (the history doubles as documentation).
- No `Co-Authored-By` line in commit messages (GitHub would count every commit
  fully for both authors).
- The repo must not mention the earlier web version of this tool (its language,
  name or paths): this project stands on its own.

## Rules

- Never drive the real desktop (no xdotool, no opening windows to click around).
  Use the in-app test; it runs offscreen.
- No system libraries besides libc, so the Windows build stays a single exe.
- Targets: Linux (tested), Windows (cross-compiled here, not run), macOS (must be
  built on a Mac; nothing in the code may be Linux-specific).

## Build and test

- Build: `zig build`. The first build compiles LVGL and SDL (a few minutes).
- Unit tests: `zig build test` (src/core: the calculation against the first version's results).
- In-app test (offscreen, DebugAllocator reports leaks):
  `(ulimit -v 4000000; SHADOW_TEST=1 SDL_VIDEO_DRIVER=offscreen SHADOW_TEST_DIR=<tmp>/testdir SHADOW_SHOT=<tmp>/shots timeout 300 nice ./zig-out/bin/shadow)`
  → must end with `test: ok`. Screenshots are BMP; convert to PNG to look at them.
- After UI changes, look at the screenshots, not only the test result.
- Speed: a debug build computes a film in ~0.7 s and draws the lamp's light in ~1 s;
  a release build in ~0.2 s / ~0.25 s.
- Windows: `zig build -Dtarget=x86_64-windows`; check the imports and subsystem of the PE file.

## Layout

- `src/main.zig`: SDL3 window, LVGL display driver, mouse/keyboard input, shortcuts.
- `src/ui.zig`: menu, page frame (title, toolbar, drawing card, information, settings
  panel), navigation. `refs` exposes widgets to the test.
- `src/pages.zig`: products (Night Lamp, Candle Glass) and their pages.
- `src/style.zig`: colors, scale (`dp`), fonts, widget helpers.
- `src/settings.zig`: the table of settings fields (label, kind, when shown), defaults,
  light source presets, the values of a product (kept as the text the fields show)
  and the settings panel built from the table.
- `src/workbench.zig`: per-product state (`Bench`: values, picture, analysis, computed
  result), computing the film on a worker thread (a timer picks up the result),
  suggestions, information under the drawing, picture loading.
- `src/views.zig`: the drawings: Image, Film, Light (lamp), with the glass, labels and
  scale bar drawn over the computed pixels.
- `src/flame.zig`: the candle's light on the table with a flickering flame (five flame
  points sampled at quarter resolution, enlarged, blurred by the flame width), animated
  by an LVGL timer at ~12 frames/s; paused while the window is minimized or hidden.
- `src/parts_view.zig`: the parts drawing on screen, from the same list of shapes as
  the SVG, with the SVG classes' styles (wood hatching computed per circle/rectangle).
- `src/export.zig`: saved files. Print PNG (actual size, cut border, labels, 50 mm
  bar, cable mark; drawn on a hidden canvas), laser PNG (plain gray pattern; black =
  laser fires), the same inside an SVG with its size in mm, parts SVG. PNGs carry
  the dpi (pHYs). The extension is added when the name has none.
- `src/canvas.zig` + `src/draw.c`: an LVGL canvas with its own pixel buffer; shapes and
  text go through C because LVGL's draw descriptors have bit fields (opaque in Zig).
  LVGL turns each glyph on its own, so upward text (`textUpward`) is drawn flat on a
  small canvas and its pixels are turned and blended in.
- `src/picture.zig` + `src/image.c`: picture files (stb_image), resampling, the
  brightness grid the calculation reads; PNG writing (stb_image_write).
- `assets/sample_portrait.jpg`: the picture both products open with (embedded).
- `src/dialogs.zig`: native open/save dialogs through SDL (result via an atomic flag).
- `src/lv_helpers.c`: LVGL fields with bit fields (fonts, draw buffers).
- `src/app_test.zig`: in-app test.
- `docs/`: screenshots for the README (from the in-app test's `SHADOW_SHOT`).
- `src/core/`: the calculation, no UI (module `core`):
  - `format.zig`: JavaScript-compatible number text (`jsFixed` = toFixed, `jsNum`, `jsRound`).
  - `film.zig`: pattern settings, film raster, `mapFilm` (film pixel → lit surface,
    exact every 4 px and interpolated, stored as f32), `fillFilm`.
  - `screen.zig`: halftone patterns. `optics.zig`: cylinder and glass refraction.
  - `lamp.zig`, `lamp_dims.zig`: night lamp geometry, wooden part sizes, warnings.
  - `candle.zig`: candle glass. `suggest.zig`: settings suggested from the picture.
  - `parts.zig`: parts drawing as a list of shapes; written as SVG (byte-identical to
    the first version) and drawn on screen.
  - `png.zig`: pHYs chunk so PNGs print at actual size.
  - `reference_test.zig`: compares with `test/reference/reference.json` (results of
    the first version; fixed data, not generated by the build).

## Plan

Phases, each ending with a commit:

1. Skeleton: build, platform layer, app frame (menu, pages, settings panel), in-app test.
2. Calculation core in Zig (no UI), checked against the first version's results.
3. Night lamp workbench: settings panel, picture loading, Image / Film / Light views,
   computing off the UI thread.
4. Output: print and laser files (PNG with dpi, SVG), parts drawing on screen and as SVG.
5. Candle glass: views, flame animation, simulation sliders.
6. Picture suggestions, Ctrl + drag, finishing, README, Windows build check.

All phases are done. Open: test on Windows and macOS; the project has no license
file yet (the user decides).

## Notes

- `@cImport` is gone in Zig 0.17: C headers go through `b.addTranslateC`.
  Optimize modes are `.debug`, `.safe`, `.fast`, `.small`.
- LVGL 9.6 deprecates `lv_obj_add_flag(.., HIDDEN)` / `CLICKABLE` and NULL displays;
  use `lv_obj_set_hidden`, `lv_obj_set_clickable`, `lv_display_get_default()`.
- LVGL 9.6's canvas destructor passes the address of its buffer pointer to the image
  cache ("invalid magic" error); `Canvas.destroy` detaches the buffer first.
- Zig array literals assigned to the same array alias: `q.* = .{ f(q[0]), g(q[0]) }`
  writes q[0] before g reads it. Copy first (see `parts.zig` slot).
- Numbers that JavaScript formatted: `Math.round` → `jsRound`, `toFixed` → `jsFixed`,
  number to text → `jsNum`.
- The app sets the halftone grid to `wall`; `film` stays for the reference tests.
- The page's toolbar items are created before the drawing is sized: a widget added
  later changes the drawing area (the timer redraws if the size changes anyway).
