--[[
	Lobby queue pad rules (owner's rules, 17 Nov 2026). The Lobby place's code
	lives in lobby/src and is loaded on its own.
]]

local lobby = loadLobby()
local PadQueue = lobby.require(lobby.game.ServerScriptService.Logic.PadQueue)
local Config = lobby.require(lobby.game.ReplicatedStorage.Shared.Config)

local MIN, MAX = Config.Match.MinPlayers, Config.Match.MaxPlayers

local function fill(pad, count, from)
	for id = from or 1, (from or 1) + count - 1 do
		PadQueue.join(pad, id)
	end
end

test("joining: first in is the host, no duplicates, 12 seats", function()
	local pad = PadQueue.new(1)
	expect(PadQueue.join(pad, 7)).toBe(true)
	expect(PadQueue.join(pad, 7)).toBe(false)
	expect(PadQueue.host(pad)).toBe(7)
	fill(pad, MAX - 1, 100)
	expect(#pad.Members).toBe(MAX)
	expect(PadQueue.join(pad, 999)).toBe(false)
end)

test("the host leaves: the next in line becomes host", function()
	local pad = PadQueue.new(1)
	fill(pad, 3)
	expect(PadQueue.leave(pad, 1)).toBe(true)
	expect(PadQueue.host(pad)).toBe(2)
	expect(PadQueue.leave(pad, 99)).toBe(false)
end)

test("under 8 nobody can start; from 8 only the host can, at once", function()
	local pad = PadQueue.new(1)
	fill(pad, MIN - 1)
	expect(PadQueue.state(pad)).toBe("Waiting")
	expect(PadQueue.requestStart(pad, 1)).toBe(false)
	PadQueue.join(pad, MIN)
	expect(PadQueue.tick(pad, 0)).toBe(false) -- no countdown below 12
	expect(PadQueue.state(pad)).toBe("Ready")
	expect(PadQueue.requestStart(pad, 2)).toBe(false) -- not the host
	expect(PadQueue.requestStart(pad, 1)).toBe(true)
	-- Not locked: people may still step off before the host starts.
	expect(PadQueue.leave(pad, 5)).toBe(true)
	expect(PadQueue.state(pad)).toBe("Waiting")
end)

test("a host who never starts: the match starts by itself after the idle time", function()
	local pad = PadQueue.new(1)
	fill(pad, MIN)
	expect(PadQueue.tick(pad, 100)).toBe(false)
	expect(PadQueue.tick(pad, 100 + Config.Lobby.HostIdleStart - 1)).toBe(false)
	expect(PadQueue.tick(pad, 100 + Config.Lobby.HostIdleStart)).toBe(true)
	-- Dropping below 8 resets the idle timer.
	local other = PadQueue.new(2)
	fill(other, MIN)
	PadQueue.tick(other, 0)
	PadQueue.leave(other, 3)
	PadQueue.tick(other, 10)
	PadQueue.join(other, 3)
	expect(PadQueue.tick(other, 20)).toBe(false) -- back to 8 at t = 20: the wait starts again
	expect(PadQueue.tick(other, 20 + Config.Lobby.HostIdleStart - 1)).toBe(false)
	expect(PadQueue.tick(other, 20 + Config.Lobby.HostIdleStart)).toBe(true)
end)

test("full: 10 s countdown, locked, then launch; a disconnect does not stop it", function()
	local pad = PadQueue.new(1)
	fill(pad, MAX)
	expect(PadQueue.tick(pad, 0)).toBe(false)
	expect(PadQueue.state(pad)).toBe("Countdown")
	expect(pad.CountdownEndsAt).toBe(Config.Lobby.FullCountdown)
	expect(PadQueue.leave(pad, 4)).toBe(false) -- nobody can step off
	expect(PadQueue.join(pad, 50)).toBe(false)
	expect(PadQueue.leave(pad, 4, true)).toBe(true) -- but a player can quit Roblox
	expect(PadQueue.tick(pad, 5)).toBe(false)
	expect(PadQueue.state(pad)).toBe("Countdown") -- still counting with 11
	expect(PadQueue.tick(pad, Config.Lobby.FullCountdown)).toBe(true)
	-- The host may still start early during the countdown.
	local early = PadQueue.new(2)
	fill(early, MAX)
	PadQueue.tick(early, 0)
	expect(PadQueue.requestStart(early, 1)).toBe(true)
end)

test("too many disconnect during the countdown: it stops and the pad opens again", function()
	local pad = PadQueue.new(1)
	fill(pad, MAX)
	PadQueue.tick(pad, 0)
	for id = 1, MAX - MIN + 1 do
		PadQueue.leave(pad, id, true)
	end
	expect(#pad.Members).toBe(MIN - 1)
	expect(PadQueue.tick(pad, 1)).toBe(false)
	expect(PadQueue.state(pad)).toBe("Waiting")
	expect(PadQueue.isLocked(pad)).toBe(false)
end)

test("launching, a failed teleport, and starting over", function()
	local pad = PadQueue.new(1)
	fill(pad, MIN)
	local party = PadQueue.launch(pad)
	expect(#party).toBe(MIN)
	expect(PadQueue.state(pad)).toBe("Launching")
	expect(PadQueue.isLocked(pad)).toBe(true)
	expect(PadQueue.tick(pad, 999)).toBe(false)
	expect(PadQueue.requestStart(pad, 1)).toBe(false)
	PadQueue.release(pad, 10)
	expect(PadQueue.state(pad)).toBe("Ready")
	expect(#pad.Members).toBe(MIN)
	PadQueue.reset(pad)
	expect(#pad.Members).toBe(0)
	expect(PadQueue.state(pad)).toBe("Waiting")
end)
