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

feature -- Drives

	logical_drives_mask: INTEGER
			-- GetLogicalDrives: bit 0 = A:, bit 1 = B:, ... bit 25 = Z:.
			-- Which drive letters exist, answered WITHOUT touching any
			-- media - no network timeouts, no removable spin-up. The
			-- probe-free way to build a drive picker (probing a dead
			-- network letter with DIRECTORY.exists blocks for minutes -
			-- simple_speed_reader hand-test, 2026-08-26).
		external
			"C inline use %"simple_shell.h%""
		alias
			"return (EIF_INTEGER)GetLogicalDrives();"
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

feature -- Pumping

	pump_for (a_ms: INTEGER)
			-- Pump this thread's queue for `a_ms' milliseconds
			-- WITHOUT a main window: lets facility windows
			-- (outlines, the strip) paint during short windowless
			-- diagnostics. Returns at the deadline regardless.
			--
			-- `blocking': this is a `Sleep(5)' loop for the WHOLE span the
			-- caller asked for. Unmarked, ISE's collector could not begin
			-- while it ran, so every other processor stopped at its next
			-- allocation for that entire span.
			--
			-- SAFE: one integer in, nothing out; the `MSG' is a C local and
			-- the dispatched window procs write only static C memory.
		require
			positive: a_ms > 0
		external
			"C blocking inline use %"simple_shell.h%""
		alias
			"shell_pump_for($a_ms);"
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
			-- DELIBERATELY NOT `blocking'. A full-screen BitBlt is long CPU,
			-- not a wait, so there is no idle span to hand back; and the
			-- buffer is the CALLER'S. The only in-fleet caller (SW_SCREEN,
			-- through `CAIRO_SURFACE.data') supplies cairo's own C heap, but
			-- the signature admits any POINTER, and this library cannot
			-- prove a consumer did not hand it `$' of an Eiffel area. The
			-- marker would let a collection MOVE that area mid-BitBlt.
			-- An unverifiable safety obligation is not one to export.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_grab_screen($a_x, $a_y, $a_w, $a_h, $a_bits, $a_stride);"
		end

	c_shell_open (a_path: POINTER): INTEGER
			-- `ShellExecuteW', which hands the path to the shell and can
			-- sit there while a COM server, a browser or a mapped drive
			-- wakes up - seconds, on a cold association.
			--
			-- SAFE, and CHECKED: `open_externally' is the only caller and it
			-- passes `NATIVE_STRING.item', whose bytes are a MANAGED_POINTER
			-- allocated by `memory_alloc' - the C heap, not Eiffel-collected
			-- memory. No copy was needed; only the marker.
		external
			"C blocking inline use %"simple_shell.h%""
		alias
			"return shell_shell_open((const wchar_t*)$a_path);"
		end

end
