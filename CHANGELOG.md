# Changelog

All notable changes to simple_shell.

## 1.27.0 - 2026-10-26

### Added

- `SHELL_DESKTOP.work_area_x`, `work_area_y`, `work_area_width`, `work_area_height`: the primary monitor's work area (`SPI_GETWORKAREA`), where a main window should open; `SW_SCREEN` has them by inheritance. First user: simple_bible opens at most of the screen.

## 1.26.0 - 2026-10-26

### Changed

- Alt+Left and Alt+Right reach the window (the Alt door claims them): the Back and Forward keys of every browser, which simple_bible's guide puts on its C3 buttons. Before, they went to DefWindowProc and nothing happened. Alt+Up, Alt+Down and the other system keys stay unclaimed.

## 1.25.0 - 2026-10-26

### Added

- `SHELL_WINDOW.set_caption`: change the main window's caption while it is up (`SetWindowTextW`), as `SHELL_PANEL.set_title` already did for framed panels. First user: simple_bible, whose title names the chapter and version it reads (the GUI guide's C1).

## 1.24.1 - 2026-10-25

### Fixed (design scan 20, since 1260e13; report in simple_widgets)

- `SHELL_PRINTER`'s one document per process was modelled per instance:
  any instance could end or abort another's document. Now
  `owns_document` says whether the open document is this printer's, and
  pages, `dc`, `end_document` and `abort_document` require it. The C side
  claims the document with an interlocked flag (released on end, abort or
  a failed begin), so two processors cannot both begin one, and
  `begin_document` no longer has a check-then-call `not_printing`
  precondition - it answers False when another document is open. Test
  `scan20_a_printer_owns_only_its_own_document` failed on the old code
  (the second printer could not even ask) and passes now. 56 pass.

## 1.24.0 - 2026-10-25

### Added (GW-20: printing)

- **`SHELL_PRINTER`** (header `Clib/simple_shell_print.h`, links
  winspool): `printer_names`, `default_printer`, `has_printer`; one
  document at a time per process - `begin_document (printer, title, output,
  paper, landscape)` with the paper (`Paper_letter`, `Paper_a4`, ...) and
  orientation set in the printer's own settings, `begin_page`, `end_page`,
  `end_document`, `abort_document`, `dc`; the page in device dots
  (`dots_per_inch_x/y`, `paper_width/height`, `printable_width/height`,
  `unprintable_left/top`). An output file makes a file printer (Microsoft
  Print to PDF) write there without asking. No print dialog: the
  application lists the printers itself, so the path runs headless.
- Test `gw20_printers_and_a_document_written_to_a_file`: on this machine a
  Letter page went through Microsoft Print to PDF to a temporary file (the
  PDF arrived), and a landscape document turned the sheet. 55 pass.

## 1.23.1 - 2026-10-25

### Fixed (design scan 19, since b8d50ce; report in simple_widgets)

- A panel destroyed behind its back - framed panels go with their owner,
  Windows destroying owned windows first - kept its dead handle in the
  slot table and `is_open` kept answering True; a later `close` could hit
  a reused handle. The panel procedure now forgets its slot on
  WM_NCDESTROY, and `SHELL_PANEL` remembers the window it opened, so
  `is_open` asks the window itself and never mistakes another panel in
  the same slot for this one. Test door `simulate_destroyed_behind`; test
  `scan19_a_panel_destroyed_behind_its_back_is_closed` failed on the old
  code ("closed when its window is gone") and passes now. 54 pass.

## 1.23.0 - 2026-10-25

### Added (GW-22: framed panels, the floating windows of a study layout)

- `SHELL_PANEL.open_framed (x, y, width, height, title)`: a panel with a
  caption and a sizing border that takes the focus when clicked, owned by
  the main window (above it, minimized with it, no taskbar button) and never
  topmost - a pane torn off onto a second monitor. `is_framed`, `title`,
  `set_title`, `client_width`, `client_height`, `is_topmost`.
- New events (in `SHELL_EVENTS`; `SHELL_PANEL` names them short): 60 key
  (through the main window's own key filter, Alt door included), 61 char,
  62 close request (Alt+F4 or the close box; the window stays until
  `close`), 63 activated (1 or 0), 64 double click, 65 leave. A framed
  panel's 48 carries the client size on every WM_SIZE, live while sizing;
  47 still arrives when a move ends.
- Messages of window creation read slot 0 before the slot is stored; every
  framed branch checks `s_shell_panel[slot] == h` first, so another panel in
  slot 0 is never told about them.
- Test door `simulate_message` (the panel's real window procedure). Test
  `gw22_framed_panel_is_a_floating_window`, with a plain panel beside it
  keeping its old behaviour (topmost, never activated, no characters).
  53 pass.
- Open: a framed panel shows the arrow cursor only (no per-panel cursor
  kind yet).

## 1.22.2 - 2026-10-25

### Changed (one registry of event numbers)

- New deferred **`SHELL_EVENTS`**: every number the native queue carries,
  named, in one place (window 2-18 and 25, strip 21-23, overlay 31-37,
  panels 41-50, hot key 51, tray 52, appearance 53, wake 54, dwell 55,
  contrast 56, motion 57, focus request 58, refresh request 59), with
  `registry` and `next_free_event`. The numbers had lived in seven
  classes, 53 to 57 twice. SHELL_WINDOW, SHELL_PANEL, SHELL_TRAY,
  SHELL_HOTKEYS, SHELL_APPEARANCE, SHELL_WAKE and SHELL_ACCESSIBILITY
  inherit it; SHELL_PANEL, SHELL_TRAY and SHELL_APPEARANCE keep their
  short names by renaming (`{SHELL_PANEL}.Event_press`,
  `{SHELL_TRAY}.Event_click`, `{SHELL_APPEARANCE}.Event_changed`), so no
  client changes. A new event takes `next_free_event` and joins
  `registry` before it goes into the header.
- Test `event_numbers_never_collide`. 52 pass; simple_widgets rebuilt
  clean against it, 537 pass.

## 1.22.1 - 2026-10-25

### Fixed (the design scan since 7443e02)
Each with a test that failed with the old behaviour:
- **A client's focus request reaches the queue on the pump thread.** UI
  Automation calls SetFocus on its own thread, and the provider pushed
  event 58 straight onto the unsynchronized queue. It now posts a private
  window message; the window procedure pushes the event
  (`scan13_focus_request_is_pushed_on_the_pump_thread`).
- **Destroying the window stops serving.** The table, the hook and the
  window handle outlived the window; WM_DESTROY now tells the bridge
  through a second hook (`scan13_destroying_the_window_stops_serving`).
- **A client's request asks for a republish:** event 59
  (`Event_refresh_request`), once until the next commit
  (`scan13_a_client_request_asks_for_a_republish`).
- `simple_shell_uia.h` includes simple_shell.h first: it used SHELL_SHARED
  before including the header that defines it, which compiled here only
  because another class came first (simple_widgets failed with C2061).
- New: `served_window`, `Role_window`. Not done: one table per process,
  no property-changed or structure-changed events, only a read-only Value
  pattern. Report: `.eiffel-workflow/evidence/design-scan-since-7443e02.md`.
  51 pass.

## 1.22.0 - 2026-10-25

### Added
- **The UI Automation bridge (GW-14, for simple_bible).** A drawn toolkit
  has no child windows for a screen reader to find, so `SHELL_ACCESSIBILITY`
  lets the application publish its widget tree as a table - id, parent,
  control type (`Role_` constants, UI Automation's control type ids), name,
  value, bounds, focusable, enabled - with `begin_tree`, `add_node` and
  `commit`, and tell the focus with `focus_changed`. The new header
  `Clib/simple_shell_uia.h` serves it: per-node providers for
  IRawElementProviderSimple, Fragment, FragmentRoot (node 0) and a
  read-only IValueProvider, behind WM_GETOBJECT through a hook pointer in
  simple_shell.h, so no COM header enters that file. The table is read
  under a lock and swapped in whole, because UI Automation calls from its
  own threads. A client's SetFocus arrives as event 58
  (`Event_focus_request`) with the node id. `clients_listening`,
  `served_focus` and readers of the served table (`served_name`,
  `served_role`, `served_parent`, `served_value`, `served_row_of`).
- UIAutomationCore.h defines `UIA_ScrollPatternNoScroll` at file scope, which
  C links twice when two translation units include it; the header renames
  it into a selectany definition.
- Test: `uia_bridge_serves_the_published_tree` - a real UI Automation
  client on a worker thread (testing/Clib/shell_uia_client.h) reads back the
  tree published for a hidden probe window on the shipped window
  procedure: names, control types, a value, a nested node and the focus;
  disabled, nothing. 48 pass.

## 1.21.0 - 2026-10-25

### Added
- **Reduced motion (GW-14, for simple_bible).**
  `SHELL_APPEARANCE.system_reduces_motion`: has the user turned Windows'
  animation effects off (Settings > Accessibility > Visual effects;
  SPI_GETCLIENTAREAANIMATION, False where it cannot be read)? Event 57
  (`Event_motion_changed`, also on SHELL_WINDOW) with 1 for reduced, pushed
  when WM_SETTINGCHANGE names SPI_SETCLIENTAREAANIMATION. Test door
  `report_motion_change`.
- Tests: `motion_change_is_queued`, `reduced_motion_reads_the_windows_setting`
  (against PowerShell's own SystemParametersInfo call). 47 pass at an
  interactive console.

## 1.20.1 - 2026-10-25

### Changed
- Documentation only, from the design scan since a8de272 (no HIGH
  findings): the dispatch comment lists events 55 and 56, and
  `Event_contrast_changed` says to read event 56 as "look again" (one flip
  can arrive twice, and a light/dark flip arrives with 0). The scan's
  shared event-number ancestor (`SHELL_EVENTS`) waits for Larry's word.
  Report: `.eiffel-workflow/evidence/design-scan-since-a8de272.md`.

## 1.20.0 - 2026-10-25

### Added
- **Windows high contrast (GW-16, for simple_bible).**
  - `SHELL_APPEARANCE.system_high_contrast`: is a Windows contrast theme
    on (SystemParametersInfo, `HCF_HIGHCONTRASTON`)?
  - `system_color (index)`: a system color as 0xRRGGBB, with the indexes
    a contrast theme paints with (`Color_window`, `Color_window_text`,
    `Color_highlight`, `Color_highlight_text`, `Color_button_face`,
    `Color_gray_text`, `Color_button_text`, `Color_hotlight`).
  - Event 56 (`Event_contrast_changed`, also on SHELL_WINDOW) with 1 for on
    or 0 for off, pushed when WM_SETTINGCHANGE names
    `SPI_SETHIGHCONTRAST` and on WM_SYSCOLORCHANGE (the contrast palette
    changed).
  - Test doors `report_contrast_change` and `report_system_colors_change`.
    A client tested without touching Windows inherits SHELL_APPEARANCE and
    redefines the three queries (simple_widgets does).
- Tests: `high_contrast_reads_the_windows_setting` and
  `system_colors_read_the_windows_palette` (each against reg.exe's own
  reading of the registry), `contrast_change_is_queued`. 42 of 45 pass in
  a locked session; `desktop_grab`, `input_keys_are_accepted` and
  `panel_capture_exclusion_really_hides` need the interactive desktop.

## 1.19.0 - 2026-10-23

### Added
- **A one-shot dwell timer (GW-08, for simple_bible).** It lets a word's
  hover card open 400 milliseconds after the pointer rests, instead of
  waiting for the next 250-millisecond heartbeat.
  - `SHELL_WINDOW.arm_dwell_timer (ms)` fires event 55 (`Event_dwell`)
    once. Re-arming replaces the pending shot, so a caller that arms on
    every pointer move hears one event, after the pointer rests.
  - `cancel_dwell_timer` and `is_dwell_timer_armed`.
  - It is a thread timer, so it needs no main window, and the
    windowless pump delivers it.

## 1.18.0 - 2026-10-23

### Added
- **A worker wakes the pump at once (GW-26, for simple_bible).** Search
  streaming and job completion show as soon as they happen, not at the
  next heartbeat.
  - `SHELL_WAKE.wake`, from any processor, puts event 54 (`Event_wake`)
    on the GUI's queue.
  - The wake goes to the main window when one is open; window messages
    survive the modal loops of a window drag or resize. Otherwise it goes
    to a thread claimed with `claim_pump_thread`.
  - Wakes coalesce while one is pending. The heartbeat clears a stuck
    flag, so a lost message costs at most one tick.
  - `last_outcome` reports posted, coalesced, or nobody to wake.
- **A settable heartbeat:** `SHELL_WINDOW.set_heartbeat_ms` and
  `heartbeat_ms`. The default is still 250 milliseconds.
- Tests (41 pass; SCOOP target 5 pass; 0 warnings):
  - with no pump, nobody is woken;
  - posted, then coalesced twice, then exactly one event 54 out of a pump,
    then posted again;
  - the heartbeat is settable;
  - SCOOP: a worker processor sleeps 200 milliseconds and wakes the root's
    windowless pump. Event 54 arrived 16 milliseconds after the post, most
    of it the test's own `pump_for` sleep granularity; the budget is 50.

## 1.17.0 - 2026-10-23

### Added
- **Function keys and Ctrl+digit reach the window (GW-24, for simple_bible).**
  - A plain WM_KEYDOWN now becomes event 4 for F1-F12, under any modifier.
  - With Ctrl held and Alt not held, digits (row and numpad) and the OEM
    punctuation keys also become event 4. None of these make a WM_CHAR the
    window could hear, and Ctrl+[ would otherwise arrive as 27, which reads
    as Escape.
  - Ctrl+Alt (AltGr on European layouts) still types its character.
  - Letters stay with WM_CHAR (Ctrl+letter is the control code 1..26), so
    nothing is delivered twice.
  - The policy is one pure predicate, `shell_keydown_is_ours (vk, ctrl, alt)`,
    which the window procedure consults with the live modifier state.
- Tests (39 pass, 0 fail, 0 warnings):
  - F1-F12 bare and with Ctrl; F13 not.
  - Ctrl+0..9, Ctrl+numpad and Ctrl+[ ] ; / ' , are claimed. Bare digits,
    AltGr+digit and Ctrl+A are not, and the stepping keys are unchanged.
  - WM_KEYDOWN(F5) handed to the window procedure comes out of the queue.

## 1.16.0 - 2026-10-22

### Added
- **Follow the Windows light/dark setting (GW-27, for simple_bible).**
  - `SHELL_APPEARANCE.system_prefers_dark` reads `AppsUseLightTheme`. The
    value 0 means dark; a missing or unreadable value means light, as in
    Windows.
  - When the setting flips, the main window's queue receives event 53
    (`Event_appearance_changed`): first field 1 for dark, 0 for light. It
    comes from WM_SETTINGCHANGE naming "ImmersiveColorSet".
  - `SHELL_WINDOW.set_dark_title_bar` and `SHELL_APPEARANCE.set_dark_title_bar`
    ask DWM to draw the caption dark or light, so it matches the content.
    They use attribute 20, or 19 on builds 1809-1909. The window remembers
    the choice before it opens.
  - dwmapi is loaded at run time and the registry is read with
    RegOpenKeyExW/RegQueryValueExW, both available at the Windows 2000
    target that ISE's C compiles for.
- The test runner prints the failing assertion's tag and description.
- Tests (37 pass, 0 fail, 0 warnings; SCOOP target 4/0):
  - the reading agrees with reg.exe's;
  - "ImmersiveColorSet" in any case queues 53 with the setting, and other
    areas queue nothing;
  - DWM accepts dark and light captions on a real hidden offscreen window.

## 1.15.0 - 2026-10-11

### Added
- **The bottom edge sizes on a plain press**: `SHELL_PANEL.set_bottom_sizes_on_press`
  lets a plain press within the grip of a panel's bottom edge size it downward, its top
  staying put (the native HTBOTTOM resize). simple_prompter's pill grows taller from
  under the webcam.

## 1.14.0 - 2026-10-10

### Added
- **A panel can be a handle**: `SHELL_PANEL.set_drags_on_press` lets a plain press
  drag it (no Shift), and `set_drag_axis` keeps any move to one axis
  (`Axis_horizontal`: it slides left and right only; enforced in WM_MOVING).
  simple_prompter's slide handle under the pill.
- **`Event_moving` (49)**: a panel reports its left and top while it moves
  (coalesced), so what is attached to it can follow live; 47 and 48 still come
  when the move ends.
- **`set_sides_size_on_press`**: a plain press within the grip of the left or
  right edge sizes a resizable panel, with the sizing cursor shown there.
  Shift keeps its meaning (move, or size from any edge or corner).
- **`press_grip_at (x, y, shift)`**: what a press would do (`Grip_none` for a
  click), and **`axis_result (dx, dy)`**: where a move would land after the
  axis - both for tests without a mouse.
- **Files dropped on a panel**: `SHELL_PANEL.set_accepts_files` turns them into
  `Event_dropped` (50, the drop point, the slot in the fourth field); the paths
  wait in `SHELL_WINDOW.take_dropped_paths`, the same buffer the window's own
  drops (18) use. `simulate_drop` builds a real WM_DROPFILES for tests.
- **Tray clicks and menu**: a click on a `SHELL_TRAY` icon arrives as
  `Event_click` (52: `Click_left`, `Click_right` or `Click_double`, the icon's
  `id` in the fourth field), and `choose` opens a popup menu at the pointer.
  The icon is the program's own (resource 1) when it has one. The anchor window
  is now a hidden tool window, not message-only: a menu needs a window that can
  come to the foreground. `simulate_click` for tests.
- **A window that starts hidden**: `SHELL_WINDOW.set_starts_hidden` before
  `shell_run`; it still pumps timers, panels, hotkeys and the tray.
  `show_window`, `hide_window`, `is_window_shown`. 34 tests.

## 1.13.1 - 2026-10-10

### Fixed
- **A `SHELL_WINDOW` shows its program's icon** in the title bar, the taskbar
  and Alt+Tab. The window class registered no icon, so Windows drew its
  generic one even when the exe carried an icon. It now loads resource 1 of
  the exe, the way WEL's `class_icon` does: put `1 ICON "app.ico"` in the
  system's .rc (`<system>.rc` beside the ECF, compiled into the exe by the
  build). A program without one looks as before.

## 1.13.0 - 2026-10-09

### Added
- **`SHELL_PANEL.is_cursor_over`**: is the mouse pointer over the panel now?
  False while closed or hidden; click-through does not change the answer. A
  panel gets no "mouse left" event, so an app that shows controls on hover
  polls this from its timer (simple_prompter's transport bar). The C reads the
  window from `handle`, not from the header's panel table.

## 1.12.1 - 2026-10-08

### Fixed
- **`SHELL_CLIPBOARD.image_width` and `image_height` retry like every other
  clipboard read.** Both read the bitmap header through `OpenClipboard` once,
  and a clipboard history manager opens the clipboard to copy each new bitmap
  the moment it arrives. That is exactly when a caller who has just put one, or
  is pasting one, asks its size. Probed right after `set_image`, `image_width`
  answered 0 while `has_image` was True on 4 of 8 runs. simple_chat's
  paste-a-picture test failed 7 of 15 isolated runs, because its PNG path sizes
  its buffer from these two. Both now go through one `image_size_read`: up to
  five retries, 10 ms apart, while a bitmap is still advertised, the same
  discipline as `image_into`, `text` and the setters. The other clipboard calls
  were checked: `text`, `image_into`, `set_text` and `set_image` already
  retried, and `has_text` / `has_image` use `IsClipboardFormatAvailable`, which
  never opens the clipboard.
- New test `clipboard_image_survives_repeated_round_trips`: 200 set-then-read
  cycles, with the size changing every cycle so a stale bitmap cannot pass.
  Without the fix it reported 2 of 200 damaged and failed. With it, 0 of 200 on
  each of 5 runs (suite 30 to 31, all passing).

## 1.12.0 - 2026-10-06

### Added
- **`SHELL_PANEL` resizing by Shift+drag on an edge or corner.** `set_resizable
  (grip, min_width, min_height)` (requires `is_draggable`) turns a Shift+press
  within `grip` pixels of an edge or corner into a native resize: the same
  `WM_NCLBUTTONDOWN` route a move takes, with that edge's hit code. Elsewhere
  Shift+drag still moves. While Shift is held the sizing cursor shows over the
  grips; `WM_GETMINMAXINFO` holds the minimum. `grip_at` answers what a press
  at a point would do (`Grip_move`, `Grip_left` .. `Grip_bottom_right`), so
  the geometry is testable without a mouse. Event 48 (resized: width, height)
  follows event 47 when a drag ends; `sync_geometry` reads the window's real
  rectangle back into `x`, `y`, `width`, `height`. `is_shift_held` reads the
  physical key, as does the press itself (`MK_SHIFT`): a panel never has the
  keyboard focus, so the thread's own key state can be stale. Found from
  simple_prompter, whose reader wants to size the pill where it sits.

## 1.11.0 - 2026-10-06

### Added
- **`SHELL_PANEL`: an on-screen instrument that stays out of the way.** A
  borderless topmost panel (up to 8 per process) that never takes focus when
  clicked and has no taskbar button - the shape of a teleprompter pill under a
  webcam. `request_capture_exclusion` leaves it out of screen captures
  (`SetWindowDisplayAffinity` with `WDA_EXCLUDEFROMCAPTURE`; Windows before 10
  2004 can only black it out, and `capture_affinity` says which was granted).
  The function is looked up at run time: ISE's generated C targets Windows
  2000, where it is not declared. Panels are layered from birth, so
  `set_opacity` is one call and `set_click_through` works at any time;
  `set_draggable` allows Shift+drag moves. Events 41-47 carry the slot in the
  fourth field. Found from simple_prompter, whose pill must not appear in the
  recording or the meeting it is helping with.
- **`SHELL_HOTKEYS`: global hotkeys.** `RegisterHotKey` bound to the pumping
  thread (no window needed, so they work while every window is hidden); both
  pumps turn the thread's `WM_HOTKEY` into event 51 [id, vk, modifiers]. A held
  chord fires once (`MOD_NOREPEAT`). `register` requires a modifier: a bare key
  is taken from every application on the desktop, so that has its own name,
  `register_bare`, for the deliberate case (a presentation clicker while
  recording). A chord another application holds is refused and reported
  (`last_succeeded`), never silently lost.
- **`SHELL_DESKTOP.become_dpi_aware`, `system_dpi`, `dpi_scale`: the display
  scale.** An app that builds fonts and layouts before its window exists (so
  before `shell_create_window` makes the process DPI aware) can become aware
  first and read the real DPI - 144 on a 150% display, where an unaware process
  sees 96 and draws everything a third too small on a 4K screen.
- **`SHELL_FILE_DIALOG`: the Windows Open dialog.** `choose_file (title,
  filter, initial_dir)` (filter pairs separated by '|') and `chosen_path`,
  empty when cancelled. Modal, owned by the main window, and marked blocking so
  SCOOP processors keep running while it waits for the user.
- **`SHELL_MONITORS`: the displays.** Bounds, work area, primary flag and device
  name per monitor (`EnumDisplayMonitors`), plus `index_at` and `primary_index`.
### Fixed
- `SHELL_DESKTOP.pump_for` measured its deadline with GetTickCount, which moves
  in ~16 ms steps, so a 60 ms pump could return after ~45 ms (seen once as a
  failure of `windowless_pump_returns_on_deadline`). The deadline now uses the
  performance counter.

### Tests
- Panel lifecycle; capture exclusion proved through a real screen grab
  (the BitBlt + CAPTUREBLT path recorders and meeting apps use: 256 red pixels
  before, 0 after, affinity 0x11); hotkey registration and delivery as event 51;
  hotkey conflict reported; monitor enumeration; display scale; file dialog. 29/29, SCOOP target 4/4.

## 1.10.0 - 2026-09-05

### Added
- **`SHELL_CLIPBOARD.image_into (a_bits, a_width, a_height, a_stride)`: the
  clipboard bitmap can be READ, not only put.** `set_image` has written a
  CF_DIB from an ARGB32 buffer since 1.8; `image_width` / `image_height`
  read the header back; but no caller could get at the pixels, so a picture
  on the clipboard was a thing this library could describe and not deliver.
  `image_into` copies the DIB into the caller's ARGB32 top-down buffer -
  the mirror of `set_image`, and the layout a cairo ARGB32 surface exposes
  through `data` - so a pasted screenshot goes straight into a surface and
  out as a PNG. 24- and 32-bit DIBs (BI_RGB, or BI_BITFIELDS in Windows'
  own BGRA order) are read; anything else answers False, as does a bitmap
  whose size is not what the caller sized its buffer on - a refusal, never
  an overrun, checked against `GlobalSize` too. Alpha is forced opaque on
  the way out, as `set_image` forces it on the way in: a screenshot's DIB
  carries 0 in that channel, and the honest reading is always "a picture".
  Found from simple_chat: pasting an image into the composer had nothing to
  read the clipboard with.
- `shell_clip_get_image` in `simple_shell.h`, beside `shell_clip_set_image`.
- `test_clipboard_image_roundtrip` now reads the pixels back: coded by
  position, so a row in the wrong order is caught; alpha proved forced; a
  wrong-size claim proved refused.

## 1.9.3 - 2026-09-03

### Fixed
- **THE ALT DOOR: Alt+letter now reaches the window.**
  Windows routes a key pressed while Alt is held to `WM_SYSKEYDOWN`, not
  `WM_KEYDOWN`, and hands the letter behind it to `WM_SYSCHAR`. This header
  answered `WM_SYSKEYDOWN` for the OEM/numpad plus-minus pair alone and let
  every other syskey fall through to `DefWindowProc`; it swallowed
  `WM_SYSCHAR` for those same four keys alone.

  The consequence was narrow and total. `SHELL_KEYS.alt_down` reported the
  Alt modifier perfectly - it reads `GetKeyState(VK_MENU)` the way
  `shift_down` reads `VK_SHIFT` - so an application could register an Alt
  accelerator and the modifier would match. But **Alt+F never arrived. It
  opened the system menu.** A menu mnemonic - Alt+F for `&File`, the oldest
  gesture on the platform - could not be built on this shell at any layer
  above it.

  `simple_widgets` found the hole on 2026-09-02 and named it *the Alt gap*
  in `SW_WINDOW`'s class note and its README rather than hiding it:
  `activate_mnemonic` was implemented, contracted and tested, and nothing
  could call it. The missing half was here, in eleven lines of C.

  **NOW CLAIMED by the window**, pushed as the ordinary key-down event
  (type 4, virtual key in field a) that the arrows have always used:

  | claimed | why |
  |---|---|
  | Alt + `A`..`Z` | menu mnemonics - the gesture that was impossible |
  | Alt + `0`..`9` | numbered picks |
  | Alt + OEM/numpad plus and minus | as since 1.8 - unchanged |
  | `F10` | Windows sends it as `WM_SYSKEYDOWN` with no Alt at all, being the documented menu key |

  The `WM_SYSCHAR` behind each is swallowed - letters in both cases, since
  Alt+Shift+F arrives as `F` - or `DefWindowProc` would open the system menu
  on the matching mnemonic behind the application's back or, finding none,
  beep on every keystroke.

  **LEFT TO `DefWindowProc`, deliberately.** This half is the one a careless
  widening would break, and it is asserted on by its own test:

  | left alone | why |
  |---|---|
  | Alt+F4 (`VK_F4`) | closes the window. It must keep closing it. |
  | Alt+Space (`VK_SPACE`) | the system menu - and its `WM_SYSCHAR` is a space, which the swallow list does not claim, so the menu still opens |
  | Alt+Enter (`VK_RETURN`) | the properties / fullscreen convention |
  | Alt+Tab, Alt+Shift+Tab, Alt+Esc | the shell eats these; they never reach any window procedure |
  | Alt alone (`VK_MENU`) and its key-up | the menu-key contract. Nothing needs the keystroke: `alt_down` already answers the state, and a window with no menu bar has no underlines to reveal - Larry asked for "Alt / Alt+F, no mnemonic underlines" |
  | Alt+F1..F9, F11, F12 | unclaimed; F10 is the one menu key |
  | Alt+arrow / Home / End / Page / Delete | unclaimed; the unmodified forms arrive on the `WM_KEYDOWN` door as they always have |

  **Nothing was renumbered and no signature moved.** Event 4 is the same
  event 4, with the same three-integer `dispatch`; a consumer reads the key
  through the door it already reads arrows through and asks `alt_down` for
  the modifier. That is why `simple_widgets` needed no change to receive
  this: its `dispatch_plain` already tries the accelerator table on event 4
  by virtual key, and `SW_TEXT_BOX.handle_key` already ends its `inspect`
  with an empty `else`, so an unclaimed Alt+letter reaching a focused text
  box does nothing.

### Added
- **The policy is two pure predicates**, `shell_syskey_is_ours` and
  `shell_syschar_is_ours`, and the window procedure does nothing but consult
  them. That is not decoration: a real Alt+F needs a visible window holding
  the focus and a synthesised keystroke on the tester's own desktop, and this
  library will not take a machine away from the person sitting at it. Naming
  the policy makes it assertable with no window, no desktop and no keystroke.
- `SHELL_SYSKEY_PROBE` (testing/): both predicates, plus `deliver_syskeydown`,
  which hands `WM_SYSKEYDOWN(a_vk)` to the window procedure itself from its
  own translation unit with a null `HWND` - safe because the claimed branch
  never touches the handle, and restricted to claimed keys BY CONTRACT
  (`require claimed`), because an unclaimed one would fall through to
  `DefWindowProcW` and DefWindowProc without a window is not something this
  library will ask for.
- `SHELL_TEST_WINDOW.drain_key`, the general form of `drain_marker`: drains
  the shared queue through `SHELL_WINDOW`'s own external and answers whether
  a key-down carrying a given virtual key came out.
- Three tests (17 -> 20 passing, the same 2 documented headless refusals):
  `alt_keys_are_claimed`, `system_alt_keys_are_left_alone`,
  `alt_letter_reaches_the_queue`.

### Tested by inspection only, said plainly
- **That Windows delivers Alt+F to the window procedure as `WM_SYSKEYDOWN`
  at all.** That is the operating system's documented contract, not this
  library's behaviour, and reaching it needs a visible window with the focus
  and a synthetic keystroke on a live desktop. Everything on this side of
  that line - which keys the procedure claims, which it refuses, which
  `WM_SYSCHAR` it eats, and that a claimed key comes back out of the pump's
  own drain as event 4 across translation units - is asserted.

### Changed
- The SDK macro-namespace tripwire (1.9.1) grew to cover the identifiers
  this version declares: `shell_syskey_is_ours`, `shell_syschar_is_ours`,
  `l_vk`, `l_ch`.

## 1.9.2 - 2026-09-02

### Fixed
- **Every external in this library that WAITS is now marked `blocking`.**
  A platform shell is, almost by definition, a stack of waits: `GetMessageW`
  until the desktop has a message, `TrackPopupMenu` until the user picks,
  `Sleep(5)` around a windowless pump for the caller's whole span. All of
  them were declared plain `external "C inline use "simple_shell.h""`.

  ISE's garbage collector stops every thread of the system before it
  collects, and a thread inside an unmarked external is one the runtime can
  neither see nor stop: the collection WAITS for that call to return, and
  every other processor waits with it, at its very next allocation. The
  library that owns the message pump was therefore the library best placed
  to stop the whole program.

  The class was proved in simple_winhttp on 2026-09-02 (0.1.1) - Larry's
  simple_chat window froze 13 times for 211 seconds in one 20-minute
  session, and the stall was in the ROOT PROCESSOR'S ALLOCATOR, not in any
  wiring. simple_shell was audited for the same shape immediately after and
  had nine instances of it.

  MARKED, with the safety check that permits each:

  | external | the wait | why marking is safe |
  |---|---|---|
  | `SHELL_WINDOW.shell_pump` | `GetMessageW` - until Windows has a message | the `MSG` is a C local; the window proc writes only C memory |
  | `SHELL_WINDOW.shell_text_menu_ext` | `TrackPopupMenu` - until the user picks | four integers in, one out; every menu string is a C literal |
  | `SHELL_DESKTOP.pump_for` | a `Sleep(5)` loop for the caller's whole span | one integer in, nothing out; `MSG` is a C local |
  | `SHELL_DESKTOP.c_shell_open` | `ShellExecuteW` - a cold association wakes a COM server | CHECKED: the sole caller passes `NATIVE_STRING.item`, a `MANAGED_POINTER` on the C heap |
  | `SHELL_INPUT.c_input_click` | a deliberate `Sleep(120)` before restoring focus | four integers in, one out; the `INPUT` array is a C local |
  | `SHELL_SPELLER.c_spell_check` | `CoCreateInstance` + dictionary load on first call, a COM round trip after | CHECKED: `NATIVE_STRING.item` in, `MANAGED_POINTER` out - both C heap |
  | `SHELL_SPELLER.c_spell_suggest` | same COM object | CHECKED: same two buffer kinds |
  | `SHELL_SPELLER.c_spell_ignore` | same COM object | CHECKED: `NATIVE_STRING.item` |
  | `SHELL_SPELLER.c_spell_add` | same COM object, and a dictionary file write | CHECKED: `NATIVE_STRING.item` |

  The rule the checks apply: mark only when the C code touches no
  Eiffel-collected memory while it waits. C locals, the C heap,
  `MANAGED_POINTER` and `C_STRING` are fine; the address of an Eiffel
  attribute or `SPECIAL` area is not, because the collection the marker
  permits may MOVE it. This library passes the rule everywhere by
  construction: the queue law - **C pushes events into a static C array,
  Eiffel polls; no `$`-callback ever crosses** - is what makes it SEGV-proof
  under `EIF_THREADS`, and it is the same property that makes the marker
  safe.

  LEFT UNMARKED, deliberately:
  - `SHELL_DESKTOP.c_grab` (full-screen `BitBlt`). Long CPU, not a wait, so
    there is no idle span to hand back - and the buffer is the CALLER'S. The
    only in-fleet caller (`SW_SCREEN`, through `CAIRO_SURFACE.data`) supplies
    cairo's own C heap, but the signature admits any `POINTER` and this
    library cannot prove a consumer did not hand it `$` of an Eiffel area.
    An unverifiable safety obligation is not one to export to consumers.
  - The `Sleep(100)` in `shell_watchdog_main`. That loop runs on a raw OS
    thread created with `CreateThread`, which never enters the Eiffel runtime
    at all; there is no external to mark and no collector to hold.
  - Everything else. `shell_next_event`, the clipboard calls, the metrics,
    the window services: microseconds, and `OpenClipboard` fails rather than
    waits when another process holds the clipboard.

  WHAT THE UNMARKED `GetMessageW` ACTUALLY COST THE CHAT CLIENT. `GetMessageW`
  blocks until ANY message arrives, which on a genuinely idle desktop is
  unbounded - so the audit's first question was whether anything guarantees
  one. It does: `shell_create_window` installs `SetTimer(h, 1, 250, 0)`
  unconditionally on every window it makes, and its `WM_TIMER` handler pushes
  the heartbeat event. That timer is killed only at `WM_DESTROY`, which
  immediately posts `WM_QUIT` and ends the pump anyway. simple_chat's client
  is an `SW_WINDOW` and does not arm the optional fast timer, so it lives on
  the 250 ms heartbeat.

  So the chat client was in the BOUNDED case, and this defect is NOT what
  froze its window for 8 to 25 seconds - `SIMPLE_WINHTTP.c_send` was. What
  the unmarked pump cost was a stall of up to 250 ms on **every other
  processor, at its next allocation, for every collection** - the event
  poller and the inbox among them. That is under the ~5 s at which Windows
  ghosts a window, and over fifteen frames. A consumer that closes its window
  and keeps pumping, or one on a desktop where the heartbeat is throttled,
  would have had no bound at all. The marker removes the whole question.

### Added
- `simple_shell_scoop_tests` - a SCOOP target carrying the vector test that
  would have caught this. `BLOCKING_PROBE` holds the law itself (the same
  3 s wait taken three ways: an Eiffel sleep, an unmarked C call, the same
  call marked `blocking`); `SHELL_PUMPER` drives the REAL
  `SHELL_DESKTOP.pump_for` from its own processor while the root does nothing
  but allocate. `pump_for` is the vector because it needs no window and no
  user, so the assault runs headless and unattended.

  RED (`pump_for` unmarked), two runs: worst allocation on the root
  **3,009 ms** and **3,004 ms**, for pumps of 3,008 ms and 3,002 ms. The root
  waited out the entire pump. 3 passed, 1 failed.
  GREEN (marked), four runs: **3, 3, 3 and 4 ms**, for pumps of 3,000 / 3,003
  / 2,990 / 3,003 ms. 4 passed, 0 failed. The bound is 500 ms - three orders
  of magnitude off the measured green, so nothing here is tuned to just
  barely pass. The controls, unchanged by the fix and reading the same in
  both columns: an Eiffel sleep costs the root 3-5 ms, an unmarked C sleep
  3,006-3,136 ms, the same C sleep marked `blocking` 3-6 ms.

  THE PROBE MUST RETAIN A LIVE SET, AND MUST ASK. Every allocation burst
  keeps 200 KiB of what it allocates, so the heap grows and the collector has
  real work when it runs. That alone left the instrument FLAKY: measured on
  2026-09-02, roughly one run in four the runtime answered a whole six-second
  burst train out of a free list an earlier test had left it, never
  collected, and the UNMARKED wait scored 3 ms - the freeze reported as
  absent when it was merely unexercised, on the very test whose job is to
  prove the freeze exists. Each burst therefore also ASKS, with
  `MEMORY.full_collect`, inside the timed span. That is the honest probe for
  this defect: what the marker changes is not whether a collection is wanted
  but whether a requested one can proceed while another processor is inside
  C. With the ask in place the law tests read identically across every run.

### Verified at the consumers
Nothing downstream was edited; all three were clean-built against this branch.

| consumer | before (main) | after (1.9.2) |
|---|---|---|
| `simple_shell_tests` | 17 passed, 2 failed | 17 passed, 2 failed |
| `simple_widgets_tests` | 203 passed, 1 failed | 203 passed, 1 failed |
| `simple_ocr_capture_tests` | - | 75 passed, 0 failed |
| `simple_chat` `simple_chat_client` | - | finalizes (lean + DBC) |

The failures on both sides of the change are the documented headless ones -
`desktop_grab` / `input_keys_are_accepted` here and `screen_grab_marries_cairo`
in simple_widgets - where Windows refuses `BitBlt` and `SendInput` from a
session without an interactive desktop (OS error 5). They were measured on
main and on the branch and are identical. Zero new compiler warnings; the
final proof builds were clean compiles.

## 1.9.1 - 2026-09-02

### Fixed
- **`shell_set_window_icon` declared a local named `small`, and `small` is a
  Windows SDK macro.** `rpcndr.h` does `#define small char`, and every COM
  header in the fleet reaches it - `unknwn.h`, `objbase.h`, `mmdeviceapi.h`
  (simple_audio), `dwrite.h` (simple_shaping), `sapi.h` (simple_speech). A
  finalized Eiffel build concatenates many classes into ONE translation unit,
  so a sibling library's COM header is routinely preprocessed AHEAD of
  `simple_shell.h`; `HICON big, small;` then compiled as `HICON big, char;`
  and the C phase died:

  ```
  simple_shell.h(410): error C2059: syntax error: 'type'
  simple_shell.h(414): error C2513: 'char': no variable declared before '='
  simple_shell.h(416): error C2059: syntax error: 'type'
  NMAKE : fatal error U1077: 'cl ... -c big_file_C1_c.c' : return code '0x2'
  ```

  Present since 1.7.0 (commit c1bd5b5, 2026-08-26), which added the icon
  feature. It sat unfired for a week because whether it fires depends
  entirely on which sibling library's header lands earlier in the same
  generated unit. Found on 2026-09-02 by the simple_widgets adoption
  work: `ec.sh release -target sw_demo` failed in the C phase on a clean
  main, reproducibly and independently of any other change. It **blocked
  release builds of every GUI app in the fleet** whose unit ordering put a
  COM header first - simple_chat's client among them. Consumers built in a
  luckier order (simple_ocr_capture, simple_chat's test targets, and
  simple_shell's own suite) never saw it, which is why 1.9.0 shipped green.

  Fix: the locals are `l_big` and `l_small`. No C ABI, no Eiffel external
  signature and no behaviour changed. A full sweep of the header against the
  Windows SDK's macro and typedef namespaces (250,501 `#define`s, 16,004
  typedefs, 10.0.26100.0) found `small` to be the ONLY declared identifier
  in collision - `hyper`, `byte`, `boolean`, `far`, `near`, `pascal`,
  `interface`, `min`, `max`, `IN`, `OUT` and the rest are all clear.

### Added
- **SDK-macro tripwire** so this cannot recur silently. `SDK_MACRO_TRIPWIRE`
  (testing/) has inline externals whose `use` list pulls `shell_sdk_poison.h`
  - which arms `rpcndr.h`'s macros - BEFORE `simple_shell.h`, mirroring the
  include order that broke sw_demo. On the pre-1.9.1 header the test target
  does not compile at all; that is the test. Two run-time assertions guard
  the guard: `sdk_macro_poison_is_armed` fails loudly if a future SDK stops
  defining `small` (a silent tripwire is worse than none) and
  `sdk_macro_tripwire` proves the poisoned unit really reached the header.
  The class name is load-bearing: finalized C concatenates a partition's
  files alphabetically, so `sd` must sort ahead of every `SHELL_*` class's
  `sh` or the include guard makes the tripwire's own include a no-op - the
  first cut of this test passed on a broken header for exactly that reason.
  `shell_sdk_poison.h` now `#error`s the build if it is ever sorted out of
  position. Test-only: `testing/Clib` is on the tests target's include path
  and nobody else's.
- A `SHELL_SDK_MACRO_TRIPWIRE` block at the head of `simple_shell.h` stating
  the law - no identifier this header DECLARES may live in the SDK's macro
  namespace; locals carry the `l_` prefix - and `#error`ing by name if the
  SDK ever captures one we do use, instead of leaving a C2059 forty lines
  below the real cause.

  Assault 17/19 from a non-interactive session (`desktop_grab` and
  `input_keys_are_accepted` need the interactive desktop and were refused,
  the same two as 1.8.0); 15/17 on the same machine before this change.

## 1.9.0 - 2026-09-01

### Added
- SHELL_TRAY: one icon in the notification area on a message-only window
  (no callbacks - the queue-polled pump law holds). `set_tooltip` carries
  an unread count, `balloon` posts a notice, `remove` is idempotent; an
  environment that refuses the icon leaves `is_installed` False and the
  caller degrades instead of raising. Built for simple_chat's
  TRAY_NOTIFIER (the dependency task).

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
