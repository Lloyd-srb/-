--!strict
--[[
	RoleSelectService — the players' 3 roles (GDD §4).
	[owner] 18 Nov 2026: players choose their 3 roles in the Lobby (Role page)
	and they are saved in their profile; there is no role screen in the match.
	During the short "RoleSelect" phase this service reads every player's
	saved picks (validated again: owned, no duplicates, never the wolf) and
	starts the match as soon as everyone's profile has loaded. A profile that
	is still loading when the phase ends gets random usable roles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Rng = require(ReplicatedStorage.Shared.Rng)

local RoleAssignment = require(script.Parent.Parent.Logic.RoleAssignment)

local MatchService = require(script.Parent.MatchService)
local ProfileService = require(script.Parent.ProfileService)
local RoundService = require(script.Parent.RoundService)

local RoleSelectService = {}

local rng = Rng.wrap(Random.new())

local function isOpen(): boolean
	return RoundService.State.Phase == "RoleSelect" and not MatchService.Started
end

local function takePicks(player: Player)
	if not isOpen() or not ProfileService.Get(player) then
		return
	end
	local picks = ProfileService.RolePicks(player, rng)
	if RoleAssignment.validatePicks(picks, ProfileService.UsableRoles(player)) then
		MatchService.SetPicks(player.UserId, picks)
	end
end

local function startWhenReady()
	if isOpen() and MatchService.AllPicked() then
		RoundService.Advance()
	end
end

function RoleSelectService.Init() end

function RoleSelectService.Start()
	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "RoleSelect" then
			for _, player in Players:GetPlayers() do
				takePicks(player)
			end
			task.defer(startWhenReady)
		end
	end)
	-- A profile that arrives during the phase.
	ProfileService.Loaded:Connect(function(player: Player)
		takePicks(player)
		startWhenReady()
	end)
end

return RoleSelectService
