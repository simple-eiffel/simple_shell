note
	description: "[
		Frame ticks (1x, 1.53.0): `Event_frame_tick' (69), its first field the
		milliseconds since the tick before, at the display's rate while started -
		simple_gui's animation clock on Windows.

		A helper thread waits on the compositor's frame (DwmFlush) and wakes the
		pump that `SHELL_WAKE' would (the main window's thread, or the claimed
		one), so the GUI thread never blocks on it. Ticks coalesce: while one
		waits to be handled, the next is not posted. When the compositor gives no
		frame (a minimized or covered window, Remote Desktop, DwmFlush failing),
		a high-resolution timer paces that turn instead. `stop' never waits: the
		thread ends at its next turn without posting.

		Measured (the 1x spike, 2026-11-12): a USER timer asked for 16 ms ticks
		at 31 ms; DwmFlush-paced ticks hold 17.2 ms median, 17.7 ms p95 with
		every core busy.
	]"

class
	SHELL_FRAME_TICKS

inherit
	SHELL_EVENTS

feature -- Access

	Source_none: INTEGER = 0
			-- No tick yet.

	Source_compositor: INTEGER = 1
			-- The last tick was paced by the compositor's frame.

	Source_timer: INTEGER = 2
			-- The last tick was paced by the high-resolution timer (the fallback).

	source: INTEGER
			-- What paced the last tick.
		do
			Result := c_source
		ensure
			known: Result >= Source_none and Result <= Source_timer
		end

feature -- Basic operations

	start
			-- Tick at the display's rate until `stop' (already running: nothing changes).
		do
			last_started := c_start /= 0
		end

	last_started: BOOLEAN
			-- Did the last `start' leave ticks running?

	stop
			-- No more ticks, at once and without waiting, so an idle program never wakes
			-- at the display's rate.
		do
			c_stop
		end

feature -- Tests

	set_paced_by_timer (a_on: BOOLEAN)
			-- Pace by the high-resolution timer (`a_on'), as when the compositor gives no
			-- frame, or by the compositor again.
		do
			c_force_timer (a_on.to_integer)
		end

feature {NONE} -- Externals

	c_start: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_start_frame_ticks();"
		end

	c_stop
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_stop_frame_ticks();"
		end

	c_source: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_frame_tick_source();"
		end

	c_force_timer (a_on: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_frame_ticks_force_timer($a_on);"
		end

end
