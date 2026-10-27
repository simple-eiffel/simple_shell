# Design Scan (diff mode): simple_shell since ca43280
# Date: 2026-10-26
# Subjects: src/shell_window.e (set_caption, c_set_caption), Clib/simple_shell.h (shell_set_caption), CHANGELOG.md (1.25.0)
# Compared against: all of src/ and Clib/simple_shell.h
# Read-only scan: no source file was modified, nothing was compiled.

## Summary

| Severity | Findings |
|----------|----------|
| HIGH | 0 |
| MEDIUM | 1 |
| LOW | 2 |

Nothing is HIGH. The header-static hazard was checked explicitly and does not apply.

## Header-static hazard check (asked for by Larry)

- The new external `c_set_caption` is in SHELL_WINDOW (src/shell_window.e:231-236), the same class as `shell_run` (src/shell_window.e:25), so both inline C bodies land in the same generated translation unit.
- Even if they did not, the only state `shell_set_caption` reads is `s_shell_hwnd`, which is declared `SHELL_SHARED HWND s_shell_hwnd = 0;` (Clib/simple_shell.h:73). `SHELL_SHARED` is `__declspec(selectany)` (see the shared-state law comment above line 73), so it is one process-wide instance however many files include the header. It is assigned at header line 725 in the window creation function.
- `shell_set_caption` itself is a `static` function (header line 791), which the law allows ("functions stay static").
- Verdict: no per-translation-unit fork. The same pattern is already used by `shell_close_window` (header line 785, class SHELL_WINDOW) and `shell_set_window_icon` (line 761).

## Findings

### Finding 1: MEDIUM - no test for set_caption
**Evidence:** `grep -rn "set_caption\|shell_set_caption" testing/` finds nothing. The 1.25.0 diff touched only CHANGELOG.md, Clib/simple_shell.h and src/shell_window.e.
**Proposal:** add a test beside the existing window tests: before `shell_run` the call does nothing and does not crash; on a window opened with a short timer, call `set_caption ("x")` and read it back with `GetWindowTextW` on `hwnd` (SHELL_WINDOW.hwnd, src/shell_window.e:17). One test, no new class.
**Effort:** one test.

### Finding 2: LOW - three ways to ask "is there a window" and two copies of the handle
**Evidence:** the C side guards on `s_shell_hwnd` (header line 792); the Eiffel side keeps `hwnd` (src/shell_window.e:17, set at line 31). They agree because `shell_create_window` sets both, but `set_caption` never consults `hwnd`. After a failed creation `hwnd` is the null pointer and `s_shell_hwnd` stays 0, so the guard holds.
**Proposal:** none now. If a precondition is ever wanted, state it on `hwnd /= default_pointer`, not on the C static.

### Finding 3: LOW - set_caption keeps no copy of the caption
**Evidence:** SHELL_PANEL.set_title keeps `title` (src/shell_panel.e:304-314); SHELL_WINDOW.set_caption keeps none, so a caller cannot read back what it set (SW_WINDOW keeps its own `title` for that).
**Proposal:** leave it. The caption lives in the operating system and in the SW_WINDOW above; a second copy here would be a third owner.

## Duplication check
- Compared with `shell_panel_set_title` (header line 1493) and SHELL_PANEL.set_title: same NATIVE_STRING-then-inline-C shape, but different targets (a panel slot versus the main window). Two three-line bodies do not justify a shared ancestor.
- No other class in src/ changes the main window's text.

## Recommended Order
1. Finding 1 (one test).
