--!strict
--[[
	PadQueue — pure rules for one lobby queue pad (owner's rules, 17 Nov 2026).

	- Stepping on the pad joins its queue; stepping off leaves it.
	- The first player in the queue is the host; if they leave, the next one is.
	- Up to Config.Match.MaxPlayers (12) seats.
	- With Config.Match.MinPlayers (8) or more, the host can start at any time.
	- [owner] 18 Nov 2026: with 8-11 players a Config.Lobby.ReadyCountdown
	  (20 s) countdown runs and the match starts by itself at 0; it starts
	  over every time someone joins or leaves.
	- When all 12 seats are taken, a Config.Lobby.FullCountdown (10 s)
	  countdown starts and the pad is locked: nobody can step off. A
	  disconnect cannot be prevented: then it is back to the 20 s countdown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

-- "Waiting" (< 8) | "Ready" (host may start) | "Countdown" (full, locked) | "Launching"
export type PadState = string

export type Pad = {
	Id: number,
	Members: { number }, -- in the order they joined; [1] is the host
	AutoStartAt: number?, -- 8-11 players: the match starts by itself at this time
	CountdownEndsAt: number?, -- full: locked countdown
	LastCount: number, -- members at the last tick (a change restarts the countdown)
	Launching: boolean,
}

local PadQueue = {}

function PadQueue.new(id: number): Pad
	return { Id = id, Members = {}, AutoStartAt = nil, CountdownEndsAt = nil, LastCount = 0, Launching = false }
end

function PadQueue.host(pad: Pad): number?
	return pad.Members[1]
end

function PadQueue.isLocked(pad: Pad): boolean
	return pad.CountdownEndsAt ~= nil or pad.Launching
end

function PadQueue.state(pad: Pad): PadState
	if pad.Launching then
		return "Launching"
	elseif pad.CountdownEndsAt then
		return "Countdown"
	elseif #pad.Members >= Config.Match.MinPlayers then
		return "Ready"
	end
	return "Waiting"
end

function PadQueue.join(pad: Pad, id: number): boolean
	if PadQueue.isLocked(pad) or #pad.Members >= Config.Match.MaxPlayers or table.find(pad.Members, id) then
		return false
	end
	table.insert(pad.Members, id)
	return true
end

-- `forced` = the player left the game (cannot be refused).
function PadQueue.leave(pad: Pad, id: number, forced: boolean?): boolean
	local index = table.find(pad.Members, id)
	if not index or (PadQueue.isLocked(pad) and not forced) then
		return false
	end
	table.remove(pad.Members, index)
	return true
end

-- The host asks to start. Returns true when the match should launch now.
function PadQueue.requestStart(pad: Pad, id: number): boolean
	return not pad.Launching and PadQueue.host(pad) == id and #pad.Members >= Config.Match.MinPlayers
end

-- Advances the timers. Returns true when the match should launch now.
function PadQueue.tick(pad: Pad, now: number): boolean
	if pad.Launching then
		return false
	end
	local count = #pad.Members
	local min, max = Config.Match.MinPlayers, Config.Match.MaxPlayers

	-- Someone joined or left: the 8-11 countdown starts over.
	if count ~= pad.LastCount then
		pad.LastCount = count
		pad.AutoStartAt = if count >= min and count < max then now + Config.Lobby.ReadyCountdown else nil
	end

	if count >= max and not pad.CountdownEndsAt then
		pad.CountdownEndsAt = now + Config.Lobby.FullCountdown
	end
	if pad.CountdownEndsAt then
		if count < max then
			pad.CountdownEndsAt = nil -- a disconnect: unlocked, back to the 20 s countdown
		elseif now >= pad.CountdownEndsAt then
			return true
		else
			return false
		end
	end

	return pad.AutoStartAt ~= nil and now >= pad.AutoStartAt
end

-- Marks the pad as launching and returns who goes.
function PadQueue.launch(pad: Pad): { number }
	pad.Launching = true
	return table.clone(pad.Members)
end

-- After the players have gone (or to start over).
function PadQueue.reset(pad: Pad)
	table.clear(pad.Members)
	pad.AutoStartAt = nil
	pad.CountdownEndsAt = nil
	pad.LastCount = 0
	pad.Launching = false
end

-- The teleport failed: the queue is open again with the same people.
function PadQueue.release(pad: Pad, now: number)
	pad.Launching = false
	pad.CountdownEndsAt = nil
	pad.LastCount = -1 -- the next tick starts a fresh countdown
	pad.AutoStartAt = nil
end

return PadQueue
