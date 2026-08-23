note
	description: "[
		Up to four click-through coloured rectangle FRAMES on the
		desktop: topmost, toolwindow, never activated, and input-
		transparent - a click lands on whatever is underneath. The
		visible shape is a frame region (outer minus inner), so the
		middle is not even part of the window. Born for the OCR
		capture tool's region outlines; general to anything that
		must point at the screen without touching it.
	]"

class
	SHELL_OUTLINES

feature -- Constants

	Slot_count: INTEGER = 4

feature -- Basic operations

	show (a_slot, a_x, a_y, a_w, a_h, a_thickness: INTEGER; a_rgb: NATURAL_32)
			-- Show frame `a_slot' at the SCREEN rectangle, walls
			-- `a_thickness' pixels thick, in `a_rgb'.
		require
			slot_known: a_slot >= 0 and a_slot < Slot_count
			sane_size: a_w > 0 and a_h > 0
			walls: a_thickness >= 1
		do
			c_show (a_slot, a_x, a_y, a_w, a_h, a_thickness, a_rgb.to_integer_32)
		end

	hide (a_slot: INTEGER)
		require
			slot_known: a_slot >= 0 and a_slot < Slot_count
		do
			c_hide (a_slot)
		end

	hide_all
		local
			i: INTEGER
		do
			from
				i := 0
			until
				i >= Slot_count
			loop
				c_hide (i)
				i := i + 1
			end
		end

feature {NONE} -- Externals

	c_show (a_slot, a_x, a_y, a_w, a_h, a_thick, a_rgb: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_outline_show($a_slot, $a_x, $a_y, $a_w, $a_h, $a_thick, $a_rgb);"
		end

	c_hide (a_slot: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_outline_hide($a_slot);"
		end

end
