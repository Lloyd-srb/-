--!strict
--[[
	RoundService — runs the round loop (GDD §6) on top of PhaseMachine.

	For every phase: PhaseStarted fires, the phase is broadcast, the timer runs
	(or is cut short by a called meeting / a win), then PhaseEnded fires.
	Other services react to those two signals; they never drive the clock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Signal = require(ReplicatedStorage.Shared.Signal)

local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)

local TAUNT_COUNT = 3 -- Morning.Taunt1..3 in Strings
local POLL = 0.1

local RoundService = {}

RoundService.State = PhaseMachine.initial()
RoundService.PhaseStarted = Signal.new() -- (state)
RoundService.PhaseEnded = Signal.new() -- (state)

local random = Random.new()
local startedAt = os.clock()
local duration = 0 -- real seconds (debug-scaled)
local endsAt = 0 -- server time, for client countdowns
local meetingCaller: string? = nil
local meetingRequested = false
local advanceRequested = false

local function timerScale(): number
	return if Config.Debug.Enabled then Config.Debug.TimerScale else 1
end

-- Game-time seconds since the current phase began (independent of TimerScale).
function RoundService.Elapsed(): number
	return (os.clock() - startedAt) / timerScale()
end

function RoundService.IsNight(): boolean
	return RoundService.State.Phase == "Night"
end

local function payload(): { [string]: any }
	local state = RoundService.State
	return {
		Phase = state.Phase,
		Day = state.Day,
		Night = state.Night,
		Duration = duration,
		EndsAt = endsAt,
		MeetingForced = state.MeetingForced,
	}
end

local function announce(key: string, args: { [string]: any }?, style: string?)
	Net.fireAll("Announcement", { Key = key, Args = args, Style = style or "Normal" })
end

RoundService.Announce = announce

local function announcePhase(state: PhaseMachine.PhaseState)
	if state.Phase == "Day" and state.Day > 1 then
		-- Red morning message (GDD §6.1).
		if MatchService.DeathsThisNight > 0 then
			announce("Morning.Taunt" .. random:NextInteger(1, TAUNT_COUNT), nil, "Red")
		else
			announce("Morning.Safe", nil, "Red")
		end
	elseif state.Phase == "MeetingCountdown" and not state.MeetingForced and meetingCaller then
		announce("Phase.MeetingCalled", { name = meetingCaller, seconds = math.round(duration) })
	elseif (state.Phase == "Meeting" or state.Phase == "MeetingCountdown") and state.MeetingForced then
		announce("Phase.MeetingForced")
	end
end

local function enter(state: PhaseMachine.PhaseState)
	RoundService.State = state
	duration = PhaseMachine.scaledDuration(state)
	startedAt = os.clock()
	endsAt = workspace:GetServerTimeNow() + duration
	if state.Phase == "Day" then
		meetingCaller = nil
		meetingRequested = false
	elseif state.Phase == "Night" then
		MatchService.BeginNight(state.Night)
	end
	RoundService.PhaseStarted:Fire(state)
	Net.fireAll("PhaseChanged", payload())
	announcePhase(state)
end

-- Ends the current phase early, as if its timer had run out (used when every
-- player has confirmed their roles).
function RoundService.Advance()
	advanceRequested = true
end

-- Waits for the phase to finish. Returns why it ended.
local function waitPhase(): string
	advanceRequested = false
	while os.clock() - startedAt < duration do
		if MatchService.Winner then
			return "GameOver"
		elseif meetingRequested then
			meetingRequested = false
			return "MeetingCalled"
		elseif advanceRequested then
			break
		end
		task.wait(POLL)
	end
	return "Timeout"
end

-- A living player rang the bell. Returns true if the meeting was accepted.
function RoundService.CallMeeting(player: Player): boolean
	if MatchService.Winner or meetingRequested or not MatchService.IsAlive(player) then
		return false
	end
	if not PhaseMachine.canCallMeeting(RoundService.State, RoundService.Elapsed()) then
		return false
	end
	meetingCaller = player.DisplayName
	meetingRequested = true
	return true
end

local function run()
	while MatchService.PlayerCount() < MatchService.RequiredPlayers() do
		Net.fireAll("PhaseChanged", {
			Phase = "Waiting",
			Count = MatchService.PlayerCount(),
			Needed = MatchService.RequiredPlayers(),
		})
		task.wait(1)
	end

	enter(PhaseMachine.initial())
	local event = "Timeout"
	if not (Config.Debug.Enabled and Config.Debug.SkipRoleSelect) then
		event = waitPhase()
	end
	MatchService.BeginMatch()

	while true do
		local state = RoundService.State
		RoundService.PhaseEnded:Fire(state)
		if state.Phase == "Night" then
			MatchService.EndNight()
		end
		if MatchService.Winner then
			enter(PhaseMachine.gameOver(state))
			break
		end
		local nextState = PhaseMachine.next(state, if event == "MeetingCalled" then "MeetingCalled" else "Timeout")
		if not nextState then
			break
		end
		enter(nextState)
		event = waitPhase()
	end
end

function RoundService.Init() end

function RoundService.Start()
	MatchService.SyncRequested:Connect(function(player: Player)
		if RoundService.State.Phase ~= "RoleSelect" or MatchService.PlayerCount() >= MatchService.RequiredPlayers() then
			Net.fire(player, "PhaseChanged", payload())
		end
	end)
	-- Deferred so every service has connected to the phase signals first.
	task.defer(run)
end

return RoundService
