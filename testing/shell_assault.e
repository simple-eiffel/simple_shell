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
			-- Put a synthetic 4x3 ARGB32 image on the clipboard and read
			-- its size back through the DIB header. The pixels are given
			-- with alpha 0 - the C side must force them opaque.
		local
			c: SHELL_CLIPBOARD
			bits: MANAGED_POINTER
			i: INTEGER
		do
			create c
			create bits.make (4 * 4 * 3)
			from i := 0 until i >= 12 loop
				bits.put_natural_32 (0x00FF8000, i * 4)
				i := i + 1
			end
			c.set_image (bits.item, 4, 3, 16)
			assert ("a bitmap is on the clipboard", c.has_image)
			assert_integers_equal ("width read back", 4, c.image_width)
			assert_integers_equal ("height read back", 3, c.image_height)
			assert ("and it is not text", not c.has_text)
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
