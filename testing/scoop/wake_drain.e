note
	description: "[
		Drains the shared shell queue on the root processor, looking for
		the wake event, without opening a window.
	]"

class
	WAKE_DRAIN

inherit
	SHELL_WINDOW

feature -- Operation

	dispatch (a_type, a_x, a_y: INTEGER)
		do
		end

feature -- Probes

	drained_wake: BOOLEAN
			-- Did event 54 come out of the queue? Other events are skipped.
		local
			ev: INTEGER
		do
			from
				ev := shell_next_event (ev_buf.item)
			until
				ev = 0 or Result
			loop
				Result := ev = Event_wake
				if not Result then
					ev := shell_next_event (ev_buf.item)
				end
			end
		end

end
