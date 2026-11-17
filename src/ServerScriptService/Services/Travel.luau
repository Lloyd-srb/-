--!strict
--[[
	Travel — sending players back to the Lobby place (end of match, or not
	enough players arrived). Teleports do not work in Studio, and need
	Config.Places.LobbyPlaceId.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)

local Travel = {}

-- Returns whether the teleport was started.
function Travel.toLobby(players: { Player }): boolean
	local lobby = Config.Places.LobbyPlaceId
	if lobby == 0 or RunService:IsStudio() or #players == 0 then
		return false
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(lobby, players)
	end)
	if not ok then
		warn("[Travel] teleport to the lobby failed: " .. tostring(err))
	end
	return ok
end

return Travel
