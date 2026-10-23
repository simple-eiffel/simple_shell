note
	description: "[
		Wake the GUI's message pump from any processor (GW-26). A SCOOP
		worker that has a result ready creates its own SHELL_WAKE and
		calls `wake': the GUI's queue receives `Event_wake' (54) at once,
		instead of the worker's result waiting for the next heartbeat.

		The pump to wake is the thread that opened the main window
		(`SHELL_WINDOW' claims it) or, for a windowless host, the thread
		that called `claim_pump_thread'. Wakes coalesce: while one is
		waiting to be handled, more post nothing, so a busy worker cannot
		flood the queue. The heartbeat clears a stuck flag, so a lost
		message costs at most one tick.

		State lives in C, process-wide, which is what lets an object on
		any processor reach the one pump.
	]"

class
	SHELL_WAKE

feature -- Access

	Event_wake: INTEGER = 54
			-- The queue event a wake becomes.

	Outcome_none: INTEGER = 0
			-- Nobody to wake: no window open and no thread claimed.

	Outcome_posted: INTEGER = 1
			-- The pump was woken.

	Outcome_coalesced: INTEGER = 2
			-- A wake was already pending; this one merged into it.

	last_outcome: INTEGER
			-- What the last `wake' did.

feature -- Basic operations

	wake
			-- Make the pump return now with `Event_wake'.
		do
			last_outcome := c_wake
		ensure
			known_outcome: last_outcome >= Outcome_none and last_outcome <= Outcome_coalesced
		end

	claim_pump_thread
			-- Make the calling thread the one `wake' reaches: for a host
			-- that pumps without a main window (`SHELL_DESKTOP.pump_for').
			-- Clears any pending wake.
		do
			c_claim (1)
		end

	release_pump_thread
			-- Forget the claimed thread; with no main window, `wake' then
			-- reaches nobody.
		do
			c_claim (0)
		end

feature {NONE} -- Externals

	c_wake: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_wake();"
		end

	c_claim (a_on: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_claim_pump_thread((int)$a_on);"
		end

end
