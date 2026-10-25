note
	description: "[
		The Windows light/dark app setting (Settings > Personalization >
		Colors > "Choose your app mode") and the caption that matches
		it. When the setting flips, the main window's queue receives
		`Event_changed' (53) with 1 for dark or 0 for light in its first
		field; `system_prefers_dark' answers at any time. GW-27, asked
		for by simple_bible: default Light, Dark on request, and the
		option to follow Windows.

		GW-16 (1.20.0): the high-contrast switch (Settings >
		Accessibility > Contrast themes) and the system colors it paints
		with. When the switch flips, or the contrast palette changes, the
		queue receives `Event_contrast_changed' (56) with 1 for on or 0
		for off; `system_high_contrast' and `system_color' answer at any
		time. A client that must be tested without touching Windows
		inherits this class and redefines the three queries.

		GW-14 (1.21.0): the Animation effects setting (Settings >
		Accessibility > Visual effects). `system_reduces_motion' answers;
		`Event_motion_changed' (57) arrives when it flips, 1 reduced.
	]"

class
	SHELL_APPEARANCE

inherit
	SHELL_EVENTS
		rename
			Event_appearance_changed as Event_changed
		end

feature -- Access

	system_prefers_dark: BOOLEAN
			-- Is Windows set to dark for apps? False when the setting is
			-- absent or unreadable (Windows' own default is light).
		do
			Result := c_system_prefers_dark /= 0
		end

	system_high_contrast: BOOLEAN
			-- Is a Windows contrast theme on?
		do
			Result := c_high_contrast_on /= 0
		end

	system_color (a_index: INTEGER): NATURAL_32
			-- The system color `a_index' (a Win32 COLOR_ index such as
			-- `Color_window'), as 0xRRGGBB.
		require
			known_index: a_index >= 0 and a_index <= Color_last
		do
			Result := c_system_color (a_index)
		ensure
			rgb: Result <= 0xFFFFFF
		end

	system_reduces_motion: BOOLEAN
			-- Has the user turned Windows' animation effects off? False where
			-- the setting cannot be read (before Vista).
		do
			Result := c_reduces_motion /= 0
		end

	Spi_set_client_area_animation: INTEGER = 0x1043
			-- The SystemParametersInfo action WM_SETTINGCHANGE names when the
			-- animation setting flips.

feature -- System color indexes (Win32 COLOR_*)

	Color_window: INTEGER = 5
			-- The ground of text areas.

	Color_window_text: INTEGER = 8
			-- Text on `Color_window'.

	Color_highlight: INTEGER = 13
			-- The ground of selected items.

	Color_highlight_text: INTEGER = 14
			-- Text on `Color_highlight'.

	Color_button_face: INTEGER = 15
			-- The face of buttons.

	Color_gray_text: INTEGER = 17
			-- Disabled text.

	Color_button_text: INTEGER = 18
			-- Text on `Color_button_face'.

	Color_hotlight: INTEGER = 26
			-- Hyperlinks.

	Color_last: INTEGER = 30
			-- The highest index Windows defines.

	Spi_set_high_contrast: INTEGER = 0x43
			-- The SystemParametersInfo action WM_SETTINGCHANGE names when
			-- the high-contrast switch flips.

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

	report_contrast_change (a_spi: INTEGER): BOOLEAN
			-- What the main window procedure does on WM_SETTINGCHANGE whose
			-- wParam is `a_spi': push `Event_contrast_changed' when it is
			-- `Spi_set_high_contrast'. Answers whether it pushed.
		do
			Result := c_contrast_changed (a_spi.to_natural_32) /= 0
		ensure
			only_the_switch: Result = (a_spi = Spi_set_high_contrast)
		end

	report_motion_change (a_spi: INTEGER): BOOLEAN
			-- What the main window procedure does on WM_SETTINGCHANGE whose
			-- wParam is `a_spi': push `Event_motion_changed' when it is
			-- `Spi_set_client_area_animation'. Answers whether it pushed.
		do
			Result := c_motion_changed (a_spi.to_natural_32) /= 0
		ensure
			only_the_setting: Result = (a_spi = Spi_set_client_area_animation)
		end

	report_system_colors_change
			-- What the main window procedure does on WM_SYSCOLORCHANGE: push
			-- `Event_contrast_changed'.
		do
			c_system_colors_changed
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

	c_high_contrast_on: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_high_contrast_on();"
		end

	c_system_color (a_index: INTEGER): NATURAL_32
		external
			"C inline use %"simple_shell.h%""
		alias
			"return (EIF_NATURAL_32)shell_system_color((int)$a_index);"
		end

	c_contrast_changed (a_spi: NATURAL_32): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_contrast_changed((unsigned int)$a_spi);"
		end

	c_reduces_motion: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_reduces_motion();"
		end

	c_motion_changed (a_spi: NATURAL_32): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_motion_changed((unsigned int)$a_spi);"
		end

	c_system_colors_changed
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_system_colors_changed();"
		end

end
