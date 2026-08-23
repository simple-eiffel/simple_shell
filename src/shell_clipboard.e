note
	description: "[
		The system clipboard, as text. a service: clients
		use it so they never declare the externals.
	]"

class
	SHELL_CLIPBOARD

feature -- Access

	text: STRING_32
			-- Clipboard content as text; empty when none.
		local
			buf: MANAGED_POINTER
			n, i, attempts: INTEGER
			c: NATURAL_16
			env: EXECUTION_ENVIRONMENT
		do
			create Result.make_empty
			create buf.make (Buffer_bytes)
			n := c_clip_get (buf.item, Buffer_bytes // 2)
			from
				attempts := 0
			until
				n > 0 or attempts >= 5 or not has_text
			loop
					-- the format probe says text exists but the read
					-- came back empty: OpenClipboard lost the race
					-- against a history manager - retry briefly.
				create env
				env.sleep (10_000_000)
				n := c_clip_get (buf.item, Buffer_bytes // 2)
				attempts := attempts + 1
			end
			from
				i := 0
			until
				i >= n
			loop
				c := buf.read_natural_16 (i * 2)
				if c >= 0xD800 and c <= 0xDBFF and i + 1 < n then
						-- surrogate pair: one code point across two units (R8)
					Result.append_code (0x10000
						+ (c.to_natural_32 - 0xD800) * 0x400
						+ (buf.read_natural_16 ((i + 1) * 2).to_natural_32 - 0xDC00))
					i := i + 2
				else
					Result.append_character (c.to_character_32)
					i := i + 1
				end
			end
		end

	has_text: BOOLEAN
		do
			Result := c_clip_has_text = 1
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- Write to the clipboard, retrying briefly: history
			-- managers grab the clipboard right after every change,
			-- so the very next OpenClipboard often loses the race.
		local
			ns: NATIVE_STRING
			env: EXECUTION_ENVIRONMENT
			attempts: INTEGER
		do
			create ns.make (a_text)
			from
				attempts := 0
			until
				attempts >= 5 or else c_clip_set (ns.item) = 1
			loop
				create env
				env.sleep (10_000_000)
				attempts := attempts + 1
			end
		end

feature {NONE} -- Implementation

	Buffer_bytes: INTEGER = 2097152
			-- One million characters of paste headroom (the old 128k
			-- cap was the limit a document paste could actually hit).

feature {NONE} -- Externals

	c_clip_set (a_s: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_clip_set((const wchar_t*)$a_s);"
		end

	c_clip_get (a_buf: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_clip_get((wchar_t*)$a_buf, (int)$a_cap);"
		end

	c_clip_has_text: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_clip_has_text();"
		end

end
