note
	description: "[
		Synthesised input - mouse clicks and keystrokes delivered
		through SendInput - as a service: clients use it so they
		never declare the externals.

		Lineage: OCR_CLICKER in simple_ocr_capture, returned home.
		That class turned pages unattended, so it put the pointer and
		the foreground window back after every click. A paste flow
		wants the opposite: the click IS the focus change, and the
		keystrokes that follow must land in the window it activated.
		Both are here - `click_at' for the paste case,
		`click_at_quietly' for the page-turn case.
	]"
	design: "[
		SendInput rather than mouse_event / keybd_event: those are
		superseded, and SendInput's absolute coordinates are
		normalised to 0..65535 over the WHOLE virtual desktop, so a
		second monitor is addressed correctly where SetCursorPos
		plus mouse_event depends on the primary screen's origin.

		Every click is guarded by `is_on_desktop'. A rectangle
		defaulted to zero would otherwise quietly click the top-left
		corner of the desktop - the Start button - once per cycle.

		Acceptance is a STATUS, not a guarantee. Windows may refuse an
		injection outright - a locked session, a secure desktop, a
		UIPI boundary against a higher-integrity window - and
		SendInput then reports fewer events than were handed to it
		(typically none, with OS error 5). So each operation records
		what it expected and what was accepted, and `was_accepted'
		says whether they agree; a postcondition would turn a locked
		screen into an exception. Same stance as
		SHELL_DESKTOP.grab_into, which answers False when the desktop
		cannot be read.
	]"

class
	SHELL_INPUT

feature -- Status report

	is_on_desktop (a_x, a_y: INTEGER): BOOLEAN
			-- Is (`a_x', `a_y') inside the virtual desktop?
		do
			Result := c_input_on_desktop (a_x, a_y) = 1
		end

	was_accepted: BOOLEAN
			-- Did Windows take every event of the most recent operation?
		do
			Result := last_expected > 0 and last_accepted = last_expected
		ensure
			definition: Result = (last_expected > 0 and last_accepted = last_expected)
		end

	last_expected: INTEGER
			-- Events the most recent operation handed to SendInput.

	last_accepted: INTEGER
			-- Events Windows reported accepting from it.

	last_os_error: INTEGER
			-- GetLastError after the most recent SendInput; 5 is
			-- ERROR_ACCESS_DENIED, the refused-injection case.

feature -- Pointer

	pointer_x: INTEGER
			-- Where the pointer is now, virtual-desktop x. The
			-- calibration primitive: hover a control, read this.
		local
			xy: MANAGED_POINTER
		do
			create xy.make (8)
			if c_input_pointer (xy.item, xy.item.plus (4)) = 1 then
				Result := xy.read_integer_32 (0)
			end
		end

	pointer_y: INTEGER
			-- Where the pointer is now, virtual-desktop y.
		local
			xy: MANAGED_POINTER
		do
			create xy.make (8)
			if c_input_pointer (xy.item, xy.item.plus (4)) = 1 then
				Result := xy.read_integer_32 (4)
			end
		end

feature -- Mouse

	click_at (a_x, a_y: INTEGER)
			-- Move the pointer to (`a_x', `a_y') and left-click. Focus
			-- lands on whatever was clicked and stays there - the
			-- paste case.
		require
			on_desktop: is_on_desktop (a_x, a_y)
		do
			last_expected := 3
			last_accepted := c_input_click (a_x, a_y, 0, 0)
			last_os_error := c_input_last_error
		ensure
			three_handed_over: last_expected = 3
		end

	click_at_quietly (a_x, a_y: INTEGER)
			-- Click at (`a_x', `a_y'), then put the pointer and the
			-- foreground window back - the unattended page-turn case,
			-- where an owner taking notes must not lose focus once per
			-- page for hours.
		require
			on_desktop: is_on_desktop (a_x, a_y)
		do
			last_expected := 3
			last_accepted := c_input_click (a_x, a_y, 1, 1)
			last_os_error := c_input_last_error
		ensure
			three_handed_over: last_expected = 3
		end

	click_centre_of (a_x, a_y, a_width, a_height: INTEGER)
			-- `click_at' the middle of a rectangle: the user drags a
			-- box around a control, and the edges of that box are the
			-- parts most likely to fall outside it.
		require
			positive: a_width > 0 and a_height > 0
			on_desktop: is_on_desktop (a_x + a_width // 2, a_y + a_height // 2)
		do
			click_at (a_x + a_width // 2, a_y + a_height // 2)
		ensure
			three_handed_over: last_expected = 3
		end

feature -- Keyboard

	press_key (a_vk: INTEGER)
			-- Press and release the virtual key `a_vk'.
		require
			valid_key: a_vk > 0 and a_vk < 256
		do
			press_chord (False, False, False, a_vk)
		ensure
			two_handed_over: last_expected = 2
		end

	press_chord (a_ctrl, a_shift, a_alt: BOOLEAN; a_vk: INTEGER)
			-- Press `a_vk' with the named modifiers held: modifiers
			-- down, key down, key up, modifiers up.
		require
			valid_key: a_vk > 0 and a_vk < 256
		do
			last_expected := 2 + 2 * (a_ctrl.to_integer + a_shift.to_integer + a_alt.to_integer)
			last_accepted := c_input_chord (a_ctrl.to_integer, a_shift.to_integer, a_alt.to_integer, a_vk)
			last_os_error := c_input_last_error
		ensure
			all_handed_over: last_expected = 2 + 2 * (a_ctrl.to_integer + a_shift.to_integer + a_alt.to_integer)
		end

	paste
			-- Ctrl+V into the focused window.
		do
			press_chord (True, False, False, Vk_v)
		ensure
			four_handed_over: last_expected = 4
		end

	press_enter
			-- Enter into the focused window.
		do
			press_key (Vk_return)
		ensure
			two_handed_over: last_expected = 2
		end

	type_text (a_text: READABLE_STRING_GENERAL)
			-- Type `a_text' into the focused window as Unicode key
			-- events, one down/up pair per UTF-16 unit. No clipboard
			-- is involved, so the owner's clipboard is left alone.
			-- Slower than `paste' for long text.
		require
			not_empty: not a_text.is_empty
		local
			ns: NATIVE_STRING
		do
			create ns.make (a_text)
			last_expected := 2 * c_input_type_units (ns.item)
			last_accepted := c_input_type (ns.item)
			last_os_error := c_input_last_error
		ensure
			two_per_unit: last_expected >= 2
		end

feature -- Virtual keys

	Vk_tab: INTEGER = 0x09
	Vk_return: INTEGER = 0x0D
	Vk_shift: INTEGER = 0x10
	Vk_control: INTEGER = 0x11
	Vk_menu: INTEGER = 0x12
			-- Alt
	Vk_escape: INTEGER = 0x1B
	Vk_space: INTEGER = 0x20
	Vk_end: INTEGER = 0x23
	Vk_home: INTEGER = 0x24
	Vk_a: INTEGER = 0x41
	Vk_c: INTEGER = 0x43
	Vk_v: INTEGER = 0x56
	Vk_x: INTEGER = 0x58
	Vk_z: INTEGER = 0x5A

feature {NONE} -- Externals

	c_input_on_desktop (a_x, a_y: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_on_desktop((int)$a_x, (int)$a_y);"
		end

	c_input_pointer (a_x, a_y: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_pointer((int*)$a_x, (int*)$a_y);"
		end

	c_input_click (a_x, a_y, a_restore_cursor, a_restore_focus: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_click((int)$a_x, (int)$a_y, (int)$a_restore_cursor, (int)$a_restore_focus);"
		end

	c_input_chord (a_ctrl, a_shift, a_alt, a_vk: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_chord((int)$a_ctrl, (int)$a_shift, (int)$a_alt, (int)$a_vk);"
		end

	c_input_type (a_s: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_type((const wchar_t*)$a_s);"
		end

	c_input_type_units (a_s: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_type_units((const wchar_t*)$a_s);"
		end

	c_input_last_error: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_input_last_error();"
		end

invariant
	counts_non_negative: last_expected >= 0 and last_accepted >= 0
	never_more_than_handed_over: last_accepted <= last_expected

end
