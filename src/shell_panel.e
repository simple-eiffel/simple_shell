note
	description: "[
		A borderless topmost panel for an on-screen instrument: a teleprompter
		pill under the webcam, a heads-up strip. Never takes focus when clicked,
		no taskbar button, any number per process up to `Max_panels'. It can be
		left out of screen captures (meetings, recorders, screenshots), made
		click-through so the desktop under it stays usable, given a whole-window
		opacity, moved by Shift+drag when `is_draggable', and resized by Shift+drag
		on an edge or corner when also `is_resizable'.

		Events arrive on the shared queue with the slot in the fourth field
		(`SHELL_WINDOW.event_extra'): 41 press, 42 release, 43 move (coalesced),
		44 expose, 45 wheel (delta in the first field), 46 right press,
		47 moved (new left, top after a drag), 48 resized (width, height when a drag
		ends; call `sync_geometry' to update `x', `y', `width', `height'), 49 moving
		(left, top during any move, coalesced; 1.14.0).
		Since 1.14.0 a panel can also be a handle - a plain press drags it
		(`set_drags_on_press'), its moves kept to one axis (`set_drag_axis') - and
		can size from its left or right edge on a plain press (`set_sides_size_on_press').
		`press_grip_at' answers what any press would do. A panel that
		`accepts_files' reports files dropped on it as event 50 (x, y of the drop);
		the paths wait in `SHELL_WINDOW.take_dropped_paths'.
		Paint through `dc' / `release_dc'.
	]"

class
	SHELL_PANEL

create
	make

feature {NONE} -- Initialization

	make
			-- A closed panel; `open' creates its window.
		do
			slot := -1
		ensure
			closed: not is_open
		end

feature -- Constants

	Max_panels: INTEGER = 8
			-- Panels one process may have open at once.

	Affinity_none: INTEGER = 0x0
	Affinity_black_in_captures: INTEGER = 0x1
			-- WDA_MONITOR: captures show a black box (Windows before 10 2004).
	Affinity_excluded_from_captures: INTEGER = 0x11
			-- WDA_EXCLUDEFROMCAPTURE: captures show what is behind the panel.

	Event_press: INTEGER = 41
	Event_release: INTEGER = 42
	Event_move: INTEGER = 43
	Event_expose: INTEGER = 44
	Event_wheel: INTEGER = 45
	Event_right_press: INTEGER = 46
	Event_moved: INTEGER = 47
	Event_resized: INTEGER = 48
	Event_moving: INTEGER = 49
			-- During a move: the panel's left and top now (1.14.0).
	Event_dropped: INTEGER = 50
			-- Files dropped on the panel, at (x, y) in it (1.14.0, `set_accepts_files').

	Axis_free: INTEGER = 0
	Axis_horizontal: INTEGER = 1
	Axis_vertical: INTEGER = 2
			-- What `set_drag_axis' keeps a move to.

	Grip_none: INTEGER = 0
			-- `press_grip_at' for a press that is a plain click.

	Grip_move: INTEGER = 2
			-- `grip_at' answers for a press that moves the panel (HTCAPTION)...
	Grip_left: INTEGER = 10
	Grip_right: INTEGER = 11
	Grip_top: INTEGER = 12
	Grip_top_left: INTEGER = 13
	Grip_top_right: INTEGER = 14
	Grip_bottom: INTEGER = 15
	Grip_bottom_left: INTEGER = 16
	Grip_bottom_right: INTEGER = 17
			-- ...and for one that resizes from that edge or corner (the Windows hit codes).

feature -- Access

	slot: INTEGER
			-- Native slot while open, -1 when closed.

	x, y, width, height: INTEGER
			-- Geometry last given to `open', `show' or `place'.

	handle: POINTER
			-- The native window, while open.
		require
			open: is_open
		do
			Result := c_handle (slot)
		end

	opacity: INTEGER
			-- Whole-window alpha, 0 (invisible) to 255 (opaque).
		require
			open: is_open
		do
			Result := c_opacity (slot)
		end

	capture_affinity: INTEGER
			-- Display affinity now in force: `Affinity_excluded_from_captures',
			-- `Affinity_black_in_captures', or `Affinity_none'.
		require
			open: is_open
		do
			Result := c_capture_affinity (slot)
		end

feature -- Status

	is_open: BOOLEAN
			-- Does the panel have a native window?
		do
			Result := slot >= 0
		end

	is_visible: BOOLEAN
			-- Is the panel on screen?
		require
			open: is_open
		do
			Result := c_is_visible (slot) = 1
		end

	is_click_through: BOOLEAN
			-- Do clicks pass through to whatever is underneath?
		require
			open: is_open
		do
			Result := c_is_click_through (slot) = 1
		end

	is_resizable: BOOLEAN
			-- Does a Shift+drag on an edge or corner resize the panel?

	grip_at (a_x, a_y: INTEGER): INTEGER
			-- What a Shift+press at client point (`a_x', `a_y') does: `Grip_move' or a resize grip.
		require
			open: is_open
		do
			Result := c_grip_at (slot, a_x, a_y)
		ensure
			known: Result = Grip_move or (Result >= Grip_left and Result <= Grip_bottom_right)
			moves_unless_resizable: not is_resizable implies Result = Grip_move
		end

	is_shift_held: BOOLEAN
			-- Is a Shift key down now (whichever window has the keyboard focus)?
		do
			Result := c_shift_held /= 0
		end

	is_cursor_over: BOOLEAN
			-- Is the mouse pointer over the panel now? False while closed or hidden.
			-- Click-through does not change the answer: the pointer is over it all the same.
		do
			Result := is_open and then c_cursor_over (handle) /= 0
		ensure
			closed_never: not is_open implies not Result
		end

	is_draggable: BOOLEAN
			-- May Shift+drag move the panel (event 47 reports where it landed)?

	drags_on_press: BOOLEAN
			-- Does a plain press drag the panel (a handle)?

	drag_axis: INTEGER
			-- `Axis_free', or the one axis a move keeps to.

	sides_size_on_press: BOOLEAN
			-- Does a plain press within the grip of the left or right edge size the panel?

	is_capture_excluded: BOOLEAN
			-- Is the panel left out of screen captures?
		require
			open: is_open
		do
			Result := capture_affinity = Affinity_excluded_from_captures
		end

feature -- Lifecycle

	open (a_x, a_y, a_width, a_height: INTEGER)
			-- Create the native window, hidden, at the given geometry. Stays closed
			-- when all `Max_panels' slots are in use.
		require
			closed: not is_open
			sane_size: a_width > 0 and a_height > 0
		do
			slot := c_open (a_x, a_y, a_width, a_height)
			if is_open then
				set_geometry (a_x, a_y, a_width, a_height)
				is_draggable := False
				drags_on_press := False
				drag_axis := Axis_free
				sides_size_on_press := False
			end
		ensure
			geometry_when_open: is_open implies (x = a_x and y = a_y and width = a_width and height = a_height)
			opaque_when_open: is_open implies opacity = 255
			hidden_when_open: is_open implies not is_visible
		end

	show (a_x, a_y, a_width, a_height: INTEGER)
			-- Put the panel on screen at the given geometry, without activating it.
		require
			open: is_open
			sane_size: a_width > 0 and a_height > 0
		do
			c_show (slot, a_x, a_y, a_width, a_height)
			set_geometry (a_x, a_y, a_width, a_height)
		ensure
			visible: is_visible
			placed: x = a_x and y = a_y and width = a_width and height = a_height
		end

	place (a_x, a_y, a_width, a_height: INTEGER)
			-- Move or resize, keeping visibility.
		require
			open: is_open
			sane_size: a_width > 0 and a_height > 0
		do
			c_place (slot, a_x, a_y, a_width, a_height)
			set_geometry (a_x, a_y, a_width, a_height)
		ensure
			placed: x = a_x and y = a_y and width = a_width and height = a_height
			visibility_kept: is_visible = old is_visible
		end

	hide
			-- Take the panel off screen.
		require
			open: is_open
		do
			c_hide (slot)
		ensure
			hidden: not is_visible
		end

	close
			-- Destroy the native window; the slot is free again.
		require
			open: is_open
		do
			c_close (slot)
			slot := -1
			is_draggable := False
			is_resizable := False
			drags_on_press := False
			drag_axis := Axis_free
			sides_size_on_press := False
		ensure
			closed: not is_open
			plain: not drags_on_press and not sides_size_on_press and drag_axis = Axis_free
		end

feature -- Appearance

	set_opacity (a_alpha: INTEGER)
			-- Whole-window alpha (capture exclusion still applies).
		require
			open: is_open
			alpha_range: a_alpha >= 0 and a_alpha <= 255
		do
			c_set_opacity (slot, a_alpha)
		ensure
			set: opacity = a_alpha
		end

	set_click_through (a_on: BOOLEAN)
			-- Let clicks pass through (on) or reach the panel (off).
		require
			open: is_open
		do
			c_set_click_through (slot, a_on.to_integer)
		ensure
			set: is_click_through = a_on
		end

	accepts_files: BOOLEAN
			-- Do files dropped on the panel arrive as `Event_dropped'?
		require
			open: is_open
		do
			Result := c_accepts_files (slot) = 1
		end

	set_accepts_files (a_on: BOOLEAN)
			-- Take files dropped on the panel (event 50; the paths in
			-- `SHELL_WINDOW.take_dropped_paths'), or refuse them.
		require
			open: is_open
		do
			c_set_accepts_files (slot, a_on.to_integer)
		ensure
			set: accepts_files = a_on
		end

	simulate_drop (a_x, a_y: INTEGER; a_paths: READABLE_STRING_GENERAL)
			-- Hand the panel a real drop of `a_paths' (newline-separated) at (`a_x', `a_y'),
			-- built as the shell builds one: the test door to `Event_dropped'.
		require
			open: is_open
			accepting: accepts_files
			paths_given: not a_paths.is_empty
		local
			l_ns: NATIVE_STRING
		do
			create l_ns.make (a_paths)
			c_try_drop (slot, a_x, a_y, l_ns.item)
		end

	set_draggable (a_on: BOOLEAN)
			-- Allow or forbid Shift+drag moves (forbidding them forbids resizing too).
		require
			open: is_open
		do
			c_set_draggable (slot, a_on.to_integer)
			is_draggable := a_on
			if not a_on and is_resizable then
				c_set_resizable (slot, 0, 0, 0)
				is_resizable := False
			end
		ensure
			set: is_draggable = a_on
			no_resize_without_drag: not a_on implies not is_resizable
		end

	set_drags_on_press (a_on: BOOLEAN)
			-- Let a plain press drag the panel (a handle), or not. Event 49 reports it moving,
			-- 47 and 48 where it landed.
		require
			open: is_open
		do
			c_set_press_drag (slot, a_on.to_integer)
			drags_on_press := a_on
		ensure
			set: drags_on_press = a_on
		end

	set_drag_axis (a_axis: INTEGER)
			-- Keep every move to `a_axis' (`Axis_horizontal': the panel slides left and right only).
		require
			open: is_open
			known: a_axis >= Axis_free and a_axis <= Axis_vertical
		do
			c_set_axis (slot, a_axis)
			drag_axis := a_axis
		ensure
			set: drag_axis = a_axis
		end

	set_sides_size_on_press (a_on: BOOLEAN)
			-- Let a plain press within the grip of the left or right edge size the panel, or not.
		require
			open: is_open
			grips: a_on implies is_resizable
		do
			c_set_side_grip (slot, a_on.to_integer)
			sides_size_on_press := a_on
		ensure
			set: sides_size_on_press = a_on
		end

	press_grip_at (a_x, a_y: INTEGER; a_shift: BOOLEAN): INTEGER
			-- What a press at client point (`a_x', `a_y') does, Shift held or not: `Grip_none' (a
			-- click: event 41), `Grip_move', or a resize grip.
		require
			open: is_open
		do
			Result := c_press_code (slot, a_x, a_y, a_shift.to_integer)
		ensure
			known: Result = Grip_none or Result = Grip_move or (Result >= Grip_left and Result <= Grip_bottom_right)
			handle_moves: (drags_on_press and not (a_shift and is_draggable)) implies Result = Grip_move
			plain_click: (not drags_on_press and not sides_size_on_press and not a_shift) implies Result = Grip_none
		end

	axis_result (a_dx, a_dy: INTEGER): TUPLE [x, y: INTEGER]
			-- Where a move of the panel by (`a_dx', `a_dy') would put its top left, kept to
			-- `drag_axis' (it reports the move as event 49, but the panel stays put).
		require
			open: is_open
		local
			l_x, l_y: INTEGER
		do
			c_try_move (slot, a_dx, a_dy, $l_x, $l_y)
			Result := [l_x, l_y]
		end

	set_resizable (a_grip, a_min_width, a_min_height: INTEGER)
			-- Let a Shift+drag within `a_grip' pixels of an edge or corner resize the panel,
			-- never below `a_min_width' x `a_min_height'.
		require
			open: is_open
			draggable: is_draggable
			grip_sane: a_grip >= 1 and a_grip <= 64
			minimum_sane: a_min_width >= 1 and a_min_height >= 1
		do
			c_set_resizable (slot, a_grip, a_min_width, a_min_height)
			is_resizable := True
		ensure
			resizable: is_resizable
		end

	set_fixed_size
			-- Shift+drag moves only.
		require
			open: is_open
		do
			c_set_resizable (slot, 0, 0, 0)
			is_resizable := False
		ensure
			fixed: not is_resizable
		end

	sync_geometry
			-- Read `x', `y', `width', `height' back from the window (after a native move or resize).
		require
			open: is_open
		local
			l_x, l_y, l_w, l_h: INTEGER
		do
			l_x := x
			l_y := y
			l_w := width
			l_h := height
			c_rect (slot, $l_x, $l_y, $l_w, $l_h)
			set_geometry (l_x, l_y, l_w, l_h)
		end

	request_capture_exclusion
			-- Ask to be left out of screen captures; Windows before 10 2004 can only
			-- black the panel out. Read `capture_affinity' for what was granted.
		require
			open: is_open
		do
			c_set_capture_excluded (slot, 1)
		end

	allow_capture
			-- Appear in screen captures again.
		require
			open: is_open
		do
			c_set_capture_excluded (slot, 0)
		ensure
			allowed: capture_affinity = Affinity_none
		end

feature -- Painting

	invalidate
			-- Ask for an expose event (44).
		require
			open: is_open
		do
			c_invalidate (slot)
		end

	dc: POINTER
			-- The panel's device context; release promptly with `release_dc'.
		require
			open: is_open
		do
			Result := c_dc (slot)
		end

	release_dc (a_dc: POINTER)
		require
			open: is_open
		do
			c_release_dc (slot, a_dc)
		end

	fill (a_rgb: INTEGER)
			-- Paint the whole panel one colour (0xRRGGBB): placeholders and tests.
		require
			open: is_open
			colour: a_rgb >= 0 and a_rgb <= 0xFFFFFF
		do
			c_fill (slot, a_rgb)
		end

feature {NONE} -- Implementation

	set_geometry (a_x, a_y, a_width, a_height: INTEGER)
		do
			x := a_x
			y := a_y
			width := a_width
			height := a_height
		ensure
			set: x = a_x and y = a_y and width = a_width and height = a_height
		end

feature {NONE} -- Externals

	c_handle (a_slot: INTEGER): POINTER
		external "C inline use %"simple_shell.h%""
		alias "return (EIF_POINTER)shell_panel_hwnd($a_slot);"
		end

	c_open (a_x, a_y, a_w, a_h: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_open($a_x, $a_y, $a_w, $a_h);"
		end

	c_show (a_slot, a_x, a_y, a_w, a_h: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_show($a_slot, $a_x, $a_y, $a_w, $a_h);"
		end

	c_place (a_slot, a_x, a_y, a_w, a_h: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_place($a_slot, $a_x, $a_y, $a_w, $a_h);"
		end

	c_hide (a_slot: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_hide($a_slot);"
		end

	c_close (a_slot: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_close($a_slot);"
		end

	c_is_visible (a_slot: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_is_visible($a_slot);"
		end

	c_invalidate (a_slot: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_invalidate($a_slot);"
		end

	c_dc (a_slot: INTEGER): POINTER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_dc($a_slot);"
		end

	c_release_dc (a_slot: INTEGER; a_dc: POINTER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_release_dc($a_slot, $a_dc);"
		end

	c_set_opacity (a_slot, a_alpha: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_opacity($a_slot, $a_alpha);"
		end

	c_opacity (a_slot: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_opacity($a_slot);"
		end

	c_set_click_through (a_slot, a_on: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_click_through($a_slot, $a_on);"
		end

	c_is_click_through (a_slot: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_is_click_through($a_slot);"
		end

	c_set_draggable (a_slot, a_on: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_draggable($a_slot, $a_on);"
		end

	c_set_resizable (a_slot, a_grip, a_min_w, a_min_h: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_resizable($a_slot, $a_grip, $a_min_w, $a_min_h);"
		end

	c_set_accepts_files (a_slot, a_on: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_accepts_files($a_slot, $a_on);"
		end

	c_accepts_files (a_slot: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_accepts_files($a_slot);"
		end

	c_try_drop (a_slot, a_x, a_y: INTEGER; a_paths: POINTER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_try_drop($a_slot, $a_x, $a_y, (const wchar_t*)$a_paths);"
		end

	c_set_press_drag (a_slot, a_on: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_press_drag($a_slot, $a_on);"
		end

	c_set_axis (a_slot, a_axis: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_axis($a_slot, $a_axis);"
		end

	c_set_side_grip (a_slot, a_on: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_side_grip($a_slot, $a_on);"
		end

	c_press_code (a_slot, a_x, a_y, a_shift: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_press_code($a_slot, $a_x, $a_y, $a_shift);"
		end

	c_try_move (a_slot, a_dx, a_dy: INTEGER; a_x, a_y: TYPED_POINTER [INTEGER])
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_try_move($a_slot, $a_dx, $a_dy, (int*)$a_x, (int*)$a_y);"
		end

	c_grip_at (a_slot, a_x, a_y: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_grip_code($a_slot, $a_x, $a_y);"
		end

	c_rect (a_slot: INTEGER; a_x, a_y, a_w, a_h: TYPED_POINTER [INTEGER])
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_rect($a_slot, (int*)$a_x, (int*)$a_y, (int*)$a_w, (int*)$a_h);"
		end

	c_shift_held: INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_shift_held();"
		end

	c_cursor_over (a_hwnd: POINTER): INTEGER
			-- 1 when the pointer is inside visible window `a_hwnd'.
		external "C inline use %"simple_shell.h%""
		alias "[
			POINT l_p;
			RECT l_r;
			HWND l_hwnd = (HWND)$a_hwnd;
			if (!l_hwnd || !IsWindowVisible(l_hwnd) || !GetCursorPos(&l_p) || !GetWindowRect(l_hwnd, &l_r)) return 0;
			return PtInRect(&l_r, l_p) ? 1 : 0;
		]"
		end

	c_capture_affinity (a_slot: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_panel_capture_affinity($a_slot);"
		end

	c_set_capture_excluded (a_slot, a_on: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_set_capture_excluded($a_slot, $a_on);"
		end

	c_fill (a_slot, a_rgb: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_panel_fill($a_slot, $a_rgb);"
		end

invariant
	slot_range: slot >= -1 and slot < Max_panels
	drag_only_when_open: is_draggable implies is_open
	resize_only_with_drag: is_resizable implies is_draggable

end
