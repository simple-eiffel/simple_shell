note
	description: "[
		THE ALT DOOR, callable without a keystroke (1.9.3).

		The Alt half of the keyboard cannot be assaulted the way the
		rest of this library is. Every other service here is exercised
		for real - the desktop IS grabbed, the clipboard DOES round
		trip - but a real Alt+F needs a visible window with the focus
		and a synthesised keystroke on the tester's own desktop, and
		this library will not take a machine away from the person
		sitting at it. So the header names its policy in two pure
		predicates, `shell_syskey_is_ours' and `shell_syschar_is_ours',
		and the window procedure does nothing but consult them. This
		class puts both, and the procedure's own claimed branch, where
		a headless test can reach them.

		What that leaves UNTESTED, said plainly: that Windows delivers
		Alt+F to the window procedure as WM_SYSKEYDOWN at all. That is
		the operating system's documented contract, and it was checked
		here by inspection only.
	]"

class
	SHELL_SYSKEY_PROBE

feature -- Status report

	syskey_is_claimed (a_vk: INTEGER): BOOLEAN
			-- Does the window procedure take WM_SYSKEYDOWN for virtual
			-- key `a_vk' - Alt+letter, Alt+digit, the Alt step keys,
			-- F10 - instead of leaving it to DefWindowProc?
		do
			Result := c_syskey_is_ours (a_vk) /= 0
		end

	syschar_is_swallowed (a_code: INTEGER): BOOLEAN
			-- Is the WM_SYSCHAR carrying character `a_code' eaten, so
			-- that Windows neither beeps nor opens the system menu
			-- behind a syskey the window has already taken?
		do
			Result := c_syschar_is_ours (a_code) /= 0
		end

feature -- Basic operations

	deliver_syskeydown (a_vk: INTEGER)
			-- Hand WM_SYSKEYDOWN(`a_vk') to the window procedure
			-- itself, from THIS translation unit, with a null window
			-- handle: the claimed branch never touches the handle - it
			-- pushes onto the shared queue and returns 0.
			--
			-- CLAIMED KEYS ONLY, by contract. An unclaimed key falls
			-- through to `DefWindowProcW', and DefWindowProc without a
			-- window is not something this library will ask for; the
			-- unclaimed side of the policy is asserted through
			-- `syskey_is_claimed' instead.
		require
			claimed: syskey_is_claimed (a_vk)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_wndproc((HWND)0, WM_SYSKEYDOWN, (WPARAM)$a_vk, (LPARAM)0);"
		end

feature {NONE} -- Externals

	c_syskey_is_ours (a_vk: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_syskey_is_ours((int)$a_vk);"
		end

	c_syschar_is_ours (a_code: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_syschar_is_ours((int)$a_code);"
		end

end
