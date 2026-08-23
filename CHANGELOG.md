# Changelog

All notable changes to simple_shell.

## 1.4.0 - 2026-08-23

### Added
- App-settable FAST TIMER: set_fast_timer (ms) arms a second native
  timer (event 25) beside the 250ms heartbeat - polling loops that
  outpace it (the OCR capture cycle: 50ms) get their own clock.
- close: programmatic DestroyWindow - the pump sees WM_QUIT and
  shell_run returns. SW applications can finally quit themselves.
- SHELL_DESKTOP.pump_for (ms): a WINDOWLESS PeekMessage pump so
  facility windows (outlines, strip) paint during short CLI
  diagnostics with no main window at all. Assault 11/11.
- Strip drag law measured properly: the no-drag corner is exactly
  the transport corner (right 90px of the top 26px).

## 1.3.0 — 2026-08-23

### Added
- SHELL_OUTLINES: up to four click-through coloured rectangle FRAMES
  on the desktop (topmost, toolwindow, never activated, input-
  transparent; the visible shape is a frame REGION, so the middle is
  not part of the window). Born for simple_ocr_capture's region
  outlines. Assault grows to 10/10 (real frame shown, reshown,
  hidden, offscreen).

### Changed
- Overlay events renumbered 31..35 (were 12..16): the old numbers
  collided with the main window's triple/move/leave/wheel/resize
  types the moment one pump served both windows - the OCR capture
  rebuild found it on day one.

## 1.2.0 — 2026-08-23

### Added
- VK_PRIOR / VK_NEXT (PgUp/PgDn) cross the C keydown filter - the
  toolkit's lists and grids stride by pages now.

## 1.1.0 — 2026-08-23

### Added
- Cursor shaping: `SHELL_WINDOW.set_cursor_kind` (arrow, I-beam, hand,
  size-we, size-ns, cross, wait) applied through the native
  WM_SETCURSOR path - zero cost until the pointer moves. Constants on
  the class; contract-guarded. Assault grows to 9/9.

## 1.0.0 — 2026-08-23

### Added (the carve)
- **SHELL_WINDOW** (deferred): native window + queue-polled message pump
  carved out of simple_widgets' SW_WINDOW. Events queue in C, drain in
  one loop, land in the deferred `dispatch` — never `$`-callbacks (the
  EIF_THREADS SEGV law). Plus: DC access, theme backdrop brush,
  drag-drop path decoding (surrogate-paired), private font loading,
  native text context menu, GetTickCount clock, shift state.
- **SHELL_KEYS**: physical Shift / Ctrl / Alt queries.
- **SHELL_CLIPBOARD**: CF_UNICODETEXT get/set with retry against
  clipboard-history managers; 2 MB (1M character) paste headroom.
- **SHELL_SPELLER**: ISpellChecker COM — misspelling ranges and
  suggestions; absent language support degrades to zero findings.
- **SHELL_DESKTOP**: virtual-screen metrics; `grab_into` — BitBlt any
  desktop region into a caller-supplied ARGB32 buffer with alpha forced
  opaque (the pure-route EV_SCREEN.sub_pixmap); `now_ms`
  (QueryPerformanceCounter); `minutes_of_day`; `open_externally`
  (ShellExecute). The grab, clock and shell-open faces are NEW — the C
  existed dormant in simple_widgets with no Eiffel caller.
- **SHELL_OVERLAY** / **SHELL_STRIP**: the frozen-desktop drag overlay
  and the topmost tool-window strip, with device-context access; their
  events ride the shared queue (12–16, 21–23).
- Contract assault, 8/8: real desktop grab (alpha checked), real
  clipboard round-trip (astral-safe path), real strip window created
  offscreen, spell checker consulted, missing font refused.

### Lineage
Header born as `ocr_cairo_win.h` in simple_ocr_capture; matured inside
simple_widgets 1.0–1.7; carved here so the platform is reusable without
the toolkit. simple_widgets 1.8 is its first descendant.
