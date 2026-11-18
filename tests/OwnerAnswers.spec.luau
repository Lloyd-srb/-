--[[
	Owner's answers of 18 Nov 2026 (questions 13, 15, 19, 34, 47, 53, 55, 56,
	59, 64, 67, 106, 109, 112, 113 and the "eyes closed" screen).
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local VoiceRules = require(game.ServerScriptService.Logic.VoiceRules)

local BOT_A, BOT_B = -1004, -1005

local function start(scale, roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = { TimerScale = scale, MinPlayers = 3, FillWithBots = true, UnlockAllRoles = false, ForceRoles = roles },
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

test("prices and numbers: attack speed scale, Premium 499, skins by rarity", function()
	expect(Config.MonsterStatValues.AttackSpeed).toEqual({ 3, 2.5, 2, 1.5, 1 })
	expect(Config.SeasonPass.PremiumRobuxPrice).toBe(499)
	expect(Config.SkinRarityPrice).toEqual({ Rare = 99, Epic = 199, Legendary = 399 })
	for skinId, def in Config.Skins do
		if def.Source == "Shop" then
			expect(def.Rarity ~= nil).toBe(true)
			expect(def.Price).toBe(Config.SkinRarityPrice[def.Rarity])
		end
	end
	expect(Config.Skins.GunGold.Price).toBe(99)
	expect(Config.Skins.WolfShadow.Price).toBe(199)
end)

test("voice: ghosts are heard by ghosts only; a werewolf in beast form by nobody", function()
	local function speaker(id, alive, beast, phase)
		return { Id = id, Phase = phase or "Match", Alive = alive, Beast = beast }
	end
	local everyone = { speaker(1, true, false), speaker(2, false, false), speaker(3, false, false), speaker(4, true, true) }
	expect(VoiceRules.forSpeaker(everyone[1], everyone)).toEqual({ Open = true, Allow = {} })
	expect(VoiceRules.forSpeaker(everyone[2], everyone)).toEqual({ Open = false, Allow = { 3 } })
	expect(VoiceRules.forSpeaker(everyone[4], everyone)).toEqual({ Open = false, Allow = {} })
	-- A werewolf in human form (by day) talks normally.
	expect(VoiceRules.forSpeaker(speaker(4, true, false), everyone).Open).toBe(true)
	-- Before and after the match, everyone talks.
	expect(VoiceRules.forSpeaker(speaker(2, false, false, "Over"), everyone).Open).toBe(true)
	expect(VoiceRules.forSpeaker(speaker(2, false, false, "Lobby"), everyone).Open).toBe(true)
end)

test("in a match: eyes closed at night and in the morning (not the wolf); voice rules applied; crates go", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Day", 1)
	expect(#server.sent("EyesClosed", 2)).toBe(0) -- not at the start
	local crate = svc.Inventory.SpawnCrate(Vector3.new(150, 0, 0))

	waitFor(server, "Night", 1)
	expect(#server.sent("EyesClosed", 2)).toBe(1)
	expect(server.last("EyesClosed", 2)[1].Seconds).toBe(3)
	expect(#server.sent("EyesClosed", 3)).toBe(1)
	expect(#server.sent("EyesClosed", 1)).toBe(0) -- the wolf keeps its eyes open
	task.wait(0.1)
	local Voice = svc.Voice
	expect(Voice.Applied[1].Open).toBe(false) -- the werewolf, transformed: nobody hears it
	expect(Voice.Applied[2].Open).toBe(true)

	-- Bob dies: only ghosts hear him (nobody else is dead yet).
	expect(svc.Combat.Damage(BOT_B, 100, "Wolf", 1)).toBe("Converted") -- (the first bite makes the pup)
	expect(svc.Combat.Damage(2, 100, "Wolf", 1)).toBe("Killed")
	task.wait(0.1)
	expect(Voice.Applied[2]).toEqual({ Open = false, Allow = {} })

	waitFor(server, "Day", 2)
	expect(#server.sent("EyesClosed", 3)).toBe(2)
	expect(#server.sent("EyesClosed", 2)).toBe(1) -- a ghost is not woken
	expect(crate.Parent).toBeNil() -- an unopened crate is gone the next morning
	task.wait(0.1)
	expect(Voice.Applied[1].Open).toBe(true) -- human again

	-- Someone tries to join the started match: sent back (here: only marked).
	server.addPlayer(9, "Late")
	expect(svc.Match.LateJoiners[9]).toBe(true)
	expect(svc.Match.Roster.Members[9]).toBeNil()

	svc.Match.Exile(BOT_B)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("a Lover who becomes the pup: the aura is gone, as if dead", function()
	local server, svc = start(0.02, { [1] = "Lover", [2] = "Lover", [3] = "Villager", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	expect(server.last("Highlight", 1)[1].Ids).toEqual({ 2 })
	waitFor(server, "Night", 1)
	expect(svc.Combat.Damage(2, 100, "Wolf", BOT_A)).toBe("Converted")
	local function loverIds(id)
		local found = nil
		for _, args in server.sent("Highlight", id) do
			if args[1].Kind == "Lover" then
				found = args[1].Ids
			end
		end
		return found
	end
	expect(loverIds(1)).toEqual({})
	expect(loverIds(2)).toEqual({})
	svc.Match.Exile(2)
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

test("codes DAY1 (5 spins) and UPD0 (200 Diamonds)", function()
	local lobby = startLobby({ Players = { { Id = 1, Name = "P1" } } })
	lobby.Config.Data.LoadRetryDelay = 0.05
	lobby.waitFor("profile", function()
		return lobby.last("ProfileView", 1) ~= nil
	end, 3)
	local before = lobby.last("ProfileView", 1)[1]
	lobby.fireServer("CodeRedeem", 1, "day1")
	task.wait(0.15)
	expect(lobby.last("CodeResult", 1)[1].Ok).toBe(true)
	lobby.fireServer("CodeRedeem", 1, "UPD0")
	task.wait(0.15)
	expect(lobby.last("CodeResult", 1)[1].Ok).toBe(true)
	task.wait(0.1)
	local after = lobby.last("ProfileView", 1)[1]
	expect(after.Spin.Extra - before.Spin.Extra).toBe(5)
	expect(after.Diamonds - before.Diamonds).toBe(200)
end)
