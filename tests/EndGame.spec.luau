--[[
	End of match (GDD §7, §13): scoreboard, likes, MVP and rewards, on the
	real server with the fake engine.
]]

local Likes = require(game.ServerScriptService.Logic.Likes)

test("likes: one per player, never yourself, can be moved", function()
	local state = Likes.new()
	expect(Likes.give(state, 1, 1)).toBe(false)
	expect(Likes.give(state, 1, 2)).toBe(true)
	expect(Likes.give(state, 3, 2)).toBe(true)
	expect(Likes.counts(state)).toEqual({ [2] = 2 })
	Likes.give(state, 1, 3) -- Alice changes her mind
	expect(Likes.counts(state)).toEqual({ [2] = 1, [3] = 1 })
end)

local function start(scale, roles, debug)
	debug = debug or {}
	debug.TimerScale = scale
	debug.MinPlayers = 3
	debug.FillWithBots = true
	debug.UnlockAllRoles = false
	debug.ForceRoles = roles
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

local function waitFor(server, phase, number)
	server.waitFor(phase .. " " .. number, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == phase and (if phase == "Night" then last[1].Night else last[1].Day) == number
	end, 10)
end

local function row(rows, id)
	for _, entry in rows do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

test("village wins: roles revealed, likes, MVP, rewards into profiles", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" }, { ForceTask = "PlantCarrot" })
	waitFor(server, "Day", 1)
	-- Bob finishes his task.
	local plot = server.game.Workspace.Map.Gardens.Garden03.Soil.PromptAnchor.PlantCarrotPrompt
	svc.Match.RootOf(2).CFrame = CFrame.new((plot.Parent.Parent.CFrame * plot.Parent.CFrame).Position + Vector3.new(2, 0, 0))
	server.trigger(plot, 2)
	expect(svc.Match.Roster.Members[2].TasksCompleted).toBe(1)

	waitFor(server, "Day", 2)
	expect(#server.sent("Scoreboard", "all")).toBe(0) -- roles stay secret until the end
	svc.Match.Exile(1)
	server.waitForPhase("GameOver", 10)

	-- The scoreboard reveals everyone's role, to everyone.
	local board = server.last("Scoreboard", "all")[1]
	expect(board.Winner).toBe("Village")
	expect(#board.Rows).toBe(12)
	expect(row(board.Rows, 1).Role).toBe("Wolf")
	expect(row(board.Rows, 1).Won).toBe(false)
	expect(row(board.Rows, 1).Alive).toBe(false)
	expect(row(board.Rows, 2).Role).toBe("Villager")
	expect(row(board.Rows, 2).Won).toBe(true)
	expect(row(board.Rows, 3).Won).toBe(true)

	-- Likes: not yourself; the dead can like too; one each.
	server.fireServer("Like", 2, 2)
	expect(#server.last("LikeCounts", "all")[1]).toBe(0)
	server.fireServer("Like", 2, 3)
	server.fireServer("Like", 3, 2)
	server.fireServer("Like", 1, 2) -- Alice is a ghost: still allowed
	server.fireServer("Like", 1, 999) -- nobody
	local counts = {}
	for _, entry in server.last("LikeCounts", "all")[1] do
		counts[entry.Id] = entry.Count
	end
	expect(counts).toEqual({ [2] = 2, [3] = 1 })

	-- After the like window: Bob is MVP, everyone gets their own reward.
	local results = server.waitFor("results", function()
		return server.last("Results", "all")
	end, 5)[1]
	expect(results.MvpId).toBe(2)
	server.fireServer("Like", 3, 1) -- too late
	expect(svc.End.Granted[2] ~= nil).toBe(true)
	expect(#server.sent("RewardSummary", "all")).toBe(0) -- rewards are private

	local bob = server.last("RewardSummary", 2)[1]
	expect(bob.Won).toBe(true)
	expect(bob.IsMvp).toBe(true)
	expect(bob.NightsSurvived).toBe(1)
	expect(bob.TasksCompleted).toBe(1)
	expect(bob.Coins).toBe(48) -- (1 night x 20 + 1 task x 20) x 1.2
	expect(bob.Exp).toBe(60) -- 50 x 1.2
	expect(bob.PassExp).toBe(150)
	expect(bob.MasteryRole).toBe("Villager")
	expect(bob.MasteryPoints).toBe(2)

	local alice = server.last("RewardSummary", 1)[1]
	expect(alice.Won).toBe(false)
	expect(alice.Coins).toBe(10) -- half for losing
	expect(alice.PassExp).toBe(50)
	expect(alice.MasteryRole).toBe("Wolf")
	expect(alice.MasteryPoints).toBe(1)

	-- Saved into the (in-memory) profiles.
	local profile = svc.Profile.Get(server.player(2))
	expect(profile.Coins).toBe(48)
	expect(profile.Exp).toBe(60)
	expect(profile.Pass.Exp).toBe(150)
	expect(profile.Mastery.Villager).toBe(2)
	expect(svc.Profile.Get(server.player(3)).Mastery.Doctor).toBe(2)
	expect(svc.End.Granted[-1005]).toBeNil() -- bots get nothing
end)

test("leaving early keeps the nights survived (as a loss); the pup wins with the wolves", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Doctor", [3] = "Villager" })
	waitFor(server, "Night", 1)
	expect(svc.Combat.Damage(2, 100, "Wolf", 1)).toBe("Converted") -- Bob is the pup now
	waitFor(server, "Day", 2)

	-- Cara survived one night and leaves: rewarded at once, as a loss.
	server.removePlayer(3)
	local cara = svc.End.Granted[3]
	expect(cara.NightsSurvived).toBe(1)
	expect(cara.Won).toBe(false)
	expect(cara.Coins).toBe(10)

	-- The wolves take the village: every bot falls.
	for _, member in svc.Match.Roster.Members do
		if member.IsBot and member.Alive then
			svc.Combat.Damage(member.Id, 100, "Killer", nil)
		end
	end
	server.waitForPhase("GameOver", 10)
	local board = server.last("Scoreboard", "all")[1]
	expect(board.Winner).toBe("Wolf")
	expect(row(board.Rows, 2).Role).toBe("Pup")
	expect(row(board.Rows, 2).StartRole).toBe("Doctor")
	expect(row(board.Rows, 2).Won).toBe(true)

	server.waitFor("results", function()
		return server.last("Results", "all")
	end, 5)
	local bob = server.last("RewardSummary", 2)[1]
	expect(bob.Won).toBe(true)
	expect(bob.MasteryRole).toBe("Doctor") -- mastery goes to the role dealt at the start
	expect(bob.IsMvp).toBe(false) -- nobody liked anyone: no MVP
	expect(svc.End.Granted[3].Coins).toBe(10) -- Cara was not rewarded twice
end)

test("mastery: every 20 points is worth 20 diamonds", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	server.waitForPhase("RoleSelect")
	local player = server.player(2)
	local grant = { Coins = 0, Exp = 0, PassExp = 0, MasteryRole = "Seer", MasteryPoints = 19 }
	expect(svc.Profile.Grant(player, grant)).toBe(0)
	grant.MasteryPoints = 2
	expect(svc.Profile.Grant(player, grant)).toBe(20)
	expect(svc.Profile.Get(player).Diamonds).toBe(20)
	expect(svc.Profile.Get(player).Mastery.Seer).toBe(21)
	server.removePlayer(1)
	server.removePlayer(2)
	server.removePlayer(3)
end)
