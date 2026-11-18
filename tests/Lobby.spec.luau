--[[
	The Lobby place's queue pads (owner's rules, 17 Nov 2026) and the Match
	place's arrival rules, on the fake engine. Teleports are recorded.
]]

local function players(count, from)
	local list = {}
	for id = from or 1, (from or 1) + count - 1 do
		table.insert(list, { Id = id, Name = "P" .. id })
	end
	return list
end

local function openLobby(count)
	local server = startLobby({ Players = players(count) })
	server.Config.Places.MatchPlaceId = 555
	server.Config.Lobby.ReturnCheck = 0.3
	return server
end

local function padPart(server, id)
	return server.game.Workspace.Lobby.Pads["Pad" .. id]
end

local function stand(server, playerId, padId, offset)
	local pad = padPart(server, padId)
	server.root(playerId).CFrame = CFrame.new(pad.CFrame.Position + Vector3.new(offset or 0, 3, 0))
end

local function stepOff(server, playerId)
	server.root(playerId).CFrame = CFrame.new(0, 3, 40)
end

local function pad(server, id)
	local list = server.last("PadsChanged", "all")
	for _, entry in (list and list[1]) or {} do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

local function settle()
	task.wait(0.35) -- the server checks who stands where every 0.25 s
end

test("lobby: four 12-seat pads; host = first in; start from 8; host-only", function()
	local server = openLobby(9)
	settle()
	for id = 1, 4 do
		expect(server.game.Workspace.Lobby.Pads["Pad" .. id]:HasTag("QueuePad")).toBe(true)
	end
	expect(pad(server, 1).Max).toBe(12)

	stand(server, 3, 1)
	settle()
	expect(pad(server, 1).Count).toBe(1)
	expect(server.last("QueueChanged", 3)[1]).toEqual({ PadId = 1, IsHost = true, CanStart = false })
	for id = 1, 7 do
		if id ~= 3 then
			stand(server, id, 1, id - 4)
		end
	end
	settle()
	expect(pad(server, 1).Count).toBe(7)
	expect(pad(server, 1).State).toBe("Waiting")
	server.fireServer("StartRequest", 3) -- fewer than 8: nothing happens
	settle()
	expect(#server.teleports()).toBe(0)

	stand(server, 8, 1, 4)
	settle()
	expect(pad(server, 1).State).toBe("Ready")
	expect(pad(server, 1).HostName).toBe("P3")
	expect(server.last("QueueChanged", 3)[1].CanStart).toBe(true)
	expect(server.last("QueueChanged", 1)[1]).toEqual({ PadId = 1, IsHost = false, CanStart = false })

	-- Not full: a player may still step off.
	stepOff(server, 8)
	settle()
	expect(pad(server, 1).Count).toBe(7)
	stand(server, 8, 1, 4)
	settle()

	server.fireServer("StartRequest", 1) -- not the host
	settle()
	expect(#server.teleports()).toBe(0)
	server.fireServer("StartRequest", 3)
	task.wait(0.05)
	local trip = server.teleports()[1]
	expect(trip.PlaceId).toBe(555)
	expect(#trip.Players).toBe(8)
	expect(trip.Data.Expected).toBe(8)
	expect(#trip.Data.Party).toBe(8)
	expect(table.find(trip.Players, 9)).toBeNil() -- player 9 never stood on the pad
	expect(pad(server, 1).State).toBe("Launching")

	-- In this simulation nobody really leaves, as if the teleport had failed:
	-- they are told, and since they still stand on the pad they queue again.
	task.wait(0.6)
	expect(server.last("LobbyNotice", 3)[1].Key).toBe("Lobby.TeleportFailed")
	expect(server.humanoid(3).WalkSpeed).toBe(16) -- free to move again
	expect(pad(server, 1).State ~= "Launching").toBe(true)
end)

test("lobby: the host leaves, the next in line takes over", function()
	local server = openLobby(3)
	settle()
	stand(server, 2, 2)
	settle()
	stand(server, 1, 2, 3)
	stand(server, 3, 2, -3)
	settle()
	expect(pad(server, 2).HostName).toBe("P2")
	stepOff(server, 2)
	settle()
	expect(pad(server, 2).Count).toBe(2)
	local host = pad(server, 2).HostName
	expect(host == "P1" or host == "P3").toBe(true)
	server.removePlayer(1)
	server.removePlayer(3)
	settle()
	expect(pad(server, 2).Count).toBe(0)
end)

test("lobby: a full pad counts down 10 s, holds everyone; a quitter restarts the 20 s countdown", function()
	local server = openLobby(12)
	server.Config.Lobby.FullCountdown = 0.6
	settle()
	for id = 1, 12 do
		stand(server, id, 3, (id - 6.5) * 0.9)
	end
	settle()
	local entry = pad(server, 3)
	expect(entry.Count).toBe(12)
	expect(entry.State).toBe("Countdown")
	expect(type(entry.CountdownEndsAt)).toBe("number")
	expect(server.humanoid(5).WalkSpeed).toBe(0) -- held in place
	stepOff(server, 5) -- trying to leave anyway
	settle()
	expect(pad(server, 3).Count).toBe(12)
	-- Someone quits Roblox: unlocked, back to the 8-11 countdown (restarted).
	stand(server, 5, 3, (5 - 6.5) * 0.9) -- back on the pad, so nobody else leaves
	server.Config.Lobby.ReadyCountdown = 0.6
	server.removePlayer(12)
	settle()
	expect(pad(server, 3).State).toBe("Ready")
	task.wait(0.8)
	local trip = server.teleports()[1]
	expect(trip ~= nil).toBe(true)
	expect(#trip.Players).toBe(11)
	expect(trip.Data.Expected).toBe(11)
end)

test("lobby: 8+ players and nobody presses Start: the match starts by itself after the countdown", function()
	local server = openLobby(8)
	server.Config.Lobby.ReadyCountdown = 0.6
	settle()
	for id = 1, 8 do
		stand(server, id, 4, (id - 4.5) * 1.2)
	end
	settle()
	expect(#server.teleports()).toBe(0)
	task.wait(0.8)
	expect(#server.teleports()).toBe(1)
	expect(#server.teleports()[1].Players).toBe(8)
end)

test("lobby: in Studio (or without the Match place id) nobody is sent, the pad resets", function()
	local server = openLobby(8)
	server.Config.Places.MatchPlaceId = 0
	settle()
	for id = 1, 8 do
		stand(server, id, 1, (id - 4.5) * 1.2)
	end
	settle()
	server.fireServer("StartRequest", 1)
	settle()
	expect(#server.teleports()).toBe(0)
	expect(server.last("LobbyNotice", 1)[1].Key).toBe("Lobby.NoTeleport")
end)

--------------------------------------------------------------------------------
-- The Match place: waiting for the players the lobby sent
--------------------------------------------------------------------------------

local function startMatch(count, expected)
	local list = players(count)
	for _, entry in list do
		entry.TeleportData = { Expected = expected, Party = {} }
	end
	local server = startServer({ Players = list, Debug = { Enabled = false } })
	server.Config.Match.ArrivalTimeout = 0.4
	server.Config.Places.LobbyPlaceId = 777
	return server
end

test("match: everyone the lobby sent has arrived: the match begins at once", function()
	local server = startMatch(8, 8)
	server.waitForPhase("RoleSelect", 2)
	expect(#server.teleports()).toBe(0)
end)

test("match: one missing, still 8 or more: begins after the wait", function()
	local server = startMatch(9, 10)
	task.wait(0.2)
	expect(server.phase()).toBe("Waiting")
	server.waitForPhase("RoleSelect", 3)
end)

test("match: fewer than 8 arrived: everyone goes back to the lobby", function()
	local server = startMatch(5, 8)
	server.waitFor("teleport home", function()
		return server.teleports()[1]
	end, 6)
	local trip = server.teleports()[1]
	expect(trip.PlaceId).toBe(777)
	expect(#trip.Players).toBe(5)
	expect(server.phase()).toBe("Waiting")
end)

--------------------------------------------------------------------------------
-- Found in the code review of 17 Nov 2026
--------------------------------------------------------------------------------

test("bug: a full pad's countdown stopped (too many quit) and the rest stayed frozen", function()
	local server = openLobby(12)
	server.Config.Lobby.FullCountdown = 30
	settle()
	for id = 1, 12 do
		stand(server, id, 2, (id - 6.5) * 0.9)
	end
	settle()
	expect(pad(server, 2).State).toBe("Countdown")
	expect(server.humanoid(1).WalkSpeed).toBe(0)
	for id = 8, 12 do
		server.removePlayer(id) -- 7 left: fewer than 8, the countdown stops
	end
	settle()
	expect(pad(server, 2).State).toBe("Waiting")
	expect(server.humanoid(1).WalkSpeed).toBe(16)
	expect(server.humanoid(7).JumpPower).toBe(50)
	stepOff(server, 1) -- free to leave again
	settle()
	expect(pad(server, 2).Count).toBe(6)
end)

test("bug: one failed teleport home left everyone on a finished match server", function()
	local server = startMatch(5, 8)
	server.Config.Match.HomeRetryDelay = 0.3
	server.waitFor("teleport home", function()
		return server.teleports()[1]
	end, 6)
	-- In this simulation nobody really leaves, as if the trip had failed.
	server.waitFor("second try", function()
		return server.teleports()[2]
	end, 3)
	task.wait(1)
	expect(#server.teleports()).toBe(server.Config.Match.HomeAttempts) -- then it stops trying
end)
