note
	description: "[
		Global hotkeys: chords that reach this application whichever window has
		focus, even when all of its windows are hidden. Each registered chord
		arrives on the shared queue as event 51 with the id in the first field,
		the virtual key in the second and the modifiers in the fourth
		(`SHELL_WINDOW.event_extra'). A held chord fires once (MOD_NOREPEAT).

		Safety interlock: `register' requires a modifier. A chord with no
		modifier takes that key away from EVERY application on the desktop
		until it is unregistered, so it has its own name, `register_bare', for
		the deliberate case (a presentation clicker's PageDown while recording),
		and the caller owns unregistering it promptly.

		Register from the thread that pumps events: Windows binds the hotkey to
		the calling thread.
	]"

class
	SHELL_HOTKEYS

create
	make

feature {NONE} -- Initialization

	make
			-- No hotkeys registered.
		do
			create registered.make (16)
		ensure
			none: count = 0
		end

feature -- Constants

	Mod_alt: INTEGER = 0x1
	Mod_control: INTEGER = 0x2
	Mod_shift: INTEGER = 0x4
	Mod_win: INTEGER = 0x8
	All_modifiers: INTEGER = 0xF

	Max_id: INTEGER = 0xBFFF
			-- Application hotkey ids are 1..0xBFFF (higher ids belong to DLLs).

	Event_hotkey: INTEGER = 51

feature -- Access

	count: INTEGER
			-- Hotkeys currently registered through this object.
		do
			Result := registered.count
		end

	last_succeeded: BOOLEAN
			-- Did the last `register' or `register_bare' get its chord?
			-- (False when another application already holds it.)

feature -- Status

	is_registered (a_id: INTEGER): BOOLEAN
			-- Is hotkey `a_id' registered through this object?
		do
			Result := registered.has (a_id)
		end

feature -- Element change

	register (a_id, a_modifiers, a_vk: INTEGER)
			-- Register the chord `a_modifiers' + `a_vk' as hotkey `a_id'.
		require
			id_range: a_id >= 1 and a_id <= Max_id
			free_id: not is_registered (a_id)
			has_modifier: a_modifiers /= 0
			known_modifiers: a_modifiers <= All_modifiers
			vk_range: a_vk >= 1 and a_vk <= 254
		do
			grab (a_id, a_modifiers, a_vk)
		ensure
			outcome: last_succeeded = is_registered (a_id)
			counted: count = old count + last_succeeded.to_integer
		end

	register_bare (a_id, a_vk: INTEGER)
			-- Take key `a_vk' itself, with no modifier, from every application
			-- until `unregister' (a clicker or foot pedal while recording).
		require
			id_range: a_id >= 1 and a_id <= Max_id
			free_id: not is_registered (a_id)
			vk_range: a_vk >= 1 and a_vk <= 254
		do
			grab (a_id, 0, a_vk)
		ensure
			outcome: last_succeeded = is_registered (a_id)
			counted: count = old count + last_succeeded.to_integer
		end

	unregister (a_id: INTEGER)
			-- Give hotkey `a_id' back.
		require
			registered: is_registered (a_id)
		do
			c_unregister (a_id)
			registered.prune (a_id)
		ensure
			released: not is_registered (a_id)
			counted: count = old count - 1
		end

	unregister_all
			-- Give every hotkey of this object back.
		do
			across registered as ic loop
				c_unregister (ic)
			end
			registered.wipe_out
		ensure
			none: count = 0
		end

feature -- Testing

	simulate (a_id, a_modifiers, a_vk: INTEGER)
			-- Post the message Windows would send for hotkey `a_id' to this thread,
			-- so the next pump turns it into event 51.
		require
			id_range: a_id >= 1 and a_id <= Max_id
		do
			c_simulate (a_id, a_modifiers, a_vk)
		end

feature {NONE} -- Implementation

	registered: ARRAYED_SET [INTEGER]
			-- Ids registered through this object.

	grab (a_id, a_modifiers, a_vk: INTEGER)
			-- Register and record the outcome.
		do
			last_succeeded := c_register (a_id, a_modifiers, a_vk) = 1
			if last_succeeded then
				registered.extend (a_id)
			end
		ensure
			recorded: last_succeeded = registered.has (a_id)
		end

feature {NONE} -- Externals

	c_register (a_id, a_mods, a_vk: INTEGER): INTEGER
		external "C inline use %"simple_shell.h%""
		alias "return shell_hotkey_register($a_id, $a_mods, $a_vk);"
		end

	c_unregister (a_id: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_hotkey_unregister($a_id);"
		end

	c_simulate (a_id, a_mods, a_vk: INTEGER)
		external "C inline use %"simple_shell.h%""
		alias "shell_hotkey_simulate($a_id, $a_mods, $a_vk);"
		end

invariant
	ids_in_range: across registered as ic all ic >= 1 and ic <= Max_id end

end
