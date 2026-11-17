--!strict
--[[
	RoleSelectService — the role-selection screen (GDD §4).
	Before day 1, every player picks 3 of the roles they may use. The server
	validates the picks (owned, level gate, no duplicates, never the wolf).
	Anyone who has not confirmed when the timer ends gets random picks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)

local RoleAssignment = require(script.Parent.Parent.Logic.RoleAssignment)

local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)
local RoundService = require(script.Parent.RoundService)

local RoleSelectService = {}

local function isOpen(): boolean
	return RoundService.State.Phase == "RoleSelect" and not MatchService.Started
end

local function sendOptions(player: Player)
	local usable: { Config.RoleId } = {}
	local map = ProfileService.UsableRoles(player)
	for _, roleId in Config.RoleOrder do
		if map[roleId] then
			table.insert(usable, roleId)
		end
	end
	Net.fire(player, "RoleOptions", {
		Usable = usable,
		PickCount = Config.RoleSelect.PickCount,
		Level = ProfileService.Level(player),
	})
	local confirmed = MatchService.PicksOf(player.UserId)
	if confirmed then
		Net.fire(player, "RolePicksAck", confirmed)
	end
end

local function onPicks(player: Player, chosen: any)
	if not isOpen() or type(chosen) ~= "table" then
		return
	end
	-- Copy into a clean array of strings: never trust the client's table.
	local picks: { Config.RoleId } = {}
	for index = 1, Config.RoleSelect.PickCount + 1 do
		local roleId = chosen[index]
		if type(roleId) == "string" then
			table.insert(picks, roleId)
		end
	end
	if not RoleAssignment.validatePicks(picks, ProfileService.UsableRoles(player)) then
		return
	end
	MatchService.SetPicks(player.UserId, picks)
	Net.fire(player, "RolePicksAck", picks)

	if Config.RoleSelect.EndWhenAllPicked and MatchService.AllPicked() then
		RoundService.Advance()
	end
end

function RoleSelectService.Init() end

function RoleSelectService.Start()
	Net.on("RolePicks", onPicks, 10, 5)

	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "RoleSelect" then
			for _, player in Players:GetPlayers() do
				sendOptions(player)
			end
		end
	end)
	MatchService.SyncRequested:Connect(function(player: Player)
		if isOpen() then
			sendOptions(player)
		end
	end)
	-- The saved profile arrived after the screen opened: show the roles owned.
	ProfileService.Loaded:Connect(function(player: Player)
		if isOpen() then
			sendOptions(player)
		end
	end)
end

return RoleSelectService
