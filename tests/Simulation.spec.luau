--[[
	End-to-end simulations: the REAL server scripts (ServerScriptService.Main and
	every service) run on a fake engine with fake players. This checks the round
	flow, warps, doors, voting, exile and win conditions working together.
	It cannot check anything visual or client-side.
]]

local SCALE = 0.004 -- 180 s -> 0.72 s

local function start(debug)
	debug.TimerScale = SCALE
	debug.MinPlayers = 3
	debug.FillWithBots = true
	return startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = debug,
	})
end

local function services(server)
	local folder = server.game.ServerScriptService.Services
	return {
		House = server.require(folder.HouseService),
		Match = server.require(folder.MatchService),
		Round = server.require(folder.RoundService),
	}
end

local function waitForDay(server, day)
	server.waitFor("day " .. day, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Day" and last[1].Day == day
	end)
end

local function flatRadius(position)
	return math.sqrt(position.X * position.X + position.Z * position.Z)
end

local function door(server, houseId)
	return server.game.Workspace.Map.Houses[string.format("House%02d", houseId)].Door
end

local function bell(server)
	return server.game.Workspace.Map.Plaza.MeetingTable.Bell.PromptAnchor.CallMeeting
end

local function hasAnnouncement(server, key)
	for _, args in server.sent("Announcement", "all") do
		if args[1].Key == key then
			return args[1]
		end
	end
	return nil
end

local function ringBell(server, playerId)
	server.waitFor("bell to unlock", function()
		return bell(server).Enabled
	end)
	expect(server.trigger(bell(server), playerId)).toBe(true)
end

local function firstBot(server)
	local opened = server.last("VoteOpened", "all")[1]
	for _, candidate in opened.Candidates do
		if candidate.IsBot then
			return candidate.Id
		end
	end
	error("no bot candidate")
end

test("full match: roles, night warp, doors, meeting, vote, exile, village wins", function()
	local server = start({ ForceRole = "Wolf", ForceRoleUserId = 1 })
	local svc = services(server)

	------------------------------------------------------------------ day 1
	waitForDay(server, 1)
	expect(server.last("RoleAssigned", 1)[1]).toBe("Wolf")
	for _, id in { 2, 3 } do
		local role = server.last("RoleAssigned", id)[1]
		expect(type(role)).toBe("string")
		expect(role ~= "Wolf").toBe(true)
	end
	expect(#server.sent("RoleAssigned", "all")).toBe(0) -- roles are never broadcast
	local roster = server.last("RosterChanged", "all")[1]
	expect(#roster).toBe(12)
	for _, entry in roster do
		expect(entry.Role).toBeNil()
		expect(entry.Faction).toBeNil()
	end
	-- No meeting on day 1.
	expect(bell(server).Enabled).toBe(false)
	expect(server.humanoid(2).WalkSpeed).toBe(16)

	---------------------------------------------------------------- night 1
	server.waitForPhase("Night")
	local bobHouse = server.last("HouseAssigned", 2)[1]
	local caraHouse = server.last("HouseAssigned", 3)[1]
	expect(bobHouse >= 1 and bobHouse <= 12).toBe(true)
	expect(caraHouse >= 1 and caraHouse <= 12).toBe(true)
	expect(bobHouse ~= caraHouse).toBe(true)
	expect(server.last("HouseAssigned", 1)[1]).toBe(0) -- the wolf has no door to open
	expect(#server.sent("HouseAssigned", "all")).toBe(0) -- houses are secret

	expect(svc.House.HouseAt(server.root(2).CFrame.Position)).toBe(bobHouse)
	expect(svc.House.HouseAt(server.root(3).CFrame.Position)).toBe(caraHouse)
	expect(flatRadius(server.root(1).CFrame.Position) < 15).toBe(true) -- wolf at the plaza centre
	expect(svc.House.HouseAt(server.root(1).CFrame.Position)).toBeNil()

	for houseId = 1, 12 do
		expect(door(server, houseId):GetAttribute("State")).toBe("Closed")
		expect(door(server, houseId):GetAttribute("HP")).toBe(100)
		expect(door(server, houseId).HPBar.Enabled).toBe(true)
	end

	-- Only the occupant can open a door, and the wolf cannot open "its" house.
	local bobDoor, caraDoor = door(server, bobHouse), door(server, caraHouse)
	server.trigger(caraDoor.PromptAnchor.OpenPrompt, 2)
	expect(caraDoor:GetAttribute("State")).toBe("Closed")
	local wolfHouse = svc.House.Assigned[1]
	server.trigger(door(server, wolfHouse).PromptAnchor.OpenPrompt, 1)
	expect(door(server, wolfHouse):GetAttribute("State")).toBe("Closed")
	server.trigger(bobDoor.PromptAnchor.OpenPrompt, 2)
	expect(bobDoor:GetAttribute("State")).toBe("Open")
	expect(bobDoor.CFrame.Position).toEqual(bobDoor:GetAttribute("OpenCFrame").Position)
	expect(bobDoor.PromptAnchor.OpenPrompt.Enabled).toBe(false) -- cannot be closed again

	-- Five wolf hits break a door.
	for hit = 1, 4 do
		expect(svc.House.DamageDoor(caraHouse, server.Config.Wolf.DoorDamage)).toBe(false)
		expect(caraDoor:GetAttribute("HP")).toBe(100 - hit * 20)
	end
	expect(svc.House.DamageDoor(caraHouse, server.Config.Wolf.DoorDamage)).toBe(true)
	expect(caraDoor:GetAttribute("State")).toBe("Broken")
	expect(caraDoor.Transparency).toBe(1)
	expect(caraDoor.CanCollide).toBe(false)

	------------------------------------------------------------------ day 2
	waitForDay(server, 2)
	expect(hasAnnouncement(server, "Morning.Safe").Style).toBe("Red")
	expect(caraDoor:GetAttribute("State")).toBe("Closed")
	expect(caraDoor.Transparency).toBe(0)
	expect(caraDoor.RepairFront.Enabled).toBe(true) -- repair marks the morning after
	expect(bobDoor.RepairFront.Enabled).toBe(false)
	expect(bobDoor:GetAttribute("State")).toBe("Closed")
	expect(caraDoor.HPBar.Enabled).toBe(false)
	for _, id in { 1, 2, 3 } do
		local position = server.root(id).CFrame.Position
		expect(svc.House.HouseAt(position)).toBeNil() -- warped out to the front of the house
		expect(flatRadius(position) < server.Config.Map.HouseRingRadius).toBe(true)
	end
	expect(svc.Match.Roster.Members[2].NightsSurvived).toBe(1)

	-- The bell is locked for the first 3 minutes.
	expect(server.trigger(bell(server), 2)).toBe(false)
	ringBell(server, 2)
	server.waitForPhase("MeetingCountdown")
	expect(hasAnnouncement(server, "Phase.MeetingCalled").Args.name).toBe("Bob")
	expect(bell(server).Enabled).toBe(false) -- once per day

	---------------------------------------------------------------- meeting
	server.waitForPhase("Meeting")
	for _, id in { 1, 2, 3 } do
		expect(server.humanoid(id).WalkSpeed).toBe(0)
		expect(flatRadius(server.root(id).CFrame.Position)).toBeNear(server.Config.Map.MeetingSpotRadius, 0.01)
	end
	expect(#server.last("VoteOpened", "all")[1].Candidates).toBe(12)
	local bot = firstBot(server)

	server.fireServer("VoteSelect", 2, 2) -- no self vote
	expect(#server.last("VoteCounts", "all")[1]).toBe(0)
	server.fireServer("VoteSelect", 2, "garbage")
	server.fireServer("VoteSelect", 2, 999999)
	expect(#server.last("VoteCounts", "all")[1]).toBe(0)
	server.fireServer("VoteConfirm", 2) -- nothing selected: ignored
	expect(#server.last("VoteCounts", "all")[1]).toBe(0)

	server.fireServer("VoteSelect", 2, bot)
	server.fireServer("VoteConfirm", 2)
	server.fireServer("VoteSelect", 3, bot) -- selected, not confirmed
	expect(server.last("VoteCounts", "all")[1]).toEqual({ { Id = bot, Pending = 1, Confirmed = 1 } })
	expect(server.last("VoteMine", 2)[1]).toEqual({ Target = bot, Confirmed = true })
	expect(server.last("VoteMine", 3)[1]).toEqual({ Target = bot, Confirmed = false })

	server.fireServer("VoteSelect", 2, 3) -- a confirmed vote is final
	expect(server.last("VoteCounts", "all")[1]).toEqual({ { Id = bot, Pending = 1, Confirmed = 1 } })

	local closed = server.waitFor("vote result", function()
		return server.last("VoteClosed", "all")
	end)[1]
	expect(closed.ExiledId).toBe(bot) -- the unconfirmed selection was auto-confirmed
	expect(closed.Resolution).toBe("Majority")
	expect(closed.Role).toBeNil() -- no role reveal
	expect(svc.Match.Roster.Members[bot].Alive).toBe(false)
	expect(svc.Match.Winner).toBeNil()
	expect(server.humanoid(2).WalkSpeed).toBe(16)

	---------------------------------------------------------------- night 2
	server.waitForPhase("FullMoonWarning")
	server.waitForPhase("Night")
	expect(door(server, caraHouse).RepairFront.Enabled).toBe(false) -- back to normal the next night
	expect(server.last("PhaseChanged", "all")[1].Night).toBe(2)

	------------------------------------------------- day 3: exile the wolf
	waitForDay(server, 3)
	ringBell(server, 3)
	server.waitForPhase("Meeting")
	expect(#server.last("VoteOpened", "all")[1].Candidates).toBe(11)
	server.fireServer("VoteSelect", 2, 1)
	server.fireServer("VoteConfirm", 2)
	server.fireServer("VoteSelect", 3, 1)
	server.fireServer("VoteConfirm", 3)

	local over = server.waitFor("game over", function()
		return server.last("GameOver", "all")
	end)[1]
	expect(over.Winner).toBe("Village")
	expect(over.EndingKey).toBe("Ending.Village")
	server.waitForPhase("GameOver")
	expect(svc.Match.CharacterOf(1)).toBeNil() -- the exiled player's body is gone
end)

test("forced meeting, nobody votes, forest player is not warped, wolf leaves", function()
	local server = start({ ForceRole = "Wolf", ForceRoleUserId = 1 })
	local svc = services(server)

	waitForDay(server, 1)
	-- Cara walks into the forest before nightfall.
	local forest = server.root(3).CFrame.Rotation + Vector3.new(150, 3, 0)
	server.root(3).CFrame = forest

	server.waitForPhase("Night")
	expect(server.last("HouseAssigned", 3)[1]).toBe(0)
	expect(server.root(3).CFrame.Position).toEqual(forest.Position)
	expect(svc.House.Assigned[3]).toBeNil()

	-- Morning: she is still in the forest, so she is not warped either.
	waitForDay(server, 2)
	expect(server.root(3).CFrame.Position).toEqual(forest.Position)

	-- Nobody rings the bell: the meeting is forced when the day runs out,
	-- and it pulls in the forest player too.
	server.waitForPhase("Meeting")
	expect(server.last("PhaseChanged", "all")[1].MeetingForced).toBe(true)
	expect(hasAnnouncement(server, "Phase.MeetingForced") ~= nil).toBe(true)
	expect(flatRadius(server.root(3).CFrame.Position)).toBeNear(server.Config.Map.MeetingSpotRadius, 0.01)

	local closed = server.waitFor("vote result", function()
		return server.last("VoteClosed", "all")
	end)[1]
	expect(closed.Resolution).toBe("NoVotes")
	expect(closed.ExiledId).toBeNil()
	expect(#svc.Match.Roster.Order).toBe(12)

	server.waitForPhase("Night")
	-- The wolf leaves with no pup alive: the village wins at once.
	server.removePlayer(1)
	local over = server.waitFor("game over", function()
		return server.last("GameOver", "all")
	end)[1]
	expect(over.Winner).toBe("Village")
	server.waitForPhase("GameOver")
end)

test("the fool wins by being voted out", function()
	local server = start({ ForceRole = "Fool", ForceRoleUserId = 2 })

	waitForDay(server, 1)
	expect(server.last("RoleAssigned", 2)[1]).toBe("Fool")
	waitForDay(server, 2)
	ringBell(server, 1)
	server.waitForPhase("Meeting")
	server.fireServer("VoteSelect", 1, 2)
	server.fireServer("VoteSelect", 3, 2)

	local over = server.waitFor("game over", function()
		return server.last("GameOver", "all")
	end)[1]
	expect(over.Winner).toBe("Fool")
	expect(over.EndingKey).toBe("Ending.Fool")
	server.waitForPhase("GameOver")
end)
