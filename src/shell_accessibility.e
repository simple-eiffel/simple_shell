note
	description: "[
		The UI Automation bridge (GW-14, 1.22.0): a drawn toolkit has no
		child windows for a screen reader to find, so the application
		publishes its widget tree as a table - one row per element: id,
		parent, control type, name, value, bounds in client pixels,
		focusable, enabled - and the window answers UI Automation from it
		(Narrator, NVDA, JAWS, Accessibility Insights).

		Publish with `begin_tree', `add_node' (node 0 is the content root;
		rows in tree order, a parent before its children) and `commit'.
		Tell clients about the keyboard focus with `focus_changed'. A
		client that asks to move the focus (UI Automation's SetFocus)
		reaches the queue as `Event_focus_request' (58) carrying the node
		id. The table is served from C under a lock, so UI Automation's
		own threads never touch Eiffel objects.
	]"

class
	SHELL_ACCESSIBILITY

inherit
	SHELL_EVENTS

feature -- Publishing

	begin_tree (a_capacity: INTEGER)
			-- Start a new table of at most `a_capacity' rows; the published
			-- one keeps serving until `commit'.
		require
			positive: a_capacity > 0
		do
			is_building := c_begin (a_capacity) /= 0
			rows_added := 0
			capacity := a_capacity
		ensure
			sized: capacity = a_capacity
			empty: rows_added = 0
		end

	add_node (a_id, a_parent, a_role: INTEGER; a_name: READABLE_STRING_GENERAL;
			a_value: detachable READABLE_STRING_GENERAL; a_x, a_y, a_w, a_h: REAL_64;
			a_focusable, a_enabled: BOOLEAN)
			-- Add one row: element `a_id' under `a_parent' (node 0 under
			-- itself), of control type `a_role' (a `Role_' constant), named
			-- `a_name', with `a_value' when it has one (UI Automation's Value
			-- pattern, read-only), at (`a_x', `a_y') `a_w' by `a_h' in client
			-- pixels.
		require
			building: is_building
			room: rows_added < capacity
			id_non_negative: a_id >= 0
			root_first: rows_added = 0 implies a_id = 0
			parent_non_negative: a_parent >= 0
			size_non_negative: a_w >= 0.0 and a_h >= 0.0
		local
			l_name: NATIVE_STRING
			l_value: detachable NATIVE_STRING
			l_value_item: POINTER
		do
			create l_name.make (a_name)
			if attached a_value as al_value then
				create l_value.make (al_value)
				l_value_item := l_value.item
			end
			if c_add (a_id, a_parent, a_role, a_focusable.to_integer, a_enabled.to_integer,
				a_x, a_y, a_w, a_h, l_name.item, l_value_item) /= 0
			then
				rows_added := rows_added + 1
			end
		ensure
			one_more: rows_added = old rows_added + 1
		end

	commit (a_hwnd: POINTER)
			-- Serve the new table for window `a_hwnd' (a window not yet open,
			-- `default_pointer', keeps the table for the readers below and
			-- answers no client).
		require
			building: is_building
			has_root: rows_added >= 1
		do
			c_commit (a_hwnd)
			is_building := False
		ensure
			served: is_serving
			not_building: not is_building
		end

	focus_changed (a_id: INTEGER)
			-- Element `a_id' took the keyboard focus: tell any listening
			-- client (UI Automation's focus-changed event).
		require
			serving: is_serving
		do
			c_focus_changed (a_id)
		end

	disable
			-- Stop answering; clients see the bare window again.
		do
			c_disable
			is_building := False
		ensure
			stopped: not is_serving
		end

feature -- Status

	is_building: BOOLEAN
			-- Has `begin_tree' started a table not yet committed?

	rows_added: INTEGER
			-- Rows in the table being built.

	capacity: INTEGER
			-- Rows the table being built can hold.

	is_serving: BOOLEAN
			-- Is a table being served?
		do
			Result := c_row_count > 0
		end

	served_rows: INTEGER
			-- Rows in the table being served.
		do
			Result := c_row_count
		end

	clients_listening: BOOLEAN
			-- Is any UI Automation client (a screen reader, an inspector)
			-- listening right now? Publishing on every frame can wait for one.
		do
			Result := c_clients_listening /= 0
		end

	served_window: POINTER
			-- The window the table is served for; `default_pointer' when none
			-- (published before the window opened, or never).
		do
			Result := c_served_window
		end

	served_focus: INTEGER
			-- The node last told to hold the focus.
		do
			Result := c_served_focus
		end

feature -- Reading the served table (tests and tools)

	served_id (a_row: INTEGER): INTEGER
			-- The id of served row `a_row' (1-based).
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := c_row_int (a_row - 1, 0)
		end

	served_parent (a_row: INTEGER): INTEGER
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := c_row_int (a_row - 1, 1)
		end

	served_role (a_row: INTEGER): INTEGER
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := c_row_int (a_row - 1, 2)
		end

	served_focusable (a_row: INTEGER): BOOLEAN
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := c_row_int (a_row - 1, 3) = 1
		end

	served_has_value (a_row: INTEGER): BOOLEAN
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := c_row_int (a_row - 1, 5) = 1
		end

	served_name (a_row: INTEGER): STRING_32
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := row_text (a_row, 0)
		end

	served_value (a_row: INTEGER): STRING_32
		require
			in_range: a_row >= 1 and a_row <= served_rows
		do
			Result := row_text (a_row, 1)
		end

	served_row_of (a_id: INTEGER): INTEGER
			-- The row serving node `a_id'; 0 when none does.
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > served_rows or Result > 0
			loop
				if served_id (i) = a_id then
					Result := i
				end
				i := i + 1
			end
		end

feature -- Control types (UI Automation's UIA_*ControlTypeId)

	Role_button: INTEGER = 50000
	Role_calendar: INTEGER = 50001
	Role_check_box: INTEGER = 50002
	Role_combo_box: INTEGER = 50003
	Role_edit: INTEGER = 50004
	Role_hyperlink: INTEGER = 50005
	Role_image: INTEGER = 50006
	Role_list_item: INTEGER = 50007
	Role_list: INTEGER = 50008
	Role_menu: INTEGER = 50009
	Role_menu_bar: INTEGER = 50010
	Role_menu_item: INTEGER = 50011
	Role_progress_bar: INTEGER = 50012
	Role_radio_button: INTEGER = 50013
	Role_scroll_bar: INTEGER = 50014
	Role_slider: INTEGER = 50015
	Role_spinner: INTEGER = 50016
	Role_status_bar: INTEGER = 50017
	Role_tab: INTEGER = 50018
	Role_tab_item: INTEGER = 50019
	Role_text: INTEGER = 50020
	Role_tool_bar: INTEGER = 50021
	Role_tool_tip: INTEGER = 50022
	Role_tree: INTEGER = 50023
	Role_tree_item: INTEGER = 50024
	Role_custom: INTEGER = 50025
	Role_group: INTEGER = 50026
	Role_data_grid: INTEGER = 50028
	Role_data_item: INTEGER = 50029
	Role_document: INTEGER = 50030
	Role_window: INTEGER = 50032
	Role_pane: INTEGER = 50033
	Role_header: INTEGER = 50034
	Role_header_item: INTEGER = 50035
	Role_table: INTEGER = 50036
	Role_separator: INTEGER = 50038

feature {NONE} -- Externals

	row_text (a_row, a_which: INTEGER): STRING_32
		local
			l_buf: MANAGED_POINTER
		do
			create l_buf.make (1024 * 2)
			if c_row_text (a_row - 1, a_which, l_buf.item, 1024) >= 0 then
			end
			Result := (create {NATIVE_STRING}.make_from_pointer (l_buf.item)).string
		end

	c_row_int (a_i, a_field: INTEGER): INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_row_int((int)$a_i, (int)$a_field);"
		end

	c_row_text (a_i, a_which: INTEGER; a_out: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_row_text((int)$a_i, (int)$a_which, (wchar_t*)$a_out, (int)$a_cap);"
		end

	c_served_window: POINTER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_served_window();"
		end

	c_served_focus: INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_served_focus();"
		end

	c_clients_listening: INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_clients_listening();"
		end

	c_begin (a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_begin((int)$a_cap);"
		end

	c_add (a_id, a_parent, a_role, a_focusable, a_enabled: INTEGER; a_x, a_y, a_w, a_h: REAL_64; a_name, a_value: POINTER): INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_add((int)$a_id, (int)$a_parent, (int)$a_role, (int)$a_focusable, (int)$a_enabled, (double)$a_x, (double)$a_y, (double)$a_w, (double)$a_h, (const wchar_t*)$a_name, (const wchar_t*)$a_value);"
		end

	c_commit (a_hwnd: POINTER)
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"shell_uia_commit($a_hwnd);"
		end

	c_focus_changed (a_id: INTEGER)
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"shell_uia_focus_changed((int)$a_id);"
		end

	c_disable
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"shell_uia_disable();"
		end

	c_row_count: INTEGER
		external
			"C inline use %"simple_shell_uia.h%""
		alias
			"return shell_uia_row_count();"
		end

invariant
	rows_within_capacity: rows_added <= capacity

end
