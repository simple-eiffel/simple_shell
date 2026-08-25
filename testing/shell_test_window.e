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

feature -- Probes

	drain_marker: BOOLEAN
			-- Drain the shared queue through SHELL_WINDOW's own
			-- external (the pump's translation unit): True when
			-- SHELL_PUSH_PROBE's type-77 marker with payload
			-- (7, 8, 9) comes out. Leftover events from earlier
			-- assaults are skipped, not failed on.
		local
			ev: INTEGER
		do
			from
				ev := shell_next_event (ev_buf.item)
			until
				ev = 0 or Result
			loop
				Result := ev = 77
					and then ev_buf.read_integer_32 (4) = 7
					and then ev_buf.read_integer_32 (8) = 8
					and then ev_buf.read_integer_32 (12) = 9
				if not Result then
					ev := shell_next_event (ev_buf.item)
				end
			end
		end

end
