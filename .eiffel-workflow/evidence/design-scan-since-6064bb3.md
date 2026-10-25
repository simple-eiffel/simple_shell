# Design Scan (diff mode): simple_shell, since 6064bb3
# Head: ebebc54 (GW-14a, 1.21.0). Read-only; nothing compiled or run.
# Subjects: Clib/simple_shell.h, src/shell_appearance.e, src/shell_window.e, testing/shell_assault.e, testing/test_app.e

## Summary

| Category | Findings | High | Medium | Low |
|----------|----------|------|--------|-----|
| Abstraction / drift | 3 | 0 | 0 | 3 |
| Correctness / robustness | 3 | 0 | 1 | 2 |
| Tests | 2 | 0 | 2 | 0 |
| **Total** | **8** | **0** | **3** | **5** |

No HIGH finding. The C side is a faithful, small copy of the GW-16 contrast code and is correct as far as it can be read.

## Findings

| # | Priority | Topic |
|---|----------|-------|
| 1 | MEDIUM | PowerShell oracle test depends on Add-Type (compiler, language mode) and can fail for environmental reasons |
| 2 | MEDIUM | Nothing proves the real WM_SETTINGCHANGE reaches the window procedure line (only the test door does) |
| 3 | MEDIUM | `system_reduces_motion` is a fresh system call on every read; callers that read it twice can disagree |
| 4 | LOW | Third copy of the "setting to event" recipe (53, 56, 57) in C, Eiffel door and tests |
| 5 | LOW | Event numbers and SPI codes spelled in several places each |
| 6 | LOW | Class note says "the three queries"; there are now four |
| 7 | LOW | Quoting of the PowerShell command passes through cmd.exe by luck of quote parity |
| 8 | LOW | `lParam` is dereferenced as a string for every WM_SETTINGCHANGE |

## Detailed Findings

### Finding 1: PowerShell oracle test is environment-fragile
**Priority:** MEDIUM
**Category:** tests
**Where:** testing/shell_assault.e:727-757 (`test_reduced_motion_reads_the_windows_setting`), command line at :740.
**Description:** The oracle uses `Add-Type -MemberDefinition` to compile a C# P/Invoke stub. That launches the C# compiler (about one to three seconds), writes to the temp directory, and fails under PowerShell Constrained Language Mode, AppLocker, or a policy that blocks Add-Type. The sibling registry oracle (:619-620) uses reg.exe and has none of those dependencies.
**Failure scenario:** On a locked-down machine `Add-Type` throws. The redirected file exists anyway (the redirect creates it, so `assert ("PowerShell answered", f.exists)` at :742 always passes), no line contains True or False, `l_out` stays empty, and the last assertion fails with a message that blames the setting rather than the environment. A line of error text containing the word True would also be taken as the answer (:747 uses a substring match).
**Suggested fix:** Make the test skip (record "oracle unavailable") when no line is exactly True or False. Match the whole trimmed line, not a substring.

### Finding 2: The real message path is untested
**Priority:** MEDIUM
**Category:** tests
**Where:** Clib/simple_shell.h:531-537 (window procedure), testing/shell_assault.e:709-725.
**Description:** `test_motion_change_is_queued` calls `report_motion_change`, which calls `shell_motion_changed` directly. The line `shell_motion_changed((unsigned int)w)` (:536) is never exercised: deleting it or mistyping the variable passes every test. The same gap exists for contrast (:535), so it is inherited, but this is a third unchecked line.
**Failure scenario:** The call is lost in a merge; all tests pass; no window ever hears event 57.
**Suggested fix:** One test that sends `WM_SETTINGCHANGE` with wParam 0x1043 to a real hidden test window (the dark-title-bar test already builds one) and drains the queue for 57.

### Finding 3: `system_reduces_motion` is not stable across two reads
**Priority:** MEDIUM
**Category:** correctness (contract)
**Where:** src/shell_appearance.e:66-71, Clib/simple_shell.h:322-327.
**Description:** Each call is a fresh SystemParametersInfoW. Event 57 carries the value at push time in its first field, but the client library (simple_widgets) ignores the field and re-reads, up to three times in one routine, against its own "read once" rule (scan 10). The contrast query has a test double with `flips_on_read`; the motion query has none, and the feature comment does not warn that the answer is live.
**Failure scenario:** A client reads twice while the user toggles the setting; two objects end with different values.
**Suggested fix:** State in the feature comment that the answer is live and callers read once. Optionally cache the last pushed value for clients that want the value event 57 carried.

### Finding 4: Third copy of one recipe
**Priority:** LOW
**Category:** A5 (duplicated bodies)
**Evidence:**
- Clib/simple_shell.h:293-303 `shell_contrast_changed`: if spi equals X, push 56 with the current reading, answer 1.
- Clib/simple_shell.h:331-337 `shell_motion_changed`: the same body with 0x1043, 57, another reader.
- src/shell_appearance.e:143-150 `report_contrast_change` and :154-162 `report_motion_change`: same contract shape (`only_the_...: Result = (a_spi = ...)`), same pair of externals (`c_contrast_changed` and `c_motion_changed`, :206-228).
**Description:** Two copies is tolerable; a third setting makes one C helper `shell_push_if (spi, wanted, event, value)` worthwhile, so the window procedure reads as a table.
**Effort:** one helper function.

### Finding 5: Event numbers and SPI codes spelled several times
**Priority:** LOW
**Category:** T1 (token drift)
**Evidence:** 57 appears in the C push (:333), `SHELL_APPEARANCE.Event_motion_changed` (shell_appearance.e:73), `SHELL_WINDOW.Event_motion_changed` (shell_window.e:322) and two comments. 0x1043 appears in the C macro (:318) and `Spi_set_client_area_animation` (shell_appearance.e:77); 0x1042 appears in the C macro and in the test (shell_assault.e:740). The equality test between window and appearance constants exists for 56 and 57 but is a convention, not a structure.
**Suggested fix:** Define the numbers once in the header and expose them through one inline external, or a constants ancestor both classes inherit side by side. Low urgency.

### Finding 6: Stale class note
**Priority:** LOW
**Where:** src/shell_appearance.e:17 ("redefines the three queries").
**Description:** There are four queries now (`system_prefers_dark`, `system_high_contrast`, `system_color`, `system_reduces_motion`). A test double that redefines only three silently reads the real machine for motion and becomes machine-dependent.
**Suggested fix:** Say "the four queries".

### Finding 7: cmd.exe quote parity in the oracle
**Priority:** LOW
**Where:** testing/shell_assault.e:740.
**Description:** The command carries `\"user32.dll\"` inside a double-quoted `-Command` argument followed by a quoted redirect path. cmd.exe toggles its quote state on every quote including the escaped ones; the segment `user32.dll\` falls outside quotes and contains nothing special, so it works today. Adding a character such as `&`, `|` or `)` there would break it silently. Writing the script to a temporary file and running it with `-File` removes the question.

### Finding 8: lParam treated as a string for every setting change
**Priority:** LOW
**Where:** Clib/simple_shell.h:534 (`shell_setting_changed((const wchar_t*)l)`), pre-existing, now one of three consumers.
**Description:** For WM_SETTINGCHANGE lParam is a string only for some notifications; for SPI actions it is usually null. A non-string pointer passed to `lstrcmpiW` would fault. Guard the string path on wParam being zero.

## Checked and found fine
- Constants spelled out for the 0x0500 target (:315-320). BOOL is four bytes, matching the P/Invoke `ref bool` default marshaling.
- A failed read answers "not reduced" (:324-325), the safe direction.
- Event 57 does not collide with 53 to 56; the event list in the `SHELL_WINDOW` pump comment was updated (shell_window.e:70).
- The new tests are registered (testing/test_app.e:47-48).
- Nothing else in simple_shell animates on the heartbeat; the dwell timer (55) and the wake event (54) are not visual motion.

## Recommended Order
1. Finding 2 (a real window-procedure test)
2. Finding 1 (make the oracle skippable)
3. Findings 3, 6, 8 (comments and one guard)
4. Findings 4, 5, 7 when a fourth setting arrives
