note
	description: "[
		Windows' inbox spell checker (ISpellChecker, Windows 8+) as a
		SURFACE-layer service - the zero-model, zero-license AI-assist:
		misspelling ranges for a text, suggestions for a word. Absent
		language support degrades to no findings, never to failure.

		WINDOWS-ONLY: ISpellChecker is a Windows 8+ platform service.
		On any other OS this class must be replaced (SymSpell, MIT, is
		the portable path) - it will not merely degrade, it will not
		exist. The toolkit itself is currently Win32-only by charter,
		but any future port must treat this service as a seam.
	]"

class
	SHELL_SPELLER

feature -- Queries

	misspellings (a_text: READABLE_STRING_GENERAL): ARRAYED_LIST [TUPLE [lo, hi: INTEGER]]
			-- Ranges (character positions, 1-based inclusive bounds
			-- as lo+1..hi convention like selections) of misspelled
			-- words in `a_text'. UTF-16 unit indices; identical to
			-- code-point indices for BMP text.
		local
			ns: NATIVE_STRING
			buf: MANAGED_POINTER
			n, i, s, l: INTEGER
		do
			create Result.make (8)
			if not a_text.is_empty then
				create ns.make (a_text)
				create buf.make (Cap_pairs * 8)
				n := c_spell_check (ns.item, buf.item, Cap_pairs)
				from
					i := 0
				until
					i >= n
				loop
					s := buf.read_integer_32 (i * 8)
					l := buf.read_integer_32 (i * 8 + 4)
					if l > 0 then
						Result.extend ([s, s + l])
					end
					i := i + 1
				end
			end
		ensure
			ranges_ordered: across Result as r all r.lo < r.hi end
		end

	suggestions (a_word: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
			-- Up to five corrections for `a_word'.
		local
			ns: NATIVE_STRING
			buf: MANAGED_POINTER
			n, i: INTEGER
			c: NATURAL_16
			cur: STRING_32
		do
			create Result.make (5)
			if not a_word.is_empty then
				create ns.make (a_word)
				create buf.make (Sug_bytes)
				n := c_spell_suggest (ns.item, buf.item, Sug_bytes // 2)
				if n > 0 then
					create cur.make (16)
					from
						i := 0
					until
						i >= Sug_bytes // 2
					loop
						c := buf.read_natural_16 (i * 2)
						if c = 0 then
							if not cur.is_empty then
								Result.extend (cur.twin)
							end
							i := Sug_bytes
						elseif c = 10 then
							Result.extend (cur.twin)
							cur.wipe_out
						else
							cur.append_character (c.to_character_32)
						end
						i := i + 1
					end
				end
			end
		ensure
			few: Result.count <= 5
		end

feature -- Teaching

	ignore (a_word: READABLE_STRING_GENERAL): BOOLEAN
			-- Stop flagging `a_word' for THIS SESSION; the squiggle
			-- returns next launch. False when the checker is absent.
		require
			something: not a_word.is_empty
		local
			ns: NATIVE_STRING
		do
			create ns.make (a_word)
			Result := c_spell_ignore (ns.item) = 1
		end

	add_to_dictionary (a_word: READABLE_STRING_GENERAL): BOOLEAN
			-- Teach `a_word' PERMANENTLY: it lands in the user's
			-- Windows dictionary, the same one Edge and Office
			-- honour. False when the checker is absent.
		require
			something: not a_word.is_empty
		local
			ns: NATIVE_STRING
		do
			create ns.make (a_word)
			Result := c_spell_add (ns.item) = 1
		end

feature {NONE} -- Implementation

	Cap_pairs: INTEGER = 64
	Sug_bytes: INTEGER = 2048

feature {NONE} -- Externals

	c_spell_check (a_text, a_out: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_spell_check((const wchar_t*)$a_text, (int*)$a_out, (int)$a_cap);"
		end

	c_spell_ignore (a_word: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_spell_ignore((const wchar_t*)$a_word);"
		end

	c_spell_add (a_word: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_spell_add((const wchar_t*)$a_word);"
		end

	c_spell_suggest (a_word, a_buf: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_spell_suggest((const wchar_t*)$a_word, (wchar_t*)$a_buf, (int)$a_cap);"
		end

end
