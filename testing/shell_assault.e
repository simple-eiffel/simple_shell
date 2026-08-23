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

end
