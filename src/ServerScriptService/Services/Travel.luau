--!strict
--[[
	Travel — sending players back to the Lobby place (end of match, or not
	enough players arrived). Teleports do not work in Studio, and need
	Config.Places.LobbyPlaceId.
]]

local Players = game:GetService("Players")
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

--[[
	Sends everyone on this server to the lobby, then tries again for whoever
	is still here a little later: a teleport can fail on its own (Roblox
	hiccup, a slow client), and a finished match server must not keep anyone.
]]
function Travel.sendEveryoneHome()
	if Config.Places.LobbyPlaceId == 0 or RunService:IsStudio() then
		return
	end
	task.spawn(function()
		for _ = 1, Config.Match.HomeAttempts do
			local players = Players:GetPlayers()
			if #players == 0 then
				return
			end
			Travel.toLobby(players)
			task.wait(Config.Match.HomeRetryDelay)
		end
	end)
end

return Travel
