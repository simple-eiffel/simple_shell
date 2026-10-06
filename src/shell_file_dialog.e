note
	description: "[
		The Windows Open dialog: let the user pick an existing file. Modal on
		the calling thread and owned by the application's main window, so it
		sits above it. `choose_file' blocks until the user answers (other SCOOP
		processors keep running: the external is marked blocking); read the
		answer from `chosen_path', empty when the user cancelled.
	]"

class
	SHELL_FILE_DIALOG

create
	make

feature {NONE} -- Initialization

	make
			-- Nothing chosen yet.
		do
			create chosen_path.make_empty
		ensure
			nothing_chosen: not has_choice
		end

feature -- Constants

	Max_path_chars: INTEGER = 4096
			-- Longest path the dialog may return (long paths included).

feature -- Access

	chosen_path: STRING_32
			-- Full path from the last `choose_file', empty when cancelled.

feature -- Status

	has_choice: BOOLEAN
			-- Did the last `choose_file' end with a file chosen?
		do
			Result := not chosen_path.is_empty
		end

feature -- Commands

	choose_file (a_title, a_filter, a_initial_dir: READABLE_STRING_GENERAL)
			-- Show the Open dialog titled `a_title' with filter `a_filter' (pairs separated
			-- by '|': "Scripts|*.md;*.txt|All files|*.*") starting in `a_initial_dir' (empty:
			-- wherever Windows last was).
		require
			title_present: not a_title.is_empty
			filter_paired: a_filter.has ('|')
		local
			l_title, l_filter, l_dir, l_answer: NATIVE_STRING
			l_buffer: MANAGED_POINTER
		do
			create l_title.make (a_title)
			create l_filter.make (a_filter)
			create l_dir.make (a_initial_dir)
			create l_buffer.make ((Max_path_chars + 1) * 2)
			if c_open_dialog (l_title.item, l_filter.item, l_dir.item, l_buffer.item, Max_path_chars) = 1 then
				create l_answer.make_from_pointer (l_buffer.item)
				chosen_path := l_answer.string
			else
				create chosen_path.make_empty
			end
		end

feature {NONE} -- Externals

	c_open_dialog (a_title, a_filter, a_dir, a_out: POINTER; a_cap: INTEGER): INTEGER
		external
			"C blocking inline use %"simple_shell.h%""
		alias
			"return shell_open_file_dialog((const wchar_t*)$a_title, (const wchar_t*)$a_filter, (const wchar_t*)$a_dir, (wchar_t*)$a_out, $a_cap);"
		end

end
