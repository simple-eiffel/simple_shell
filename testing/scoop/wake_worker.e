note
	description: "[
		A worker processor that sleeps, notes the time on the system-wide
		high-resolution counter, and wakes the pump - the shape of a real
		job that has a result ready (GW-26).
	]"

class
	WAKE_WORKER

create
	make

feature {NONE} -- Initialization

	make
		do
		ensure
			not_yet: woke_at_ms = 0
		end

feature -- Access

	woke_at_ms: INTEGER_64
			-- When `wake_after' called `SHELL_WAKE.wake'.

	outcome: INTEGER
			-- `SHELL_WAKE.last_outcome' of that call.

feature -- Basic operations

	wake_after (a_ms: INTEGER)
			-- Sleep `a_ms' milliseconds, then wake the pump.
		require
			positive: a_ms > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			l_clock: PRECISE_CLOCK
			l_wake: SHELL_WAKE
		do
			create l_env
			l_env.sleep (a_ms.to_integer_64 * 1_000_000)
			create l_clock
			create l_wake
			woke_at_ms := l_clock.now_ms
			l_wake.wake
			outcome := l_wake.last_outcome
		ensure
			stamped: woke_at_ms > 0
		end

end
