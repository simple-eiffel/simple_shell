# simple_shell

![tests](https://img.shields.io/badge/tests-22%2F22-brightgreen) ![freeze assault](https://img.shields.io/badge/freeze%20assault-4%2F4-brightgreen) ![platform](https://img.shields.io/badge/platform-Win32-blue) ![language](https://img.shields.io/badge/Eiffel-25.02-purple)

**The Win32 platform shell for the Simple Eiffel ecosystem.** One header of
battle-tested C, nine Eiffel classes, no rendering opinion. This is the
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
            -- 2 press, 3 char, 4 key, 6 expose, 7 tick (250ms),
            -- 9 drag, 10 release, 13 move, 15 wheel, 16 resize, 18 drop …
        do
            -- marry the events to any rendering substrate you like
        end

end
```

## The classes

| Class | Service |
|---|---|
| `SHELL_WINDOW` | *(deferred)* native window + queue-polled pump; DC access, backdrop brush, drag-drop paths, private fonts, native text menu, tick clock, **cursor shaping** (`set_cursor_kind`: arrow, I-beam, hand, resize, cross, wait) |
| `SHELL_KEYS` | physical Shift / Ctrl / Alt state |
| `SHELL_CLIPBOARD` | Unicode text get/set with history-manager retry; 1M-character headroom; **bitmap put** (`set_image`, CF_DIB from an ARGB32 buffer) with size read-back |
| `SHELL_INPUT` | **synthesised input** via SendInput: `pointer_x` / `pointer_y` (calibration), `click_at` (focus lands and stays) / `click_at_quietly` (pointer and foreground restored), `press_chord`, `paste`, `press_enter`, Unicode `type_text`; virtual-desktop bounds guard on every click |
| `SHELL_SPELLER` | Windows inbox `ISpellChecker` (COM): misspelling ranges + suggestions; degrades to no findings, never to failure |
| `SHELL_DESKTOP` | virtual-screen metrics, **pure screen grab** into a caller ARGB32 buffer, `now_ms` (QPC), `minutes_of_day`, `open_externally` |
| `SHELL_OVERLAY` | frozen-desktop topmost overlay (the region-picker pattern) |
| `SHELL_STRIP` | small topmost tool-window strip (the dictation-bar pattern) |
| `SHELL_OUTLINES` | click-through coloured frame regions on the desktop (the region-outline pattern) |
| `SHELL_TRAY` | one notification-area icon on a message-only window (1.9.0): `set_tooltip` (unread counts), `balloon` notices, idempotent `remove`; a refusing environment leaves `is_installed` False and the caller degrades |

## Keyboard: which keys reach the window

Two doors, and an application reads both:

| Message | Event | Carries |
|---|---|---|
| `WM_CHAR` | **3** (char) | the typed character, and the Ctrl **control codes** - Ctrl+C is code 3 |
| `WM_KEYDOWN` | **4** (key) | the stepping keys: arrows, Home, End, Page Up/Down, Delete, the OEM and numpad plus/minus pair |
| `WM_SYSKEYDOWN` | **4** (key) | **new in 1.9.3 - the Alt door** |

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
offscreen, the spell checker is consulted. 22/22 under full DBC **at an
interactive console**. Run it from a locked or headless session and
`desktop_grab` and `input_keys_are_accepted` fail by design - Windows
refuses BitBlt and SendInput there (OS error 5), and that refusal is a
status the tests report rather than swallow.

Two of the twenty-two are the **SDK-macro tripwire** (`SDK_MACRO_TRIPWIRE`),
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
system's documented contract, not this library's behaviour.

A second, SCOOP target carries the **freeze assault** - the vector test for
the blocking-marker law below. It needs no window and no user:

```
/d/prod/ec.sh test -config simple_shell.ecf -target simple_shell_scoop_tests
./EIFGENs/simple_shell_scoop_tests/F_code/simple_shell.exe
```

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
