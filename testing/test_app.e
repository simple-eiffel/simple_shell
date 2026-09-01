note
	description: "Contract-assault runner for simple_shell."
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Assault the platform shell under full DBC.
		local
			t: SHELL_ASSAULT
		do
			print ("simple_shell contract assault (F_code -keep, all assertions live)%N%N")
			passed := 0
			failed := 0
			create t

			print ("=== PLATFORM SHELL ===%N")
			run_test (agent t.test_tray_lifecycle, "tray_lifecycle")
			run_test (agent t.test_desktop_metrics, "desktop_metrics")
			run_test (agent t.test_desktop_grab, "desktop_grab")
			run_test (agent t.test_clock, "clock")
			run_test (agent t.test_keys_answer, "keys_answer")
			run_test (agent t.test_clipboard_roundtrip, "clipboard_roundtrip")
			run_test (agent t.test_speller_degrades_never_fails, "speller_degrades_never_fails")
			run_test (agent t.test_speller_ignore_is_session_scoped, "speller_ignore_is_session_scoped")
			run_test (agent t.test_window_services_without_pump, "window_services_without_pump")
			run_test (agent t.test_cursor_kind_accepted, "cursor_kind_accepted")
			run_test (agent t.test_windowless_pump_returns_on_deadline, "windowless_pump_returns_on_deadline")
			run_test (agent t.test_outline_frames_really_create, "outline_frames_really_create")
			run_test (agent t.test_strip_window_really_creates, "strip_window_really_creates")
			run_test (agent t.test_queue_is_one_instance_across_units, "queue_is_one_instance_across_units")
			run_test (agent t.test_clipboard_image_roundtrip, "clipboard_image_roundtrip")
			run_test (agent t.test_input_knows_the_desktop, "input_knows_the_desktop")
			run_test (agent t.test_input_keys_are_accepted, "input_keys_are_accepted")

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Harness

	run_test (a_test: PROCEDURE; a_name: STRING)
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
			failed := failed + 1
			l_retried := True
			retry
		end

	passed: INTEGER

	failed: INTEGER

end
