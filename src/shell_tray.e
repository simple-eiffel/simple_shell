note
	description: "[
		One icon in the Windows notification area: a tooltip that can
		carry an unread count, and balloon notices. Anchored on a
		hidden window of its own, removed cleanly on `remove'. The icon
		is the program's own (resource 1 of its .rc) when it has one.
		Since 1.14.0 clicks on the icon arrive on the shared queue as
		`Event_click' (button in the first field, `id' in the fourth -
		pushed, never called back: the queue-polled pump law holds),
		and `choose' opens a popup menu at the pointer.
		Built for simple_chat's TRAY_NOTIFIER: balloon per notice unless
		the window is in front, the unread count on the tooltip.

		The environment can refuse an icon (no shell, a locked-down
		session): `make' then leaves `is_installed' False and every
		operation requires an installed icon - the caller falls back to
		nothing rather than raising.
	]"
	author: "Larry Rix"

class
	SHELL_TRAY

create
	make

feature {NONE} -- Initialization

	make (a_tooltip: READABLE_STRING_GENERAL)
			-- Install the icon with `a_tooltip'; `is_installed' says whether
			-- the shell accepted it.
		require
			tip_given: not a_tooltip.is_empty
			tip_fits: a_tooltip.count <= Tooltip_maximum
		local
			ns: NATIVE_STRING
		do
			create ns.make (a_tooltip)
			handle := shell_tray_add (ns.item)
			is_installed := handle /= default_pointer
			if is_installed then
				id := shell_tray_id (handle)
			end
		ensure
			outcome: is_installed = (handle /= default_pointer)
			identified: is_installed implies id > 0
		end

feature -- Access

	handle: POINTER
			-- The anchoring message-only window; null when not installed.

	is_installed: BOOLEAN
			-- Is the icon in the notification area?

	id: INTEGER
			-- This icon's number among the process's tray icons: `Event_click' carries it
			-- in the fourth field (`SHELL_WINDOW.event_extra').

feature -- Clicks and menu (1.14.0)

	Event_click: INTEGER = 52
			-- A click on the icon: the button (`Click_left', `Click_right', `Click_double')
			-- in the first field, `id' in the fourth.

	Click_left: INTEGER = 1
	Click_right: INTEGER = 2
	Click_double: INTEGER = 3

	choose (a_items: ARRAY [READABLE_STRING_GENERAL]): INTEGER
			-- Open a popup menu of `a_items' ("-" for a separator) at the pointer; the number
			-- of the item chosen (1-based, separators counted), or 0 for none.
		require
			installed: is_installed
			items_given: not a_items.is_empty
			one_line_each: across a_items as ic all not ic.is_empty and not ic.has ('%N') end
		local
			l_lines: STRING_32
			ns: NATIVE_STRING
		do
			create l_lines.make (64)
			across a_items as ic loop
				if not l_lines.is_empty then
					l_lines.append_character ('%N')
				end
				l_lines.append (ic.to_string_32)
			end
			create ns.make (l_lines)
			Result := shell_tray_menu (handle, ns.item)
		ensure
			known: Result >= 0 and Result <= a_items.count
		end

	simulate_click (a_button: INTEGER)
			-- Send the icon's window the message the shell sends for a click: the test door
			-- to `Event_click'.
		require
			installed: is_installed
			known: a_button >= Click_left and a_button <= Click_double
		do
			inspect a_button
			when Click_left then
				shell_tray_try_click (handle, 0x0202)
			when Click_right then
				shell_tray_try_click (handle, 0x0205)
			else
				shell_tray_try_click (handle, 0x0203)
			end
		end

feature -- Element change

	set_tooltip (a_text: READABLE_STRING_GENERAL)
			-- The hover text - simple_chat shows "(n) simple_chat" here.
		require
			installed: is_installed
			text_given: not a_text.is_empty
			fits: a_text.count <= Tooltip_maximum
		local
			ns: NATIVE_STRING
			l_ok: INTEGER
		do
			create ns.make (a_text)
			l_ok := shell_tray_set_tip (handle, ns.item)
		ensure
			still_installed: is_installed
		end

	balloon (a_title, a_body: READABLE_STRING_GENERAL)
			-- One notice: who, and the start of what.
		require
			installed: is_installed
			title_given: not a_title.is_empty
			title_fits: a_title.count <= Title_maximum
			body_fits: a_body.count <= Body_maximum
		local
			ns_title, ns_body: NATIVE_STRING
			l_ok: INTEGER
		do
			create ns_title.make (a_title)
			create ns_body.make (a_body)
			l_ok := shell_tray_balloon (handle, ns_title.item, ns_body.item)
		ensure
			still_installed: is_installed
		end

feature -- Removal

	remove
			-- Take the icon out of the notification area; idempotent.
		local
			l_ok: INTEGER
		do
			if is_installed then
				l_ok := shell_tray_remove (handle)
				handle := default_pointer
				is_installed := False
			end
		ensure
			gone: not is_installed and handle = default_pointer
		end

feature -- Constants

	Tooltip_maximum: INTEGER = 127
			-- NOTIFYICONDATA.szTip is 128 wide characters with the terminator.

	Title_maximum: INTEGER = 63
			-- szInfoTitle is 64 with the terminator.

	Body_maximum: INTEGER = 255
			-- szInfo is 256 with the terminator.

feature {NONE} -- Externals (simple_shell.h)

	shell_tray_id (a_hwnd: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_tray_id((HWND)$a_hwnd);"
		end

	shell_tray_menu (a_hwnd: POINTER; a_items: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_tray_menu((HWND)$a_hwnd, (const wchar_t*)$a_items);"
		end

	shell_tray_try_click (a_hwnd: POINTER; a_message: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_tray_try_click((HWND)$a_hwnd, $a_message);"
		end

	shell_tray_add (a_tip: POINTER): POINTER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_tray_add((const wchar_t*)$a_tip);"
		end

	shell_tray_set_tip (a_hwnd: POINTER; a_tip: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_tray_set_tip((HWND)$a_hwnd, (const wchar_t*)$a_tip);"
		end

	shell_tray_balloon (a_hwnd: POINTER; a_title: POINTER; a_body: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_tray_balloon((HWND)$a_hwnd, (const wchar_t*)$a_title, (const wchar_t*)$a_body);"
		end

	shell_tray_remove (a_hwnd: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_tray_remove((HWND)$a_hwnd);"
		end

invariant
	handle_matches: is_installed = (handle /= default_pointer)

note
	copyright: "Copyright (c) 2026, Larry Rix"
	license: "MIT License"

end
