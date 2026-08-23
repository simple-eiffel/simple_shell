note
	description: "[
		The platform half of a windowed application: owns the native
		window, the message pump and the event queue. Events queue in
		C (never dollar-callbacks - they SEGV under EIF_THREADS) and
		drain here; each lands in `dispatch', the descendant's one
		obligation. What the window DRAWS is no business of this
		class - a descendant marries it to any rendering substrate.
	]"

deferred class
	SHELL_WINDOW

feature -- Access

	hwnd: POINTER
			-- The native window handle; `default_pointer' before
			-- `shell_run' or after a failed creation.

feature -- Operation

	shell_run (a_title: READABLE_STRING_GENERAL; a_x, a_y, a_w, a_h: INTEGER)
			-- Create the native window and pump until it closes,
			-- handing every queued event to `dispatch'.
		require
			sane_size: a_w > 0 and a_h > 0
		local
			ns: NATIVE_STRING
			quit: BOOLEAN
			ev: INTEGER
		do
			create ns.make (a_title)
			hwnd := shell_create_window (ns.item, a_x, a_y, a_w, a_h)
			if hwnd /= default_pointer then
				on_shell_open
				from
				until
					quit
				loop
					if shell_pump = 0 then
						quit := True
					end
					from
						ev := shell_next_event (ev_buf.item)
					until
						ev = 0
					loop
						dispatch (ev, ev_buf.read_integer_32 (4), ev_buf.read_integer_32 (8))
						ev := shell_next_event (ev_buf.item)
					end
				end
			end
		end

	dispatch (a_type, a_x, a_y: INTEGER)
			-- One event from the native queue. Types: 2 press, 3 char,
			-- 4 key, 6 expose, 7 tick, 8 double, 9 drag, 10 release,
			-- 11 context, 12 triple, 13 move, 14 leave, 15 wheel
			-- (delta in `event_extra'), 16 resize, 17 middle, 18 drop;
			-- 21..23 status strip.
		deferred
		end

	on_shell_open
			-- Hook: the native window just came up. Default: nothing.
		do
		end

feature -- Measurement

	event_extra: INTEGER
			-- The current event's fourth field (wheel delta, drop count).
		do
			Result := ev_buf.read_integer_32 (12)
		end

	tick_ms: INTEGER
			-- Milliseconds since boot (GetTickCount) - frame timing.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return (EIF_INTEGER)GetTickCount();"
		end

	shift_is_down: BOOLEAN
			-- Physical Shift state at query time.
		do
			Result := shell_shift_down = 1
		end

feature -- Element change

	set_backdrop_rgb (a_rgb: INTEGER)
			-- Keep the class brush on the application's ground colour:
			-- pixels a live resize exposes are erased with it before
			-- the next frame lands, so growth never flashes.
		do
			if hwnd /= default_pointer then
				shell_set_backdrop (hwnd, a_rgb)
			end
		end

feature -- Services

	window_dc: POINTER
			-- The window's device context; release with
			-- `release_window_dc' promptly.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_get_dc();"
		end

	release_window_dc (a_dc: POINTER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_release_dc($a_dc);"
		end

	add_font (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Load a TTF for this process only (FR_PRIVATE); its family
			-- name becomes selectable. False when the file is missing
			-- or rejected.
		local
			s8: STRING_8
			cs: C_STRING
		do
			s8 := a_path.to_string_8
			create cs.make (s8)
			Result := shell_add_font_ext (cs.item) > 0
		end

	native_text_menu (a_can_cut, a_can_copy, a_can_paste, a_can_select: BOOLEAN): INTEGER
			-- Track the OS text context menu at the cursor; 1 Cut,
			-- 2 Copy, 3 Paste, 4 Select All, 0 dismissed.
		do
			Result := shell_text_menu_ext (
				(if a_can_cut then 1 else 0 end),
				(if a_can_copy then 1 else 0 end),
				(if a_can_paste then 1 else 0 end),
				(if a_can_select then 1 else 0 end))
		ensure
			known: Result >= 0 and Result <= 4
		end

	take_dropped_paths: ARRAYED_LIST [STRING_32]
			-- The pump's dropped paths, surrogate-paired, split on the
			-- newline joins; the buffer clears on read.
		local
			buf: MANAGED_POINTER
			n, i: INTEGER
			c: NATURAL_16
			cur: STRING_32
		do
			create Result.make (4)
			create buf.make (32768)
			n := shell_drop_paths_ext (buf.item, 16384)
			create cur.make (64)
			from
				i := 0
			until
				i >= n
			loop
				c := buf.read_natural_16 (i * 2)
				if c = 10 then
					if not cur.is_empty then
						Result.extend (cur.twin)
						cur.wipe_out
					end
					i := i + 1
				elseif c >= 0xD800 and c <= 0xDBFF and i + 1 < n then
					cur.append_code (0x10000
						+ (c.to_natural_32 - 0xD800) * 0x400
						+ (buf.read_natural_16 ((i + 1) * 2).to_natural_32 - 0xDC00))
					i := i + 2
				else
					cur.append_character (c.to_character_32)
					i := i + 1
				end
			end
			if not cur.is_empty then
				Result.extend (cur)
			end
		end

feature {NONE} -- Implementation

	ev_buf: MANAGED_POINTER
			-- Four INTEGER_32 slots the queue drains into.
		attribute
			create Result.make (16)
		end

feature {NONE} -- Externals

	shell_create_window (a_title: POINTER; a_x, a_y, a_w, a_h: INTEGER): POINTER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_create_window((const wchar_t*)$a_title, (int)$a_x, (int)$a_y, (int)$a_w, (int)$a_h);"
		end

	shell_pump: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_pump();"
		end

	shell_next_event (a_buf: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_next_event((int*)$a_buf);"
		end

	shell_set_backdrop (a_hwnd: POINTER; a_rgb: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_set_backdrop($a_hwnd, $a_rgb);"
		end

	shell_add_font_ext (a_path: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_add_font((const char*)$a_path);"
		end

	shell_drop_paths_ext (a_buf: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_drop_paths((wchar_t*)$a_buf, $a_cap);"
		end

	shell_shift_down: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_shift_down();"
		end

	shell_text_menu_ext (a_cut, a_copy, a_paste, a_sel: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_text_menu($a_cut, $a_copy, $a_paste, $a_sel);"
		end

end
