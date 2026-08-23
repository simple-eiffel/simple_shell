note
	description: "[
		The frozen-desktop drag overlay: a topmost popup covering the
		whole virtual screen, crosshair cursor, its input arriving on
		the shared event queue as 12 move / 13 down / 14 up /
		15 cancel / 16 expose. The pure-route replacement for the
		Vision2 region picker. One per process; `show' reuses it.
	]"

class
	SHELL_OVERLAY

feature -- Access

	handle: POINTER
			-- The overlay window, once shown.

feature -- Operation

	show
			-- Create (first time) and raise the overlay across the
			-- whole virtual screen, taking focus for Escape.
		do
			handle := c_show_overlay
		end

	hide
		do
			c_hide_overlay
		end

feature -- Services

	dc: POINTER
			-- The overlay's device context; release promptly.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_overlay_dc();"
		end

	release_dc (a_dc: POINTER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_overlay_release($a_dc);"
		end

feature {NONE} -- Externals

	c_show_overlay: POINTER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_show_overlay();"
		end

	c_hide_overlay
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_hide_overlay();"
		end

end
