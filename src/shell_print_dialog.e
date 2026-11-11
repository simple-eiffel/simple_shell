note
	description: "[
		The Windows print dialog (1v-c, 2026-11-11): PrintDlgEx, owned by a window. It asks
		for the printer, the page range, copies and collation, and the printer choices a print
		helper can take (duplex, paper source, paper size, orientation). It prints nothing: the
		caller prints with the answers (simple_pdf's print library runs Poppler's pdftocairo).

		Windows only. On Linux and macOS a program prints an existing PDF through its toolkit's
		print operation, whose dialog is part of it (port-coordination SIMPLE_GUI_SPEC.md, 1v-c),
		so `show' requires Windows.
	]"

class
	SHELL_PRINT_DIALOG

create
	make

feature {NONE} -- Initialization

	make
			-- Nothing chosen yet.
		do
			create printer_name.make_empty
			copies := 1
			is_all_pages := True
		ensure
			nothing_chosen: printer_name.is_empty
			one_copy: copies = 1
			all_pages: is_all_pages
		end

feature -- Answers

	Answer_print: INTEGER = 1
			-- The user chose Print.

	Answer_cancel: INTEGER = 0
			-- The user cancelled (or applied and closed).

	Answer_failed: INTEGER = -1
			-- The dialog could not run (`last_error_code' says why).

	last_answer: INTEGER
			-- The answer to the last `show'.

	last_error_code: INTEGER
			-- The HRESULT when the dialog could not run; -2 when Print came without a printer.

	printer_name: STRING_32
			-- The printer chosen.

	copies: INTEGER
			-- How many copies.

	is_collated: BOOLEAN
			-- Are the copies collated?

	is_all_pages: BOOLEAN
			-- Every page, or the range `first_page' to `last_page'?

	first_page, last_page: INTEGER
			-- The page range chosen (when not `is_all_pages').

	duplex: INTEGER
			-- `Duplex_unset', `Duplex_off', `Duplex_long_edge' or `Duplex_short_edge'.

	Duplex_unset: INTEGER = 0
	Duplex_off: INTEGER = 1
	Duplex_long_edge: INTEGER = 2
	Duplex_short_edge: INTEGER = 3

	paper_source: INTEGER
			-- The paper source (a DMBIN_ value); 0 when the printer did not say.

	paper_size: INTEGER
			-- The paper (a DMPAPER_ value); 0 when the printer did not say.

	orientation: INTEGER
			-- `Orientation_unset', `Orientation_portrait' or `Orientation_landscape'.

	Orientation_unset: INTEGER = 0
	Orientation_portrait: INTEGER = 1
	Orientation_landscape: INTEGER = 2

feature -- Showing

	show (a_owner: POINTER; a_page_count: INTEGER)
			-- The print dialog over window `a_owner' (default_pointer: the desktop) for a document
			-- of `a_page_count' pages (0: no page range offered). Blocks until the user answers.
		require
			windows: {PLATFORM}.is_windows
			page_count_not_negative: a_page_count >= 0
		local
			l_name, l_ints: MANAGED_POINTER
			i: INTEGER
		do
			create l_name.make (Name_capacity * 2)
			create l_ints.make (10 * 4)
			last_answer := c_show (a_owner, a_page_count, l_name.item, Name_capacity, l_ints.item)
			create printer_name.make_empty
			from i := 0 until i >= Name_capacity or else l_name.read_natural_16 (i * 2) = 0 loop
				printer_name.append_code (l_name.read_natural_16 (i * 2).to_natural_32)
				i := i + 1
			end
			copies := l_ints.read_integer_32 (0).max (1)
			is_collated := l_ints.read_integer_32 (4) = 1
			is_all_pages := last_answer /= Answer_print or else l_ints.read_integer_32 (8) = 1
			first_page := l_ints.read_integer_32 (12)
			last_page := l_ints.read_integer_32 (16)
			duplex := l_ints.read_integer_32 (20)
			paper_source := l_ints.read_integer_32 (24)
			paper_size := l_ints.read_integer_32 (28)
			orientation := l_ints.read_integer_32 (32)
			last_error_code := l_ints.read_integer_32 (36)
		ensure
			known_answer: last_answer >= Answer_failed and last_answer <= Answer_print
			named_when_printing: last_answer = Answer_print implies not printer_name.is_empty
			copies_positive: copies >= 1
			range_in_document: (last_answer = Answer_print and not is_all_pages) implies
				(1 <= first_page and first_page <= last_page and last_page <= a_page_count)
			known_duplex: duplex >= Duplex_unset and duplex <= Duplex_short_edge
			known_orientation: orientation >= Orientation_unset and orientation <= Orientation_landscape
		end

feature {NONE} -- Implementation

	Name_capacity: INTEGER = 260
			-- Wide characters for a printer name, the terminator included.

	c_show (a_owner: POINTER; a_max_page: INTEGER; a_name: POINTER; a_cap: INTEGER; a_ints: POINTER): INTEGER
		external "C inline use %"simple_shell_print_dialog.h%""
		alias "[
#ifdef _WIN32
			return shell_print_dialog_show ((HWND) $a_owner, $a_max_page, (wchar_t *) $a_name, $a_cap, (int *) $a_ints);
#else
			return -1;
#endif
		]"
		end

invariant
	copies_positive: copies >= 1

end
