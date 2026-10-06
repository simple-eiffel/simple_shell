note
	description: "[
		The displays attached to the desktop, as a snapshot taken by `refresh':
		bounds and work area (the part not covered by the taskbar) in
		virtual-screen coordinates, the primary flag, and the device name
		(\\.\DISPLAY1 ...), which identifies a monitor across sessions. For
		placing an instrument on the right monitor: a webcam sits on one.
	]"

class
	SHELL_MONITORS

create
	make

feature {NONE} -- Initialization

	make
			-- Snapshot of the current displays.
		do
			refresh
		end

feature -- Constants

	Max_monitors: INTEGER = 16

feature -- Access

	count: INTEGER
			-- Monitors in the snapshot.

	left (a_index: INTEGER): INTEGER
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 0) end

	top (a_index: INTEGER): INTEGER
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 1) end

	right (a_index: INTEGER): INTEGER
			-- One past the last column.
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 2) end

	bottom (a_index: INTEGER): INTEGER
			-- One past the last row.
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 3) end

	work_left (a_index: INTEGER): INTEGER
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 4) end

	work_top (a_index: INTEGER): INTEGER
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 5) end

	work_right (a_index: INTEGER): INTEGER
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 6) end

	work_bottom (a_index: INTEGER): INTEGER
		require valid: valid_index (a_index)
		do Result := c_field (a_index - 1, 7) end

	device_name (a_index: INTEGER): STRING_32
			-- Windows device name, e.g. "\\.\DISPLAY1".
		require
			valid: valid_index (a_index)
		local
			l_buf: MANAGED_POINTER
			l_n, i: INTEGER
		do
			create l_buf.make (64)
			l_n := c_name (a_index - 1, l_buf.item, 32)
			create Result.make (l_n)
			from i := 0 until i >= l_n loop
				Result.append_character (l_buf.read_natural_16 (i * 2).to_character_32)
				i := i + 1
			end
		end

	primary_index: INTEGER
			-- Index of the primary monitor (0 if the snapshot has none).
		local
			i: INTEGER
		do
			from i := 1 until Result > 0 or i > count loop
				if is_primary (i) then
					Result := i
				end
				i := i + 1
			end
		ensure
			found_is_primary: Result > 0 implies is_primary (Result)
		end

	index_at (a_x, a_y: INTEGER): INTEGER
			-- Monitor containing point (`a_x', `a_y'), 0 if none.
		local
			i: INTEGER
		do
			from i := 1 until Result > 0 or i > count loop
				if a_x >= left (i) and a_x < right (i) and a_y >= top (i) and a_y < bottom (i) then
					Result := i
				end
				i := i + 1
			end
		ensure
			contains: Result > 0 implies (a_x >= left (Result) and a_x < right (Result)
				and a_y >= top (Result) and a_y < bottom (Result))
		end

feature -- Status

	valid_index (a_index: INTEGER): BOOLEAN
		do
			Result := a_index >= 1 and a_index <= count
		end

	is_primary (a_index: INTEGER): BOOLEAN
		require
			valid: valid_index (a_index)
		do
			Result := c_field (a_index - 1, 8) = 1
		end

feature -- Element change

	refresh
			-- Take a new snapshot (after a display change).
		do
			count := c_refresh
		ensure
			bounded: count >= 0 and count <= Max_monitors
		end

feature {NONE} -- Externals

	c_refresh: INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_monitors_refresh();"
		end

	c_field (a_i, a_f: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_monitor_field($a_i, $a_f);"
		end

	c_name (a_i: INTEGER; a_buf: POINTER; a_cap: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_monitor_name($a_i, (wchar_t*)$a_buf, $a_cap);"
		end

invariant
	count_range: count >= 0 and count <= Max_monitors

end
