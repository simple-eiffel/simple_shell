note
	description: "[
		The SDK-macro tripwire (the 1.9.1 defect).

		Both inline externals below pull a COM/RPC header BEFORE
		simple_shell.h - the include order a finalized build produces
		when a sibling library's COM header lands earlier in the same
		concatenated translation unit. rpcndr.h does `#define small
		char', so on the pre-1.9.1 header the declaration `HICON big,
		small;' compiled as `HICON big, char;' and the C phase died
		with C2059 / C2513. sw_demo's release build failed exactly
		there on 2026-09-02.

		This class is therefore a COMPILE-TIME test: on the old header
		the test target does not build at all. The two queries then
		prove at run time that the tripwire is still armed and that the
		poisoned unit really reached simple_shell.h.

		THE NAME IS LOAD-BEARING. Finalized C names a class's generated
		file from the class name's first two letters, lowercased, and
		concatenates a partition's files alphabetically. `sd' sorts
		ahead of every SHELL_* class's `sh', so this class's poisoned
		include of simple_shell.h is the FIRST in its unit. Sorted the
		other way, simple_shell.h would already be guarded-out and the
		test would pass on a broken header - which is how the first cut
		of this test failed silently. Rename it SHELL_-anything and the
		build stops with the #error in shell_sdk_poison.h.
	]"
	author: "Larry Rix"

class
	SDK_MACRO_TRIPWIRE

feature -- Access

	poison_is_in_force: BOOLEAN
			-- Is a Windows SDK header really defining `small' in this
			-- translation unit? False means the tripwire has gone
			-- blind and must be re-pointed - not that all is well.
		external
			"C inline use %"shell_sdk_poison.h%", %"simple_shell.h%", %"shell_sdk_tripwire.h%""
		alias
			"return (EIF_BOOLEAN) (shell_tripwire_poison_in_force() != 0);"
		end

	header_survived_the_poison: BOOLEAN
			-- Did simple_shell.h parse, compile and link in a unit the
			-- SDK had already poisoned? This is unreachable code on a
			-- broken header: the build fails first.
		external
			"C inline use %"shell_sdk_poison.h%", %"simple_shell.h%", %"shell_sdk_tripwire.h%""
		alias
			"return (EIF_BOOLEAN) (shell_tripwire_shell_header_survived() != 0);"
		end

end
