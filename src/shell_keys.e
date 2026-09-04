note
	description: "[
		Keyboard modifier state as a service - clients ask here so
		they never declare externals.

		STATE, not delivery. This class answers what is held down at
		the moment of asking; which KEYS reach the window is
		SHELL_WINDOW's event 4 and the header's Alt door (1.9.3).
		The two were out of step until then: `alt_down' reported Alt
		perfectly while Alt+F opened the system menu instead of
		reaching the window. An application pairs them - event 4
		gives the key, this class gives the modifier.
	]"

class
	SHELL_KEYS

feature -- Status

	shift_down: BOOLEAN
			-- Physical Shift state at query time.
		do
			Result := c_shift_down = 1
		end

	control_down: BOOLEAN
			-- Physical Ctrl state at query time.
		do
			Result := c_control_down = 1
		end

	alt_down: BOOLEAN
			-- Physical Alt state at query time.
		do
			Result := c_alt_down = 1
		end

feature {NONE} -- Externals

	c_control_down: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_control_down();"
		end

	c_alt_down: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_alt_down();"
		end

	c_shift_down: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_shift_down();"
		end

end
