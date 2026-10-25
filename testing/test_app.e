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
			run_test (agent t.test_display_scale, "display_scale")
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
			run_test (agent t.test_wake_needs_a_pump_and_coalesces, "wake_needs_a_pump_and_coalesces")
			run_test (agent t.test_heartbeat_is_settable, "heartbeat_is_settable")
			run_test (agent t.test_dwell_fires_once_after_rest, "dwell_fires_once_after_rest")
			run_test (agent t.test_appearance_reads_the_windows_setting, "appearance_reads_the_windows_setting")
			run_test (agent t.test_appearance_change_is_queued, "appearance_change_is_queued")
			run_test (agent t.test_high_contrast_reads_the_windows_setting, "high_contrast_reads_the_windows_setting")
			run_test (agent t.test_system_colors_read_the_windows_palette, "system_colors_read_the_windows_palette")
			run_test (agent t.test_contrast_change_is_queued, "contrast_change_is_queued")
			run_test (agent t.test_dark_title_bar_on_a_real_window, "dark_title_bar_on_a_real_window")
			run_test (agent t.test_clipboard_image_roundtrip, "clipboard_image_roundtrip")
			run_test (agent t.test_clipboard_image_survives_repeated_round_trips, "clipboard_image_survives_repeated_round_trips")
			run_test (agent t.test_input_knows_the_desktop, "input_knows_the_desktop")
			run_test (agent t.test_input_keys_are_accepted, "input_keys_are_accepted")
			run_test (agent t.test_alt_keys_are_claimed, "alt_keys_are_claimed")
			run_test (agent t.test_panel_lifecycle, "panel_lifecycle")
			run_test (agent t.test_panel_capture_exclusion_really_hides, "panel_capture_exclusion_really_hides")
			run_test (agent t.test_panel_resize_grips, "panel_resize_grips")
			run_test (agent t.test_panel_handle_and_side_grips, "panel_handle_and_side_grips")
			run_test (agent t.test_panel_file_drop, "panel_file_drop")
			run_test (agent t.test_tray_clicks, "tray_clicks")
			run_test (agent t.test_hotkey_registers_and_delivers, "hotkey_registers_and_delivers")
			run_test (agent t.test_hotkey_conflict_is_reported, "hotkey_conflict_is_reported")
			run_test (agent t.test_monitors_enumerate, "monitors_enumerate")
			run_test (agent t.test_file_dialog_starts_empty, "file_dialog_starts_empty")
			run_test (agent t.test_system_alt_keys_are_left_alone, "system_alt_keys_are_left_alone")
			run_test (agent t.test_function_keys_and_ctrl_digits_are_the_windows, "function_keys_and_ctrl_digits_are_the_windows")
			run_test (agent t.test_f5_reaches_the_queue, "f5_reaches_the_queue")
			run_test (agent t.test_alt_letter_reaches_the_queue, "alt_letter_reaches_the_queue")
			run_test (agent t.test_sdk_macro_poison_is_armed, "sdk_macro_poison_is_armed")
			run_test (agent t.test_sdk_macro_tripwire, "sdk_macro_tripwire")

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
			if attached (create {EXCEPTION_MANAGER}).last_exception as al_e then
				if attached al_e.tag as al_tag then
					print ("        tag: " + al_tag.to_string_8 + "%N")
				end
				if attached al_e.description as al_why then
					print ("        why: " + al_why.to_string_8 + "%N")
				end
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	passed: INTEGER

	failed: INTEGER

end
