note
	description: "A worker processor that asks SHELL_WAKE.is_pump_thread on its own thread (W11)."

class
	PUMP_THREAD_PROBE

feature -- Access

	answer: BOOLEAN
			-- What `ask' heard.

	asked: BOOLEAN

feature -- Basic operations

	ask
		do
			answer := (create {SHELL_WAKE}).is_pump_thread
			asked := True
		ensure
			asked: asked
		end

end
