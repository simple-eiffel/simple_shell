note
	description: "[
		The system clipboard, as text and as a bitmap. A service:
		clients use it so they never declare the externals.
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

feature -- Access: bitmap

	has_image: BOOLEAN
			-- Is there a bitmap (CF_DIB) on the clipboard?
		do
			Result := c_clip_has_image = 1
		end

	image_width: INTEGER
			-- Width of the clipboard bitmap; 0 when there is none.
		local
			wh: MANAGED_POINTER
		do
			create wh.make (8)
			if c_clip_image_size (wh.item, wh.item.plus (4)) = 1 then
				Result := wh.read_integer_32 (0)
			end
		ensure
			none_means_zero: not has_image implies Result = 0
		end

	image_height: INTEGER
			-- Height of the clipboard bitmap; 0 when there is none.
		local
			wh: MANAGED_POINTER
		do
			create wh.make (8)
			if c_clip_image_size (wh.item, wh.item.plus (4)) = 1 then
				Result := wh.read_integer_32 (4)
			end
		ensure
			none_means_zero: not has_image implies Result = 0
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

	set_image (a_bits: POINTER; a_w, a_h, a_stride: INTEGER)
			-- Put an ARGB32 image on the clipboard as a bitmap (CF_DIB):
			-- `a_bits' as `a_stride'-byte top-down rows - the layout
			-- `SHELL_DESKTOP.grab_into' delivers and cairo ARGB32
			-- surfaces expose, so a screen grab or a decoded PNG goes
			-- straight through. Alpha is forced opaque: bitmap consumers
			-- ignore the channel, and a premultiplied transparent pixel
			-- would otherwise show as its colour over black. Retries
			-- briefly against history managers, as `set_text' does.
		require
			positive: a_w > 0 and a_h > 0
			buffer: a_bits /= default_pointer
			rows_fit: a_stride >= a_w * 4
		local
			env: EXECUTION_ENVIRONMENT
			attempts: INTEGER
		do
			from
				attempts := 0
			until
				attempts >= 5 or else c_clip_set_image (a_bits, a_w, a_h, a_stride) = 1
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

	c_clip_set_image (a_bits: POINTER; a_w, a_h, a_stride: INTEGER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_clip_set_image((const void*)$a_bits, (int)$a_w, (int)$a_h, (int)$a_stride);"
		end

	c_clip_has_image: INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_clip_has_image();"
		end

	c_clip_image_size (a_w, a_h: POINTER): INTEGER
		external
			"C inline use %"simple_shell.h%""
		alias
			"return shell_clip_image_size((int*)$a_w, (int*)$a_h);"
		end

end
