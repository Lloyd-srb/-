--[[
	Role simulations: the real server scripts on the fake engine.
	Role selection (GDD §4) and roles scaled to the player count.
]]

local function start(debug)
	debug.MinPlayers = debug.MinPlayers or 3
	debug.FillWithBots = true
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = debug,
	})
	local folder = server.game.ServerScriptService.Services
	local svc = setmetatable({}, {
		__index = function(_, name)
			return server.require(folder[name .. "Service"])
		end,
	})
	return server, svc
end

local function finish(server, svc)
	-- End the match so its loop stops: the wolf leaves.
	for _, member in svc.Match.Roster.Members do
		if member.Role == "Wolf" and not member.IsBot then
			server.removePlayer(member.Id)
			server.waitForPhase("GameOver", 10)
			return
		end
	end
	for _, id in { 1, 2, 3 } do
		if server.player(id) then
			server.removePlayer(id)
		end
	end
end

test("role screen: options are private, bad picks are rejected, all confirmed = start early", function()
	local server, svc = start({ TimerScale = 1, UnlockAllRoles = true }) -- 30 s timer
	server.waitForPhase("RoleSelect")

	-- Everyone gets their own option list.
	for _, id in { 1, 2, 3 } do
		local options = server.last("RoleOptions", id)[1]
		expect(#options.Usable).toBe(10)
		expect(options.PickCount).toBe(3)
		expect(table.find(options.Usable, "Wolf")).toBeNil() -- the wolf can never be picked
	end
	expect(#server.sent("RoleOptions", "all")).toBe(0)

	-- Rejected: wrong count, duplicate, the wolf, unknown role, garbage.
	server.fireServer("RolePicks", 1, { "Seer", "Monk" })
	server.fireServer("RolePicks", 1, { "Seer", "Seer", "Monk" })
	server.fireServer("RolePicks", 1, { "Seer", "Monk", "Wolf" })
	server.fireServer("RolePicks", 1, { "Seer", "Monk", "Hacker" })
	server.fireServer("RolePicks", 1, "Seer")
	server.fireServer("RolePicks", 1, { 1, 2, 3 })
	expect(#server.sent("RolePicksAck", 1)).toBe(0)
	expect(svc.Match.PicksOf(1)).toBeNil()

	-- Accepted, and can be changed until the phase ends.
	server.fireServer("RolePicks", 1, { "Seer", "Monk", "Engineer" })
	expect(server.last("RolePicksAck", 1)[1]).toEqual({ "Seer", "Monk", "Engineer" })
	server.fireServer("RolePicks", 1, { "Chief", "Bodyguard", "Doctor" })
	expect(svc.Match.PicksOf(1)).toEqual({ "Chief", "Bodyguard", "Doctor" })
	expect(server.phase()).toBe("RoleSelect") -- still waiting for the others

	server.fireServer("RolePicks", 2, { "Seer", "Monk", "Engineer" })
	server.fireServer("RolePicks", 3, { "Killer", "Fool", "Sheriff" })
	-- All three confirmed: day 1 starts right away instead of after 30 s.
	server.waitFor("day 1", function()
		return server.phase() == "Day"
	end, 2)

	-- Everyone got one of their own picks (or was drawn as the wolf).
	local chosen = {
		[1] = { "Chief", "Bodyguard", "Doctor" },
		[2] = { "Seer", "Monk", "Engineer" },
		[3] = { "Killer", "Fool", "Sheriff" },
	}
	local roles = {}
	for id, picks in chosen do
		local role = server.last("RoleAssigned", id)[1]
		expect(role == "Wolf" or table.find(picks, role) ~= nil).toBe(true)
		expect(roles[role]).toBeNil() -- no duplicates among special roles
		roles[role] = true
	end
	-- Picks are no longer accepted once the match has started.
	server.fireServer("RolePicks", 1, { "Seer", "Monk", "Engineer" })
	expect(svc.Match.PicksOf(1)).toEqual({ "Chief", "Bodyguard", "Doctor" })
	finish(server, svc)
end)

test("role screen: new players only see and can only pick the three free roles", function()
	local server, svc = start({ TimerScale = 0.01, UnlockAllRoles = false })
	server.waitForPhase("RoleSelect")
	local options = server.last("RoleOptions", 2)[1]
	expect(options.Usable).toEqual({ "Villager", "Sheriff", "Doctor" })
	expect(options.Level).toBe(1)
	server.fireServer("RolePicks", 2, { "Villager", "Sheriff", "Killer" }) -- not owned
	expect(#server.sent("RolePicksAck", 2)).toBe(0)
	server.fireServer("RolePicks", 2, { "Villager", "Sheriff", "Doctor" })
	expect(#server.sent("RolePicksAck", 2)).toBe(1)

	-- Nobody else confirms: the timer runs out and they get random owned roles.
	server.waitFor("day 1", function()
		return server.phase() == "Day"
	end, 5)
	for _, id in { 1, 2, 3 } do
		local role = server.last("RoleAssigned", id)[1]
		expect(role == "Wolf" or role == "Villager" or role == "Sheriff" or role == "Doctor").toBe(true)
	end
	finish(server, svc)
end)

test("an 8-player match: 1 wolf, at most 4 special roles, at most one of Killer / Fool", function()
	local server, svc = start({ TimerScale = 0.01, FillTo = 8, UnlockAllRoles = true })
	server.waitFor("day 1", function()
		return server.phase() == "Day"
	end, 5)
	local counts, total, special = {}, 0, 0
	for _, member in svc.Match.Roster.Members do
		counts[member.Role] = (counts[member.Role] or 0) + 1
		total += 1
		if server.Config.Roles[member.Role].Kind == "Special" then
			special += 1
		end
	end
	expect(total).toBe(8)
	expect(counts.Wolf).toBe(1)
	expect(special <= 4).toBe(true)
	expect((counts.Killer or 0) + (counts.Fool or 0) <= 1).toBe(true)
	finish(server, svc)
end)
