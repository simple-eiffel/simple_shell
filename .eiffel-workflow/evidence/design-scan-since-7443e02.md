# Design Scan (diff mode): simple_shell, since 7443e02 (main 7c2e363)
# Date: 2026-10-25
# Scope: GW-14b 1.22.0, the UI Automation bridge
# Subjects: Clib/simple_shell_uia.h (new, 657 lines), Clib/simple_shell.h (hook pointer, WM_GETOBJECT arm),
#           src/shell_accessibility.e (new), src/shell_window.e (comment), testing/Clib/shell_uia_client.h, testing/shell_assault.e
# Read-only: nothing compiled, no source edited.

## Summary

| Category | Findings | High | Medium | Low |
|----------|----------|------|--------|-----|
| COM correctness | 3 | 0 | 1 | 2 |
| Thread safety | 2 | 1 | 0 | 1 |
| Lifecycle (window, multiple windows) | 2 | 0 | 2 | 0 |
| Protocol coverage | 3 | 0 | 3 | 0 |
| Tests | 2 | 0 | 1 | 1 |
| Build / text | 2 | 0 | 0 | 2 |
| **Total** | **14** | **1** | **7** | **6** |

No duplicated bodies, no drift between copies, no token drift and no missing standard parents were found in the subjects: the
four vtables are four distinct protocols, and SHELL_ACCESSIBILITY is a thin facade with no sibling class to merge with.

## Verified correct (checked line by line, no finding)

- Reference counting: every path that returns an interface hands over exactly one reference. `shell_uia_new` starts at 1 and the
  caller owns it (Navigate :327-330, Root :386-388, ElementProviderFromPoint :423-425, GetFocus :439-441); QueryInterface and
  GetPatternProvider add a reference (:191, :218); `shell_uia_getobject` releases its own reference after UiaReturnRawElementProvider has
  taken one (:525-526); `shell_uia_focus_changed` releases after raising (:589-590). No leak and no early free was found.
- QueryInterface identity: IUnknown and IRawElementProviderSimple both answer `&l_simple` (:181-182), so every interface of one
  element queries to one IUnknown. IRawElementProviderFragmentRoot only on node 0, IValueProvider only when the row has a value.
- The four interface ids and every UI Automation property, pattern and event id in the header match the documented values.
- GetRuntimeId: the root returns S_OK with a null array (:340), correct for a window-hosted fragment root; other rows return
  {UiaAppendRuntimeId, id}, unique as long as ids are unique (see finding 6).
- Lock discipline for the table: every read of `s_uia_nodes` and `s_uia_count` in provider code is under `s_uia_lock`;
  commit swaps both under the lock and frees the old table after leaving it; no call into UI Automation is made while the lock is held
  (events and UiaReturnRawElementProvider are called outside it), so there is no lock-order cycle. The lazy initialization race
  (:102-109) is handled correctly by the 0, 1, 2 state machine. The staging table is touched only by the publishing thread; provider threads never read it.
- 64-bit comparison: `(long)l_l != (long)UiaRootObjectId` (:518) is the documented idiom; `long` is 32 bits on Windows.
- Static vtables and functions per translation unit are fine: an element vtable pointers and the code they name come from the
  same translation unit that allocated the element, `free` is the one C runtime, and all shared state is SHELL_SHARED (selectany).
- After `shell_uia_disable`: the table is gone, so Name, Bounds, Navigate and Value answer UIA_E_ELEMENTNOTAVAILABLE, the pattern and
  interface paths answer "not supported", and the hook pointer is cleared first (:598), so no new provider is created.

## Findings

| # | Priority | Category | Where | Finding |
|---|----------|----------|-------|---------|
| 1 | HIGH | thread safety | simple_shell_uia.h:376-381, simple_shell.h:98-106 | SetFocus pushes into the unsynchronized event queue from a UI Automation thread |
| 2 | MEDIUM | lifecycle | simple_shell.h WM_DESTROY arm, shell_window.e | Destroying the window does not disable the bridge: stale hook, window handle and table |
| 3 | MEDIUM | lifecycle | simple_shell_uia.h:92-100, shell_accessibility.e:30,66 | One global table, window handle and staging area: a second window, or a second facade object, clobbers the first |
| 4 | MEDIUM | protocol | simple_shell_uia.h:561-593 | No property-changed, structure-changed or first-publish notification; clients keep stale data |
| 5 | MEDIUM | protocol | simple_shell_uia.h:212-221, :457-481 | Only a read-only Value pattern: no Invoke, Toggle, RangeValue, Selection or ExpandCollapse |
| 6 | MEDIUM | protocol | simple_shell_uia.h:542-558, :290-325 | The table is never validated (duplicate ids, missing parent, parent after child); Navigate is linear per call |
| 7 | MEDIUM | COM / geometry | simple_shell_uia.h:349-369, :403-427 | Bounds and hit testing ignore clipping; IsOffscreen is not served |
| 8 | MEDIUM | tests | testing/shell_assault.e:759-795 | The test never exercises SetFocus, Navigate, ElementProviderFromPoint, a stale element, or a commit during a client read |
| 9 | LOW | COM | simple_shell_uia.h:376-381 | SetFocus answers S_OK for a released element |
| 10 | LOW | thread safety | simple_shell_uia.h:99, :274, :412, :518, :642 | Unlocked reads of `s_uia_hwnd` and `s_uia_focus`; the lock state is not volatile |
| 11 | LOW | COM | simple_shell_uia.h:341-347, :238-261 | SAFEARRAY and BSTR allocation failures are unchecked |
| 12 | LOW | build | simple_shell_uia.h:36-43 | The selectany rename of UIA_ScrollPatternNoScroll needs SHELL_SHARED defined before the SDK header, but the header that defines it is included after |
| 13 | LOW | text | simple_shell_uia.h:629-639, shell_accessibility.e:256-264 | `row_text` writes `l_out[0]` even when the capacity is zero; the Eiffel caller has an empty `if` |
| 14 | LOW | tests | testing/Clib/shell_uia_client.h:131-136 | A client timeout returns while the worker thread still holds pointers into the caller stack |

## Detailed findings

### Finding 1: SetFocus races the event queue (HIGH)
**Where:** `shell_uia_f_set_focus`, simple_shell_uia.h:376-381 calls `shell_push (58, id, 0, 0)`; `shell_push` is simple_shell.h:98-106.
**Failure scenario:** `shell_push` is a plain single-producer ring: it reads `s_shell_qtail`, writes the slot, then stores the new tail,
with no lock or interlock. Every other producer runs on the pump thread. IFragment::SetFocus is called on a UI Automation
thread (the provider declares ProviderOptions_ServerSideProvider, so UI Automation does not marshal to the window thread).
While the pump thread pushes a mouse or key event, a screen reader SetFocus pushes at the same moment: both read the same tail,
one event overwrites the other, and the tail advances once. A lost key-down or a torn slot (type from one event, coordinates from the other) follows.
The pump is also not woken (`shell_wake` is not called), so the request waits for the next heartbeat (up to 250 ms).
**Suggested fix:** do not touch the queue from the foreign thread. `PostMessageW (s_uia_hwnd, SHELL_WM_UIA_FOCUS, id, 0)` (a private message
in the WM_APP range), and handle it in `shell_wndproc` on the pump thread, where `shell_push (58, ...)` is safe. The message also wakes the pump.
At the same time check that the id still exists in the table (finding 9).

### Finding 2: No disable on window destruction (MEDIUM)
**Where:** simple_shell.h WM_DESTROY arm (the diff hunk after the WM_SYSCOLORCHANGE arm) and src/shell_window.e (comment-only change).
**Failure scenario:** nothing in the shell calls `shell_uia_disable` when the window is destroyed; the toolkit window does not either (only `set_accessible (False)`
does). After the window closes the hook pointer, `s_uia_hwnd`, the table and `s_uia_focus` stay. A client that still holds an element keeps getting S_OK answers with
bounds computed from `ClientToScreen` on a dead handle (it fails and leaves the origin at 0, 0, so the rectangle is wrong, not an error). UiaReturnRawElementProvider (hwnd, 0, 0, 0), which the
documentation requires on destruction so that UI Automation drops its provider references, is never called for a closing window.
**Suggested fix:** in the WM_DESTROY arm, call a second hook (`s_shell_destroy_hook`) or have the shell window call `disable` after the pump ends; clear `s_uia_hwnd` and call UiaReturnRawElementProvider (h, 0, 0, 0) from the window thread.

### Finding 3: One table for the process (MEDIUM)
**Where:** simple_shell_uia.h:92-100 (`s_uia_nodes`, `s_uia_stage*`, `s_uia_hwnd`, `s_uia_focus` are single globals); shell_accessibility.e:30, :66 (`is_building` is per object, the staging table is global).
**Failure scenario:** two shell windows (a tool window, a secondary document window) each publishing: every commit replaces the other table and
`s_uia_hwnd`, so `shell_uia_getobject` (:518) answers only for the last publisher and the first window loses its tree. Two
facade objects interleaving `begin_tree` and `commit` publish each other rows, because `shell_uia_begin` frees the other staging table.
**Suggested fix:** key the state by window handle (a small array of hwnd, table, focus; the element object stores its slot). Short of that, document and enforce one facade per process with a contract.

### Finding 4: No change notifications (MEDIUM)
**Where:** `shell_uia_commit` (:561-576) and `shell_uia_focus_changed` (:579-593) are the only raisers.
**Failure scenario:** a value changes (progress bar, text box, check box state) or a node appears; the new table is swapped in but no
UiaRaiseAutomationPropertyChangedEvent or UiaRaiseStructureChangedEvent is raised, so Narrator, NVDA and Accessibility Insights keep the
old cached name, value and children until they re-query by chance. The first commit has the same problem: a client that asked before
anything was published got "no provider" (:522) and has no reason to ask again.
**Suggested fix:** compare the old and new row by id inside `commit` (the old table is in hand) and raise PropertyChanged for name, value, enabled and bounds; raise StructureChanged (ChildrenInvalidated on the host provider)
when the id set or the parent links differ, and once on the first commit.

### Finding 5: Only a read-only Value pattern (MEDIUM)
**Where:** `shell_uia_s_pattern` (:212-221) and the IValueProvider (:457-481).
**Failure scenario:** a button, check box, slider and tab are announced but cannot be operated through UI Automation: the screen reader "do default
action" finds no Invoke or Toggle pattern; a user can move focus (SetFocus) and then press a key, but cannot ask the
control to act, and states live in the Value string ("checked") instead of ToggleState, RangeValue or SelectionItem, which clients do not interpret.
**Suggested fix:** add a role-to-pattern table and forward Invoke, Toggle and SelectionItem as a queue event (the same marshaled path as finding 1: a private message, then `shell_push`).

### Finding 6: The table is trusted (MEDIUM)
**Where:** `shell_uia_add` (:542-558), `shell_uia_f_navigate` (:290-325); the only enforcement is prose in the header and `root_first` in shell_accessibility.e:50.
**Failure scenario:** a publisher that repeats an id gets two rows served under one runtime id (`shell_uia_index` always finds the first); a row whose parent
is missing or comes later makes NextSibling skip it, Parent return an element that answers UIA_E_ELEMENTNOTAVAILABLE, and the last-box-wins hit test (:416) pick the wrong depth.
Navigate scans the whole table for every call (FirstChild from index 0), so a client walking N nodes costs N squared steps.
**Suggested fix:** validate once in `shell_uia_commit` (reject the table, keep serving the old one, when an id repeats, a parent is unknown, or a parent row is after its child); store a first-child and next-sibling index per row while validating, which makes Navigate constant time after the one linear pass.

### Finding 7: Bounds are unclipped, IsOffscreen is missing (MEDIUM)
**Where:** `shell_uia_f_bounds` (:349-369), `shell_uia_r_from_point` (:403-427); the property switch (:236-266) has no IsOffscreen (30022).
**Failure scenario:** a row rectangle is whatever the toolkit gave it; content scrolled out of a viewport keeps rectangles that overlap its neighbors. Because
`shell_uia_r_from_point` picks the LAST row containing the point, a scrolled-away row painted over a toolbar wins the hit test. Clients cannot learn that a row is off screen.
**Suggested fix:** the publisher intersects each rectangle with its ancestors clip (the table carries a clip rectangle or an `l_offscreen` flag per row) and the bridge serves IsOffscreen; `from_point` skips offscreen rows.

### Finding 8: Test gaps (MEDIUM)
**Where:** `test_uia_bridge_serves_the_published_tree`, testing/shell_assault.e:759-795; testing/Clib/shell_uia_client.h.
**Failure scenario:** the one test reads Name, ControlType, Value and HasKeyboardFocus through FindAll. Nothing exercises SetFocus (finding 1), Navigate in each direction,
ElementProviderFromPoint, GetFocus, a held element after `commit` or `disable` (the UIA_E_ELEMENTNOTAVAILABLE path), reference-count balance, nor
a commit racing a client read. The "disabled" assertion (:790-791) passes if the client simply caches, since UI Automation may answer from its own cache.
**Suggested fix:** add a live-element counter (`s_uia_live`) asserted zero after the client releases; a second client pass using a tree walker and ElementFromPoint; a loop that commits fifty tables while the worker reads; a SetFocus call asserting the pump receives exactly one event 58.

### Finding 9: SetFocus never checks the element (LOW)
`shell_uia_f_set_focus` (:376-381) pushes for any id and answers S_OK. For a released id it should answer UIA_E_ELEMENTNOTAVAILABLE (look the id up under the lock first, as every other method does).

### Finding 10: Unlocked reads, non-volatile lock state (LOW)
`s_uia_hwnd` is read without the lock in `shell_uia_s_host` (:274), `shell_uia_r_from_point` (:412) and `shell_uia_getobject` (:518); `s_uia_focus` in `shell_uia_served_focus` (:642).
These are aligned word reads, benign on x64, but the handle read in `r_from_point` can predate a commit. `s_uia_lock_state` (:99) is read in a spin loop (:107) without volatile, unlike `s_shell_wake_pending`
in simple_shell.h; declare it `volatile LONG`.

### Finding 11: Allocation failures (LOW)
`SafeArrayPutElement` results are ignored (:344, :346), so a failed put leaves a half-filled array that is returned; `SysAllocString` failure leaves vt = VT_BSTR with a null string, which clients read as empty (benign, but E_OUTOFMEMORY is the honest answer).

### Finding 12: Include-order dependence (LOW)
Line 40 renames `UIA_ScrollPatternNoScroll` to `SHELL_SHARED shell_uia_scroll_pattern_no_scroll`, and the SDK header at line 41 expands it. `SHELL_SHARED` is defined only by simple_shell.h, included at line 43. In a translation unit that reaches simple_shell_uia.h first (testing/Clib/shell_uia_client.h:7 includes it first) the macro is undefined at the point of use and the declaration does not parse; the build works only because another header pulled simple_shell.h in earlier. Move `#include "simple_shell.h"` above line 36 (it needs only windows.h, which line 33 already includes).

### Finding 13: Small text hygiene (LOW)
`shell_uia_row_text` (:629-639) writes `l_out[l_n] = 0` even if `l_cap` is zero or negative. shell_accessibility.e:261 has `if ... >= 0 then end`, an empty branch; remove it or use the length.

### Finding 14: Test client leaves a running thread (LOW)
shell_uia_client.h:135 returns -1 on timeout while the worker still writes into `l_job` (a stack variable) and `l_out`. Wait for the thread, or allocate the job on the heap and let the worker free it.

## Recommended order

1. Finding 1 (data race on the event queue; also fixes the 250 ms latency and finding 9).
2. Finding 2, then 3 (lifecycle), because every later test depends on a clean teardown.
3. Finding 6 (validation, index) before 7 and 4, since both want a validated table to compare and clip.
4. Findings 4, 5, 7 (protocol), then 8 (tests that pin all of the above), then the LOW items.
