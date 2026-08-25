note
	description: "[
		One inline external of its own, so finalized C gives THIS
		class a translation unit apart from SHELL_WINDOW's pump.
		Pushing from here and draining there proves the header's
		SHELL_SHARED state is one process-wide instance - the 1.8.0
		lockup was exactly these two sites holding different copies
		of the queue: the overlay pushed where nobody drained.
	]"

class
	SHELL_PUSH_PROBE

feature -- Basic operations

	push_marker
			-- Push the cross-unit marker event (type 77, payload
			-- 7, 8, 9) onto the shared shell queue from this class's
			-- translation unit.
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_push(77, 7, 8, 9);"
		end

end
