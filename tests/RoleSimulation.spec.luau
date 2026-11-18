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

test("role picks are chosen in the Lobby, saved, and used in the match; no role screen (owner, 18 Nov 2026)", function()
	local people = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } }
	local lobby = startLobby({ Players = people, Experience = "role-picks" })
	lobby.Config.Data.LoadRetryDelay = 0.05
	local Profiles = lobby.require(lobby.game.ServerStorage.ServerShared.Profiles)
	local function view(id)
		lobby.waitFor("profile view " .. id, function()
			return lobby.last("ProfileView", id) ~= nil
		end, 3)
		task.wait(0.1)
		return lobby.last("ProfileView", id)[1]
	end
	-- A new player starts with the three free roles picked.
	expect(view(1).RolePicks).toEqual({ "Villager", "Sheriff", "Doctor" })
	Profiles.Update(lobby.player(1), function(data)
		data.Roles.Seer, data.Roles.Priest, data.Roles.Engineer = true, true, true
	end)
	-- Refused: not owned, the wolf, a duplicate, more than three, garbage.
	for _, bad in { { "Killer" }, { "Wolf" }, { "Seer", "Seer" }, { "Seer", "Priest", "Engineer", "Doctor" }, { 1, 2 } } do
		lobby.fireServer("SaveRolePicks", 1, bad)
	end
	lobby.fireServer("SaveRolePicks", 1, "Seer")
	expect(view(1).RolePicks).toEqual({ "Villager", "Sheriff", "Doctor" })
	-- Accepted.
	lobby.fireServer("SaveRolePicks", 1, { "Seer", "Priest", "Engineer" })
	expect(view(1).RolePicks).toEqual({ "Seer", "Priest", "Engineer" })
	for _, person in people do
		lobby.removePlayer(person.Id) -- off to the match (saved)
	end

	local match = startServer({ Players = {}, Experience = "role-picks", Debug = { TimerScale = 1, MinPlayers = 3, FillWithBots = true } })
	match.Config.Data.LoadRetryDelay = 0.05
	for _, person in people do
		match.addPlayer(person.Id, person.Name)
	end
	-- Everyone's profile loads quickly: day 1 starts well before the phase's limit.
	match.waitFor("day 1", function()
		return match.phase() == "Day"
	end, 6)
	local alice = match.last("RoleAssigned", 1)[1]
	expect(alice == "Wolf" or table.find({ "Seer", "Priest", "Engineer" }, alice) ~= nil).toBe(true)
	for _, id in { 2, 3 } do
		local role = match.last("RoleAssigned", id)[1]
		expect(role == "Wolf" or table.find({ "Villager", "Sheriff", "Doctor" }, role) ~= nil).toBe(true)
	end
	-- No role screen any more.
	local Remotes = match.require(match.game.ReplicatedStorage.Shared.Remotes)
	expect(table.find(Remotes.Names, "RoleOptions")).toBeNil()
	expect(table.find(Remotes.Names, "RolePicks")).toBeNil()
	finish(match, setmetatable({}, {
		__index = function(_, name)
			return match.require(match.game.ServerScriptService.Services[name .. "Service"])
		end,
	}))
end)

test("new players: the match uses their three free roles", function()
	local server, svc = start({ TimerScale = 0.01, UnlockAllRoles = false })
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
	-- A Lover's partner may come from the villagers (no slot).
	expect(special - (if counts.Lover == 2 then 1 else 0) <= 4).toBe(true)
	expect((counts.Killer or 0) + (counts.Fool or 0) + (counts.FireManiac or 0) <= 1).toBe(true)
	finish(server, svc)
end)
