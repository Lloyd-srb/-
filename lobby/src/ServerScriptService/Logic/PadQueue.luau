--!strict
--[[
	PadQueue — pure rules for one lobby queue pad (owner's rules, 17 Nov 2026).

	- Stepping on the pad joins its queue; stepping off leaves it.
	- The first player in the queue is the host; if they leave, the next one is.
	- Up to Config.Match.MaxPlayers (12) seats.
	- With Config.Match.MinPlayers (8) or more, the host can start at any time.
	- If the host waits Config.Lobby.HostIdleStart seconds with 8+ players,
	  the match starts by itself (so nobody is held hostage).
	- When all 12 seats are taken, a Config.Lobby.FullCountdown (10 s)
	  countdown starts and the pad is locked: nobody can step off.
	  A disconnect cannot be prevented; the countdown goes on while 8+ remain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

-- "Waiting" (< 8) | "Ready" (host may start) | "Countdown" (full, locked) | "Launching"
export type PadState = string

export type Pad = {
	Id: number,
	Members: { number }, -- in the order they joined; [1] is the host
	ReadySince: number?,
	CountdownEndsAt: number?,
	Launching: boolean,
}

local PadQueue = {}

function PadQueue.new(id: number): Pad
	return { Id = id, Members = {}, ReadySince = nil, CountdownEndsAt = nil, Launching = false }
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
	local min = Config.Match.MinPlayers

	if count >= min then
		pad.ReadySince = pad.ReadySince or now
	else
		pad.ReadySince = nil
	end

	if count >= Config.Match.MaxPlayers and not pad.CountdownEndsAt then
		pad.CountdownEndsAt = now + Config.Lobby.FullCountdown
	end
	if pad.CountdownEndsAt then
		if count < min then
			pad.CountdownEndsAt = nil -- too many dropped out: unlock and wait again
		elseif now >= pad.CountdownEndsAt then
			return true
		end
		return false
	end

	return pad.ReadySince ~= nil and now - pad.ReadySince >= Config.Lobby.HostIdleStart
end

-- Marks the pad as launching and returns who goes.
function PadQueue.launch(pad: Pad): { number }
	pad.Launching = true
	return table.clone(pad.Members)
end

-- After the players have gone (or to start over).
function PadQueue.reset(pad: Pad)
	table.clear(pad.Members)
	pad.ReadySince = nil
	pad.CountdownEndsAt = nil
	pad.Launching = false
end

-- The teleport failed: the queue is open again with the same people.
function PadQueue.release(pad: Pad, now: number)
	pad.Launching = false
	pad.CountdownEndsAt = nil
	pad.ReadySince = if #pad.Members >= Config.Match.MinPlayers then now else nil
end

return PadQueue
