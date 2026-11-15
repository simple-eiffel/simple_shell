note
	description: "[
		Whether the machine has a usable route to a network, as the system
		sees it: not whether a given server answers. A cached answer kept by
		the platform's own monitor, which starts on the first question:
		Windows' Network List Manager (asked again after each change of the
		machine's addresses), macOS's nw_path_monitor (online when the path
		is satisfied) and GIO's GNetworkMonitor (network-available). Asking
		costs nothing and never waits on the network. Tests feed the same
		cache with `test_report', so they need no network.
	]"

class
	SHELL_NETWORK

feature -- Status

	is_online: BOOLEAN
			-- Does the system have a usable route to a network now? True until the
			-- platform's monitor first answers (milliseconds), and where there is none.
		do
			Result := c_online /= 0
		end

feature -- Tests

	test_report (a_online: BOOLEAN)
			-- Tests: answer `is_online' with `a_online' until the network really
			-- changes; the platform's monitor writes only on a change of its own answer.
		do
			c_test_report (if a_online then 1 else 0 end)
		ensure
			reported: is_online = a_online
		end

feature {NONE} -- Externals

	c_online: INTEGER
			-- The cached answer, 1 or 0; the first call starts the platform's monitor.
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_network_online();"
		end

	c_test_report (a_online: INTEGER)
		external
			"C inline use %"simple_shell.h%""
		alias
			"shell_network_test_report($a_online);"
		end

end
