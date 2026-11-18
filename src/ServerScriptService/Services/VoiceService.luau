--!strict
--[[
	VoiceService — applies Logic.VoiceRules to every player's microphone.

	Uses Roblox's audio API: each player's voice is an AudioDeviceInput under
	their Player. Its AccessType + SetUserIdAccessList decide who can hear it,
	so the server decides; a modified client cannot get around it.
	Needs VoiceChatService.UseAudioApi = Enabled in the place (see
	docs/OWNER_TODO.md). Without it there is nothing to control, and this
	service does nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)

local Logic = script.Parent.Parent.Logic
local Roster = require(Logic.Roster)
local VoiceRules = require(Logic.VoiceRules)

local MatchService = require(script.Parent.MatchService)
local RoundService = require(script.Parent.RoundService)
local WolfService = require(script.Parent.WolfService)

local VoiceService = {}

-- Last rule applied per user id (tests read it; also avoids repeating calls).
VoiceService.Applied = {} :: { [number]: VoiceRules.Rule }

local function speakerOf(userId: number): VoiceRules.Speaker
	local phase: "Lobby" | "Match" | "Over" = if not MatchService.Started
		then "Lobby"
		elseif MatchService.Winner then "Over"
		else "Match"
	local member = MatchService.Roster.Members[userId]
	if not member then
		return { Id = userId, Phase = phase, Alive = phase ~= "Match", Beast = false }
	end
	return {
		Id = userId,
		Phase = phase,
		Alive = member.Alive,
		Beast = member.Alive and Roster.isWolfSide(member) and WolfService.IsTransformed(member.Id),
	}
end

local function microphone(player: Player): Instance?
	return player:FindFirstChildOfClass("AudioDeviceInput")
end

local function apply(player: Player, rule: VoiceRules.Rule)
	VoiceService.Applied[player.UserId] = rule
	local mic = microphone(player)
	if not mic then
		return
	end
	pcall(function()
		local input = mic :: any
		if rule.Open then
			input.AccessType = Enum.AccessModifierType.Deny
			input:SetUserIdAccessList({})
		else
			input.AccessType = Enum.AccessModifierType.Allow
			input:SetUserIdAccessList(rule.Allow)
		end
	end)
end

function VoiceService.Refresh()
	local everyone: { VoiceRules.Speaker } = {}
	for _, player in Players:GetPlayers() do
		table.insert(everyone, speakerOf(player.UserId))
	end
	for _, player in Players:GetPlayers() do
		apply(player, VoiceRules.forSpeaker(speakerOf(player.UserId), everyone))
	end
end

function VoiceService.Init() end

function VoiceService.Start()
	local function refreshSoon()
		task.defer(VoiceService.Refresh)
	end
	MatchService.MatchStarted:Connect(refreshSoon)
	MatchService.MemberDied:Connect(refreshSoon)
	MatchService.MemberRevived:Connect(refreshSoon)
	MatchService.MemberConverted:Connect(refreshSoon)
	MatchService.GameOver:Connect(refreshSoon)
	WolfService.FormChanged:Connect(refreshSoon)
	RoundService.PhaseStarted:Connect(function(_state: PhaseMachine.PhaseState)
		refreshSoon()
	end)
	local function watch(player: Player)
		-- The microphone object can arrive after the player (pcall: the offline
		-- test engine's players have no ChildAdded).
		pcall(function()
			player.ChildAdded:Connect(function(child: Instance)
				if child:IsA("AudioDeviceInput") then
					refreshSoon()
				end
			end)
		end)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		watch(player)
		refreshSoon()
	end)
	Players.PlayerRemoving:Connect(refreshSoon)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return VoiceService
