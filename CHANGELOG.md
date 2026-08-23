# Changelog

All notable changes to simple_shell.

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
