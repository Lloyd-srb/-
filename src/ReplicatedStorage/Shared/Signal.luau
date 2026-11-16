--!strict
--[[
	Signal — minimal in-process event. Handlers run immediately, in connection
	order, each in its own thread (so a handler may yield without blocking the
	others or the code that fired the signal).
]]

local Signal = {}
Signal.__index = Signal

export type Handler = (...any) -> ()
export type Signal = typeof(setmetatable({} :: { _handlers: { Handler } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

-- Returns a function that disconnects the handler.
function Signal.Connect(self: Signal, handler: Handler): () -> ()
	table.insert(self._handlers, handler)
	return function()
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

return Signal
