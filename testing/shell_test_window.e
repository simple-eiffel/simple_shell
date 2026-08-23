note
	description: "[
		The deferred contract effected minimally: a dispatch that
		counts. Exists so the assault can exercise SHELL_WINDOW's
		non-pumping services without a native window.
	]"

class
	SHELL_TEST_WINDOW

inherit
	SHELL_WINDOW

feature -- Access

	events_seen: INTEGER

feature -- Operation

	dispatch (a_type, a_x, a_y: INTEGER)
		do
			events_seen := events_seen + 1
		end

end
