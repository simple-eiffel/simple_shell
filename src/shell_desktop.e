note
	description: "[
		The machine outside any window: virtual-screen geometry, a
		pure screen grab into a caller-supplied ARGB32 buffer (the
		route that replaced EV_SCREEN.sub_pixmap), wall-clock
		helpers, and handing paths to the OS shell.
	]"

class
	SHELL_DESKTOP

feature -- Virtual screen

	virtual_x: INTEGER
			-- Left edge of the virtual desktop (negative with a
			-- monitor left of primary).
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_screen_x();"
		end

	virtual_y: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_screen_y();"
		end

	virtual_width: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_screen_w();"
		end

	virtual_height: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_screen_h();"
		end

feature -- Capture

	grab_into (a_x, a_y, a_w, a_h: INTEGER; a_bits: POINTER; a_stride: INTEGER): BOOLEAN
			-- BitBlt the desktop region into `a_bits' (ARGB32 rows of
			-- `a_stride' bytes), alpha forced opaque. False when the
			-- desktop cannot be read (locked session, secure screen).
		require
			positive: a_w > 0 and a_h > 0
			buffer: a_bits /= default_pointer
			rows_fit: a_stride >= a_w * 4
		do
			Result := c_grab (a_x, a_y, a_w, a_h, a_bits, a_stride) = 1
		end

feature -- Time

	now_ms: REAL_64
			-- High-resolution wall clock in milliseconds
			-- (QueryPerformanceCounter).
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_now_ms();"
		end

	minutes_of_day: INTEGER
			-- Local time as minutes since midnight.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_minutes_of_day();"
		end

feature -- Shell

	open_externally (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Hand `a_path' (file, folder or URL) to the OS shell's
			-- 'open' verb; False when the shell refuses.
		local
			ns: NATIVE_STRING
		do
			create ns.make (a_path)
			Result := c_shell_open (ns.item) = 1
		end

feature {NONE} -- Externals

	c_grab (a_x, a_y, a_w, a_h: INTEGER; a_bits: POINTER; a_stride: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_grab_screen($a_x, $a_y, $a_w, $a_h, $a_bits, $a_stride);"
		end

	c_shell_open (a_path: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_shell_open((const wchar_t*)$a_path);"
		end

end
