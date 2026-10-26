note
	description: "[
		Printing (1.24.0, simple_bible GW-20): the printers there are, and
		one document at a time per process on the one chosen - its paper,
		its orientation, its pages, and an output file when the printer
		writes files (Microsoft Print to PDF then writes there without
		asking). What goes on a page is drawn on `dc' by the caller;
		simple_widgets draws it through cairo's Windows printing surface.

		No print dialog: the application lists `printer_names' itself, so
		the whole path runs headless.

		ONE DOCUMENT PER PROCESS (scan 20). `is_printing' says whether any
		document is open in the process; `owns_document' whether it is this
		printer's. Pages, the end and the abort belong to the owner only,
		and the C side claims the document atomically, so two processors
		cannot both begin one.
	]"

class
	SHELL_PRINTER

create
	make

feature {NONE} -- Initialization

	make
		do
		end

feature -- Printers

	default_printer: STRING_32
			-- The default printer's name; empty when there is none.
		local
			l_buf: MANAGED_POINTER
			l_n: INTEGER
		do
			create l_buf.make (Name_capacity * 2)
			l_n := c_default (l_buf.item, Name_capacity)
			Result := wide_string (l_buf, l_n)
		end

	printer_names: ARRAYED_LIST [STRING_32]
			-- Every local and connected printer.
		local
			l_buf: MANAGED_POINTER
			l_n: INTEGER
		do
			create l_buf.make (List_capacity * 2)
			l_n := c_names (l_buf.item, List_capacity)
			create Result.make (8)
			across wide_string (l_buf, l_n).split ('%N') as ic_name loop
				if not ic_name.is_empty then
					Result.extend (ic_name)
				end
			end
		end

	has_printer (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Is there a printer called `a_name'?
		do
			Result := across printer_names as ic_name some ic_name.same_string_general (a_name) end
		end

feature -- Paper (Windows DMPAPER codes)

	Paper_default: INTEGER = 0
			-- The printer's own.
	Paper_letter: INTEGER = 1
	Paper_legal: INTEGER = 5
	Paper_a4: INTEGER = 9

feature -- Document

	is_printing: BOOLEAN
			-- Is a document open (in this process)?
		do
			Result := c_dc /= default_pointer
		end

	owns_document: BOOLEAN
			-- Is the open document this printer's?
		do
			Result := began and then is_printing
		end

	is_in_page: BOOLEAN
			-- Is a page open?
		do
			Result := c_in_page = 1
		end

	begin_document (a_printer, a_title: READABLE_STRING_GENERAL; a_output: detachable READABLE_STRING_GENERAL;
			a_paper: INTEGER; a_landscape: BOOLEAN): BOOLEAN
			-- Begin a document titled `a_title' on `a_printer', written to
			-- `a_output' when given, on paper `a_paper' (`Paper_default' keeps
			-- the printer's), landscape when `a_landscape'. True when it began.
			-- False too when another document is open in the process (the C
			-- side claims it atomically: no check-then-call race).
		require
			printer_named: not a_printer.is_empty
			paper_known: a_paper >= 0
		local
			l_printer, l_title, l_output: NATIVE_STRING
		do
			create l_printer.make (a_printer)
			create l_title.make (a_title)
			if attached a_output as al_output then
				create l_output.make (al_output)
			else
				create l_output.make ("")
			end
			Result := c_begin (l_printer.item, l_title.item, l_output.item, a_paper, a_landscape.to_integer) = 1
			began := Result
		ensure
			owned_when_begun: Result = owns_document
		end

	begin_page: BOOLEAN
			-- Open the next page. True when it opened.
		require
			owner: owns_document
			between_pages: not is_in_page
		do
			Result := c_begin_page = 1
		ensure
			open_when_true: Result implies is_in_page
		end

	end_page: BOOLEAN
			-- Close the page. True when the printer took it.
		require
			owner: owns_document
			in_page: is_in_page
		do
			Result := c_end_page = 1
		ensure
			closed: not is_in_page
		end

	end_document: BOOLEAN
			-- Hand the document to the spooler (closing an open page). True
			-- when it was accepted.
		require
			owner: owns_document
		do
			Result := c_end = 1
			began := False
		ensure
			done: not owns_document
		end

	abort_document
			-- Throw the document away.
		require
			owner: owns_document
		do
			c_abort
			began := False
		ensure
			done: not owns_document
		end

	dc: POINTER
			-- The printer's device context, to draw a page on.
		require
			owner: owns_document
		do
			Result := c_dc
		end

feature -- The page (while printing, in device dots)

	dots_per_inch_x: INTEGER
		require
			printing: is_printing
		do
			Result := c_caps (88)
		end

	dots_per_inch_y: INTEGER
		require
			printing: is_printing
		do
			Result := c_caps (90)
		end

	printable_width: INTEGER
			-- The part of the paper the printer can reach, across.
		require
			printing: is_printing
		do
			Result := c_caps (8)
		end

	printable_height: INTEGER
		require
			printing: is_printing
		do
			Result := c_caps (10)
		end

	paper_width: INTEGER
			-- The whole sheet, across.
		require
			printing: is_printing
		do
			Result := c_caps (110)
		end

	paper_height: INTEGER
		require
			printing: is_printing
		do
			Result := c_caps (111)
		end

	unprintable_left: INTEGER
			-- From the sheet's left edge to where `dc' starts drawing.
		require
			printing: is_printing
		do
			Result := c_caps (112)
		end

	unprintable_top: INTEGER
		require
			printing: is_printing
		do
			Result := c_caps (113)
		end

feature {NONE} -- Implementation

	began: BOOLEAN
			-- Did this printer begin the open document?

	Name_capacity: INTEGER = 512
	List_capacity: INTEGER = 16384

	wide_string (a_buf: MANAGED_POINTER; a_count: INTEGER): STRING_32
			-- The first `a_count' UTF-16 units of `a_buf' (printer names are
			-- in the Basic Multilingual Plane in practice; a pair is kept as two).
		require
			fits: a_count >= 0 and a_count * 2 <= a_buf.count
		local
			i: INTEGER
		do
			create Result.make (a_count)
			from
				i := 0
			until
				i >= a_count
			loop
				Result.append_code (a_buf.read_natural_16 (i * 2).to_natural_32)
				i := i + 1
			end
		end

	c_default (a_buf: POINTER; a_cap: INTEGER): INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_default((wchar_t*)$a_buf, $a_cap);"
		end

	c_names (a_buf: POINTER; a_cap: INTEGER): INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_names((wchar_t*)$a_buf, $a_cap);"
		end

	c_begin (a_printer, a_title, a_output: POINTER; a_paper, a_landscape: INTEGER): INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_begin((const wchar_t*)$a_printer, (const wchar_t*)$a_title, (const wchar_t*)$a_output, $a_paper, $a_landscape);"
		end

	c_begin_page: INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_begin_page();"
		end

	c_end_page: INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_end_page();"
		end

	c_end: INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_end();"
		end

	c_abort
		external "C inline use %"simple_shell_print.h%""
		alias "shell_print_abort();"
		end

	c_caps (a_index: INTEGER): INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_caps($a_index);"
		end

	c_dc: POINTER
		external "C inline use %"simple_shell_print.h%""
		alias "return (EIF_POINTER)shell_print_dc();"
		end

	c_in_page: INTEGER
		external "C inline use %"simple_shell_print.h%""
		alias "return shell_print_in_page();"
		end

end
