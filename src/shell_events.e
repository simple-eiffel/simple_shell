note
	description: "[
		Every number the native queue carries, in one place (pushed up
		2026-10-25: the numbers lived in SHELL_WINDOW, SHELL_PANEL,
		SHELL_TRAY, SHELL_HOTKEYS, SHELL_APPEARANCE, SHELL_WAKE and
		SHELL_ACCESSIBILITY, 53 to 57 twice, and a new event had no list to
		take the next free number from). The C side pushes these numbers
		(Clib/simple_shell.h, `shell_push'). A NEW EVENT TAKES THE NEXT FREE
		NUMBER HERE, joins `registry', and only then goes into the header.

		The classes that own an event inherit this and keep their own short
		names by renaming (SHELL_PANEL's `Event_press' is
		`Event_panel_press' here, SHELL_TRAY's `Event_click' is
		`Event_tray_click', SHELL_APPEARANCE's `Event_changed' is
		`Event_appearance_changed').
	]"

deferred class
	SHELL_EVENTS

feature -- The main window

	Event_window_press: INTEGER = 2
	Event_window_char: INTEGER = 3
	Event_window_key: INTEGER = 4
	Event_window_expose: INTEGER = 6
	Event_tick: INTEGER = 7
			-- The heartbeat (`SHELL_WINDOW.heartbeat_ms').
	Event_window_double: INTEGER = 8
	Event_window_drag: INTEGER = 9
	Event_window_release: INTEGER = 10
	Event_window_context: INTEGER = 11
	Event_window_triple: INTEGER = 12
	Event_window_move: INTEGER = 13
	Event_window_leave: INTEGER = 14
	Event_window_wheel: INTEGER = 15
			-- Delta in `SHELL_WINDOW.event_extra'.
	Event_window_resize: INTEGER = 16
	Event_window_middle: INTEGER = 17
	Event_window_drop: INTEGER = 18
	Event_fast_tick: INTEGER = 25
			-- The app-settable fast tick.

feature -- The status strip

	Event_strip_press: INTEGER = 21
	Event_strip_moved: INTEGER = 22
	Event_strip_expose: INTEGER = 23

feature -- The overlay (renumbered 2026-08-23 out of the main window's numbers)

	Event_overlay_move: INTEGER = 31
	Event_overlay_press: INTEGER = 32
	Event_overlay_release: INTEGER = 33
	Event_overlay_cancel: INTEGER = 34
			-- Escape, a right press or Alt+F4: the overlay is already hidden.
	Event_overlay_expose: INTEGER = 35
	Event_overlay_accept: INTEGER = 36
			-- Enter, in adjust mode.
	Event_overlay_arrow: INTEGER = 37
			-- An arrow key (its virtual key in the first field), in adjust mode.

feature -- Panels (`SHELL_PANEL'; the panel's slot in the third field)

	Event_panel_press: INTEGER = 41
	Event_panel_release: INTEGER = 42
	Event_panel_move: INTEGER = 43
	Event_panel_expose: INTEGER = 44
	Event_panel_wheel: INTEGER = 45
	Event_panel_right_press: INTEGER = 46
	Event_panel_moved: INTEGER = 47
	Event_panel_resized: INTEGER = 48
	Event_panel_moving: INTEGER = 49
			-- During a move: the panel's left and top now (1.14.0).
	Event_panel_dropped: INTEGER = 50
			-- Files dropped on the panel, at (x, y) in it (1.14.0).

feature -- The system

	Event_hotkey: INTEGER = 51
			-- A registered hot key (`SHELL_HOTKEYS').
	Event_tray_click: INTEGER = 52
			-- A tray icon clicked (`SHELL_TRAY').
	Event_appearance_changed: INTEGER = 53
			-- The Windows light/dark app setting flipped: first field 1
			-- dark, 0 light (`SHELL_APPEARANCE', 1.16.0).
	Event_wake: INTEGER = 54
			-- A processor called `SHELL_WAKE.wake' (1.18.0).
	Event_dwell: INTEGER = 55
			-- The dwell timer ran out: the pointer has rested (1.19.0).
	Event_contrast_changed: INTEGER = 56
			-- The Windows high-contrast switch flipped or its palette
			-- changed: first field 1 on, 0 off (1.20.0). Read it as "look
			-- again": one flip can arrive as two events (the setting change
			-- and the color change that follows), and a light/dark flip also
			-- changes the system colors, so it arrives with 0 while contrast
			-- is off. Re-read `SHELL_APPEARANCE.system_high_contrast' and
			-- `system_prefers_dark' rather than counting events.
	Event_motion_changed: INTEGER = 57
			-- The Windows animation setting flipped: first field 1 reduced,
			-- 0 not (1.21.0).
	Event_focus_request: INTEGER = 58
			-- A UI Automation client asked to move the focus: first field
			-- the node id. Pushed on the pump thread (`SHELL_ACCESSIBILITY').
	Event_refresh_request: INTEGER = 59
			-- A UI Automation client asked for the tree: republish. Once
			-- until the next `SHELL_ACCESSIBILITY.commit'.

feature -- The registry

	registry: ARRAY [INTEGER]
			-- Every event number above, for the test that no two collide.
		once
			Result := <<Event_window_press, Event_window_char, Event_window_key, Event_window_expose,
				Event_tick, Event_window_double, Event_window_drag, Event_window_release,
				Event_window_context, Event_window_triple, Event_window_move, Event_window_leave,
				Event_window_wheel, Event_window_resize, Event_window_middle, Event_window_drop,
				Event_fast_tick, Event_strip_press, Event_strip_moved, Event_strip_expose,
				Event_overlay_move, Event_overlay_press, Event_overlay_release, Event_overlay_cancel,
				Event_overlay_expose, Event_overlay_accept, Event_overlay_arrow,
				Event_panel_press, Event_panel_release, Event_panel_move, Event_panel_expose,
				Event_panel_wheel, Event_panel_right_press, Event_panel_moved, Event_panel_resized,
				Event_panel_moving, Event_panel_dropped,
				Event_hotkey, Event_tray_click, Event_appearance_changed, Event_wake, Event_dwell,
				Event_contrast_changed, Event_motion_changed, Event_focus_request, Event_refresh_request>>
		ensure
			every_event: Result.count = 46
		end

	next_free_event: INTEGER
			-- The number a new event takes.
		do
			across registry as ic_event loop
				Result := Result.max (ic_event)
			end
			Result := Result + 1
		end

end
