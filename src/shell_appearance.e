note
	description: "[
		The Windows light/dark app setting (Settings > Personalization >
		Colors > "Choose your app mode") and the caption that matches
		it. When the setting flips, the main window's queue receives
		`Event_changed' (53) with 1 for dark or 0 for light in its first
		field; `system_prefers_dark' answers at any time. GW-27, asked
		for by simple_bible: default Light, Dark on request, and the
		option to follow Windows.
	]"

class
	SHELL_APPEARANCE

feature -- Access

	system_prefers_dark: BOOLEAN
			-- Is Windows set to dark for apps? False when the setting is
			-- absent or unreadable (Windows' own default is light).
		do
			Result := c_system_prefers_dark /= 0
		end

	Event_changed: INTEGER = 53
			-- The queue event for a flip of the setting: first field 1
			-- dark, 0 light.

	last_title_bar_applied: BOOLEAN
			-- Did DWM accept the last `set_dark_title_bar'? False before
			-- Windows 10 1809, where the caption cannot be darkened.

feature -- Element change

	set_dark_title_bar (a_hwnd: POINTER; a_dark: BOOLEAN)
			-- Ask DWM to draw the caption and frame of `a_hwnd' dark (or
			-- light), so they match the content beneath them.
		require
			window_given: a_hwnd /= default_pointer
		do
			last_title_bar_applied := c_set_dark_title_bar (a_hwnd, a_dark.to_integer) /= 0
		end

feature -- Test door

	report_setting_change (a_area: READABLE_STRING_GENERAL): BOOLEAN
			-- What the main window procedure does on WM_SETTINGCHANGE
			-- naming `a_area': push `Event_changed' when it is
			-- "ImmersiveColorSet" (any case). Answers whether it pushed.
		local
			l_area: NATIVE_STRING
		do
			create l_area.make (a_area)
			Result := c_setting_changed (l_area.item) /= 0
		ensure
			only_the_color_set: Result = a_area.as_string_32.is_case_insensitive_equal ({STRING_32} "ImmersiveColorSet")
		end

feature {NONE} -- Externals

	c_system_prefers_dark: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_system_prefers_dark();"
		end

	c_set_dark_title_bar (a_hwnd: POINTER; a_on: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_set_dark_title_bar($a_hwnd, (int)$a_on);"
		end

	c_setting_changed (a_area: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_setting_changed((const wchar_t*)$a_area);"
		end

end
