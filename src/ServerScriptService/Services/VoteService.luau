--!strict
--[[
	VoteService — the daily meeting and vote (GDD §6.2).

	- The bell on the meeting table can be rung once the day is 3 minutes old.
	- When the meeting starts, every living player (forest included) is warped
	  to the table and cannot walk.
	- Clients send "select" / "confirm" intents. Everyone receives silhouette
	  counts only; who voted for whom never leaves the server.
	- [owner] Config.Vote.LockBeforeEnd seconds before the end every vote is
	  locked (selections are confirmed, nothing can change) and the Chief's
	  silhouette gets a crown: everyone sees whom the Chief voted for.
	- When the timer ends, the result is tallied and the exiled player dies
	  without a role reveal.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local Roster = require(Logic.Roster)
local VoteTally = require(Logic.VoteTally)

local AudioService = require(script.Parent.AudioService)
local MatchService = require(script.Parent.MatchService)
local MoveService = require(script.Parent.MoveService)
local MovementGuard = require(script.Parent.MovementGuard)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)

local FREEZE_KEY = "Meeting"
local CLEAR_SELECTION = 0 -- VoteSelect(0) removes an unconfirmed selection

local VoteService = {}

local rng = Rng.wrap(Random.new())
local isOpen = false
local isLocked = false
local meetingToken = 0
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
-- After the lock, the Chief's target carries Chief = true (the crown).
local function countsPayload(): { any }
	local chief = chiefId()
	local chiefBallot = if isLocked and chief then ballots[chief] else nil
	local list = {}
	for target, count in VoteTally.publicCounts(ballots, chief) do
		table.insert(list, {
			Id = target,
			Pending = count.Pending,
			Confirmed = count.Confirmed,
			Chief = if chiefBallot and chiefBallot.Target == target then true else nil,
		})
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

-- The last seconds: every selection becomes final and the crown shows.
local function lockVotes()
	if not isOpen or isLocked then
		return
	end
	isLocked = true
	for _, ballot in ballots do
		ballot.Confirmed = true
	end
	Net.fireAll("VoteLocked")
	Net.fireAll("VoteCounts", countsPayload())
	for _, player in Players:GetPlayers() do
		sendMine(player)
	end
end

local function openMeeting(state: PhaseMachine.PhaseState)
	table.clear(ballots)
	isOpen = true
	isLocked = false
	meetingToken += 1
	local token = meetingToken
	local scale = if Config.Debug.Enabled then Config.Debug.TimerScale else 1
	local lockIn = math.max(0, PhaseMachine.scaledDuration(state) - Config.Vote.LockBeforeEnd * scale)
	task.delay(lockIn, function()
		if meetingToken == token then
			lockVotes()
		end
	end)

	local seat = 0
	for _, member in Roster.alive(MatchService.Roster) do
		seat += 1
		local spot = meetingSpot((seat - 1) % Config.Map.HouseCount + 1)
		if spot then
			MovementGuard.Warp(member.Id, Zones.worldCFrame(spot))
		end
		-- Nobody can walk during the meeting (GDD §6.2).
		MoveService.SetModifier(member.Id, FREEZE_KEY, { Override = 0, NoJump = true })
	end

	Net.fireAll("VoteOpened", { Candidates = candidates() })
	Net.fireAll("VoteCounts", countsPayload())
	AudioService.All("MeetingBell")
end

local function closeMeeting()
	if not isOpen then
		return
	end
	isOpen = false
	isLocked = false
	meetingToken += 1
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
		AudioService.All("Exile")
		MatchService.Exile(exiled.Id)
	end
end

--------------------------------------------------------------------------------
-- Client intents
--------------------------------------------------------------------------------

local function onSelect(player: Player, target: any)
	if not isOpen or isLocked or type(target) ~= "number" or target ~= target then
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
	if not isOpen or isLocked or not ballot or ballot.Confirmed then
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
		bellPrompt:SetAttribute("Active", enabled)
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
		prompt:SetAttribute("Audience", "Alive") -- ghosts cannot ring it
		local reach = prompt.MaxActivationDistance + 4
		prompt.Triggered:Connect(function(player: Player)
			-- Prompts are triggered from the player's computer: check they are
			-- really at the table (a modified client could ring from anywhere).
			local member = MatchService.MemberOf(player)
			local root = if member then MatchService.RootOf(member.Id) else nil
			local anchor = prompt.Parent
			local at = if anchor and anchor:IsA("Attachment")
				then Zones.worldCFrame(anchor).Position
				elseif anchor and anchor:IsA("BasePart") then anchor.CFrame.Position
				else nil
			if not root or not at or (root.CFrame.Position - at).Magnitude > reach then
				return
			end
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
			openMeeting(state)
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
			if isLocked then
				Net.fire(player, "VoteLocked")
			end
			Net.fire(player, "VoteCounts", countsPayload())
			sendMine(player)
		end
	end)
end

return VoteService
