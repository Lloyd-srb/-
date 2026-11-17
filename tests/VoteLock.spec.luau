--[[
	Owner's vote rules (17 Nov 2026): the Chief's vote shows as one silhouette;
	in the last seconds every vote is locked and the Chief's silhouette gets a
	crown; nobody is exiled with fewer than 2 votes.
]]

local function start(roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = { TimerScale = 0.02, MinPlayers = 3, FillWithBots = true, UnlockAllRoles = false, ForceRoles = roles },
	})
	return server
end

local function counts(server)
	local list = server.last("VoteCounts", "all")[1]
	local byId = {}
	for _, entry in list do
		byId[entry.Id] = entry
	end
	return byId
end

test("vote: the chief is one silhouette; at the lock votes freeze and the chief's gets a crown", function()
	local server = start({ [1] = "Chief", [2] = "Wolf", [3] = "Villager" })
	server.waitForPhase("Meeting", 15)
	server.fireServer("VoteSelect", 1, 2) -- the Chief
	server.fireServer("VoteSelect", 3, 2)
	task.wait(0.02)
	local before = counts(server)[2]
	expect(before.Pending).toBe(2) -- one silhouette each, the Chief included
	expect(before.Chief).toBeNil() -- no crown before the lock

	server.waitFor("votes locked", function()
		return server.last("VoteLocked", "all") ~= nil
	end, 5)
	local after = counts(server)[2]
	expect(after.Confirmed).toBe(2) -- selections became final
	expect(after.Pending).toBe(0)
	expect(after.Chief).toBe(true) -- the crown
	expect(server.last("VoteMine", 3)[1].Confirmed).toBe(true)

	-- Too late to change anything.
	server.fireServer("VoteSelect", 3, 1)
	task.wait(0.02)
	expect(server.last("VoteMine", 3)[1].Target).toBe(2)

	server.waitFor("vote result", function()
		return server.last("VoteClosed", "all") ~= nil
	end, 5)
	expect(server.last("VoteClosed", "all")[1].ExiledId).toBe(2)
	server.waitForPhase("GameOver", 10) -- the wolf was voted out
end)

test("vote: one lone vote exiles nobody", function()
	local server = start({ [1] = "Villager", [2] = "Wolf", [3] = "Doctor" })
	server.waitForPhase("Meeting", 15)
	server.fireServer("VoteSelect", 3, 2)
	server.waitFor("vote result", function()
		return server.last("VoteClosed", "all") ~= nil
	end, 5)
	local result = server.last("VoteClosed", "all")[1]
	expect(result.Resolution).toBe("TooFewVotes")
	expect(result.ExiledId).toBeNil()
	server.removePlayer(2)
	server.waitForPhase("GameOver", 10)
end)
