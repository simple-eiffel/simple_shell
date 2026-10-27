# Design Scan (diff mode): simple_shell since 75121de
# Date: 2026-10-27
# Subjects: src/shell_desktop.e (the only file under src and Clib that changed in 75121de..HEAD)
# Compared against: all 19 classes in src/ and Clib/simple_shell.h

Scope note: `git diff --name-only 75121de..HEAD -- src Clib` lists only
src/shell_desktop.e (work area, 1.27.0). The set_caption (1.25.0) and Alt+Left/Right
(1.26.0) changes landed at or before 75121de (commits ab893a6, 12b9c6b) and are outside this
diff. For reference, shell_syskey_is_ours is Clib/simple_shell.h:171 and set_caption is
src/shell_window.e:210; neither was re-scanned.

## Summary

| Category | Findings | High | Medium | Low |
|----------|----------|------|--------|-----|
| Abstraction (A1/A4/A5/A3/A6) | 4 | 2 | 1 | 1 |
| Drift (D1) | 1 | 1 | 0 | 0 |
| MI | 0 | 0 | 0 | 0 |
| Generics | 0 | 0 | 0 | 0 |
| **Total** | **5** | **3** | **1** | **1** |

| # | Priority | Category | Classes | Opportunity |
|---|----------|----------|---------|-------------|
| 1 | HIGH | D1 | SHELL_DESKTOP, SHELL_MONITORS | Two independent sources for the primary work area |
| 2 | HIGH | A5 | SHELL_DESKTOP | Four inline-C bodies repeat one SPI_GETWORKAREA call |
| 3 | HIGH | A4 | SHELL_DESKTOP | New queries (and the virtual_* siblings) have no contracts |
| 4 | MEDIUM | A3/A6 | SHELL_DESKTOP, SHELL_MONITORS | The x/y/width/height quadruple is hand-spread over many features |
| 5 | LOW | A5 | simple_shell.h | Virtual-screen metrics re-derived inline beside shell_screen_* |

## Detailed Findings

### Finding 1: Work area now has two independent sources (D1, HIGH)
**Classes:** src/shell_desktop.e, src/shell_monitors.e, Clib/simple_shell.h
**Description:** SHELL_MONITORS already reports every monitor's work area, taken from
MONITORINFO.rcWork (Clib/simple_shell.h:1786-1789), with `work_left/top/right/bottom`
(src/shell_monitors.e:51, 55, 59, 63), `is_primary` (122) and `primary_index` (84-96, with
the postcondition `found_is_primary` at 96). The 1.27.0 SHELL_DESKTOP
work_area_x/y/width/height (src/shell_desktop.e:44-77) answer the same question for the
primary monitor through a different API (SystemParametersInfoW SPI_GETWORKAREA). Two copies
of one fact with different refresh and failure rules are drift waiting to happen:
- SHELL_MONITORS is a snapshot refreshed only by `refresh` (shell_monitors.e:16-18, `make`
  calls it once); work_area_* is read live on every call. After a taskbar move, auto-hide
  change, or monitor change the two disagree until someone calls `refresh`.
- On API failure work_area_* silently return 0 (shell_desktop.e:51, 59, 67, 75); the monitor
  snapshot reports `count = 0` and `primary_index = 0` instead (shell_monitors.e:84-96).
- Coordinates: shell_desktop.e:44 says "primary monitor's work area" while its neighbors
  virtual_x/y (lines 10-23) are virtual-desktop values; nothing states that work_area_x/y are
  in the same (virtual-screen) coordinate space.
**Behavior that should win:** the live reading, which is what a main window needs. Keep
work_area_* but give both classes ONE source (the header function of Finding 2), or document
SHELL_MONITORS as a snapshot and add a contract tying work_area_* to the primary monitor's
work rectangle after a `refresh`.
**Evidence:** shell_desktop.e:44-77; shell_monitors.e:4, 16-18, 51-63, 84-96, 122;
simple_shell.h:1771 (snapshot array), 1786-1789.
**Suggested Action:** refactor branch (no skill fits exactly); Larry decides the owner.
**Effort:** 4 features rerouted, 1 header function.

### Finding 2: Four duplicated inline-C bodies (A5, HIGH)
**Class:** SHELL_DESKTOP (src/shell_desktop.e:44-77)
**Description:** Each query repeats
`RECT l_r; if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &l_r, 0)) return 0; return l_r.<field>;`
(lines 51, 59, 67, 75). That is four system calls to read one rectangle, so the four numbers
are not read atomically: x and width can come from different taskbar states if the user moves
or auto-hides the taskbar between calls. It also departs from the convention in this same
class: virtual_* (lines 10-42) delegate to named header functions
shell_screen_x/y/w/h (simple_shell.h:926-929); the inline form is the odd one out.
**Header statics check (known ecosystem trap):** the new code adds NO header statics; the
`RECT l_r` is a stack local in each inline body. The header's mutable shared state uses
SHELL_SHARED (simple_shell.h:50-54; 52 uses, for example line 1771), and a grep for plain
mutable `static ... s_shell...;` declarations finds only the two `static const` COM GUIDs at
lines 1959 and 1961 (constants, harmless). No fork-per-translation-unit hazard found.
**Suggested Action:** add a `shell_work_area` function to simple_shell.h beside line 929 and
have the four features call it; ideally one call fills all four values (see Finding 4).
**Evidence:** shell_desktop.e:51, 59, 67, 75 versus simple_shell.h:926-929.
**Effort:** 4 features, 1 header function.

### Finding 3: No contracts on the new queries (A4, HIGH)
**Class:** SHELL_DESKTOP (src/shell_desktop.e:44-77; also virtual_* at 10-42)
**Description:** None of the work_area_* or virtual_* features has a postcondition, and the
class has no invariant. The failure path returns 0 (lines 51, 59, 67, 75), so a width or
height of 0 is a silent "unknown", indistinguishable from a real value. The only checks live
in a test: testing/shell_assault.e:44 (`virtual_width > 0`), 47 (`work_area_width > 0 and
work_area_height > 0`), 48 (work area no larger than the desktop). Those belong in the class:
- work_area_width, work_area_height: `ensure non_negative: Result >= 0`, and
  `within_desktop: Result <= virtual_width` (resp. virtual_height); true because the primary
  work area lies inside the virtual desktop.
- An honest "known" query (`has_work_area: BOOLEAN`) so callers need not treat 0 as magic.
- work_area_x/y: `ensure within_desktop: Result >= virtual_x` (resp. virtual_y).
**Suggested Action:** /eiffel.contracts on SHELL_DESKTOP.
**Effort:** 8 features (4 new, 4 sibling).

### Finding 4: Rectangle quadruple spread by hand (A3/A6, MEDIUM)
**Classes:** SHELL_DESKTOP, SHELL_MONITORS
**Description:** The same shape (x, y, width, height or left, top, right, bottom) is written
out by hand: virtual_* (shell_desktop.e:10-42), work_area_* (44-77), and per-monitor bounds
and work rectangles (shell_monitors.e:29-63, 8 features); shell_printer.e:190 and 205 carry
similar width/height pairs. A small immutable rectangle value (left/top/right/bottom, derived
width/height, invariant `width >= 0 and height >= 0`) returned by `work_area`,
`virtual_area` and SHELL_MONITORS bounds/work would cut about 16 accessors to a handful, fix
the non-atomic read (Finding 2), and carry the contracts once (Finding 3). Not urgent: the flat
accessors are released API (1.27.0), so add the value type alongside and keep old names as thin
wrappers.
**Suggested Action:** proposal for Larry; a new helper class, later /eiffel.abstract.
**Effort:** about 1 new class, 8 features rerouted.

### Finding 5: Virtual-screen metrics re-derived inline (A5, LOW)
**Class:** Clib/simple_shell.h (sibling of the new code, not itself a subject)
**Description:** shell_screen_x/y/w/h exist (lines 926-929) and line 1003 uses them, but
shell_input_on_desktop (2167-2171) and shell_input_click (2178-2181) repeat the raw
GetSystemMetrics(SM_*VIRTUALSCREEN) calls. No divergence today (same metrics). Noted because
the work-area function of Finding 2 will join this family.
**Evidence:** simple_shell.h:926-929, 1003, 2168-2169, 2179-2180.
**Effort:** 2 header functions, mechanical.

## Checks that found nothing
- Mutable header statics: none added (Finding 2).
- Name clash: no other `work_area` in src/ or testing/ beyond shell_desktop.e and the test
  lines cited in Finding 3.
- MI and generics: SHELL_DESKTOP has no parents and no collections; no opportunity there.

## Recommended Order
1. Findings 1 and 2 together (one header function, one source of truth; settles atomicity).
2. Finding 3 (contracts), which then locks the behavior chosen in step 1.
3. Findings 4 and 5 only if Larry wants the rectangle value type.
