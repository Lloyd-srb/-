--!strict
--[[
	PhaseMachine — pure round state machine (GDD §6).

	RoleSelect -> Day 1 (3 min, no meeting) -> FullMoonWarning (10 s) -> Night (3 min)
	-> Day (5 min; meeting unlocks after 3 min; forced meeting at 0)
	-> MeetingCountdown (1 min) -> Meeting (2 min) -> FullMoonWarning (10 s) -> Night ...

	It only decides "what comes next". Timing, warps, win checks and the
	transition to GameOver are driven by RoundService.
]]

local Config = require(script.Parent.Parent.Config)

export type PhaseName =
	"RoleSelect"
	| "Day"
	| "MeetingCountdown"
	| "Meeting"
	| "FullMoonWarning"
	| "Night"
	| "GameOver"

export type PhaseEvent = "Timeout" | "MeetingCalled"

export type PhaseState = {
	Phase: PhaseName,
	Day: number, -- 0 during RoleSelect, then 1, 2, ...
	Night: number, -- number of nights started so far
	Duration: number, -- seconds (unscaled)
	MeetingForced: boolean, -- true when the current meeting was forced by the day timer
}

local PhaseMachine = {}

local Timers = Config.Timers

local function make(phase: PhaseName, day: number, night: number, duration: number, forced: boolean?): PhaseState
	return {
		Phase = phase,
		Day = day,
		Night = night,
		Duration = duration,
		MeetingForced = forced == true,
	}
end

function PhaseMachine.initial(): PhaseState
	return make("RoleSelect", 0, 0, Config.RoleSelect.Duration)
end

-- Meetings exist from day 2 on, once per day, after MeetingUnlockAfter seconds.
function PhaseMachine.canCallMeeting(state: PhaseState, elapsed: number): boolean
	return state.Phase == "Day" and state.Day > 1 and elapsed >= Timers.MeetingUnlockAfter
end

-- Returns the next state, or nil when the event is not valid in this phase.
function PhaseMachine.next(state: PhaseState, event: PhaseEvent): PhaseState?
	local phase = state.Phase

	if event == "MeetingCalled" then
		if phase == "Day" and state.Day > 1 then
			return make("MeetingCountdown", state.Day, state.Night, Timers.MeetingCountdown)
		end
		return nil
	end

	-- event == "Timeout"
	if phase == "RoleSelect" then
		return make("Day", 1, 0, Timers.FirstDay)
	elseif phase == "Day" then
		if state.Day == 1 then
			return make("FullMoonWarning", state.Day, state.Night, Timers.FullMoonWarning)
		elseif Timers.ForcedMeetingSkipsCountdown then
			return make("Meeting", state.Day, state.Night, Timers.Meeting, true)
		else
			return make("MeetingCountdown", state.Day, state.Night, Timers.MeetingCountdown, true)
		end
	elseif phase == "MeetingCountdown" then
		return make("Meeting", state.Day, state.Night, Timers.Meeting, state.MeetingForced)
	elseif phase == "Meeting" then
		return make("FullMoonWarning", state.Day, state.Night, Timers.FullMoonWarning)
	elseif phase == "FullMoonWarning" then
		return make("Night", state.Day, state.Night + 1, Timers.Night)
	elseif phase == "Night" then
		return make("Day", state.Day + 1, state.Night, Timers.Day)
	end

	return nil -- GameOver has no successor
end

function PhaseMachine.gameOver(state: PhaseState): PhaseState
	return make("GameOver", state.Day, state.Night, Timers.GameOverScoreboard)
end

-- Applies Config.Debug.TimerScale (Studio only) to a duration.
function PhaseMachine.scaledDuration(state: PhaseState): number
	local scale = if Config.Debug.Enabled then Config.Debug.TimerScale else 1
	return math.max(1, state.Duration * scale)
end

return PhaseMachine
