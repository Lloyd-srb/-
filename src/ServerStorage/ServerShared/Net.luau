--!strict
--[[
	Net — server side of the RemoteEvents (used by both places).
	Every client -> server remote goes through Net.on, which rate-limits per
	player and per remote. Handlers must still validate every argument.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

local calls: { [Player]: { [string]: { number } } } = {}

local function allow(player: Player, name: string, rate: number, window: number): boolean
	local now = os.clock()
	local perPlayer = calls[player]
	if not perPlayer then
		perPlayer = {}
		calls[player] = perPlayer
	end
	local stamps = perPlayer[name]
	if not stamps then
		stamps = {}
		perPlayer[name] = stamps
	end
	while stamps[1] and now - stamps[1] > window do
		table.remove(stamps, 1)
	end
	if #stamps >= rate then
		return false
	end
	table.insert(stamps, now)
	return true
end

function Net.Init()
	Remotes.createAll()
	Players.PlayerRemoving:Connect(function(player)
		calls[player] = nil
	end)
end

function Net.Start() end

-- Listens to a client intent. `rate` calls per `window` seconds (defaults from Config.Net).
function Net.on(name: string, handler: (player: Player, ...any) -> (), rate: number?, window: number?)
	local maxCalls = rate or Config.Net.DefaultRate
	local perSeconds = window or Config.Net.DefaultWindow
	Remotes.get(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if allow(player, name, maxCalls, perSeconds) then
			handler(player, ...)
		end
	end)
end

function Net.fire(player: Player, name: string, ...: any)
	Remotes.get(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	Remotes.get(name):FireAllClients(...)
end

return Net
