--!strict
--[[
	ClientState — the few private facts this client was told by the server,
	shared between controllers: own form, own house tonight, own pack.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local ClientState = {
	Form = "Human", -- "Human" | "Wolf" | "Pup"
	HouseId = 0, -- 0 = no door of my own
	Hidden = false,
	Changed = Signal.new(),
}

function ClientState.set(key: string, value: any)
	if (ClientState :: any)[key] ~= value then
		(ClientState :: any)[key] = value
		ClientState.Changed:Fire(key)
	end
end

return ClientState
