# simple_shell

![tests](https://img.shields.io/badge/tests-9%2F9-brightgreen) ![platform](https://img.shields.io/badge/platform-Win32-blue) ![language](https://img.shields.io/badge/Eiffel-25.02-purple)

**The Win32 platform shell for the Simple Eiffel ecosystem.** One header of
battle-tested C, seven Eiffel classes, no rendering opinion. This is the
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
| `SHELL_CLIPBOARD` | Unicode text get/set with history-manager retry; 1M-character headroom |
| `SHELL_SPELLER` | Windows inbox `ISpellChecker` (COM): misspelling ranges + suggestions; degrades to no findings, never to failure |
| `SHELL_DESKTOP` | virtual-screen metrics, **pure screen grab** into a caller ARGB32 buffer, `now_ms` (QPC), `minutes_of_day`, `open_externally` |
| `SHELL_OVERLAY` | frozen-desktop topmost overlay (the region-picker pattern) |
| `SHELL_STRIP` | small topmost tool-window strip (the dictation-bar pattern) |

## Build and test

```bash
/d/prod/ec.sh test -config simple_shell.ecf -target simple_shell_tests
./EIFGENs/simple_shell_tests/F_code/simple_shell.exe
```

The assault is real: the desktop is grabbed (alpha verified opaque), the
clipboard round-trips a snowman, a strip window is genuinely created
offscreen, the spell checker is consulted. 9/9 under full DBC.

## Design rules it obeys

- **Design by Contract** throughout; the finalized test binary keeps assertions.
- **Void safety**: all. **SCOOP**: supported.
- **Inline C pattern**: every external is `C inline` against one header —
  no separate `.c` files, no import libraries beyond `shell32`.
- **The queue law**: C pushes events, Eiffel polls. No `$`-agent callbacks
  cross the boundary, ever (they SEGV under threaded runtimes).

## Lineage

Born as `ocr_cairo_win.h` in `simple_ocr_capture`, matured inside
`simple_widgets`, carved into its own library on 2026-08-23 so any
application — widgets or not — can descend on the platform without
dragging in a toolkit.

## License

MIT — part of the [simple-eiffel](https://github.com/simple-eiffel) ecosystem.
