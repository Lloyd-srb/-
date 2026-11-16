--!strict
--[[
	VoteService — the daily meeting and vote (GDD §6.2).

	- The bell on the meeting table can be rung once the day is 3 minutes old.
	- When the meeting starts, every living player (forest included) is warped
	  to the table and cannot walk.
	- Clients send "select" / "confirm" intents. Everyone receives silhouette
	  counts only; who voted for whom never leaves the server.
	- When the timer ends, unconfirmed selections count, the result is tallied
	  and the exiled player dies without a role reveal.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local Roster = require(Logic.Roster)
local VoteTally = require(Logic.VoteTally)

local MatchService = require(script.Parent.MatchService)
local MoveService = require(script.Parent.MoveService)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)

local FREEZE_KEY = "Meeting"
local CLEAR_SELECTION = 0 -- VoteSelect(0) removes an unconfirmed selection

local VoteService = {}

local rng = Rng.wrap(Random.new())
local isOpen = false
local ballots: { [number]: VoteTally.Ballot } = {}
local bellPrompt: ProximityPrompt? = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function chiefId(): number?
	local chief = Roster.findRole(MatchService.Roster, "Chief")
	return if chief then chief.Id else nil
end

-- Array form: remote arguments must not use sparse numeric keys.
local function countsPayload(): { any }
	local list = {}
	for target, count in VoteTally.publicCounts(ballots, chiefId()) do
		table.insert(list, { Id = target, Pending = count.Pending, Confirmed = count.Confirmed })
	end
	return list
end

local function sendMine(player: Player)
	local ballot = ballots[player.UserId]
	Net.fire(player, "VoteMine", {
		Target = if ballot then ballot.Target else CLEAR_SELECTION,
		Confirmed = ballot ~= nil and ballot.Confirmed,
	})
end

local function candidates(): { any }
	local list = {}
	for _, member in Roster.alive(MatchService.Roster) do
		table.insert(list, { Id = member.Id, Name = member.Name, IsBot = member.IsBot })
	end
	return list
end

local function meetingSpot(index: number): Attachment?
	local map = workspace:FindFirstChild("Map")
	local markers = map and map:FindFirstChild("Markers")
	local spot = markers and markers:FindFirstChild("MeetingSpot" .. index)
	return if spot and spot:IsA("Attachment") then spot else nil
end

--------------------------------------------------------------------------------
-- Meeting
--------------------------------------------------------------------------------

local function openMeeting()
	table.clear(ballots)
	isOpen = true

	local seat = 0
	for _, member in Roster.alive(MatchService.Roster) do
		seat += 1
		local character = MatchService.CharacterOf(member.Id)
		local spot = meetingSpot((seat - 1) % Config.Map.HouseCount + 1)
		if character and spot then
			character:PivotTo(Zones.worldCFrame(spot))
		end
		-- Nobody can walk during the meeting (GDD §6.2).
		MoveService.SetModifier(member.Id, FREEZE_KEY, { Override = 0, NoJump = true })
	end

	Net.fireAll("VoteOpened", { Candidates = candidates() })
	Net.fireAll("VoteCounts", countsPayload())
end

local function closeMeeting()
	if not isOpen then
		return
	end
	isOpen = false
	MoveService.ClearModifierForAll(FREEZE_KEY)
	if MatchService.Winner then
		Net.fireAll("VoteClosed", { Resolution = "Cancelled" })
		return
	end

	local result = VoteTally.tally(ballots, chiefId(), rng)
	local exiled = if result.Exiled then MatchService.Roster.Members[result.Exiled] else nil
	Net.fireAll("VoteClosed", {
		Resolution = result.Resolution,
		ExiledId = if exiled then exiled.Id else nil,
		ExiledName = if exiled then exiled.Name else nil,
	})
	if exiled then
		MatchService.Exile(exiled.Id)
	end
end

--------------------------------------------------------------------------------
-- Client intents
--------------------------------------------------------------------------------

local function onSelect(player: Player, target: any)
	if not isOpen or type(target) ~= "number" or target ~= target then
		return
	end
	local voterId = player.UserId
	local current = ballots[voterId]
	if current and current.Confirmed and Config.Vote.ConfirmIsFinal then
		return
	end
	if target == CLEAR_SELECTION then
		ballots[voterId] = nil
	elseif VoteTally.isValidVote(voterId, target, Roster.aliveMap(MatchService.Roster)) then
		ballots[voterId] = { Target = target, Confirmed = false }
	else
		return
	end
	sendMine(player)
	Net.fireAll("VoteCounts", countsPayload())
end

local function onConfirm(player: Player)
	local ballot = ballots[player.UserId]
	if not isOpen or not ballot or ballot.Confirmed then
		return
	end
	-- The target may have left since it was selected.
	if not VoteTally.isValidVote(player.UserId, ballot.Target, Roster.aliveMap(MatchService.Roster)) then
		ballots[player.UserId] = nil
	else
		ballot.Confirmed = true
	end
	sendMine(player)
	Net.fireAll("VoteCounts", countsPayload())
end

--------------------------------------------------------------------------------

local function setBell(enabled: boolean)
	if bellPrompt then
		bellPrompt.Enabled = enabled
	end
end

function VoteService.Init()
	local bell = CollectionService:GetTagged("MeetingBell")[1]
	if bell then
		local prompt = Prompts.create(
			bell:FindFirstChild("PromptAnchor") or bell,
			"CallMeeting",
			"Prompt.CallMeeting",
			Config.Vote.CallHold
		)
		prompt.Triggered:Connect(function(player: Player)
			if RoundService.CallMeeting(player) then
				setBell(false)
			end
		end)
		bellPrompt = prompt
	else
		warn("[VoteService] meeting bell not found: run build/BuildVillage.luau in Studio")
	end
end

function VoteService.Start()
	Net.on("VoteSelect", onSelect, 20, 5)
	Net.on("VoteConfirm", onConfirm, 6, 5)

	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		setBell(false)
		if state.Phase == "Meeting" then
			openMeeting()
		elseif state.Phase == "Day" and state.Day > 1 then
			-- The bell unlocks after 3 minutes (GDD §6.1).
			local scale = if Config.Debug.Enabled then Config.Debug.TimerScale else 1
			task.delay(Config.Timers.MeetingUnlockAfter * scale, function()
				if RoundService.State == state and not MatchService.Winner then
					setBell(true)
					RoundService.Announce("Phase.MeetingUnlocked")
				end
			end)
		end
	end)

	RoundService.PhaseEnded:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Meeting" then
			closeMeeting()
		end
	end)

	-- A voter who dies or leaves loses their ballot; votes on them are dropped.
	MatchService.MemberDied:Connect(function(member: Roster.Member)
		if not isOpen then
			return
		end
		ballots[member.Id] = nil
		for voterId, ballot in ballots do
			if ballot.Target == member.Id then
				ballots[voterId] = nil
				local voter = MatchService.PlayerOf(voterId)
				if voter then
					sendMine(voter)
				end
			end
		end
		Net.fireAll("VoteOpened", { Candidates = candidates() })
		Net.fireAll("VoteCounts", countsPayload())
	end)

	MatchService.SyncRequested:Connect(function(player: Player)
		if isOpen then
			Net.fire(player, "VoteOpened", { Candidates = candidates() })
			Net.fire(player, "VoteCounts", countsPayload())
			sendMine(player)
		end
	end)
end

return VoteService
