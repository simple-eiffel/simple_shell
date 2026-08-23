note
	description: "[
		A small topmost tool-window strip (no taskbar presence, never
		activated on show): the dictation-bar pattern. Dragging its
		body moves it; events arrive on the shared queue as
		21 press / 22 moved / 23 expose. One per process.
	]"

class
	SHELL_STRIP

feature -- Access

	handle: POINTER
			-- The strip window, once shown.

feature -- Operation

	show (a_x, a_y, a_w, a_h: INTEGER)
			-- Create (first time) and place the strip.
		require
			sane_size: a_w > 0 and a_h > 0
		do
			handle := c_show_strip (a_x, a_y, a_w, a_h)
		end

	hide
		do
			c_hide_strip
		end

feature -- Services

	dc: POINTER
			-- The strip's device context; release promptly.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_strip_dc();"
		end

	release_dc (a_dc: POINTER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_strip_release($a_dc);"
		end

feature {NONE} -- Externals

	c_show_strip (a_x, a_y, a_w, a_h: INTEGER): POINTER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_show_strip($a_x, $a_y, $a_w, $a_h);"
		end

	c_hide_strip
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_hide_strip();"
		end

end
