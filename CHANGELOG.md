# Changelog

All notable changes to simple_shell.

## 1.8.0 - 2026-08-28

### Added
- SHELL_INPUT: synthesised input via SendInput, returned home from
  OCR_CLICKER in simple_ocr_capture. `click_at` leaves focus where the
  click landed (the paste case); `click_at_quietly` restores pointer and
  foreground (the page-turn case); `press_chord` / `paste` /
  `press_enter`; Unicode `type_text` with no clipboard involved. Every
  click is guarded by `is_on_desktop`; `pointer_x` / `pointer_y` read
  the pointer for calibration; and `last_accepted` reports what
  Windows actually took, so a UIPI-blocked injection is distinguishable
  from an ignored one. Acceptance is a status (`was_accepted`,
  `last_os_error`), not a postcondition: a locked screen must not
  become an exception, the same stance as `grab_into`.
- SHELL_CLIPBOARD.set_image: a bitmap (CF_DIB) from an ARGB32 top-down
  buffer - the layout `grab_into` delivers and cairo surfaces expose -
  with `has_image`, `image_width`, `image_height` read-back. Alpha forced
  opaque, bottom-up on the wire as the clipboard convention expects.
  Verified from an independent consumer: .NET's Clipboard.GetImage reads
  the 4x3 test bitmap back as Format32bppRgb with alpha 255.
  Assault 14/16 from a non-interactive session - `desktop_grab` and
  `input_keys_are_accepted` both need the interactive desktop and were
  refused (BitBlt false, SendInput OS error 5); run at the console to
  confirm 16/16.

## 1.7.0 - 2026-08-26

### Added
- Overlay adjust-mode keys: the overlay wndproc reports Enter as
  event 36 (accept) and the four arrows as 37 (vk in the first
  payload) - the region picker's micro-adjustment vocabulary.
  Escape keeps its 34 with the C-level self-dismissal.

## 1.6.0 - 2026-08-25

### Fixed
- THE 1.8.0 LOCKUP: every mutable global in simple_shell.h was a
  file-scope static in a header included by the inline externals of
  FIVE classes - and finalized C compiles each class into its own
  translation unit, so each generated file held a PRIVATE copy of
  every static. The overlay's wndproc pushed its events (mouse,
  Escape, right-click) into SHELL_OVERLAY's copy of the queue while
  the pump drained SHELL_WINDOW's: nothing ever arrived, and the
  fullscreen topmost picker ate every input in the session with
  nothing alive to dismiss it. All mutable state is now SHELL_SHARED
  (`__declspec(selectany)`, the INITGUID pattern) - linker-merged to
  ONE process-wide instance however many generated files include the
  header. The same fork silently killed strip input (21..23 went to
  a third orphaned queue) and left the clipboard opening against a
  null copy of the window handle; both healed by the same merge.
  Cross-unit regression test: a marker pushed from one class's
  translation unit must drain through another's - it cannot pass on
  the 1.8.0 arrangement. Assault 13/13.

### Added
- Overlay escape hatches BELOW the Eiffel loop: the wndproc hides
  the overlay itself on Escape, right-click and Alt+F4 (then still
  reports 34), and a dead-man watchdog thread reads the PHYSICAL
  Escape key via GetAsyncKeyState (no focus, no queue needed) -
  held ~2s posts the normal cancel through the GUI thread; still
  visible at ~5s exits the process, because only process death is
  guaranteed to free the screen. A desktop-covering window must
  never depend on a live event loop for its own dismissal.

## 1.5.0 - 2026-08-23

### Added
- SHELL_SPELLER teaching: ignore (session-scoped) and
  add_to_dictionary (persists to the user WINDOWS dictionary, the
  same one Edge and Office honour). Ignore assaulted live on a
  nonsense word; Add deliberately untested (it writes the real
  dictionary). 12/12.

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
