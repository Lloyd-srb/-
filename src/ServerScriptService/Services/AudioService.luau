--!strict
--[[
	AudioService — tells clients which sound to play (GDD §6.5).

	World sounds (door hits, screams, the wolf's swing...) are only sent to
	players close enough to hear them (Config.Audio.Radius), measured from
	where they are listening: their body, or the hiding spot their camera is
	in. Sending them to everyone would let a modified client know where every
	attack happens. A sound whose ID is still 0 is not sent at all.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Net = require(script.Parent.Net)

local AudioService = {}

local function isSet(key: string): boolean
	local id = (Config.Sounds :: any)[key]
	if id == nil then
		warn(`[AudioService] unknown sound key {key}`)
	end
	return type(id) == "number" and id ~= 0
end

-- Where this player hears from (nil = nowhere, e.g. no character yet).
local function earOf(player: Player): Vector3?
	local ok, focus = pcall(function()
		return player.ReplicationFocus -- set to the hiding spot while hidden
	end)
	if ok and focus and focus:IsA("BasePart") then
		return focus.CFrame.Position
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.CFrame.Position else nil
end

-- A sound at a place in the world, for players within its radius.
function AudioService.At(key: string, position: Vector3, radius: number?)
	if not isSet(key) then
		return
	end
	local reach = radius or Config.Audio.Radius[key] or Config.Audio.DefaultRadius
	for _, player in Players:GetPlayers() do
		local ear = earOf(player)
		if ear and (ear - position).Magnitude <= reach then
			Net.fire(player, "Sound", { Key = key, At = position })
		end
	end
end

-- A sound for one player only (no position).
function AudioService.To(player: Player, key: string)
	if isSet(key) then
		Net.fire(player, "Sound", { Key = key })
	end
end

-- A sound everybody hears (no position).
function AudioService.All(key: string)
	if isSet(key) then
		Net.fireAll("Sound", { Key = key })
	end
end

function AudioService.Init() end
function AudioService.Start() end

return AudioService
