# Changelog

All notable changes to simple_shell.

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
