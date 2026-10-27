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

feature -- Work area (1.27.0; one read since 1.27.1)

	work_area_x: INTEGER
			-- Left edge of the primary monitor's work area (the screen less the taskbar).
		do
			Result := work_area_field (Field_x)
		end

	work_area_y: INTEGER
			-- Top edge of the primary monitor's work area.
		do
			Result := work_area_field (Field_y)
		end

	work_area_width: INTEGER
			-- Width of the primary monitor's work area: where a main window should open (simple_bible opens at most of it).
		do
			Result := work_area_field (Field_width)
		ensure
			positive: Result > 0
		end

	work_area_height: INTEGER
			-- Height of the primary monitor's work area.
		do
			Result := work_area_field (Field_height)
		ensure
			positive: Result > 0
		end

	work_area_field (a_field: INTEGER): INTEGER
			-- Field `a_field' of the work area, the whole rectangle read in one system call; the virtual
			-- desktop when Windows will not say. Scan 34 (2026-10-27): each field was its own call, and a
			-- refused call answered 0, which would size a window to nothing.
		require
			valid_field: a_field >= Field_x and a_field <= Field_height
		local
			l_rect: MANAGED_POINTER
		do
			create l_rect.make (16)
			Result := work_area_or_desktop (c_read_work_area (l_rect.item), l_rect.read_integer_32 (0), l_rect.read_integer_32 (4),
				l_rect.read_integer_32 (8), l_rect.read_integer_32 (12), a_field)
		ensure
			sized: a_field >= Field_width implies Result > 0
		end

	work_area_or_desktop (a_read: BOOLEAN; a_left, a_top, a_right, a_bottom, a_field: INTEGER): INTEGER
			-- Field `a_field' of the rectangle `a_left', `a_top', `a_right', `a_bottom' when it was `a_read'
			-- and is not empty, else of the virtual desktop (a size at least 1).
		require
			valid_field: a_field >= Field_x and a_field <= Field_height
		do
			if a_read and a_right > a_left and a_bottom > a_top then
				inspect a_field
				when Field_x then
					Result := a_left
				when Field_y then
					Result := a_top
				when Field_width then
					Result := a_right - a_left
				else
					Result := a_bottom - a_top
				end
			else
				inspect a_field
				when Field_x then
					Result := virtual_x
				when Field_y then
					Result := virtual_y
				when Field_width then
					Result := virtual_width.max (1)
				else
					Result := virtual_height.max (1)
				end
			end
		ensure
			sized: a_field >= Field_width implies Result > 0
			read_kept: (a_read and a_right > a_left and a_bottom > a_top and a_field = Field_width) implies Result = a_right - a_left
		end

	Field_x: INTEGER = 1
	Field_y: INTEGER = 2
	Field_width: INTEGER = 3
	Field_height: INTEGER = 4
			-- The fields of a rectangle `work_area_field' answers.

feature {NONE} -- Work area implementation

	c_read_work_area (a_rect: POINTER): BOOLEAN
			-- Fill the RECT at `a_rect' with the primary work area; False when Windows refuses.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return (EIF_BOOLEAN) (SystemParametersInfoW(SPI_GETWORKAREA, 0, (RECT *) $a_rect, 0) != 0);"
		end

feature -- Display scale (1.11.0)

	become_dpi_aware
			-- Draw in physical pixels (system DPI aware), as `shell_create_window'
			-- makes the process anyway. Call before measuring anything that must
			-- match what will be drawn, so `system_dpi' tells the truth.
		external
			"C inline use %"simple_shell.h%""
		alias
			"SetProcessDPIAware();"
		end

	system_dpi: INTEGER
			-- Dots per inch of the primary display as this process sees it: 96 at
			-- 100%, 144 at 150%. A process that is not DPI aware always sees 96.
		external
			"C inline use %"simple_shell.h%""
		alias
			"[
				HDC l_screen = GetDC(0);
				int l_dpi = l_screen ? GetDeviceCaps(l_screen, LOGPIXELSX) : 96;
				if (l_screen) ReleaseDC(0, l_screen);
				return (EIF_INTEGER)(l_dpi > 0 ? l_dpi : 96);
			]"
		end

	dpi_scale: REAL_64
			-- `system_dpi' / 96: how many physical pixels one design pixel takes.
		do
			Result := system_dpi / 96
		ensure
			positive: Result > 0
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
