local Config = require(game.ReplicatedStorage.Shared.Config)
local PhaseMachine = require(game.ReplicatedStorage.Shared.Logic.PhaseMachine)
local WolfPack = require(game.ServerScriptService.Logic.WolfPack)

local function advance(state, event)
	local nextState = PhaseMachine.next(state, event)
	expect(nextState ~= nil).toBe(true)
	return nextState
end

test("full loop with a called meeting follows the GDD timings", function()
	local s = PhaseMachine.initial()
	expect(s.Phase).toBe("RoleSelect")

	s = advance(s, "Timeout")
	expect({ s.Phase, s.Day, s.Duration }).toEqual({ "Day", 1, 180 })
	expect(PhaseMachine.next(s, "MeetingCalled")).toBeNil() -- no meeting on day 1
	expect(PhaseMachine.canCallMeeting(s, 179)).toBe(false)

	s = advance(s, "Timeout")
	expect({ s.Phase, s.Duration }).toEqual({ "FullMoonWarning", 10 })
	s = advance(s, "Timeout")
	expect({ s.Phase, s.Night, s.Duration }).toEqual({ "Night", 1, 180 })
	s = advance(s, "Timeout")
	expect({ s.Phase, s.Day, s.Duration }).toEqual({ "Day", 2, 300 })

	expect(PhaseMachine.canCallMeeting(s, 100)).toBe(false)
	expect(PhaseMachine.canCallMeeting(s, 180)).toBe(true)

	s = advance(s, "MeetingCalled")
	expect({ s.Phase, s.Duration }).toEqual({ "MeetingCountdown", 60 })
	expect(PhaseMachine.next(s, "MeetingCalled")).toBeNil() -- once per day
	s = advance(s, "Timeout")
	expect({ s.Phase, s.Duration, s.MeetingForced }).toEqual({ "Meeting", 120, false })
	s = advance(s, "Timeout")
	expect({ s.Phase, s.Duration }).toEqual({ "FullMoonWarning", 10 })
	s = advance(s, "Timeout")
	expect({ s.Phase, s.Night }).toEqual({ "Night", 2 })
	s = advance(s, "Timeout")
	expect({ s.Phase, s.Day }).toEqual({ "Day", 3 })
end)

test("day timer reaching 0 forces a meeting", function()
	local s = PhaseMachine.initial()
	for _ = 1, 4 do
		s = advance(s, "Timeout") -- Day1, warning, night, day 2
	end
	expect(s.Phase).toBe("Day")
	s = advance(s, "Timeout")
	if Config.Timers.ForcedMeetingSkipsCountdown then
		expect(s.Phase).toBe("Meeting")
	else
		expect(s.Phase).toBe("MeetingCountdown")
	end
	expect(s.MeetingForced).toBe(true)
end)

test("game over has no successor", function()
	local over = PhaseMachine.gameOver(PhaseMachine.initial())
	expect(over.Phase).toBe("GameOver")
	expect(PhaseMachine.next(over, "Timeout")).toBeNil()
end)

test("pup: first night kill by the main wolf converts, only once", function()
	expect(WolfPack.shouldConvert(true, true, 0)).toBe(true)
	expect(WolfPack.shouldConvert(true, true, 1)).toBe(false)
	expect(WolfPack.shouldConvert(false, true, 0)).toBe(false) -- pup kills never convert
	expect(WolfPack.shouldConvert(true, false, 0)).toBe(false)
end)

test("pup becomes a wolf on the 2nd night after the wolf is gone", function()
	expect(WolfPack.shouldPromote(3, nil)).toBe(false) -- main wolf still here
	-- Wolf exiled during day 3 (2 nights already played): night 3 = 1st, night 4 = 2nd.
	expect(WolfPack.shouldPromote(3, 2)).toBe(false)
	expect(WolfPack.shouldPromote(4, 2)).toBe(true)
end)
