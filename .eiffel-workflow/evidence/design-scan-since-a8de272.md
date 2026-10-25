# Design Scan (diff mode): simple_shell, since a8de272
# Date: 2026-10-25
# Range: a8de272..b7e729c (GW-16, 1.20.0). Read-only; nothing compiled, nothing edited.
# Subjects: src/shell_appearance.e, src/shell_window.e, Clib/simple_shell.h (the C half of the same change), testing/shell_assault.e

## Summary

| Category | Findings | High | Medium | Low |
|----------|----------|------|--------|-----|
| Abstraction / drift | 5 | 0 | 3 | 2 |
| C correctness | 3 | 0 | 1 | 2 |
| Contracts / tests | 3 | 0 | 0 | 3 |
| **Total** | **11** | **0** | **4** | **7** |

No HIGH findings.

Checked and clean:
- Event 56 collides with nothing. Every shell_push number in Clib/simple_shell.h is 2-4, 6-18, 21-23, 25, 31-37, 41-56 (55 is the dwell timer, simple_shell.h:797), and no other class declares 56.
- The new C adds no mutable header statics, so nothing forks per translation unit. The two new functions are stateless statics that reach shared state only through shell_push, which writes the SHELL_SHARED queue.
- Struct size is right: HIGHCONTRASTW is zeroed and cbSize is set to sizeof (simple_shell.h:280-282). SystemParametersInfoW, HIGHCONTRASTW and GetSysColor date from Windows 2000 era (WINVER 0x0400), so the 0x0500 target is fine.
- The Win32 COLOR_ values match: 5, 8, 13, 14, 15, 17, 18, 26; 30 is COLOR_MENUBAR, the highest.

## Findings

| # | Priority | Category | Where | Opportunity |
|---|----------|----------|-------|-------------|
| 1 | MEDIUM | A1/D1 | src/shell_appearance.e:32,53; src/shell_window.e:233,255,311,315; src/shell_wake.e:24; Clib/simple_shell.h:301,308 | Event numbers have three or four independent copies and drifting names |
| 2 | MEDIUM | D1 | src/shell_window.e:58-67 | dispatch event list not updated (55 and 56 missing) |
| 3 | MEDIUM | A5 | Clib/simple_shell.h:298-310, 505-511 | Event 56 pushed from two paths with no change detection: duplicate and spurious events |
| 4 | MEDIUM | A3 | Clib/simple_shell.h:253-262, 294-310, 505-511 | WM_SETTINGCHANGE classified by two unrelated helpers (lParam string vs wParam) |
| 5 | LOW | A5 | Clib/simple_shell.h:301,308 | The same push statement written twice |
| 6 | LOW | A1/T1 | src/shell_appearance.e:86 vs Clib/simple_shell.h:272-274 | SPI_SETHIGHCONTRAST value duplicated in Eiffel and C; constant misfiled |
| 7 | LOW | C | Clib/simple_shell.h:279-286 | Failure of SystemParametersInfoW is indistinguishable from "off" |
| 8 | LOW | C | Clib/simple_shell.h:508 | WPARAM narrowed to unsigned int |
| 9 | LOW | contract | src/shell_appearance.e:120-128 | No precondition on a_spi before to_natural_32 |
| 10 | LOW | tests | testing/shell_assault.e (new tests) | Read-back tests depend on registry state and an 8-bit temp path |
| 11 | LOW | contract | src/shell_appearance.e:42-50 | The rgb postcondition cannot fail; undocumented that all indexes 0-30 are legal |

## Detailed Findings

### 1. Event numbers: three or four copies, names drift (MEDIUM, A1/D1)
Number 56 is a literal in Clib/simple_shell.h:301 and 308, `Event_contrast_changed` in src/shell_appearance.e:53, and again `Event_contrast_changed` in src/shell_window.e:315. This repeats the existing pattern for 53 (SHELL_APPEARANCE `Event_changed` at :32, SHELL_WINDOW `Event_appearance_changed` at :311) and 54 (SHELL_WAKE `Event_wake` at shell_wake.e:24, SHELL_WINDOW `Event_wake` at shell_window.e:233). 55 exists only in SHELL_WINDOW (:255). Drift already present: 53 has two different names in its two homes, 56 has the same name in both, and 55 has no owning class. The tests guard the pairs they check (`assert_integers_equal ... a.Event_contrast_changed, w.Event_contrast_changed`), but there is no single place that lists the namespace, which is what a collision check needs.
Failure scenario: the next gap item picks "56 is free" from a list that stops at 54 (finding 2), or one copy of a number is edited and the other is not; only the tested pairs notice.
Suggested fix: a deferred ancestor SHELL_EVENTS holding every `Event_*` constant once (the panel 41-50 block, 51, 52, 53-56), inherited side by side by SHELL_WINDOW, SHELL_APPEARANCE, SHELL_WAKE, SHELL_PANEL, SHELL_HOTKEYS and SHELL_TRAY (multiple inheritance; settle the 53 name with a rename and keep the old names for one release). Optionally add a `#define` block next to the queue so the literal pushes in C use names.

### 2. dispatch documentation stale (MEDIUM, D1)
src/shell_window.e:58-67 lists types up to "54 a processor called SHELL_WAKE.wake". 55 (dwell, 1.19.0) was already missing and 56 is missing now. That comment is the only description of the namespace a descendant implements.
Failure scenario: a client author reads the `dispatch` header, never learns 56 exists, and never follows Windows high contrast.
Suggested fix: add "55 the dwell timer ran out (1.19.0); 56 the Windows high-contrast switch or palette changed (1.20.0)", or replace the list with a pointer to the ancestor from finding 1.

### 3. Event 56 has no change detection: duplicates and spurious events (MEDIUM, A5)
Clib/simple_shell.h:505-511: one real high-contrast toggle sends WM_SETTINGCHANGE (SPI_SETHIGHCONTRAST) and then WM_SYSCOLORCHANGE, so a client receives two events 56 with the same first field. WM_SYSCOLORCHANGE is also broadcast for any system color change (a light/dark flip or a theme switch commonly sends it), so event 56 can arrive with first field 0 when high contrast never changed. The CHANGELOG says "1 for on or 0 for off", which reads like a flip, but the payload is the current state, not a transition.
Failure scenario: a client that rebuilds its palette and relayouts on each 56 does it twice per toggle, and again on every light/dark flip (when 53 already made it repaint), visible as flicker.
Mitigating fact: the second event is needed on purpose, because GetSysColor can still return the old palette when the first arrives (the comment at :294-296 says the system colors message follows), so do not drop it; coalesce instead.
Suggested fix: document that 56 means "re-read both queries", never "it flipped"; or keep a SHELL_SHARED last-pushed state and coalesce identical consecutive events the way SHELL_WAKE coalesces wakes (explicit initializer, per simple_shell.h:45-52).

### 4. Two classifiers for WM_SETTINGCHANGE (MEDIUM, A3)
`shell_setting_changed(const wchar_t* l_area)` (:256-262, by the lParam string) and `shell_contrast_changed(unsigned int l_spi)` (:299-305, by wParam) are called back to back from the window procedure (:505-508); every future setting (text scale, animations) would add a third call. The two keys of one message are classified in two places, and `shell_system_colors_changed` returns void (:307) while the other two return int, so the trio is not uniform.
Suggested fix: one `shell_settings_message(WPARAM, LPARAM)` router in C holding both tests, called by the window procedure and by the test doors. Low effort: two functions move, the case shrinks to one line.

### 5. Duplicated push body (LOW, A5)
Clib/simple_shell.h:301 and :308 are the same statement. Extract `static void shell_push_contrast(void)` and call it from both, so a later payload change (for example a palette stamp, finding 3) is made once.

### 6. SPI constant duplicated and misfiled (LOW, A1/T1)
`Spi_set_high_contrast: INTEGER = 0x43` (src/shell_appearance.e:86) copies `SPI_SETHIGHCONTRAST 0x0043` (Clib/simple_shell.h:272-274). It also sits under the feature clause "System color indexes (Win32 COLOR_*)" though it is not a color index, and it is exported to every client. The test passes `a.Spi_set_high_contrast` into `report_contrast_change`, so the Eiffel constant and the test agree with each other whether or not the C value ever changes.
Suggested fix: move it into the test-door clause (or export it to the test only), and add a test that asks C for its own value through an external so the copies cannot drift.

### 7. API failure reported as "off" (LOW, C)
shell_high_contrast_on (:279-286) returns 0 when SystemParametersInfoW fails. A user in high contrast on a restricted desktop gets `system_high_contrast = False`. Windows rarely refuses this call, and `shell_system_prefers_dark` has the same blind default, so this is consistent rather than a regression. Add a status query only if simple_bible needs to tell "unknown" from "off".

### 8. WPARAM narrowed to unsigned int (LOW, C)
:508 `shell_contrast_changed((unsigned int)w)` compares the low 32 bits only. A message whose wParam has low 32 bits 0x43 and nonzero high bits is treated as the switch. Practically unreachable; widen the parameter to UINT_PTR when the router of finding 4 is built.

### 9. Test door contract (LOW)
src/shell_appearance.e:120-128: `a_spi.to_natural_32` is called with no precondition, so a negative `a_spi` (a natural "bad action" probe such as -1) either violates a conversion precondition inside EiffelBase or wraps, depending on the build. Add `require non_negative: a_spi >= 0`. The postcondition `only_the_switch` cross-checks the Eiffel constant against the C constant (useful for finding 6) but does not prove the push; the test covers that.

### 10. Tests depend on registry state (LOW)
testing/shell_assault.e: `reg_value` only matches lines containing "REG_SZ", so an absent `Flags` or `Colors\Window` value yields an empty string and the test fails on `is_integer` or the "three channels" assertion instead of reporting a skip. On some Windows 11 themes the in-memory GetSysColor palette is not what HKCU\Control Panel\Colors holds. `reg_value` also calls `to_string_8` on a STRING_32 TEMP path, which fails for a profile path with non-Latin characters. The queue-door test (`contrast_change_is_queued`) is solid; the two read-back tests are the fragile ones.
Suggested fix: treat an empty reg result as a printed skip, and build the redirect path without narrowing.

### 11. system_color contract (LOW)
src/shell_appearance.e:42-50: the precondition `a_index >= 0 and a_index <= Color_last` is right (GetSysColor answers black for a bad index), but the `rgb` postcondition cannot fail because the C shifts always yield 24 bits. Note in the comment that all indexes 0-30 are legal, not only the eight named constants, so clients know the precondition is deliberate.

## Recommended Order

1. Findings 2 and 1: the comment fix is zero risk, and the SHELL_EVENTS ancestor (multiple inheritance) gives the namespace one owner before the next event number is chosen.
2. Findings 4 and 5 together (one router and one push helper in C), then finding 3 (document "re-read" semantics now, coalesce later).
3. Findings 6 and 9 (small constant and contract cleanups), then 10.
4. Findings 7, 8 and 11 only if simple_bible needs them.

Nothing was extracted; these are proposals for Larry's word.
