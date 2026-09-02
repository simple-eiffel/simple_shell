note
	description: "[
		A processor that does nothing but run the REAL library wait -
		`SHELL_DESKTOP.pump_for' - while another processor allocates.

		`pump_for' is the windowless message pump: PeekMessage, dispatch,
		`Sleep(5)', around again until the caller's deadline. It is the
		natural vector for this defect because it needs no window and no
		user, so the assault runs headless and unattended; but the whole
		family behaves the same way. `SHELL_WINDOW.shell_pump' is the one
		that matters in a GUI - it sits in `GetMessageW' until Windows has
		a message for the thread.

		Before 1.9.2 all of them were plain `external "C inline"'. A
		collection could not begin while one was running, so every OTHER
		processor stopped at its next allocation for the whole span of the
		pump. This class makes that span 3 seconds and lets the root
		measure what it cost.
	]"
	author: "Larry Rix"

class
	SHELL_PUMPER

create
	make

feature {NONE} -- Initialization

	make
			-- A pumper that has not pumped yet.
		do
			create desktop
		ensure
			nothing_pumped: pumps_done = 0
		end

feature -- Access

	desktop: SHELL_DESKTOP
			-- The real library class under assault.

	pumps_done: INTEGER
			-- Pumps completed so far.

	elapsed_milliseconds: INTEGER_64
			-- How long the whole run took, wall clock.

feature -- Basic operations

	pump (a_count, a_milliseconds: INTEGER)
			-- Run the real `SHELL_DESKTOP.pump_for' `a_count' times,
			-- `a_milliseconds' each.
		require
			positive: a_count > 0 and a_milliseconds > 0
		local
			i: INTEGER
			l_clock: PRECISE_CLOCK
			t0: INTEGER_64
		do
			create l_clock
			t0 := l_clock.now_ms
			from
				i := 1
			until
				i > a_count
			loop
				desktop.pump_for (a_milliseconds)
				pumps_done := pumps_done + 1
				i := i + 1
			variant
				a_count + 1 - i
			end
			elapsed_milliseconds := l_clock.now_ms - t0
		ensure
			done: pumps_done = old pumps_done + a_count
			timed: elapsed_milliseconds >= 0
		end

invariant
	non_negative: pumps_done >= 0 and elapsed_milliseconds >= 0

end
