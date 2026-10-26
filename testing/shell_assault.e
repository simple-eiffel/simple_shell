note
	description: "[
		The platform shell under assault: every service exercised for
		real - the desktop is grabbed, the clipboard round-trips, a
		strip window is genuinely created (offscreen), the spell
		checker is consulted. No mocks; this is the machine.
	]"

class
	SHELL_ASSAULT

inherit
	TEST_SET_BASE

feature -- Tray

	test_tray_lifecycle
			-- An icon installed, retitled, ballooned and removed; an
			-- environment that refuses the icon passes by degrading.
		local
			t: SHELL_TRAY
		do
			create t.make ("simple_shell assault")
			if t.is_installed then
				t.set_tooltip ("(3) simple_shell assault")
				t.balloon ("simple_shell", "The tray assault says hello.")
				assert ("numbered", t.id > 0)
				t.remove
				assert ("removed", not t.is_installed and t.handle = default_pointer)
				t.remove
				assert ("remove is idempotent", not t.is_installed)
			else
				assert ("no notification area in this session", True)
			end
		end

feature -- Desktop

	test_desktop_metrics
		local
			d: SHELL_DESKTOP
		do
			create d
			assert ("a desktop exists", d.virtual_width > 0)
			assert ("with height", d.virtual_height > 0)
		end

	test_display_scale
			-- Once DPI aware, the system DPI is a real value (96 at 100%, 144 at
			-- 150%) and the scale is that over 96.
		local
			d: SHELL_DESKTOP
		do
			create d
			d.become_dpi_aware
			assert ("a plausible DPI: " + d.system_dpi.out, d.system_dpi >= 96 and d.system_dpi <= 480)
			assert ("scale is dpi / 96", (d.dpi_scale - d.system_dpi / 96).abs < 1.0e-9)
		end

	test_desktop_grab
			-- Grab 4x4 real desktop pixels; the C side forces alpha
			-- opaque, so byte 3 of the first BGRA pixel must be 255.
		local
			d: SHELL_DESKTOP
			buf: MANAGED_POINTER
		do
			create d
			create buf.make (64)
			assert ("the desktop can be read",
				d.grab_into (d.virtual_x, d.virtual_y, 4, 4, buf.item, 16))
			assert_integers_equal ("alpha forced opaque", 255,
				buf.read_natural_8 (3).to_integer_32)
		end

	test_clock
		local
			d: SHELL_DESKTOP
			t1, t2: REAL_64
		do
			create d
			t1 := d.now_ms
			t2 := d.now_ms
			assert ("the clock runs", t1 > 0.0)
			assert ("and never backwards", t2 >= t1)
			assert ("minutes fit the day",
				d.minutes_of_day >= 0 and d.minutes_of_day < 1440)
		end

feature -- Keys

	test_keys_answer
		local
			k: SHELL_KEYS
			b: BOOLEAN
		do
			create k
			b := k.shift_down
			b := k.control_down
			b := k.alt_down
			assert ("all three modifiers answered without exception", True)
		end

feature -- Clipboard

	test_clipboard_roundtrip
		local
			c: SHELL_CLIPBOARD
			payload: STRING_32
		do
			create c
			create payload.make_from_string_general ("shell carve ")
			payload.append_code (0x2603)
			payload.append_string_general (" round trip")
			c.set_text (payload)
			assert ("the clipboard holds text", c.has_text)
			assert_strings_equal ("and returns the payload verbatim",
				payload, c.text)
		end

feature -- Speller

	test_speller_degrades_never_fails
		local
			s: SHELL_SPELLER
			r: ARRAYED_LIST [TUPLE [lo, hi: INTEGER]]
		do
			create s
			r := s.misspellings ("")
			assert_integers_equal ("empty text, no findings", 0, r.count)
			r := s.misspellings ("teh dogg barks")
			assert ("ranges ordered when present",
				across r as t all t.lo < t.hi end)
			assert ("suggestions capped at five",
				s.suggestions ("teh").count <= 5)
		end

	test_speller_ignore_is_session_scoped
			-- Teach Ignore on a nonsense word: its finding vanishes
			-- for the rest of the session. (Add is NOT tested - it
			-- writes the user's real Windows dictionary.)
		local
			s: SHELL_SPELLER
			had: BOOLEAN
		do
			create s
			had := not s.misspellings ("zzqqv here").is_empty
			if had then
				assert ("the checker accepts the lesson", s.ignore ("zzqqv"))
				assert ("and the finding is gone this session",
					s.misspellings ("zzqqv here").is_empty)
			else
				assert ("no checker on this box - nothing to teach", True)
			end
		end

feature -- Window services

	test_window_services_without_pump
		local
			w: SHELL_TEST_WINDOW
			paths: ARRAYED_LIST [STRING_32]
		do
			create w
			assert ("no window yet", w.hwnd = default_pointer)
			assert ("the tick clock runs", w.tick_ms > 0)
			paths := w.take_dropped_paths
			assert ("no drops pending", paths.is_empty)
			assert ("a missing font is refused, not accepted",
				not w.add_font ("no_such_font_file.ttf"))
		end

	test_cursor_kind_accepted
		local
			w: SHELL_TEST_WINDOW
		do
			create w
			w.set_cursor_kind (w.Cursor_ibeam)
			w.set_cursor_kind (w.Cursor_arrow)
			assert ("cursor kinds accepted across the range", True)
		end

	test_windowless_pump_returns_on_deadline
		local
			d: SHELL_DESKTOP
			t0: REAL_64
		do
			create d
			t0 := d.now_ms
			d.pump_for (60)
			assert ("the deadline is honoured", d.now_ms - t0 >= 55.0)
			assert ("and not wildly overshot", d.now_ms - t0 < 1000.0)
		end

	test_outline_frames_really_create
			-- A REAL click-through frame, parked far offscreen:
			-- shown, reshown (move path), hidden - and hide_all is
			-- always safe, windows or none.
		local
			o: SHELL_OUTLINES
		do
			create o
			o.show (0, -3000, -3000, 60, 40, 3, 0xFF8800)
			o.show (0, -2900, -3000, 80, 50, 2, 0x00FF88)
			o.hide (0)
			o.hide_all
			assert ("outline lifecycle survived", True)
		end

	test_strip_window_really_creates
			-- A REAL topmost tool window, parked far offscreen and
			-- never activated - creation, DC, release, hide.
		local
			s: SHELL_STRIP
			d: POINTER
		do
			create s
			s.show (-3000, -3000, 4, 4)
			assert ("the strip window exists", s.handle /= default_pointer)
			d := s.dc
			assert ("and yields a device context", d /= default_pointer)
			s.release_dc (d)
			s.hide
		end

feature -- Panels (1.11.0)

	test_panel_lifecycle
			-- A REAL panel, parked far offscreen: opened hidden, shown, made
			-- translucent and click-through and draggable, moved, hidden,
			-- closed, and its slot reused.
		local
			p: SHELL_PANEL
		do
			create p.make
			p.open (-3000, -3000, 40, 20)
			assert ("opened", p.is_open and p.handle /= default_pointer)
			assert ("hidden until shown", not p.is_visible)
			assert ("opaque from birth", p.opacity = 255)
			p.show (-3000, -3000, 40, 20)
			assert ("shown", p.is_visible)
			assert ("pointer never over an offscreen panel", not p.is_cursor_over)
			p.set_opacity (180)
			assert ("translucent", p.opacity = 180)
			p.set_click_through (True)
			assert ("click-through", p.is_click_through)
			p.set_click_through (False)
			assert ("clickable again", not p.is_click_through)
			p.set_draggable (True)
			assert ("draggable", p.is_draggable)
			p.place (-2900, -3000, 60, 24)
			assert ("moved, still visible", p.x = -2900 and p.width = 60 and p.is_visible)
			p.hide
			assert ("hidden", not p.is_visible)
			p.close
			assert ("closed", not p.is_open and not p.is_draggable)
			assert ("pointer never over a closed panel", not p.is_cursor_over)
			p.open (-3000, -3000, 10, 10)
			assert ("slot reused", p.is_open)
			p.close
		end

	test_panel_resize_grips
			-- A REAL panel, offscreen: Shift+press regions (grips at edges and corners,
			-- the middle moves), the grip switched off, geometry read back after
			-- the window changed, and resizing tied to dragging.
		local
			p: SHELL_PANEL
		do
			create p.make
			p.open (-3000, -3000, 200, 100)
			assert ("moves by default", p.grip_at (100, 50) = p.Grip_move and p.grip_at (1, 1) = p.Grip_move)
			p.set_draggable (True)
			p.set_resizable (10, 80, 40)
			assert ("resizable", p.is_resizable)
			assert ("middle moves", p.grip_at (100, 50) = p.Grip_move)
			assert ("left edge", p.grip_at (3, 50) = p.Grip_left)
			assert ("right edge", p.grip_at (195, 50) = p.Grip_right)
			assert ("top edge", p.grip_at (100, 2) = p.Grip_top)
			assert ("bottom edge", p.grip_at (100, 95) = p.Grip_bottom)
			assert ("corners", p.grip_at (2, 2) = p.Grip_top_left and p.grip_at (198, 2) = p.Grip_top_right
				and p.grip_at (2, 98) = p.Grip_bottom_left and p.grip_at (198, 98) = p.Grip_bottom_right)
			assert ("just inside the grip", p.grip_at (10, 50) = p.Grip_move)
			p.set_fixed_size
			assert ("grips off", not p.is_resizable and p.grip_at (3, 50) = p.Grip_move)
			p.set_resizable (10, 80, 40)
			p.set_draggable (False)
			assert ("no resize without drag", not p.is_resizable)
			p.show (-3000, -3000, 200, 100)
			p.place (-2950, -2990, 240, 120)
			p.sync_geometry
			assert ("geometry read back", p.x = -2950 and p.y = -2990 and p.width = 240 and p.height = 120)
			p.close
			assert ("closed", not p.is_open and not p.is_resizable)
		end

	test_tray_clicks
			-- 1.14.0: a click on the icon becomes event 52 with the button and the icon's id.
		local
			t: SHELL_TRAY
			w: SHELL_TEST_WINDOW
		do
			create t.make ("simple_shell click assault")
			create w
			if t.is_installed then
				t.simulate_click (t.Click_left)
				assert ("a left click arrives", w.drain_event (t.Event_click, t.Click_left))
				assert ("carrying the icon's id", w.last_extra = t.id)
				t.simulate_click (t.Click_right)
				assert ("a right click arrives", w.drain_event (t.Event_click, t.Click_right) and w.last_extra = t.id)
				t.remove
			else
				assert ("no notification area in this session", True)
			end
		end

	test_panel_file_drop
			-- 1.14.0, a REAL panel offscreen: a drop becomes event 50 at the drop point, the
			-- paths waiting in the shared drop buffer.
		local
			p: SHELL_PANEL
			w: SHELL_TEST_WINDOW
			l_paths: ARRAYED_LIST [STRING_32]
		do
			create p.make
			create w
			p.open (-3000, -3000, 200, 100)
			p.show (-3000, -3000, 200, 100)
			assert ("refuses files at first", not p.accepts_files)
			p.set_accepts_files (True)
			assert ("accepts files", p.accepts_files)
			p.simulate_drop (30, 40, {STRING_32} "C:/scripts/one.md%NC:/scripts/two words.txt")
			assert ("dropped at the point", w.drain_event (p.Event_dropped, 30) and w.last_second = 40)
			assert ("from this panel", w.last_extra = p.slot)
			l_paths := w.take_dropped_paths
			assert ("both paths", l_paths.count = 2)
			assert ("in order", l_paths [1].same_string ({STRING_32} "C:/scripts/one.md")
				and l_paths [2].same_string ({STRING_32} "C:/scripts/two words.txt"))
			assert ("taken once", w.take_dropped_paths.is_empty)
			p.set_accepts_files (False)
			assert ("refuses again", not p.accepts_files)
			p.close
		end

	test_panel_handle_and_side_grips
			-- 1.14.0, a REAL panel offscreen: a handle drags on a plain press and keeps its moves
			-- to one axis; side grips size on a plain press; Shift keeps its old meaning.
		local
			p: SHELL_PANEL
			l_to: TUPLE [x, y: INTEGER]
		do
			create p.make
			p.open (-3000, -3000, 200, 100)
			p.show (-3000, -3000, 200, 100)
			assert ("a plain press clicks", p.press_grip_at (100, 50, False) = p.Grip_none)
			p.set_drags_on_press (True)
			assert ("a handle moves on a plain press", p.press_grip_at (100, 50, False) = p.Grip_move
				and p.press_grip_at (2, 50, False) = p.Grip_move)
			l_to := p.axis_result (40, 25)
			assert ("free by default", l_to.x = -2960 and l_to.y = -2975)
			p.set_drag_axis (p.Axis_horizontal)
			l_to := p.axis_result (40, 25)
			assert ("slides only left and right", l_to.x = -2960 and l_to.y = -3000)
			p.set_drag_axis (p.Axis_vertical)
			l_to := p.axis_result (40, 25)
			assert ("up and down only", l_to.x = -3000 and l_to.y = -2975)
			p.set_drags_on_press (False)
			p.set_drag_axis (p.Axis_free)
			p.set_draggable (True)
			p.set_resizable (10, 80, 40)
			assert ("no side grips yet: a click", p.press_grip_at (3, 50, False) = p.Grip_none)
			p.set_sides_size_on_press (True)
			assert ("left side sizes", p.press_grip_at (3, 50, False) = p.Grip_left)
			assert ("right side sizes", p.press_grip_at (195, 50, False) = p.Grip_right)
			assert ("top is still a click", p.press_grip_at (100, 2, False) = p.Grip_none)
			assert ("middle is still a click", p.press_grip_at (100, 50, False) = p.Grip_none)
			assert ("Shift still moves", p.press_grip_at (100, 50, True) = p.Grip_move)
			assert ("Shift still sizes the top", p.press_grip_at (100, 2, True) = p.Grip_top)
			assert ("no bottom grip yet: a click", p.press_grip_at (100, 97, False) = p.Grip_none)
			p.set_bottom_sizes_on_press (True)
			assert ("bottom sizes (1.15.0)", p.press_grip_at (100, 97, False) = p.Grip_bottom)
			assert ("top is still a click with the bottom grip", p.press_grip_at (100, 2, False) = p.Grip_none)
			assert ("above the bottom grip is a click", p.press_grip_at (100, 85, False) = p.Grip_none)
			p.close
			assert ("closed: plain again", not p.drags_on_press and not p.sides_size_on_press
				and not p.bottom_sizes_on_press and p.drag_axis = p.Axis_free)
		end

	test_panel_capture_exclusion_really_hides
			-- A red panel on screen appears in a screen grab; once excluded from
			-- capture it does not (Windows 10 2004+). The grab is BitBlt with
			-- CAPTUREBLT, the same path screen recorders and meeting apps use.
		local
			p: SHELL_PANEL
			d: SHELL_DESKTOP
			l_before, l_after: INTEGER
		do
			create p.make
			create d
			p.open (40, 40, 48, 48)
			p.show (40, 40, 48, 48)
			p.fill (0xFF0000)
			d.pump_for (150)
			p.fill (0xFF0000)
			l_before := red_pixels (d, 52, 52, 24, 24)
			p.request_capture_exclusion
			d.pump_for (150)
			l_after := red_pixels (d, 52, 52, 24, 24)
			if p.capture_affinity = p.Affinity_excluded_from_captures then
					-- Thresholds are DPI-agnostic: this test process is not DPI aware, so
					-- on a scaled display the panel covers only part of the sampled square
					-- (measured 256 of 576 pixels at the first run).
				assert ("visible to captures before: " + l_before.out, l_before > 100)
				assert ("absent from captures after: " + l_after.out, l_after < 50)
			else
				assert ("older Windows: at least blacked out", p.capture_affinity = p.Affinity_black_in_captures)
			end
			p.allow_capture
			assert ("capture allowed again", p.capture_affinity = p.Affinity_none)
			p.close
		end

feature -- Hotkeys (1.11.0)

	test_hotkey_registers_and_delivers
			-- An unlikely chord (Ctrl+Alt+Shift+F24) is registered; the message
			-- Windows sends for it becomes event 51 with id, key and modifiers.
		local
			k: SHELL_HOTKEYS
			d: SHELL_DESKTOP
			w: SHELL_TEST_WINDOW
			l_mods: INTEGER
		do
			create k.make
			create d
			create w
			l_mods := k.Mod_control | k.Mod_alt | k.Mod_shift
			k.register (9001, l_mods, 0x87)
			assert ("registered", k.last_succeeded and k.is_registered (9001) and k.count = 1)
			k.simulate (9001, l_mods, 0x87)
			d.pump_for (30)
			assert ("delivered as event 51", w.drain_event (k.Event_hotkey, 9001))
			assert ("key and modifiers carried", w.last_second = 0x87 and w.last_extra = l_mods)
			k.unregister (9001)
			assert ("released", not k.is_registered (9001) and k.count = 0)
		end

	test_hotkey_conflict_is_reported
			-- A chord already held (here by this process under another id) is
			-- refused and reported, never silently lost.
		local
			k: SHELL_HOTKEYS
			l_mods: INTEGER
		do
			create k.make
			l_mods := k.Mod_control | k.Mod_alt | k.Mod_shift
			k.register (9002, l_mods, 0x86)
			assert ("first holder", k.last_succeeded)
			k.register (9003, l_mods, 0x86)
			assert ("second refused", not k.last_succeeded and not k.is_registered (9003))
			k.unregister_all
			assert ("all released", k.count = 0)
		end

feature -- File dialog (1.11.0)

	test_file_dialog_starts_empty
			-- The dialog itself is modal and needs a person; what can be proved
			-- headless is that nothing is chosen before it is shown.
		local
			f: SHELL_FILE_DIALOG
		do
			create f.make
			assert ("nothing chosen", not f.has_choice and f.chosen_path.is_empty)
		end

feature -- Monitors (1.11.0)

	test_monitors_enumerate
			-- At least one display; exactly one primary, whose top-left is the
			-- virtual-screen origin; a device name; the work area inside the bounds.
		local
			m: SHELL_MONITORS
			i, l_primaries: INTEGER
		do
			create m.make
			assert ("a display", m.count >= 1)
			from i := 1 until i > m.count loop
				if m.is_primary (i) then
					l_primaries := l_primaries + 1
				end
				assert ("work area inside bounds", m.work_left (i) >= m.left (i) and m.work_right (i) <= m.right (i)
					and m.work_top (i) >= m.top (i) and m.work_bottom (i) <= m.bottom (i))
				assert ("named", m.device_name (i).count > 0)
				i := i + 1
			end
			assert ("one primary", l_primaries = 1)
			assert ("primary holds the origin", m.index_at (0, 0) = m.primary_index)
		end

feature {NONE} -- Panel probes

	red_pixels (a_desktop: SHELL_DESKTOP; a_x, a_y, a_w, a_h: INTEGER): INTEGER
			-- Pure-red pixels in a screen grab of the given region.
		local
			l_bits: MANAGED_POINTER
			l_px: NATURAL_32
			i: INTEGER
		do
			create l_bits.make (a_w * a_h * 4)
			if a_desktop.grab_into (a_x, a_y, a_w, a_h, l_bits.item, a_w * 4) then
				from i := 0 until i >= a_w * a_h loop
					l_px := l_bits.read_natural_32 (i * 4)
					if (l_px & 0x00FFFFFF) = 0x00FF0000 then
						Result := Result + 1
					end
					i := i + 1
				end
			end
		end

feature -- Wake and heartbeat (1.18.0, GW-26)

	test_wake_needs_a_pump_and_coalesces
			-- No window and no claimed thread: nobody to wake. Claimed: the
			-- first wake posts, the next ones merge into it, one event 54
			-- comes out of a pump, and after it the next wake posts again.
		local
			k: SHELL_WAKE
			d: SHELL_DESKTOP
			w: SHELL_TEST_WINDOW
		do
			create k
			create d
			create w
			k.release_pump_thread
			k.wake
			assert_integers_equal ("nobody to wake", k.Outcome_none, k.last_outcome)
			k.claim_pump_thread
			k.wake
			assert_integers_equal ("first wake posts", k.Outcome_posted, k.last_outcome)
			k.wake
			assert_integers_equal ("second merges", k.Outcome_coalesced, k.last_outcome)
			k.wake
			assert_integers_equal ("third merges", k.Outcome_coalesced, k.last_outcome)
			d.pump_for (30)
			assert_true ("one event 54 came out", w.drain_event (k.Event_wake, 0))
			assert_false ("and only one", w.drain_event (k.Event_wake, 0))
			k.wake
			assert_integers_equal ("after it, the next wake posts", k.Outcome_posted, k.last_outcome)
			d.pump_for (30)
			assert_true ("and arrives", w.drain_event (k.Event_wake, 0))
			k.release_pump_thread
			assert_integers_equal ("the window names the same event", k.Event_wake, w.Event_wake)
		end

	test_heartbeat_is_settable
		local
			w: SHELL_TEST_WINDOW
		do
			create w
			assert_integers_equal ("250 ms by default", 250, w.heartbeat_ms)
			w.set_heartbeat_ms (100)
			assert_integers_equal ("now 100", 100, w.heartbeat_ms)
			w.set_heartbeat_ms (250)
		end

feature -- Dwell timer (1.19.0, GW-08)

	test_dwell_fires_once_after_rest
			-- Armed on every "move", the shot keeps being replaced and
			-- nothing fires; once the arming stops, ONE event 55 comes out
			-- and the timer is spent. A cancelled shot never fires.
		local
			d: SHELL_DESKTOP
			w: SHELL_TEST_WINDOW
		do
			create d
			create w
			assert_integers_equal ("event 55", 55, w.Event_dwell)
			w.cancel_dwell_timer
			from until not w.drain_event (w.Event_dwell, 0) loop end
			w.arm_dwell_timer (40)
			assert_true ("armed", w.is_dwell_timer_armed)
			d.pump_for (15)
			w.arm_dwell_timer (40)
			d.pump_for (15)
			w.arm_dwell_timer (40)
			d.pump_for (15)
			assert_false ("re-armed before it ran out: nothing yet", w.drain_event (w.Event_dwell, 0))
			assert_true ("still pending", w.is_dwell_timer_armed)
			d.pump_for (150)
			assert_true ("rested: it fired", w.drain_event (w.Event_dwell, 0))
			assert_false ("once", w.drain_event (w.Event_dwell, 0))
			assert_false ("and is spent", w.is_dwell_timer_armed)
			d.pump_for (100)
			assert_false ("a spent shot never fires again", w.drain_event (w.Event_dwell, 0))
			w.arm_dwell_timer (30)
			w.cancel_dwell_timer
			assert_false ("cancelled", w.is_dwell_timer_armed)
			d.pump_for (100)
			assert_false ("a cancelled shot never fires", w.drain_event (w.Event_dwell, 0))
		end

feature -- Appearance (1.16.0, GW-27)

	test_appearance_reads_the_windows_setting
			-- `system_prefers_dark' agrees with reg.exe's own reading of
			-- AppsUseLightTheme: 0x0 is dark, anything else (or no value)
			-- is light.
		local
			a: SHELL_APPEARANCE
			env: EXECUTION_ENVIRONMENT
			f: PLAIN_TEXT_FILE
			l_out: STRING
			l_path: STRING_32
		do
			create a
			create env
			l_path := temp_path ("shell_appearance_reg.txt")
			env.system ("C:\Windows\System32\reg.exe query %"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize%" /v AppsUseLightTheme > %"" + l_path.to_string_8 + "%" 2>&1")
			create f.make_with_name (l_path)
			assert ("reg.exe answered", f.exists)
			create l_out.make_empty
			f.open_read
			from until f.end_of_file loop
				f.read_line
				if f.last_string.has_substring ("AppsUseLightTheme") then
					l_out := f.last_string.twin
				end
			end
			f.close
			f.delete
			if l_out.is_empty then
				assert ("no value: Windows' default, light", not a.system_prefers_dark)
			else
				l_out.right_adjust
				assert ("dark exactly when reg.exe reads 0x0: " + l_out,
					a.system_prefers_dark = l_out.ends_with ("0x0"))
			end
		end

	test_appearance_change_is_queued
			-- The WM_SETTINGCHANGE path: "ImmersiveColorSet" (any case)
			-- pushes event 53 carrying the setting as it stands; any other
			-- area pushes nothing.
		local
			a: SHELL_APPEARANCE
			w: SHELL_TEST_WINDOW
		do
			create a
			create w
			assert_true ("the color set is reported", a.report_setting_change ("ImmersiveColorSet"))
			assert_true ("event 53 carries the setting", w.drain_event (a.Event_changed, a.system_prefers_dark.to_integer))
			assert_true ("case does not matter", a.report_setting_change ("immersivecolorset"))
			assert_true ("and it is queued too", w.drain_event (a.Event_changed, a.system_prefers_dark.to_integer))
			assert_false ("another area is not", a.report_setting_change ("Policy"))
			assert_false ("and nothing was queued for it",
				w.drain_event (a.Event_changed, 0) or w.drain_event (a.Event_changed, 1))
			assert_integers_equal ("the window names the same event", a.Event_changed, w.Event_appearance_changed)
		end

	test_high_contrast_reads_the_windows_setting
			-- `system_high_contrast' agrees with reg.exe's reading of the
			-- HighContrast Flags value: bit 1 (HCF_HIGHCONTRASTON) is on.
		local
			a: SHELL_APPEARANCE
			l_value: STRING
		do
			create a
			l_value := reg_value ("HKCU\Control Panel\Accessibility\HighContrast", "Flags")
			assert ("reg.exe read the flags", l_value.is_integer)
			assert ("on exactly when bit 1 is set: " + l_value,
				a.system_high_contrast = (l_value.to_integer \\ 2 = 1))
		end

	test_system_colors_read_the_windows_palette
			-- `system_color' answers 0xRRGGBB, agreeing with reg.exe's "R G B"
			-- reading of the Window and WindowText colors.
		local
			a: SHELL_APPEARANCE
		do
			create a
			assert_true ("the window color matches the registry",
				a.system_color (a.Color_window) = rgb_of (reg_value ("HKCU\Control Panel\Colors", "Window")))
			assert_true ("the window text color matches the registry",
				a.system_color (a.Color_window_text) = rgb_of (reg_value ("HKCU\Control Panel\Colors", "WindowText")))
		end

	test_contrast_change_is_queued
			-- The WM_SETTINGCHANGE path: SPI_SETHIGHCONTRAST pushes event 56
			-- carrying the switch as it stands; another action pushes nothing.
			-- The WM_SYSCOLORCHANGE path pushes it too.
		local
			a: SHELL_APPEARANCE
			w: SHELL_TEST_WINDOW
		do
			create a
			create w
			assert_true ("the switch is reported", a.report_contrast_change (a.Spi_set_high_contrast))
			assert_true ("event 56 carries the switch", w.drain_event (a.Event_contrast_changed, a.system_high_contrast.to_integer))
			assert_false ("another action is not", a.report_contrast_change (0x14))
			assert_false ("and nothing was queued for it",
				w.drain_event (a.Event_contrast_changed, 0) or w.drain_event (a.Event_contrast_changed, 1))
			a.report_system_colors_change
			assert_true ("a palette change is queued", w.drain_event (a.Event_contrast_changed, a.system_high_contrast.to_integer))
			assert_integers_equal ("the window names the same event", a.Event_contrast_changed, w.Event_contrast_changed)
		end

	test_motion_change_is_queued
			-- The WM_SETTINGCHANGE path: SPI_SETCLIENTAREAANIMATION pushes
			-- event 57 carrying the setting as it stands; another action
			-- pushes nothing.
		local
			a: SHELL_APPEARANCE
			w: SHELL_TEST_WINDOW
		do
			create a
			create w
			assert_true ("the setting is reported", a.report_motion_change (a.Spi_set_client_area_animation))
			assert_true ("event 57 carries it", w.drain_event (a.Event_motion_changed, a.system_reduces_motion.to_integer))
			assert_false ("the contrast action is not", a.report_motion_change (a.Spi_set_high_contrast))
			assert_false ("and nothing was queued for it",
				w.drain_event (a.Event_motion_changed, 0) or w.drain_event (a.Event_motion_changed, 1))
			assert_integers_equal ("the window names the same event", a.Event_motion_changed, w.Event_motion_changed)
		end

	test_reduced_motion_reads_the_windows_setting
			-- `system_reduces_motion' agrees with PowerShell's own call of
			-- SystemParametersInfo (a second, independent reading).
		local
			a: SHELL_APPEARANCE
			env: EXECUTION_ENVIRONMENT
			f: PLAIN_TEXT_FILE
			l_path: STRING_32
			l_out: STRING
		do
			create a
			create env
			l_path := temp_path ("shell_motion.txt")
			env.system ("C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command %"Add-Type -Namespace W -Name S -MemberDefinition '[DllImport(\%"user32.dll\%")] public static extern bool SystemParametersInfo(uint a, uint b, ref bool c, uint d);'; $v = $true; [void][W.S]::SystemParametersInfo(0x1042, 0, [ref]$v, 0); $v%" > %"" + l_path.to_string_8 + "%" 2>&1")
			create f.make_with_name (l_path)
			assert ("PowerShell answered", f.exists)
			create l_out.make_empty
			f.open_read
			from until f.end_of_file loop
				f.read_line
				if f.last_string.has_substring ("True") or f.last_string.has_substring ("False") then
					l_out := f.last_string.twin
				end
			end
			f.close
			f.delete
			l_out.left_adjust
			l_out.right_adjust
			assert ("PowerShell read the setting: " + l_out, l_out.same_string ("True") or l_out.same_string ("False"))
			assert ("reduced exactly when animation is off", a.system_reduces_motion = l_out.same_string ("False"))
		end

	test_uia_bridge_serves_the_published_tree
			-- A UI Automation client, on its own thread, reads back the tree
			-- published for a hidden probe window on the shipped window
			-- procedure: names, control types, a value, a nested node, and
			-- the node told to hold the focus. Disabled, it reads nothing.
		local
			acc: SHELL_ACCESSIBILITY
			h: POINTER
			l_seen: STRING_32
		do
			h := uia_probe_window
			assert ("a probe window", h /= default_pointer)
			create acc
			acc.begin_tree (8)
			acc.add_node (0, 0, acc.Role_pane, "probe", Void, 0.0, 0.0, 400.0, 300.0, False, True)
			acc.add_node (1, 0, acc.Role_button, "Search", Void, 10.0, 10.0, 80.0, 30.0, True, True)
			acc.add_node (2, 0, acc.Role_text, "Genesis 1:1", Void, 10.0, 50.0, 200.0, 20.0, False, True)
			acc.add_node (3, 0, acc.Role_edit, "Notes", "In the beginning", 10.0, 80.0, 200.0, 30.0, True, True)
			acc.add_node (4, 3, acc.Role_text, "inner", Void, 12.0, 82.0, 50.0, 20.0, False, True)
			acc.commit (h)
			assert_integers_equal ("five rows served", 5, acc.served_rows)
			assert_true ("the edit row reads back", acc.served_name (acc.served_row_of (3)).same_string ("Notes")
				and acc.served_value (acc.served_row_of (3)).same_string ("In the beginning") and acc.served_parent (acc.served_row_of (4)) = 3)
			acc.focus_changed (3)
			l_seen := uia_read (h)
			print ("    a UI Automation client read:%N" + utf8 (l_seen))
			assert ("the client finished: " + utf8 (l_seen), not l_seen.starts_with ("!"))
			assert ("the button: " + utf8 (l_seen), l_seen.has_substring ("Search|50000%N"))
			assert ("the text: " + utf8 (l_seen), l_seen.has_substring ("Genesis 1:1|50020%N"))
			assert ("the edit with its value and the focus: " + utf8 (l_seen), l_seen.has_substring ("Notes|50004=In the beginning*%N"))
			assert ("the nested node: " + utf8 (l_seen), l_seen.has_substring ("inner|50020%N"))
			acc.disable
			assert ("stopped", not acc.is_serving)
			l_seen := uia_read (h)
			assert ("disabled: no published node: " + utf8 (l_seen), not l_seen.has_substring ("Search|"))
			uia_probe_close (h)
		end

	test_scan13_focus_request_is_pushed_on_the_pump_thread
			-- HIGH: a client's SetFocus pushed event 58 from UI Automation's
			-- thread onto the unsynchronized queue. Called from a worker, it
			-- now reaches the queue through the window procedure, on the
			-- thread that pumps.
		local
			acc: SHELL_ACCESSIBILITY
			h: POINTER
			w: SHELL_TEST_WINDOW
			l_hr: INTEGER
		do
			h := uia_probe_window
			create acc
			acc.begin_tree (2)
			acc.add_node (0, 0, acc.Role_pane, "probe", Void, 0.0, 0.0, 400.0, 300.0, False, True)
			acc.add_node (3, 0, acc.Role_edit, "Notes", "x", 10.0, 10.0, 100.0, 30.0, True, True)
			acc.commit (h)
			create w
			l_hr := uia_focus_from_worker (3)
			assert_integers_equal ("SetFocus answered S_OK, not " + l_hr.to_hex_string, 0, l_hr)
			assert_true ("pushed on the pump thread", uia_focus_pushed_here)
			assert_true ("event 58 names the node", w.drain_event (acc.Event_focus_request, 3))
			acc.disable
			uia_probe_close (h)
		end

	test_scan13_destroying_the_window_stops_serving
			-- MEDIUM: the table, the hook and the window handle outlived the
			-- window. Destroyed, it is served no more.
		local
			acc: SHELL_ACCESSIBILITY
			h: POINTER
		do
			h := uia_probe_window
			create acc
			acc.begin_tree (1)
			acc.add_node (0, 0, acc.Role_pane, "probe", Void, 0.0, 0.0, 400.0, 300.0, False, True)
			acc.commit (h)
			assert_true ("serving its window", acc.is_serving and acc.served_window = h)
			uia_probe_close (h)
			assert_false ("the window gone, nothing served", acc.is_serving)
			assert_true ("and no window named", acc.served_window = default_pointer)
		end

	test_scan13_a_client_request_asks_for_a_republish
			-- A client's WM_GETOBJECT pushes event 59 once until the next
			-- commit, so a window that renders only on input can refresh.
		local
			acc: SHELL_ACCESSIBILITY
			h: POINTER
			w: SHELL_TEST_WINDOW
			l_seen: STRING_32
		do
			h := uia_probe_window
			create acc
			acc.begin_tree (2)
			acc.add_node (0, 0, acc.Role_pane, "probe", Void, 0.0, 0.0, 400.0, 300.0, False, True)
			acc.add_node (1, 0, acc.Role_button, "Search", Void, 10.0, 10.0, 80.0, 30.0, True, True)
			acc.commit (h)
			create w
			from until not w.drain_event (acc.Event_refresh_request, 0) loop end
			l_seen := uia_read (h)
			assert ("read: " + utf8 (l_seen), l_seen.has_substring ("Search|50000"))
			assert_true ("event 59 asked for a republish", w.drain_event (acc.Event_refresh_request, 0))
			assert_false ("only once until the next commit", w.drain_event (acc.Event_refresh_request, 0))
			acc.disable
			uia_probe_close (h)
		end

	test_dark_title_bar_on_a_real_window
			-- DWM accepts dark and light captions on a real (hidden,
			-- offscreen) window; a window not yet open only remembers.
		local
			a: SHELL_APPEARANCE
			p: SHELL_PANEL
			w: SHELL_TEST_WINDOW
		do
			create a
			create p.make
			p.open (-3000, -3000, 40, 20)
			assert_true ("opened", p.is_open)
			a.set_dark_title_bar (p.handle, True)
			assert_true ("DWM took dark", a.last_title_bar_applied)
			a.set_dark_title_bar (p.handle, False)
			assert_true ("DWM took light", a.last_title_bar_applied)
			p.close
			create w
			w.set_dark_title_bar (True)
			assert_true ("remembered before the window opens", w.title_bar_is_dark)
		end

feature {NONE} -- Appearance helpers

	utf8 (a_text: STRING_32): STRING_8
			-- `a_text' as UTF-8, for an assertion tag.
		do
			Result := (create {UTF_CONVERTER}).utf_32_string_to_utf_8_string_8 (a_text)
		end

	uia_read (a_hwnd: POINTER): STRING_32
			-- What a UI Automation client reads under `a_hwnd': one line per
			-- descendant; "!timeout" or "!failed <hr>" when it could not.
		local
			l_buf: MANAGED_POINTER
			l_len: INTEGER
		do
			create l_buf.make (8192 * 2)
			l_len := c_uia_client_read (a_hwnd, l_buf.item, 8192)
			if l_len = -1 then
				Result := {STRING_32} "!timeout"
			elseif l_len = -2 then
				Result := {STRING_32} "!failed " + c_uia_client_hr.to_hex_string
			else
				Result := (create {NATIVE_STRING}.make_from_pointer (l_buf.item)).string
			end
		end

	uia_focus_from_worker (a_id: INTEGER): INTEGER
			-- The HRESULT of node `a_id''s SetFocus called from a worker; -1 no
			-- thread, -2 it did not finish.
		external
			"C inline use %"shell_uia_client.h%""
		alias
			"return (EIF_INTEGER)shell_uia_focus_from_worker((int)$a_id);"
		end

	uia_focus_pushed_here: BOOLEAN
		external
			"C inline use %"shell_uia_client.h%""
		alias
			"return (EIF_BOOLEAN)(shell_uia_focus_pushed_on_this_thread() != 0);"
		end

	uia_probe_window: POINTER
		external
			"C inline use %"shell_uia_client.h%""
		alias
			"return shell_uia_probe_window();"
		end

	uia_probe_close (a_hwnd: POINTER)
		external
			"C inline use %"shell_uia_client.h%""
		alias
			"shell_uia_probe_close($a_hwnd);"
		end

	c_uia_client_read (a_hwnd, a_out: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"shell_uia_client.h%""
		alias
			"return shell_uia_client_read($a_hwnd, (wchar_t*)$a_out, (int)$a_cap);"
		end

	c_uia_client_hr: INTEGER
		external
			"C inline use %"shell_uia_client.h%""
		alias
			"return (EIF_INTEGER)s_uia_client_hr;"
		end

	reg_value (a_key, a_name: STRING): STRING
			-- The data of value `a_name' under `a_key' as reg.exe prints it;
			-- empty when absent.
		local
			env: EXECUTION_ENVIRONMENT
			f: PLAIN_TEXT_FILE
			l_path: STRING_32
		do
			create Result.make_empty
			create env
			l_path := temp_path ("shell_reg_value.txt")
			env.system ("C:\Windows\System32\reg.exe query %"" + a_key + "%" /v " + a_name + " > %"" + l_path.to_string_8 + "%" 2>&1")
			create f.make_with_name (l_path)
			if f.exists then
				f.open_read
				from until f.end_of_file loop
					f.read_line
					if f.last_string.has_substring ("REG_SZ") then
						Result := f.last_string.substring (f.last_string.substring_index ("REG_SZ", 1) + 6, f.last_string.count)
					end
				end
				f.close
				f.delete
			end
			Result.left_adjust
			Result.right_adjust
		end

	rgb_of (a_triple: STRING): NATURAL_32
			-- "R G B" as 0xRRGGBB.
		local
			l_parts: LIST [STRING]
		do
			l_parts := a_triple.split (' ')
			assert_integers_equal ("three channels in " + a_triple, 3, l_parts.count)
			Result := (l_parts [1].to_natural_32 |<< 16) | (l_parts [2].to_natural_32 |<< 8) | l_parts [3].to_natural_32
		end

	temp_path (a_name: STRING): STRING_32
			-- `a_name' in the TEMP folder.
		local
			env: EXECUTION_ENVIRONMENT
		do
			create env
			if attached env.item ("TEMP") as al_temp then
				Result := al_temp.to_string_32 + {STRING_32} "\" + a_name.to_string_32
			else
				Result := a_name.to_string_32
			end
		end

feature -- Shared state

	test_queue_is_one_instance_across_units
			-- THE 1.8.0 LOCKUP LAW: an event pushed from one class's
			-- translation unit must come out of the pump's drain in
			-- another. Before SHELL_SHARED each generated C file held
			-- a PRIVATE copy of the queue - the overlay pushed where
			-- nobody drained, and the fullscreen picker became an
			-- inescapable input sink. This cannot pass on that build.
		local
			p: SHELL_PUSH_PROBE
			w: SHELL_TEST_WINDOW
		do
			create p
			create w
			p.push_marker
			assert ("the marker crossed translation units", w.drain_marker)
		end

feature -- Clipboard bitmap

	test_clipboard_image_roundtrip
			-- Put a synthetic 4x3 ARGB32 image on the clipboard, read its
			-- size back through the DIB header, then read the PIXELS back
			-- through `image_into': every one where it was put - the DIB is
			-- bottom-up on the clipboard and top-down on both sides of it -
			-- with alpha forced opaque on the way out. The pixels are given
			-- with alpha 0 (the C side must force them opaque) and coded by
			-- position, so a row put back in the wrong order is caught. A
			-- buffer sized for another bitmap is refused, never overrun.
		local
			c: SHELL_CLIPBOARD
			bits, back: MANAGED_POINTER
			row, col: INTEGER
			l_expected, l_got: NATURAL_32
			l_all: BOOLEAN
		do
			create c
			create bits.make (4 * 4 * 3)
			from row := 0 until row >= 3 loop
				from col := 0 until col >= 4 loop
					bits.put_natural_32 ({NATURAL_32} 0x00FF0000 + row.to_natural_32 * {NATURAL_32} 0x100 + col.to_natural_32, (row * 4 + col) * 4)
					col := col + 1
				end
				row := row + 1
			end
			c.set_image (bits.item, 4, 3, 16)
			assert ("a bitmap is on the clipboard", c.has_image)
			assert_integers_equal ("width read back", 4, c.image_width)
			assert_integers_equal ("height read back", 3, c.image_height)
			assert ("and it is not text", not c.has_text)
			create back.make (4 * 4 * 3)
			assert ("the pixels come back", c.image_into (back.item, 4, 3, 16))
			l_all := True
			from row := 0 until row >= 3 loop
				from col := 0 until col >= 4 loop
					l_expected := {NATURAL_32} 0xFFFF0000 + row.to_natural_32 * {NATURAL_32} 0x100 + col.to_natural_32
					l_got := back.read_natural_32 ((row * 4 + col) * 4)
					l_all := l_all and l_got = l_expected
					col := col + 1
				end
				row := row + 1
			end
			assert ("every pixel where it was put, rows in order, alpha forced opaque", l_all)
			assert ("a buffer sized for another bitmap is refused, never overrun", not c.image_into (back.item, 5, 3, 20))
		end

	test_clipboard_image_survives_repeated_round_trips
			-- 200 set-then-read cycles, each read made the instant after the
			-- write: the moment a clipboard history manager is most likely to
			-- hold the clipboard open to copy what just arrived. Before
			-- 1.12.1 `image_width' and `image_height' made ONE OpenClipboard
			-- attempt and answered 0 when it lost that race. Every size and
			-- every pixel must now come back as it was put; the sizes change
			-- from cycle to cycle so a stale bitmap cannot pass for a fresh one.
		local
			c: SHELL_CLIPBOARD
			bits, back: MANAGED_POINTER
			i, w, h, k, l_bad: INTEGER
			l_before: STRING_32
			l_intact: BOOLEAN
		do
			create c
			l_before := c.text
			create bits.make (8 * 4 * 4)
			create back.make (8 * 4 * 4)
			from i := 1 until i > 200 loop
				w := 2 + i \\ 7
				h := 1 + i \\ 4
				from k := 0 until k >= w * h loop
					bits.put_natural_32 ({NATURAL_32} 0xFF000000 + (i * 1000 + k).to_natural_32, k * 4)
					k := k + 1
				end
				c.set_image (bits.item, w, h, w * 4)
				l_intact := c.image_width = w and then c.image_height = h
					and then c.image_into (back.item, w, h, w * 4)
				from k := 0 until not l_intact or k >= w * h loop
					l_intact := back.read_natural_32 (k * 4) = bits.read_natural_32 (k * 4)
					k := k + 1
				end
				if not l_intact then
					l_bad := l_bad + 1
				end
				i := i + 1
			end
			if not l_before.is_empty then
				c.set_text (l_before)
			end
			print ("    " + l_bad.out + " of 200 image round trips came back damaged%N")
			assert_integers_equal ("every image round trip intact", 0, l_bad)
		end

feature -- Input synthesis

	test_input_knows_the_desktop
			-- The bounds guard agrees with the desktop metrics at every
			-- edge: both corners in, one pixel past either out.
		local
			i: SHELL_INPUT
			d: SHELL_DESKTOP
		do
			create i
			create d
			assert ("origin is on it", i.is_on_desktop (d.virtual_x, d.virtual_y))
			assert ("far corner is on it",
				i.is_on_desktop (d.virtual_x + d.virtual_width - 1, d.virtual_y + d.virtual_height - 1))
			assert ("one past the right edge is not", not i.is_on_desktop (d.virtual_x + d.virtual_width, d.virtual_y))
			assert ("one before the left edge is not", not i.is_on_desktop (d.virtual_x - 1, d.virtual_y))
		end

	test_input_keys_are_accepted
			-- A lone Shift press does nothing to anything, and proves
			-- SendInput takes what it is handed: two events, down and up.
			-- Needs the interactive desktop, exactly as `test_desktop_grab'
			-- does: from a locked session Windows refuses the injection
			-- with OS error 5, and this test fails saying so.
		local
			i: SHELL_INPUT
		do
			create i
			i.press_key (i.Vk_shift)
			assert_integers_equal ("two handed over", 2, i.last_expected)
			if not i.was_accepted then
				print ("    (desktop refused the injection: accepted "
					+ i.last_accepted.out + " of 2, OS error " + i.last_os_error.out
					+ " - locked session or UIPI boundary)%N")
			end
			assert ("and both accepted", i.was_accepted)
		end

feature -- The Alt door

	test_alt_keys_are_claimed
			-- THE ALT GAP (1.9.3). Before this version the window
			-- procedure answered WM_SYSKEYDOWN for the OEM plus/minus
			-- pair alone: `shell_alt_down' said Alt was down, but
			-- Alt+F opened the SYSTEM MENU instead of reaching the
			-- window, so a menu mnemonic could not be built on this
			-- shell. The claim is now the header's own predicate.
		local
			p: SHELL_SYSKEY_PROBE
		do
			create p
			assert ("Alt+F is the window's", p.syskey_is_claimed (70))
			assert ("Alt+A is the window's", p.syskey_is_claimed (65))
			assert ("Alt+Z is the window's", p.syskey_is_claimed (90))
			assert ("Alt+1 is the window's", p.syskey_is_claimed (49))
			assert ("Alt+0 is the window's", p.syskey_is_claimed (48))
			assert ("F10 is the window's", p.syskey_is_claimed (121))
			assert ("the 1.8 Alt step keys are still the window's",
				p.syskey_is_claimed (187) and p.syskey_is_claimed (189)
				and p.syskey_is_claimed (107) and p.syskey_is_claimed (109))
		end

	test_function_keys_and_ctrl_digits_are_the_windows
			-- GW-24: F1-F12 under any modifier; Ctrl+digit and
			-- Ctrl+punctuation; and NOT letters (WM_CHAR carries
			-- Ctrl+letter), bare digits (typing), or Ctrl+Alt (AltGr).
		local
			p: SHELL_SYSKEY_PROBE
			vk: INTEGER
		do
			create p
			from vk := 112 until vk > 123 loop
				assert_true ("F" + (vk - 111).out + " bare", p.keydown_is_claimed (vk, False, False))
				assert_true ("F" + (vk - 111).out + " with Ctrl", p.keydown_is_claimed (vk, True, False))
				vk := vk + 1
			end
			assert_false ("F13 is not", p.keydown_is_claimed (124, False, False))
			from vk := 48 until vk > 57 loop
				assert_true ("Ctrl+" + (vk - 48).out, p.keydown_is_claimed (vk, True, False))
				assert_false ("bare " + (vk - 48).out + " stays typing", p.keydown_is_claimed (vk, False, False))
				assert_false ("AltGr+" + (vk - 48).out + " stays a character", p.keydown_is_claimed (vk, True, True))
				vk := vk + 1
			end
			assert_true ("Ctrl+numpad 5", p.keydown_is_claimed (101, True, False))
			assert_true ("Ctrl+[", p.keydown_is_claimed (219, True, False))
			assert_true ("Ctrl+]", p.keydown_is_claimed (221, True, False))
			assert_true ("Ctrl+;", p.keydown_is_claimed (186, True, False))
			assert_true ("Ctrl+/", p.keydown_is_claimed (191, True, False))
			assert_true ("Ctrl+'", p.keydown_is_claimed (222, True, False))
			assert_true ("Ctrl+,", p.keydown_is_claimed (188, True, False))
			assert_false ("bare [ stays typing", p.keydown_is_claimed (219, False, False))
			assert_false ("Ctrl+A stays with WM_CHAR", p.keydown_is_claimed (65, True, False))
			assert_true ("the stepping keys are unchanged", p.keydown_is_claimed (37, False, False)
				and p.keydown_is_claimed (34, True, False) and p.keydown_is_claimed (187, True, False))
		end

	test_f5_reaches_the_queue
			-- WM_KEYDOWN(F5) handed to the window procedure comes out of
			-- SHELL_WINDOW's queue as event 4.
		local
			p: SHELL_SYSKEY_PROBE
			w: SHELL_TEST_WINDOW
		do
			create p
			create w
			p.deliver_keydown (116)
			assert_true ("F5 queued as a key-down", w.drain_key (116))
		end

	test_system_alt_keys_are_left_alone
			-- The other half of the same policy, and the half a
			-- careless widening would break: an application that ate
			-- Alt+F4 would be the badly behaved one. These stay with
			-- DefWindowProc.
		local
			p: SHELL_SYSKEY_PROBE
		do
			create p
			assert ("Alt+F4 still closes the window", not p.syskey_is_claimed (115))
			assert ("Alt+Space still opens the system menu", not p.syskey_is_claimed (32))
			assert ("Alt+Enter is still the system's", not p.syskey_is_claimed (13))
			assert ("Alt alone is still the menu key", not p.syskey_is_claimed (18))
			assert ("Alt+F1 is unclaimed", not p.syskey_is_claimed (112))
			assert ("Alt+Left is unclaimed", not p.syskey_is_claimed (37))
			assert ("Alt+Space's WM_SYSCHAR is NOT swallowed - the menu needs it",
				not p.syschar_is_swallowed (32))
			assert ("but the beep behind a claimed letter is",
				p.syschar_is_swallowed (102) and p.syschar_is_swallowed (70))
			assert ("and behind a claimed digit", p.syschar_is_swallowed (49))
			assert ("and behind the 1.8 step keys",
				p.syschar_is_swallowed (43) and p.syschar_is_swallowed (45)
				and p.syschar_is_swallowed (61))
		end

	test_alt_letter_reaches_the_queue
			-- End of the reachable path: WM_SYSKEYDOWN(VK_F) handed to
			-- the window procedure comes out of SHELL_WINDOW's own
			-- drain as the ordinary key-down event 4 carrying 70 -
			-- across translation units, as `drain_marker' proves the
			-- queue must. What is NOT tested here is Windows itself
			-- delivering the message: that needs a visible window with
			-- the focus and a synthesised keystroke on the tester's
			-- desktop, and was checked by inspection only.
		local
			p: SHELL_SYSKEY_PROBE
			w: SHELL_TEST_WINDOW
		do
			create p
			create w
			p.deliver_syskeydown (70)
			assert ("Alt+F arrived as key-down 70", w.drain_key (70))
			p.deliver_syskeydown (121)
			assert ("F10 arrived as key-down 121", w.drain_key (121))
		end

feature -- Framed panels (GW-22, 1.23.0)

	test_gw22_framed_panel_is_a_floating_window
			-- A REAL framed panel offscreen and never shown on screen: caption and
			-- border (client smaller than the window), takes the focus when
			-- clicked, not topmost, titled; its keys, characters, double clicks,
			-- leaves, activation and close requests reach the queue with its slot,
			-- the close request leaving the window open; its 48 is the client
			-- size. A plain panel beside it answers none of these (before/after).
		local
			p, q: SHELL_PANEL
			w: SHELL_TEST_WINDOW
		do
			create p.make
			create q.make
			create w
			from until not w.drain_event (0, 0) loop end
			p.open_framed (-3000, -3000, 400, 300, {STRING_32} "Word Study")
			assert_true ("framed", p.is_open and p.is_framed)
			assert_true ("titled", p.title.same_string ("Word Study"))
			p.set_title ({STRING_32} "Cross references")
			assert_true ("retitled", p.title.same_string ("Cross references"))
			assert_false ("never topmost", p.is_topmost)
			assert_true ("a border and a caption", p.client_width < 400 and p.client_height < 300 - 10)
			assert_integers_equal ("a click activates it (MA_ACTIVATE)", 1, p.simulate_message (0x0021, 0, 0))
			p.place (-3000, -3000, 500, 360)
			assert_true ("48 carries the client size", w.drain_event (p.Event_resized, p.client_width)
				and w.last_second = p.client_height and w.last_extra = p.slot)
			p.simulate_message (0x0100, 0x74, 0).do_nothing
			assert_true ("F5 as a key (60)", w.drain_event (p.Event_key, 0x74) and w.last_extra = p.slot)
			p.simulate_message (0x0102, 97, 0).do_nothing
			assert_true ("a as a character (61)", w.drain_event (p.Event_char, 97) and w.last_extra = p.slot)
			p.simulate_message (0x0203, 0, 20 * 65536 + 10).do_nothing
			assert_true ("a double click (64)", w.drain_event (p.Event_double, 10) and w.last_second = 20)
			p.simulate_message (0x02A3, 0, 0).do_nothing
			assert_true ("the pointer left (65)", w.drain_event (p.Event_leave, 0))
			p.simulate_message (0x0006, 0, 0).do_nothing
			assert_true ("deactivated (63)", w.drain_event (p.Event_activated, 0) and w.last_extra = p.slot)
			p.simulate_message (0x0010, 0, 0).do_nothing
			assert_true ("Alt+F4 asks (62)", w.drain_event (p.Event_close_request, 0) and w.last_extra = p.slot)
			assert_true ("and the window stays", p.is_open and p.client_width > 0)
				-- before/after: a plain panel keeps its old behaviour
			q.open (-3000, -3000, 200, 100)
			assert_true ("the plain panel is topmost", q.is_topmost and not q.is_framed)
			assert_integers_equal ("a plain panel never takes the focus (MA_NOACTIVATE)", 3, q.simulate_message (0x0021, 0, 0))
			assert_true ("its client is all of it", q.client_width = 200 and q.client_height = 100)
			q.simulate_message (0x0102, 97, 0).do_nothing
			q.simulate_message (0x0100, 0x74, 0).do_nothing
			assert_false ("no character from a plain panel", w.drain_event (q.Event_char, 97))
			q.close
			p.close
			assert_false ("closed, no longer framed", p.is_framed)
		end

	test_scan19_a_panel_destroyed_behind_its_back_is_closed
			-- The owner's destruction takes its framed panels with it (Windows
			-- destroys owned windows first): the panel must then answer closed,
			-- and must not mistake another panel in its old slot for itself.
		local
			p, q: SHELL_PANEL
			l_slot: INTEGER
		do
			create p.make
			create q.make
			p.open_framed (-3000, -3000, 300, 200, {STRING_32} "Doomed")
			l_slot := p.slot
			p.simulate_destroyed_behind
			assert_false ("closed when its window is gone", p.is_open)
			q.open (-3000, -3000, 100, 50)
			assert_integers_equal ("the slot is free again", l_slot, q.slot)
			assert_false ("and another panel there is not this one", p.is_open)
			q.close
		end

feature -- The event registry (2026-10-25)

	test_event_numbers_never_collide
			-- Every queue event has its own number, and the owners' short
			-- names are the registry's numbers.
		local
			l_seen: ARRAYED_LIST [INTEGER]
			l_events: SHELL_WAKE
		do
			create l_events
			create l_seen.make (l_events.registry.count)
			across l_events.registry as ic_event loop
				assert_false ("event " + ic_event.out + " numbered once", l_seen.has (ic_event))
				l_seen.extend (ic_event)
			end
			assert_integers_equal ("the next free number follows the last", 66, l_events.next_free_event)
			assert_integers_equal ("panel press", {SHELL_EVENTS}.Event_panel_press, {SHELL_PANEL}.Event_press)
			assert_integers_equal ("tray click", {SHELL_EVENTS}.Event_tray_click, {SHELL_TRAY}.Event_click)
			assert_integers_equal ("appearance", {SHELL_EVENTS}.Event_appearance_changed, {SHELL_APPEARANCE}.Event_changed)
			assert_integers_equal ("the window's wake", {SHELL_WAKE}.Event_wake, {SHELL_WINDOW}.Event_wake)
		end

feature -- SDK macro tripwire

	test_sdk_macro_poison_is_armed
			-- The tripwire is only a tripwire while a Windows SDK
			-- header really does `#define small char'. If a future SDK
			-- stops, this fails and tells us to re-point it - a silent
			-- tripwire is worse than none.
		local
			t: SDK_MACRO_TRIPWIRE
		do
			create t
			assert ("an SDK header still poisons `small' - if not, re-point the tripwire",
				t.poison_is_in_force)
		end

	test_sdk_macro_tripwire
			-- simple_shell.h compiles in a translation unit that pulled
			-- a COM/RPC header FIRST - the order a finalized build hands
			-- it when a sibling library's COM header lands earlier in the
			-- same concatenated unit. On the pre-1.9.1 header (`HICON
			-- big, small;') the C phase died with C2059 / C2513 and this
			-- target never linked, so reaching this line is the proof.
		local
			t: SDK_MACRO_TRIPWIRE
		do
			create t
			assert ("the header survived the SDK macros", t.header_survived_the_poison)
		end

end
