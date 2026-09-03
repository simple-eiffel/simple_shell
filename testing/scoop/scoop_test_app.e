note
	description: "[
		THE FREEZE ASSAULT (1.9.2). The vector test for a defect class
		proven in simple_winhttp on 2026-09-02 and found here by audit:
		EVERY external in this library that WAITS was declared plain
		`external "C inline"'.

		ISE's garbage collector stops every thread of the system before
		it collects; a thread inside a plain `external "C inline"' call
		is where the runtime can neither see it nor stop it, so the
		collection WAITS for that call to return and every other
		processor waits with it, at its very next allocation.

		This library's whole job is waiting. `SHELL_WINDOW.shell_pump'
		sits in `GetMessageW' until the desktop has a message;
		`SHELL_DESKTOP.pump_for' loops on `Sleep(5)' for the caller's
		span; `shell_text_menu' sits in `TrackPopupMenu' until the user
		picks; `shell_input_click' sleeps 120 ms so a target can act.
		Unmarked, each of them stopped every OTHER processor in the
		program for its whole duration.

		Four tests, in the order the argument runs:

		1-3  THE LAW (BLOCKING_PROBE). The same wait, three ways: an
		     Eiffel sleep costs the root nothing; an UNMARKED C call
		     costs it the whole wait; the same call MARKED `blocking'
		     costs it nothing again. Test 2 asserts the freeze exists -
		     it is the mechanism, and it passes before and after the fix.

		4    THE VECTOR. A real SHELL_DESKTOP.pump_for on its own
		     processor for three seconds, while the root does nothing
		     but allocate. Unmarked, the root's worst single allocation
		     was in the thousands of milliseconds. Marked, it is single
		     digits. `pump_for' is the vector because it needs no window
		     and no user, so this suite runs headless.

		THE BAR IS THE LIVE SET, AND THE ASK. An allocator that is never
		asked to collect can never be caught waiting for one, so every
		burst below KEEPS part of what it allocates - the heap grows and
		the collector has real work to do when it runs. A probe without a
		retained live set reports a false green.

		That alone is not enough. Leaving the collection to the runtime's
		own trigger made this instrument FLAKY - measured here on
		2026-09-02, roughly one run in four the runtime answered a whole
		six-second burst train out of a free list an earlier test had
		left it, never collected, and the UNMARKED wait scored 3 ms: the
		freeze reported as absent when it was merely unexercised. So each
		burst now ASKS, with `MEMORY.full_collect', inside the timed span.
		That is the honest probe for this defect: what the marker changes
		is whether a requested collection can proceed while another
		processor is inside C.
	]"
	author: "Larry Rix"

class
	SCOOP_TEST_APP

inherit
	PRECISE_CLOCK

create
	make

feature {NONE} -- Initialization

	make
			-- Run the assault.
		do
			print ("simple_shell freeze assault (SCOOP): a waiting external must not stop the collector%N%N")
			passed := 0
			failed := 0

			run_test (agent test_an_eiffel_sleep_on_another_processor_never_stops_the_allocator,
				"an Eiffel sleep on another processor never stops the allocator")
			run_test (agent test_an_unmarked_c_call_on_another_processor_stops_the_allocator,
				"an unmarked C call on another processor stops the allocator")
			run_test (agent test_a_blocking_marked_c_call_never_stops_the_allocator,
				"a blocking-marked C call never stops the allocator")
			run_test (agent test_a_windowless_pump_never_stops_another_processors_allocator,
				"a windowless pump never stops another processor's allocator")

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
				(create {EXCEPTIONS}).die (1)
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Tests: the law

	test_an_eiffel_sleep_on_another_processor_never_stops_the_allocator
			-- EXECUTION_ENVIRONMENT.sleep is marked for the runtime, so a
			-- processor asleep in it never holds the collector.
		local
			l_probe: separate BLOCKING_PROBE
			l_worst: INTEGER_64
			l_done: INTEGER
		do
			create l_probe.make
			launch_eiffel_sleeps (l_probe)
			l_worst := worst_allocation_burst (Bursts, Burst_gap_ms)
			l_done := waits_made (l_probe)
			print ("      an Eiffel sleep of " + Wait_ms.out
				+ " ms on another processor: worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the probe waited", l_done = Waits)
			assert ("a marked wait leaves the root's allocator alone (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

	test_an_unmarked_c_call_on_another_processor_stops_the_allocator
			-- THE MECHANISM. The same wait spent inside an unmarked external:
			-- the root's very next allocation waits for it. This is the freeze,
			-- and it is still true after the fix - which is the point. What
			-- changed in 1.9.2 is that simple_shell no longer makes one.
		local
			l_probe: separate BLOCKING_PROBE
			l_worst: INTEGER_64
			l_done: INTEGER
		do
			create l_probe.make
			launch_unmarked_c_sleeps (l_probe)
			l_worst := worst_allocation_burst (Bursts, Burst_gap_ms)
			l_done := waits_made (l_probe)
			print ("      an UNMARKED C call of " + Wait_ms.out
				+ " ms on another processor: worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the probe waited", l_done = Waits)
			assert ("an unmarked wait stops the root's allocator for very nearly that long ("
				+ l_worst.out + " ms)", l_worst >= Wait_ms // 2)
		end

	test_a_blocking_marked_c_call_never_stops_the_allocator
			-- THE FIX, in one keyword. The SAME Sleep, marked
			-- `external "C blocking inline"': the root allocates through it.
		local
			l_probe: separate BLOCKING_PROBE
			l_worst: INTEGER_64
			l_done: INTEGER
		do
			create l_probe.make
			launch_blocking_c_sleeps (l_probe)
			l_worst := worst_allocation_burst (Bursts, Burst_gap_ms)
			l_done := waits_made (l_probe)
			print ("      a BLOCKING-marked C call of " + Wait_ms.out
				+ " ms on another processor: worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the probe waited", l_done = Waits)
			assert ("the marker gives the collector the thread back (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

feature {NONE} -- Tests: the vector

	test_a_windowless_pump_never_stops_another_processors_allocator
			-- THE RED-THEN-GREEN. A real SHELL_DESKTOP.pump_for on its own
			-- processor for three seconds, while the root does nothing but
			-- allocate.
			--
			-- 1.9.1 (`pump_for' unmarked): worst allocation in the thousands
			-- of ms - the whole pump. 1.9.2 (marked `blocking'): single digits.
		local
			l_pumper: separate SHELL_PUMPER
			l_worst, l_pump_ms: INTEGER_64
			l_done: INTEGER
		do
			create l_pumper.make
			launch_pump (l_pumper, Waits, Wait_ms)
			l_worst := worst_allocation_burst (Bursts, Burst_gap_ms)
			l_done := pumps_made (l_pumper)
			l_pump_ms := pump_elapsed (l_pumper)
			print ("      a real SHELL_DESKTOP.pump_for of " + Wait_ms.out
				+ " ms on another processor (" + l_pump_ms.out
				+ " ms in the library): worst allocation on the root " + l_worst.out + " ms%N")
			assert ("the pumper pumped", l_done = Waits)
			assert ("the pump really lasted its span (" + l_pump_ms.out + " ms)",
				l_pump_ms >= (Waits * Wait_ms) * 8 // 10)
			assert ("no allocation on the root waited on the pump (" + l_worst.out + " ms)",
				l_worst <= Allocation_budget_ms)
		end

feature {NONE} -- The probe's processor (each a short, separate call)

	launch_eiffel_sleeps (a_probe: separate BLOCKING_PROBE)
			-- Start the marked sleeps; asynchronous.
		do
			a_probe.run_eiffel_sleeps (Waits, Wait_ms)
		end

	launch_unmarked_c_sleeps (a_probe: separate BLOCKING_PROBE)
			-- Start the unmarked C waits; asynchronous.
		do
			a_probe.run_unmarked_c_sleeps (Waits, Wait_ms)
		end

	launch_blocking_c_sleeps (a_probe: separate BLOCKING_PROBE)
			-- Start the marked C waits; asynchronous.
		do
			a_probe.run_blocking_c_sleeps (Waits, Wait_ms)
		end

	waits_made (a_probe: separate BLOCKING_PROBE): INTEGER
			-- How many waits the probe made. A query, so it joins the probe.
		do
			Result := a_probe.waits_done
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- The pumper's processor (each a short, separate call)

	launch_pump (a_pumper: separate SHELL_PUMPER; a_count, a_milliseconds: INTEGER)
			-- Start the real library pump; asynchronous, and only integers cross.
		require
			positive: a_count > 0 and a_milliseconds > 0
		do
			a_pumper.pump (a_count, a_milliseconds)
		end

	pumps_made (a_pumper: separate SHELL_PUMPER): INTEGER
			-- How many pumps it ran. A query, so it joins the pumper.
		do
			Result := a_pumper.pumps_done
		ensure
			non_negative: Result >= 0
		end

	pump_elapsed (a_pumper: separate SHELL_PUMPER): INTEGER_64
			-- How long the whole pump took, in milliseconds.
		do
			Result := a_pumper.elapsed_milliseconds
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- The root's own allocator

	worst_allocation_burst (a_bursts, a_gap_ms: INTEGER): INTEGER_64
			-- Allocate `a_bursts' times, `a_gap_ms' apart - each burst
			-- keeping part of what it allocated and then asking for a
			-- collection - and answer the longest single burst in
			-- milliseconds. Nothing here touches another processor: a burst
			-- that takes a second took it inside the runtime, waiting for a
			-- collection that cannot start.
		require
			positive: a_bursts > 0 and a_gap_ms > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			l_mem: MEMORY
			l_live: ARRAYED_LIST [STRING_8]
			l_junk: ARRAYED_LIST [STRING_8]
			i, k: INTEGER
			t0, l_span: INTEGER_64
		do
			create l_env
			create l_mem
			create l_live.make (a_bursts * Burst_kept)
			from
				i := 1
			until
				i > a_bursts
			loop
				t0 := now_ms
				create l_junk.make (Burst_strings)
				from
					k := 1
				until
					k > Burst_strings
				loop
					l_junk.extend (create {STRING_8}.make_filled ('x', Burst_string_bytes))
					if k <= Burst_kept then
							-- A live set that keeps growing, so the collector has
							-- something to mark and cannot answer every burst out
							-- of a free list it already owns.
						l_live.extend (l_junk.last)
					end
					k := k + 1
				variant
					Burst_strings + 1 - k
				end
					-- ASK for a collection, inside the timed span. Left to the
					-- runtime's own trigger this probe was flaky: a burst train
					-- answered out of an existing free list never collects, and
					-- an unmarked wait then scores single digits - a false green
					-- on the very test whose job is to prove the freeze exists.
				l_mem.full_collect
				l_span := now_ms - t0
				if l_span > Result then
					Result := l_span
				end
				l_env.sleep (a_gap_ms.to_integer_64 * 1_000_000)
				i := i + 1
			variant
				a_bursts + 1 - i
			end
			check kept_them_alive: l_live.count = a_bursts * Burst_kept end
		ensure
			non_negative: Result >= 0
		end

feature {NONE} -- Test runner

	run_test (a_test: PROCEDURE; a_name: STRING_8)
			-- Run one test; any exception (contract or otherwise) fails it.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as ex and then attached ex.description as d then
				print ("        " + d.to_string_8 + "%N")
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	assert (a_tag: STRING_8; a_condition: BOOLEAN)
			-- Raise unless `a_condition', so `run_test' records the failure.
		do
			if not a_condition then
				print ("        FAILED: " + a_tag + "%N")
				(create {EXCEPTIONS}).raise ("freeze assault: " + a_tag)
			end
		end

	passed, failed: INTEGER

feature -- Constants: the wait under test

	Waits: INTEGER = 1
			-- Waits the other processor makes.

	Wait_ms: INTEGER = 3_000
			-- How long each of them lasts.

feature -- Constants: the root's bursts

	Bursts: INTEGER = 60

	Burst_gap_ms: INTEGER = 100
			-- 60 x 100 ms = 6 s, twice the whole wait under test.

	Burst_strings: INTEGER = 2_000

	Burst_string_bytes: INTEGER = 1_024
			-- 2 MiB a burst: enough that the collector runs many times over.

	Burst_kept: INTEGER = 200
			-- 200 KiB of every burst is kept alive, so the heap grows and the
			-- collector has real work: an allocator that is never asked to
			-- collect can never be caught waiting for one.

feature -- Constants: the bar

	Allocation_budget_ms: INTEGER_64 = 500
			-- The bound, with margin. A frame is 16 ms; Windows ghosts a window
			-- that stops pumping for about five seconds. 500 ms is far under
			-- the harm and far over the noise - and the measured GREEN is
			-- single-digit, so nothing here is tuned to just barely pass.

end
