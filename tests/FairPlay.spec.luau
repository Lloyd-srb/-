--[[
	Owner's fair-play rules (17 Nov 2026):
	  - speed / teleport cheats are put back (MovementGuard);
	  - the game's own warps are never mistaken for cheating;
	  - a night spent doing nothing at all is not a night survived (AFK),
	    while hiding (pressing "hide") counts as doing something.
]]

local function start(roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = { TimerScale = 0.02, MinPlayers = 3, FillWithBots = true, UnlockAllRoles = false, ForceRoles = roles },
	})
	local folder = server.game.ServerScriptService.Services
	local svc = setmetatable({}, {
		__index = function(_, name)
			return server.require(folder[name .. (if name == "MovementGuard" then "" else "Service")])
		end,
	})
	return server, svc
end

local function waitFor(server, phase, number)
	server.waitFor(phase .. " " .. number, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == phase and (if phase == "Night" then last[1].Night else last[1].Day) == number
	end, 10)
end

test("fair play: a teleport is put back; walking and the game's own warps are not", function()
	local server, svc = start({ [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	server.Config.AntiCheat.InStudio = true -- on, even with Studio debug settings
	server.Config.AntiCheat.Interval = 0.1
	waitFor(server, "Day", 1)
	local root = svc.Match.RootOf(2)
	root.CFrame = CFrame.new(0, 3, 0)
	svc.MovementGuard.Warp(2, CFrame.new(0, 3, 0)) -- a known starting point
	task.wait(1.7) -- past the warp grace
	local before = svc.MovementGuard.Corrections

	-- A normal step is fine.
	root.CFrame = CFrame.new(1, 3, 0)
	task.wait(0.15)
	expect(svc.MovementGuard.Corrections).toBe(before)

	-- 300 studs in a tenth of a second: put back.
	root.CFrame = CFrame.new(300, 3, 0)
	task.wait(0.15)
	expect(svc.MovementGuard.Corrections > before).toBe(true)
	expect((svc.Match.RootOf(2).CFrame.Position - Vector3.new(1, 3.5, 0)).Magnitude < 0.01).toBe(true)

	-- A warp made by the game is fine.
	local count = svc.MovementGuard.Corrections
	svc.MovementGuard.Warp(2, CFrame.new(-200, 3, 50))
	task.wait(0.3)
	expect(svc.MovementGuard.Corrections).toBe(count)
	expect((svc.Match.RootOf(2).CFrame.Position - Vector3.new(-200, 3, 50)).Magnitude < 0.01).toBe(true)

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("fair play: the night warp into houses and the meeting warp never count as cheating", function()
	local server, svc = start({ [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	server.Config.AntiCheat.InStudio = true
	server.Config.AntiCheat.Interval = 0.05
	waitFor(server, "Day", 2)
	server.waitForPhase("Meeting", 15)
	task.wait(0.2)
	expect(svc.MovementGuard.Corrections).toBe(0)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("AFK: a night of doing nothing is not counted; hiding is doing something", function()
	local server, svc = start({ [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Night", 1)
	-- Bob hides under his bed (a plan, not AFK). Cara does nothing at all.
	local houseId = server.last("HouseAssigned", 2)[1]
	local house = server.game.Workspace.Map.Houses[string.format("House%02d", houseId)]
	server.trigger(house.Bed.Frame.PromptAnchor.HidePrompt, 2)
	expect(svc.Hiding.IsHidden(2)).toBe(true)
	waitFor(server, "Day", 2)
	local roster = svc.Match.Roster
	expect(roster.Members[2].NightsSurvived).toBe(1)
	expect(roster.Members[3].NightsSurvived).toBe(0)
	-- Bots never count as AFK.
	for _, member in roster.Members do
		if member.IsBot and member.Alive then
			expect(member.NightsSurvived).toBe(1)
		end
	end
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("AFK: chatting or using a button also counts as doing something", function()
	local server, svc = start({ [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Night", 1)
	server.fireServer("AbilityUse", 3, "See") -- any button press reaches the server
	waitFor(server, "Day", 2)
	expect(svc.Match.Roster.Members[3].NightsSurvived).toBe(1)
	expect(svc.Match.Roster.Members[2].NightsSurvived).toBe(0)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)
