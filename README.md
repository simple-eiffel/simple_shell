# simple_shell

![tests](https://img.shields.io/badge/tests-62%2F62-brightgreen) ![freeze assault](https://img.shields.io/badge/freeze%20assault-4%2F4-brightgreen) ![language](https://img.shields.io/badge/Eiffel-25.02-purple)
![Windows: 62 of 62](https://img.shields.io/badge/Windows-62%2F62-0078D6?logo=windows&logoColor=white) ![macOS: simple_widgets runs](https://img.shields.io/badge/macOS-simple__widgets%20runs-success?logo=apple) ![Linux: in progress](https://img.shields.io/badge/Linux-in%20progress-lightgray)

**The platform shell for the Simple Eiffel ecosystem**: Win32 on Windows, AppKit on
macOS (see [macOS](#macos-131)), GTK on Linux next. Battle-tested C behind
one set of entry points, a handful of Eiffel classes, no rendering opinion. This is the
library that owns the native window, the message pump, the clipboard, the
keyboard, the spell checker, the desktop — so that nothing above it ever
declares an external again.

`simple_widgets` is its first consumer: the drawn toolkit is **pure Eiffel
over two substrates** — `simple_cairo` for pixels, `simple_shell` for the
platform. They meet only in the application-facing library.

```
application
    │
simple_widgets          (pure Eiffel — zero C)
    │           │
simple_cairo   simple_shell
 (drawing)     (platform: window, pump, clipboard, keys, …)
```

## The deferred model

`SHELL_WINDOW` is deferred. It owns window creation and the message pump;
events queue in C and drain through one polled loop — **never**
C-to-Eiffel `$`-callbacks, which SEGV under `EIF_THREADS`. A descendant
supplies exactly one thing: what an event *means*.

```eiffel
class MY_WINDOW

inherit
    SHELL_WINDOW        -- effect `dispatch'; optionally redefine `on_shell_open'

feature

    run
        do
            shell_run ("My app", 100, 100, 800, 600)
        end

    dispatch (a_type, a_x, a_y: INTEGER)
            -- 2 press, 3 char, 4 key, 6 expose, 7 tick (250 ms, settable),
            -- 9 drag, 10 release, 13 move, 15 wheel, 16 resize, 18 drop,
            -- 51 hotkey, 52 tray click, 53 light/dark flipped,
            -- 54 wake, 55 dwell …
        do
            -- marry the events to any rendering substrate you like
        end

end
```

## The classes

| Class | Service |
|---|---|
| `SHELL_WINDOW` | *(deferred)* native window + queue-polled pump; DC access, backdrop brush, drag-drop paths, private fonts, native text menu, tick clock, **cursor shaping** (`set_cursor_kind`: arrow, I-beam, hand, resize, cross, wait); the program's icon from resource 1 of its .rc (1.13.1); `set_starts_hidden`, `show_window`, `hide_window` for a program whose face is a panel (1.14.0); `set_dark_title_bar` (1.16.0); `set_heartbeat_ms` (1.18.0); the one-shot **dwell timer** `arm_dwell_timer` / `cancel_dwell_timer`, event 55 once the pointer rests (1.19.0); `set_caption` changes the caption while the window is up (1.25.0); Alt+Left and Alt+Right reach the window as Back and Forward (1.26.0) |
| `SHELL_KEYS` | physical Shift / Ctrl / Alt state |
| `SHELL_CLIPBOARD` | Unicode text get/set, and every bitmap read, with history-manager retry (size read-back since 1.12.1); 1M-character headroom; **bitmap put and get** (`set_image`, CF_DIB from an ARGB32 buffer; `image_into`, the DIB back into an ARGB32 buffer, 24/32-bit, alpha forced opaque, refused rather than overrun on a size mismatch) with size read-back |
| `SHELL_INPUT` | **synthesised input** via SendInput: `pointer_x` / `pointer_y` (calibration), `click_at` (focus lands and stays) / `click_at_quietly` (pointer and foreground restored), `press_chord`, `paste`, `press_enter`, Unicode `type_text`; virtual-desktop bounds guard on every click |
| `SHELL_SPELLER` | Windows inbox `ISpellChecker` (COM): misspelling ranges + suggestions; degrades to no findings, never to failure |
| `SHELL_DESKTOP` | virtual-screen metrics, **pure screen grab** into a caller ARGB32 buffer, `now_ms` (QPC), `minutes_of_day`, `open_externally` |; the primary **work area** (1.27.0) |
| `SHELL_OVERLAY` | frozen-desktop topmost overlay (the region-picker pattern) |
| `SHELL_STRIP` | small topmost tool-window strip (the dictation-bar pattern) |
| `SHELL_OUTLINES` | click-through colored frame regions on the desktop (the region-outline pattern) |
| `SHELL_PANEL` | borderless topmost instrument panels (up to 8): never take focus, can be left out of screen captures, click-through on demand, whole-window opacity, Shift+drag to move (1.11.0) and to size from an edge or corner (1.12.0), `is_cursor_over` for hover (1.13.0), handles that drag on a plain press kept to one axis, live `Event_moving`, side edges that size on a plain press, files dropped on them (1.14.0), a bottom edge that sizes on a plain press (1.15.0); framed panels - floating windows with a caption, sizing border and focus, owned by the main window, with key, character, close-request, activation, double-click and leave events (`open_framed`, 1.23.0) |
| `SHELL_HOTKEYS` | global hotkeys as queue event 51; a modifier is required unless a chord is registered bare on purpose (1.11.0) |
| `SHELL_MONITORS` | snapshot of the displays: bounds, work area, primary, device name (1.11.0) |
| `SHELL_ACCESSIBILITY` | the UI Automation bridge: publish a widget table (ids, parents, control types, names, values, bounds), served to screen readers behind WM_GETOBJECT from `Clib/simple_shell_uia.h`; focus events; event 58 for a client's focus request (1.22.0) |
| `SHELL_PRINTER` | printers by name, the default printer, and one document at a time: paper, orientation, pages, device metrics, an output file for file printers; no dialog (1.24.0) |
| `SHELL_EVENTS` | every queue event number, named, in one place, with `registry` and `next_free_event`; the owning classes inherit it (1.22.2) |
| `SHELL_APPEARANCE` | the Windows light/dark app setting (`system_prefers_dark`), event 53 when it flips, and a dark or light DWM caption (1.16.0); the high-contrast switch (`system_high_contrast`), the system colors (`system_color`), event 56 when either changes (1.20.0); the animation setting (`system_reduces_motion`), event 57 (1.21.0) |
| `SHELL_WAKE` | `wake` from any SCOOP processor puts event 54 on the GUI's queue at once, coalesced while one is pending; to the main window, or to a thread claimed with `claim_pump_thread` (1.18.0) |
| `SHELL_TRAY` | one notification-area icon (1.9.0): `set_tooltip` (unread counts), `balloon` notices, idempotent `remove`; a refusing environment leaves `is_installed` False and the caller degrades; clicks as `Event_click` (52) and a popup menu with `choose`, the program's own icon (1.14.0) |

## Keyboard: which keys reach the window

Two doors, and an application reads both:

| Message | Event | Carries |
|---|---|---|
| `WM_CHAR` | **3** (char) | the typed character, and the Ctrl **control codes** - Ctrl+C is code 3 |
| `WM_KEYDOWN` | **4** (key) | the stepping keys: arrows, Home, End, Page Up/Down, Delete, the OEM and numpad plus/minus pair |
| `WM_SYSKEYDOWN` | **4** (key) | **new in 1.9.3 - the Alt door** |
| `WM_KEYDOWN` | **4** (key) | **new in 1.17.0** - F1-F12 under any modifier; with Ctrl held and Alt not, digits (row and numpad) and the OEM punctuation keys. Ctrl+Alt (AltGr) still types its character, and letters stay with `WM_CHAR`, so nothing arrives twice |

### The Alt door (1.9.3)

Windows routes a key pressed while Alt is held to `WM_SYSKEYDOWN`, not
`WM_KEYDOWN`. Until 1.9.3 this header answered `WM_SYSKEYDOWN` for the OEM
plus/minus pair alone and let every other syskey fall through to
`DefWindowProc`. The consequence was narrow and total: `SHELL_KEYS.alt_down`
reported Alt perfectly, but **Alt+F never reached the window - it opened the
system menu**, so a menu mnemonic (Alt+F for `&File`) could not be built on
this shell at all. `simple_widgets` named the hole *the Alt gap* and shipped
`activate_mnemonic` with nothing able to call it.

**Now claimed by the window, arriving as the ordinary key-down event 4 with
the virtual key in `a_x`** - ask `SHELL_KEYS.alt_down` for the modifier, the
same way you ask `control_down` for a Ctrl accelerator:

- **Alt+letter**, `A`..`Z` - menu mnemonics
- **Alt+digit**, `0`..`9` - numbered picks
- **Alt** + the OEM/numpad **plus and minus** pair - as since 1.8
- **F10** - which Windows delivers as `WM_SYSKEYDOWN` with no Alt at all,
  being the documented menu key

The `WM_SYSCHAR` that trails each of those is swallowed, or `DefWindowProc`
would open the system menu on the matching mnemonic behind your back or,
finding none, beep on every keystroke.

**Still the system's, deliberately.** An application that ate these would be
the badly behaved one:

| Key | Why it stays with `DefWindowProc` |
|---|---|
| **Alt+F4** | closes the window. It must keep closing it. |
| **Alt+Space** | the system menu - and its `WM_SYSCHAR` is a space, which the swallow list does not claim, so the menu still opens |
| **Alt+Enter** | the properties / fullscreen convention |
| **Alt+Tab**, Alt+Shift+Tab, Alt+Esc | the shell eats these; they never reach any window procedure |
| **Alt alone** (`VK_MENU`) and its key-up | the menu-key contract. Nothing needs the keystroke: `alt_down` already answers the *state*, and a window with no menu bar has no underlines to reveal |
| **Alt+F1..F9, F11, F12** | unclaimed; F10 is the one menu key |
| **Alt+arrow / Home / End / Page / Delete** | unclaimed - the *unmodified* forms arrive on the `WM_KEYDOWN` door as they always have |

The policy is two pure predicates in the header, `shell_syskey_is_ours` and
`shell_syschar_is_ours`, and the window procedure does nothing but consult
them - so it can be asserted on headlessly, with no window, no desktop and no
keystroke. See *Build and test*.

## Build and test

```bash
/d/prod/ec.sh test -config simple_shell.ecf -target simple_shell_tests
./EIFGENs/simple_shell_tests/F_code/simple_shell.exe
```

The assault is real: the desktop is grabbed (alpha verified opaque), the
clipboard round-trips a snowman, a strip window is genuinely created
offscreen, the spell checker is consulted. 62/62 under full DBC **at an
interactive console** (Windows, November 2026). Run it from a locked or
headless session and `desktop_grab`, `input_keys_are_accepted` and
`panel_capture_exclusion_really_hides` fail by design - Windows refuses
BitBlt and SendInput there (OS error 5), and that refusal is a status the
tests report rather than swallow.

Two of them are the **SDK-macro tripwire** (`SDK_MACRO_TRIPWIRE`),
which is really a compile-time test: it includes a COM/RPC header ahead of
`simple_shell.h` and so fails the C phase outright if the header ever again
declares an identifier the Windows SDK has claimed as a macro. See 1.9.1.

Three more are the **Alt door** (1.9.3), and they are the one place this
library tests by predicate rather than by machine. A real Alt+F needs a
visible window holding the focus and a synthesised keystroke on the tester's
own desktop, and this library will not take a machine away from the person
sitting at it. So `SHELL_SYSKEY_PROBE` asserts on the header's two policy
predicates directly, and hands `WM_SYSKEYDOWN(VK_F)` to the window procedure
itself - the event comes back out of `SHELL_WINDOW`'s own drain as key-down
70, across translation units. **What is checked by inspection alone is that
Windows delivers the message in the first place**, which is the operating
system's documented contract, not this library's behavior.

A second, SCOOP target carries the **freeze assault** - the vector test for
the blocking-marker law below. It needs no window and no user:

```
/d/prod/ec.sh test -config simple_shell.ecf -target simple_shell_scoop_tests
./EIFGENs/simple_shell_scoop_tests/F_code/simple_shell.exe
```

## simple_gui's groundwork (November 2026)

simple_shell carries the platform half of [simple_gui](https://github.com/simple-eiffel/simple_gui)'s
Windows backend (simple_gui over simple_widgets):
- **A pump that returns early:** `SHELL_DESKTOP.pump_for` ends on an event or a timeout,
  so a backend can pump until idle instead of handing the thread to `shell_run`.
- **Closing the main window is an event** (66) the program may refuse, as panels' 62 is.
- **The wake belongs to the pumping thread:** `SHELL_WAKE.claim_pump_thread` and `is_pump_thread`, so a
  SCOOP worker's wake (event 54) reaches the right loop.
- **Document windows** (1.30.0): a framed panel opened as a document window has its own taskbar button and Alt+Tab entry, for a program's
  second top-level window.
- **Accessibility roles** under the shared role names, and test doors (request close, the
  pump's thread) for simple_gui's shared test suite, which passes 32 of 32 on Windows.

## macOS (1.31)

On a Mac the same classes run on an AppKit half in `Clib/macos/`: the headers declare the
same entry points, and `shell_appkit.m` and `shell_appkit_ax.m` supply them. It speaks the
Windows contract: the same events and numbers, coordinates in device pixels (as for a
DPI-aware Win32 process: the DPI is 96 times the backing scale), keys as Windows virtual
keys with Command as the primary modifier, and the window's backing cairo image in place
of a device context (simple_cairo's off-Windows contract). So simple_widgets runs
unchanged: its own suite passes 691 of 695 on macOS (the four left are three Windows
drive-letter tests and the screen-reader test), and simple_narrate's Studio builds and
passes its tests.

```bash
make -C Clib     # Clib/simple_shell_appkit.o, which the ECF links on macOS
```

Done on the Mac:

- the window and its pump (`shell_pump`, `shell_pump_pending`, `shell_pump_until`), with
  Windows' event numbers, and close as an event;
- the pointer (press, double and triple, drag, release, move, leave, wheel, middle,
  right and Control-click), keys and characters, and the cursor kinds;
- the heartbeat, fast and dwell timers, and the wake from any thread;
- framed panels (simple_widgets' floating windows), each a window of its own, with the
  panel events and the slot in the fourth field;
- the clipboard's text and images; private fonts (a repeated load is accepted, as on
  Windows);
- dark mode, Increase Contrast and Reduce Motion (events 53, 56, 57); the work area and
  DPI;
- the accessibility table (begin, add, describe, commit, read back);
- the panel extras (unframed and tool panels, grips, opacity, click-through), file dialogs
  and drops, spelling, printing (a cairo PDF sent through CUPS), monitors, the overlay and
  strip, the tray (a status item), hotkeys, input synthesis (it needs macOS's
  Accessibility permission) and the screen grab (it needs Screen Recording).

Not yet: serving the accessibility table to VoiceOver, left for last by Larry's order.

Every entry point is declared once, in `Clib/shell_posix.h`, for both the macOS and the
Linux half. `make` runs `Clib/make_stubs.pl` over that list and a half's sources, and
gives each entry point without a body a "not available" stub, so the stubs file is the
half's to-do list (on the Mac it is empty).

`SHELL_APPKIT_SCRIPT="click:X,Y;type:TEXT;shot:FILE;close"` drives a running app through
AppKit's real event dispatch, one step per heartbeat. simple_shell's own test suite is
Windows-specific (desktop grab, UI Automation, the Alt door); on the Mac the evidence is
simple_widgets' suite. The design record is `docs/SHELL_SEAM.md` in port-coordination (#25).

## Design rules it obeys

- **Design by Contract** throughout; the finalized test binary keeps assertions.
- **Void safety**: all. **SCOOP**: supported.
- **Inline C pattern**: every external is `C inline` against one header —
  no separate `.c` files, no import libraries beyond `shell32`.
- **The queue law**: C pushes events, Eiffel polls. No `$`-agent callbacks
  cross the boundary, ever (they SEGV under threaded runtimes).
- **The blocking law** (1.9.2): every external that WAITS is marked
  `external "C blocking inline"`. ISE's collector stops every thread of the
  system before it collects and cannot stop a thread inside an unmarked
  external, so an unmarked wait freezes **every other processor** at its next
  allocation for the length of the wait. `GetMessageW`, `TrackPopupMenu`, the
  windowless pump, the click's settle sleep and the four spell-checker COM
  calls are all marked. The guarantee to consumers: **a pump in flight never
  stops another processor's allocator.** A marker is only ever added when the
  C code touches no Eiffel-collected memory while it waits - which the queue
  law above already guarantees for the pump. `c_grab` is deliberately left
  unmarked: its buffer belongs to the caller, and that provenance cannot be
  proved from here. See 1.9.2.
- **The Alt door law** (1.9.3): a key the window is entitled to see must
  arrive whichever message Windows chooses to carry it in. Alt+letter and
  Alt+digit come as `WM_SYSKEYDOWN`, and forwarding them as the same event 4
  the arrows already use costs no new event type and no signature change -
  the modifier was always readable through `SHELL_KEYS.alt_down`. The line
  that must not move is the other one: **Alt+F4, Alt+Space, Alt+Enter and
  Alt alone stay with `DefWindowProc`**, and a test asserts on that half too.
- **The SDK macro-namespace law** (1.9.1): no identifier `simple_shell.h`
  declares may collide with a Windows SDK macro - `small`, `hyper`, `byte`,
  `boolean`, `far`, `near`, `pascal`, `interface`, `min`, `max` and friends.
  Locals carry the `l_` prefix. This is not pedantry: a finalized build
  concatenates many classes into one translation unit, so a sibling
  library's COM header can be preprocessed ahead of this one, and a local
  named `small` becomes `char`. It silently blocked release builds of GUI
  apps depending on nothing but generated-file ordering. The tripwire test
  now fails the build instead.

## Lineage

Born as `ocr_cairo_win.h` in `simple_ocr_capture`, matured inside
`simple_widgets`, carved into its own library on 2026-08-23 so any
application — widgets or not — can descend on the platform without
dragging in a toolkit.

## License

MIT — part of the [simple-eiffel](https://github.com/simple-eiffel) ecosystem.
