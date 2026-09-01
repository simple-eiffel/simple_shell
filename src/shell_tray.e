note
	description: "[
		One icon in the Windows notification area: a tooltip that can
		carry an unread count, and balloon notices. Anchored on a
		message-only window (no callbacks - the queue-polled pump law
		holds; clicks are a later stage), removed cleanly on `remove'.
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
		ensure
			outcome: is_installed = (handle /= default_pointer)
		end

feature -- Access

	handle: POINTER
			-- The anchoring message-only window; null when not installed.

	is_installed: BOOLEAN
			-- Is the icon in the notification area?

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
