# shadow

Desktop design tool for "shadow bottle" products: Zig 0.17.1 + LVGL 9.6 + SDL3
(allyourcodebase/SDL). A rewrite of the web app `~/project/shadow2` (Go/WASM), which is
the reference for behavior and results. Platform layer and conventions come from
`~/project/github/eexif` (desktop) and `~/project/repeto/repeto`.

## Working with the user

- Talk to the user in Turkish. Everything in the repo is English: code, comments,
  UI text, docs, commit messages.
- In explanations use the on-screen field names ("Design flame height") or plain
  words, not code abbreviations.
- Do not add features that were not asked for; ask in one sentence instead.
- Commits: at the end of each phase and for notable fixes, with a message that
  explains why (the history doubles as documentation).

## Rules

- Never drive the real desktop (no xdotool, no opening windows to click around).
  Use the in-app test; it runs offscreen.
- No system libraries besides libc, so the Windows build stays a single exe.
- Targets: Linux (tested), Windows (cross-compiled here, not run), macOS (must be
  built on a Mac; nothing in the code may be Linux-specific).

## Build and test

- Build: `zig build`. The first build compiles LVGL and SDL (a few minutes).
- In-app test (offscreen, DebugAllocator reports leaks):
  `(ulimit -v 4000000; SHADOW_TEST=1 SDL_VIDEO_DRIVER=offscreen SHADOW_SHOT=<tmp>/shots timeout 150 nice ./zig-out/bin/shadow)`
  → must end with `test: ok`. Screenshots are BMP; convert to PNG to look at them.
- After UI changes, look at the screenshots, not only the test result.
- Windows: `zig build -Dtarget=x86_64-windows`; check the imports and subsystem of the PE file.

## Layout

- `src/main.zig`: SDL3 window, LVGL display driver, mouse/keyboard input, shortcuts.
- `src/ui.zig`: menu, page frame, settings panel, navigation. `refs` exposes widgets to the test.
- `src/style.zig`: colors, scale (`dp`), fonts, widget helpers.
- `src/lv_helpers.c`: LVGL fields with bit fields (opaque in Zig).
- `src/app_test.zig`: in-app test.

## Plan

Phases, each ending with a commit:

1. Skeleton: build, platform layer, app frame (menu, pages, settings panel), in-app test.
2. Calculation core in Zig (no UI), checked against shadow2's reference results
   (`spa/lib/testdata/reference.json`, made from the first JavaScript version).
3. Night lamp workbench: settings panel, picture loading, Image / Film / Light views,
   computing off the UI thread.
4. Output: print and laser files (PNG with dpi, SVG), parts drawing on screen and as SVG.
5. Candle glass: views, flame animation, simulation sliders.
6. Picture suggestions, Ctrl + drag, finishing, README, Windows build check.

## Notes

- `@cImport` is gone in Zig 0.17: C headers go through `b.addTranslateC`.
- LVGL 9.6 deprecates `lv_obj_add_flag(.., HIDDEN)` / `CLICKABLE` and NULL displays;
  use `lv_obj_set_hidden`, `lv_obj_set_clickable`, `lv_display_get_default()`.
