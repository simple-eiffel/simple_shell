note
	description: "[
		The platform shell under assault: every service exercised for
		real - the desktop is grabbed, the clipboard round-trips, a
		strip window is genuinely created (offscreen), the spell
		checker is consulted. No mocks; this is the machine.
	]"

class
	SHELL_ASSAULT

inherit
	TEST_SET_BASE

feature -- Tray

	test_tray_lifecycle
			-- An icon installed, retitled, ballooned and removed; an
			-- environment that refuses the icon passes by degrading.
		local
			t: SHELL_TRAY
		do
			create t.make ("simple_shell assault")
			if t.is_installed then
				t.set_tooltip ("(3) simple_shell assault")
				t.balloon ("simple_shell", "The tray assault says hello.")
				t.remove
				assert ("removed", not t.is_installed and t.handle = default_pointer)
				t.remove
				assert ("remove is idempotent", not t.is_installed)
			else
				assert ("no notification area in this session", True)
			end
		end

feature -- Desktop

	test_desktop_metrics
		local
			d: SHELL_DESKTOP
		do
			create d
			assert ("a desktop exists", d.virtual_width > 0)
			assert ("with height", d.virtual_height > 0)
		end

	test_desktop_grab
			-- Grab 4x4 real desktop pixels; the C side forces alpha
			-- opaque, so byte 3 of the first BGRA pixel must be 255.
		local
			d: SHELL_DESKTOP
			buf: MANAGED_POINTER
		do
			create d
			create buf.make (64)
			assert ("the desktop can be read",
				d.grab_into (d.virtual_x, d.virtual_y, 4, 4, buf.item, 16))
			assert_integers_equal ("alpha forced opaque", 255,
				buf.read_natural_8 (3).to_integer_32)
		end

	test_clock
		local
			d: SHELL_DESKTOP
			t1, t2: REAL_64
		do
			create d
			t1 := d.now_ms
			t2 := d.now_ms
			assert ("the clock runs", t1 > 0.0)
			assert ("and never backwards", t2 >= t1)
			assert ("minutes fit the day",
				d.minutes_of_day >= 0 and d.minutes_of_day < 1440)
		end

feature -- Keys

	test_keys_answer
		local
			k: SHELL_KEYS
			b: BOOLEAN
		do
			create k
			b := k.shift_down
			b := k.control_down
			b := k.alt_down
			assert ("all three modifiers answered without exception", True)
		end

feature -- Clipboard

	test_clipboard_roundtrip
		local
			c: SHELL_CLIPBOARD
			payload: STRING_32
		do
			create c
			create payload.make_from_string_general ("shell carve ")
			payload.append_code (0x2603)
			payload.append_string_general (" round trip")
			c.set_text (payload)
			assert ("the clipboard holds text", c.has_text)
			assert_strings_equal ("and returns the payload verbatim",
				payload, c.text)
		end

feature -- Speller

	test_speller_degrades_never_fails
		local
			s: SHELL_SPELLER
			r: ARRAYED_LIST [TUPLE [lo, hi: INTEGER]]
		do
			create s
			r := s.misspellings ("")
			assert_integers_equal ("empty text, no findings", 0, r.count)
			r := s.misspellings ("teh dogg barks")
			assert ("ranges ordered when present",
				across r as t all t.lo < t.hi end)
			assert ("suggestions capped at five",
				s.suggestions ("teh").count <= 5)
		end

	test_speller_ignore_is_session_scoped
			-- Teach Ignore on a nonsense word: its finding vanishes
			-- for the rest of the session. (Add is NOT tested - it
			-- writes the user's real Windows dictionary.)
		local
			s: SHELL_SPELLER
			had: BOOLEAN
		do
			create s
			had := not s.misspellings ("zzqqv here").is_empty
			if had then
				assert ("the checker accepts the lesson", s.ignore ("zzqqv"))
				assert ("and the finding is gone this session",
					s.misspellings ("zzqqv here").is_empty)
			else
				assert ("no checker on this box - nothing to teach", True)
			end
		end

feature -- Window services

	test_window_services_without_pump
		local
			w: SHELL_TEST_WINDOW
			paths: ARRAYED_LIST [STRING_32]
		do
			create w
			assert ("no window yet", w.hwnd = default_pointer)
			assert ("the tick clock runs", w.tick_ms > 0)
			paths := w.take_dropped_paths
			assert ("no drops pending", paths.is_empty)
			assert ("a missing font is refused, not accepted",
				not w.add_font ("no_such_font_file.ttf"))
		end

	test_cursor_kind_accepted
		local
			w: SHELL_TEST_WINDOW
		do
			create w
			w.set_cursor_kind (w.Cursor_ibeam)
			w.set_cursor_kind (w.Cursor_arrow)
			assert ("cursor kinds accepted across the range", True)
		end

	test_windowless_pump_returns_on_deadline
		local
			d: SHELL_DESKTOP
			t0: REAL_64
		do
			create d
			t0 := d.now_ms
			d.pump_for (60)
			assert ("the deadline is honoured", d.now_ms - t0 >= 55.0)
			assert ("and not wildly overshot", d.now_ms - t0 < 1000.0)
		end

	test_outline_frames_really_create
			-- A REAL click-through frame, parked far offscreen:
			-- shown, reshown (move path), hidden - and hide_all is
			-- always safe, windows or none.
		local
			o: SHELL_OUTLINES
		do
			create o
			o.show (0, -3000, -3000, 60, 40, 3, 0xFF8800)
			o.show (0, -2900, -3000, 80, 50, 2, 0x00FF88)
			o.hide (0)
			o.hide_all
			assert ("outline lifecycle survived", True)
		end

	test_strip_window_really_creates
			-- A REAL topmost tool window, parked far offscreen and
			-- never activated - creation, DC, release, hide.
		local
			s: SHELL_STRIP
			d: POINTER
		do
			create s
			s.show (-3000, -3000, 4, 4)
			assert ("the strip window exists", s.handle /= default_pointer)
			d := s.dc
			assert ("and yields a device context", d /= default_pointer)
			s.release_dc (d)
			s.hide
		end

feature -- Shared state

	test_queue_is_one_instance_across_units
			-- THE 1.8.0 LOCKUP LAW: an event pushed from one class's
			-- translation unit must come out of the pump's drain in
			-- another. Before SHELL_SHARED each generated C file held
			-- a PRIVATE copy of the queue - the overlay pushed where
			-- nobody drained, and the fullscreen picker became an
			-- inescapable input sink. This cannot pass on that build.
		local
			p: SHELL_PUSH_PROBE
			w: SHELL_TEST_WINDOW
		do
			create p
			create w
			p.push_marker
			assert ("the marker crossed translation units", w.drain_marker)
		end

feature -- Clipboard bitmap

	test_clipboard_image_roundtrip
			-- Put a synthetic 4x3 ARGB32 image on the clipboard, read its
			-- size back through the DIB header, then read the PIXELS back
			-- through `image_into': every one where it was put - the DIB is
			-- bottom-up on the clipboard and top-down on both sides of it -
			-- with alpha forced opaque on the way out. The pixels are given
			-- with alpha 0 (the C side must force them opaque) and coded by
			-- position, so a row put back in the wrong order is caught. A
			-- buffer sized for another bitmap is refused, never overrun.
		local
			c: SHELL_CLIPBOARD
			bits, back: MANAGED_POINTER
			row, col: INTEGER
			l_expected, l_got: NATURAL_32
			l_all: BOOLEAN
		do
			create c
			create bits.make (4 * 4 * 3)
			from row := 0 until row >= 3 loop
				from col := 0 until col >= 4 loop
					bits.put_natural_32 ({NATURAL_32} 0x00FF0000 + row.to_natural_32 * {NATURAL_32} 0x100 + col.to_natural_32, (row * 4 + col) * 4)
					col := col + 1
				end
				row := row + 1
			end
			c.set_image (bits.item, 4, 3, 16)
			assert ("a bitmap is on the clipboard", c.has_image)
			assert_integers_equal ("width read back", 4, c.image_width)
			assert_integers_equal ("height read back", 3, c.image_height)
			assert ("and it is not text", not c.has_text)
			create back.make (4 * 4 * 3)
			assert ("the pixels come back", c.image_into (back.item, 4, 3, 16))
			l_all := True
			from row := 0 until row >= 3 loop
				from col := 0 until col >= 4 loop
					l_expected := {NATURAL_32} 0xFFFF0000 + row.to_natural_32 * {NATURAL_32} 0x100 + col.to_natural_32
					l_got := back.read_natural_32 ((row * 4 + col) * 4)
					l_all := l_all and l_got = l_expected
					col := col + 1
				end
				row := row + 1
			end
			assert ("every pixel where it was put, rows in order, alpha forced opaque", l_all)
			assert ("a buffer sized for another bitmap is refused, never overrun", not c.image_into (back.item, 5, 3, 20))
		end

feature -- Input synthesis

	test_input_knows_the_desktop
			-- The bounds guard agrees with the desktop metrics at every
			-- edge: both corners in, one pixel past either out.
		local
			i: SHELL_INPUT
			d: SHELL_DESKTOP
		do
			create i
			create d
			assert ("origin is on it", i.is_on_desktop (d.virtual_x, d.virtual_y))
			assert ("far corner is on it",
				i.is_on_desktop (d.virtual_x + d.virtual_width - 1, d.virtual_y + d.virtual_height - 1))
			assert ("one past the right edge is not", not i.is_on_desktop (d.virtual_x + d.virtual_width, d.virtual_y))
			assert ("one before the left edge is not", not i.is_on_desktop (d.virtual_x - 1, d.virtual_y))
		end

	test_input_keys_are_accepted
			-- A lone Shift press does nothing to anything, and proves
			-- SendInput takes what it is handed: two events, down and up.
			-- Needs the interactive desktop, exactly as `test_desktop_grab'
			-- does: from a locked session Windows refuses the injection
			-- with OS error 5, and this test fails saying so.
		local
			i: SHELL_INPUT
		do
			create i
			i.press_key (i.Vk_shift)
			assert_integers_equal ("two handed over", 2, i.last_expected)
			if not i.was_accepted then
				print ("    (desktop refused the injection: accepted "
					+ i.last_accepted.out + " of 2, OS error " + i.last_os_error.out
					+ " - locked session or UIPI boundary)%N")
			end
			assert ("and both accepted", i.was_accepted)
		end

feature -- The Alt door

	test_alt_keys_are_claimed
			-- THE ALT GAP (1.9.3). Before this version the window
			-- procedure answered WM_SYSKEYDOWN for the OEM plus/minus
			-- pair alone: `shell_alt_down' said Alt was down, but
			-- Alt+F opened the SYSTEM MENU instead of reaching the
			-- window, so a menu mnemonic could not be built on this
			-- shell. The claim is now the header's own predicate.
		local
			p: SHELL_SYSKEY_PROBE
		do
			create p
			assert ("Alt+F is the window's", p.syskey_is_claimed (70))
			assert ("Alt+A is the window's", p.syskey_is_claimed (65))
			assert ("Alt+Z is the window's", p.syskey_is_claimed (90))
			assert ("Alt+1 is the window's", p.syskey_is_claimed (49))
			assert ("Alt+0 is the window's", p.syskey_is_claimed (48))
			assert ("F10 is the window's", p.syskey_is_claimed (121))
			assert ("the 1.8 Alt step keys are still the window's",
				p.syskey_is_claimed (187) and p.syskey_is_claimed (189)
				and p.syskey_is_claimed (107) and p.syskey_is_claimed (109))
		end

	test_system_alt_keys_are_left_alone
			-- The other half of the same policy, and the half a
			-- careless widening would break: an application that ate
			-- Alt+F4 would be the badly behaved one. These stay with
			-- DefWindowProc.
		local
			p: SHELL_SYSKEY_PROBE
		do
			create p
			assert ("Alt+F4 still closes the window", not p.syskey_is_claimed (115))
			assert ("Alt+Space still opens the system menu", not p.syskey_is_claimed (32))
			assert ("Alt+Enter is still the system's", not p.syskey_is_claimed (13))
			assert ("Alt alone is still the menu key", not p.syskey_is_claimed (18))
			assert ("Alt+F1 is unclaimed", not p.syskey_is_claimed (112))
			assert ("Alt+Left is unclaimed", not p.syskey_is_claimed (37))
			assert ("Alt+Space's WM_SYSCHAR is NOT swallowed - the menu needs it",
				not p.syschar_is_swallowed (32))
			assert ("but the beep behind a claimed letter is",
				p.syschar_is_swallowed (102) and p.syschar_is_swallowed (70))
			assert ("and behind a claimed digit", p.syschar_is_swallowed (49))
			assert ("and behind the 1.8 step keys",
				p.syschar_is_swallowed (43) and p.syschar_is_swallowed (45)
				and p.syschar_is_swallowed (61))
		end

	test_alt_letter_reaches_the_queue
			-- End of the reachable path: WM_SYSKEYDOWN(VK_F) handed to
			-- the window procedure comes out of SHELL_WINDOW's own
			-- drain as the ordinary key-down event 4 carrying 70 -
			-- across translation units, as `drain_marker' proves the
			-- queue must. What is NOT tested here is Windows itself
			-- delivering the message: that needs a visible window with
			-- the focus and a synthesised keystroke on the tester's
			-- desktop, and was checked by inspection only.
		local
			p: SHELL_SYSKEY_PROBE
			w: SHELL_TEST_WINDOW
		do
			create p
			create w
			p.deliver_syskeydown (70)
			assert ("Alt+F arrived as key-down 70", w.drain_key (70))
			p.deliver_syskeydown (121)
			assert ("F10 arrived as key-down 121", w.drain_key (121))
		end

feature -- SDK macro tripwire

	test_sdk_macro_poison_is_armed
			-- The tripwire is only a tripwire while a Windows SDK
			-- header really does `#define small char'. If a future SDK
			-- stops, this fails and tells us to re-point it - a silent
			-- tripwire is worse than none.
		local
			t: SDK_MACRO_TRIPWIRE
		do
			create t
			assert ("an SDK header still poisons `small' - if not, re-point the tripwire",
				t.poison_is_in_force)
		end

	test_sdk_macro_tripwire
			-- simple_shell.h compiles in a translation unit that pulled
			-- a COM/RPC header FIRST - the order a finalized build hands
			-- it when a sibling library's COM header lands earlier in the
			-- same concatenated unit. On the pre-1.9.1 header (`HICON
			-- big, small;') the C phase died with C2059 / C2513 and this
			-- target never linked, so reaching this line is the proof.
		local
			t: SDK_MACRO_TRIPWIRE
		do
			create t
			assert ("the header survived the SDK macros", t.header_survived_the_poison)
		end

end
