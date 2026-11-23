--[[
	The Lurker (owner, 19 / 23 Nov 2026) and the changes that came with it:
	  - its matches get the water channel; people wade, it swims (+5, sunk)
	  - stats from its bars: speed 22, 50 damage, 1 s between attacks; no pup
	  - water bolt (shares the attack cooldown), invisibility (ends on attack,
	    bolt or water; not on a knock)
	  - anyone can knock on a door that is not their own house
	  - the forest glow lasts only the first moments of each night
	  - no names over heads at night
]]

local BOT_A, BOT_B, BOT_C = -1004, -1005, -1006

local function start(scale, roles, monster)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = {
			TimerScale = scale,
			MinPlayers = 3,
			FillWithBots = true,
			UnlockAllRoles = false,
			ForceRoles = roles,
			ForceMonster = monster,
			ForestSeed = 11,
		},
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

-- Puts a member at `position`, looking along -Z.
local function place(svc, id, position, _look)
	svc.Match.RootOf(id).CFrame = CFrame.new(position)
end

local function shellOf(svc, id)
	local body = svc.Match.CharacterOf(id) or svc.Match.BodyOf(id)
	return body and body:FindFirstChild("WolfShell")
end

test("The Lurker: its channel, its stats, no pup; bolt; invisibility; swimming and wading", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Sheriff" }, "Lurker")
	local cfg = server.Config
	waitFor(server, "Day", 1)
	expect(svc.Match.Roster.Members[1].Monster).toBe("Lurker")
	-- Its passive: the channel is on the map for this match.
	local moat = server.game.Workspace.Map:FindFirstChild("Moat")
	expect(moat ~= nil).toBe(true)
	expect(svc.Forest.MoatShown).toBe(true)

	waitFor(server, "Night", 1)
	server.waitFor("lurker form", function()
		return svc.Wolf.IsTransformed(1)
	end, 3)
	expect(server.last("FormChanged", 1)[1]).toBe("Lurker")
	expect(svc.Move.Speed(1)).toBe(22) -- Run Speed 4
	expect(shellOf(svc, 1):FindFirstChild("TailFin") ~= nil).toBe(true) -- the Lurker rig, not the wolf's

	-- Attack: 50 damage (two hits kill), and a first kill makes no pup.
	place(svc, 1, Vector3.new(0, 3, 40), Vector3.new(0, 0, -1))
	place(svc, BOT_A, Vector3.new(0, 3, 36))
	server.fireServer("WolfAttack", 1)
	expect(svc.Combat.Health(BOT_A)).toBe(50)
	server.fireServer("WolfAttack", 1) -- 1 s between attacks
	expect(svc.Combat.Health(BOT_A)).toBe(50)
	task.wait(cfg.monsterStat("Lurker", "AttackSpeed") + 0.05)
	server.fireServer("WolfAttack", 1)
	expect(svc.Match.Roster.Members[BOT_A].Alive).toBe(false)
	expect(svc.Match.Roster.PupsCreated).toBe(0)
	expect(svc.Match.Roster.Members[BOT_A].IsPup).toBe(false)

	-- Water bolt: the first survivor on the line takes 50; everyone sees it.
	task.wait(1.05)
	place(svc, 1, Vector3.new(60, 3, 50))
	place(svc, BOT_B, Vector3.new(30, 3, 50))
	server.fireServer("WolfAbility", 1, "WaterBolt", Vector3.new(-1, 0, 0))
	expect(svc.Combat.Health(BOT_B)).toBe(50)
	local bolt = server.last("Effect", "all")[1]
	expect(bolt.Kind).toBe("WaterBolt")
	server.fireServer("WolfAbility", 1, "WaterBolt", Vector3.new(-1, 0, 0)) -- shares the cooldown
	expect(svc.Combat.Health(BOT_B)).toBe(50)

	-- Invisibility: the costume disappears; a knock does not end it; an attack does.
	server.fireServer("WolfAbility", 1, "Vanish")
	local body = svc.Match.CharacterOf(1)
	expect(body:GetAttribute("Vanished")).toBe(true)
	expect(shellOf(svc, 1).Head.Transparency).toBe(1)
	cfg.Sounds.DoorKnock = 1234
	local door = server.game.Workspace.Map.Houses.House05.Door
	place(svc, 1, door.CFrame.Position + Vector3.new(0, 0, 0))
	server.trigger(door.PromptAnchor.KnockPrompt, 1)
	expect(body:GetAttribute("Vanished")).toBe(true)
	server.fireServer("WolfAbility", 1, "Vanish") -- 30 s cooldown
	task.wait(1.05)
	server.fireServer("WolfAttack", 1)
	expect(body:GetAttribute("Vanished")).toBeNil()
	expect(shellOf(svc, 1).Head.Transparency).toBe(0)

	-- The channel: it swims faster and sinks; people wade slowly.
	local path = svc.Forest.Layout.Moat
	local spot = path[math.floor(#path / 2)]
	place(svc, 1, spot + Vector3.new(0, 3, 0))
	place(svc, 3, path[math.floor(#path / 2) + 4] + Vector3.new(0, 3, 0))
	server.waitFor("swimming", function()
		return svc.Move.Speed(1) == 27
	end, 2)
	expect(shellOf(svc, 1):GetAttribute("Submerged")).toBe(true)
	expect(svc.Move.Speed(3)).toBe(cfg.Map.Moat.WadeSpeed)
	expect(svc.Match.CharacterOf(3):GetAttribute("InWater")).toBe(true)
	-- Out of the water: back to normal.
	place(svc, 1, Vector3.new(0, 3, 0))
	place(svc, 3, Vector3.new(5, 3, 0))
	server.waitFor("dry again", function()
		return svc.Move.Speed(1) == 22 and svc.Move.Speed(3) == cfg.Human.WalkSpeed
	end, 2)
	expect(shellOf(svc, 1):GetAttribute("Submerged")).toBeNil()

	svc.Match.Exile(1)
	server.waitForPhase("GameOver", 10)
end)

test("knocking: anyone alive on a door that is not their own house; nearby players hear it", function()
	local server, svc = start(0.02, { [1] = "Villager", [2] = "Doctor", [3] = "Sheriff", [BOT_A] = "Wolf" })
	server.Config.Sounds.DoorKnock = 1234
	waitFor(server, "Night", 1)
	local own = svc.House.Assigned[2]
	local other = if own == 1 then 2 else 1
	local function door(houseId)
		return server.game.Workspace.Map.Houses[string.format("House%02d", houseId)].Door
	end
	local function knocks(id)
		local n = 0
		for _, args in server.sent("Sound", id) do
			if args[1].Key == "DoorKnock" then
				n += 1
			end
		end
		return n
	end
	expect(door(other).PromptAnchor.KnockPrompt:GetAttribute("Audience")).toBe("NotOwner")
	-- Not on your own house.
	place(svc, 2, door(own).CFrame.Position)
	server.trigger(door(own).PromptAnchor.KnockPrompt, 2)
	expect(knocks(2)).toBe(0)
	-- On someone else's: heard nearby.
	place(svc, 2, door(other).CFrame.Position)
	place(svc, 3, door(other).CFrame.Position + Vector3.new(4, 0, 0))
	server.trigger(door(other).PromptAnchor.KnockPrompt, 2)
	expect(knocks(2)).toBe(1)
	expect(knocks(3)).toBe(1)
	server.trigger(door(other).PromptAnchor.KnockPrompt, 2) -- a short wait between knocks
	expect(knocks(2)).toBe(1)
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

test("a werewolf match: no channel; forest glow only at the start of the night; no names at night", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Sheriff" })
	waitFor(server, "Day", 1)
	expect(server.game.Workspace.Map:FindFirstChild("Moat")).toBeNil()
	local humanoid = svc.Match.CharacterOf(2):FindFirstChildOfClass("Humanoid")
	expect(humanoid.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.Viewer)

	place(svc, 3, Vector3.new(0, 3, -150)) -- in the forest
	waitFor(server, "Night", 1)
	expect(humanoid.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.None)
	local function forestIds()
		local found = nil
		for _, args in server.sent("Highlight", 1) do
			if args[1].Kind == "Forest" then
				found = args[1].Ids
			end
		end
		return found
	end
	-- Cara stays in the forest all night, but the glow lasts only the first
	-- ForestRevealSeconds (x the test's timer scale).
	place(svc, 3, Vector3.new(0, 3, -150))
	server.waitFor("glow on", function()
		local ids = forestIds()
		return ids ~= nil and #ids == 1
	end, 2)
	server.waitFor("glow off", function()
		local ids = forestIds()
		return ids ~= nil and #ids == 0
	end, 3)
	waitFor(server, "Day", 2)
	expect(humanoid.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.Viewer)
	svc.Match.Exile(1)
	server.waitForPhase("GameOver", 10)
end)

test("monsters for sale: The Lurker 9,999 coins / 699 R$; owned ones can be picked", function()
	local Config = require(game.ReplicatedStorage.Shared.Config)
	local Shop = require(game.ReplicatedStorage.Shared.Logic.Shop)
	local lurker = Config.monsterDef("Lurker")
	expect(lurker.CoinPrice).toBe(9999)
	expect(lurker.RobuxPrice).toBe(699)
	expect(lurker.Stats).toEqual({ RunSpeed = 4, AttackPower = 3, AttackSpeed = 5, Vision = 4 })
	expect(Config.monsterStat("Lurker", "AttackPower")).toBe(50)
	expect(Config.monsterStat("Lurker", "AttackSpeed")).toBe(1)
	expect(Shop.offer("Monster", "Lurker").ProductKey).toBe("MonsterLurker")
	expect(Shop.offer("Monster", "Werewolf")).toBeNil() -- free
	expect(Shop.offerForProduct("MonsterLurker").Id).toBe("Lurker")

	local lobby = startLobby({ Players = { { Id = 1, Name = "P1" } } })
	lobby.Config.Data.LoadRetryDelay = 0.05
	local Profiles = lobby.require(lobby.game.ServerStorage.ServerShared.Profiles)
	local function view()
		lobby.waitFor("view", function()
			return lobby.last("ProfileView", 1) ~= nil
		end, 3)
		task.wait(0.15)
		return lobby.last("ProfileView", 1)[1]
	end
	expect(view().Monster).toBe("Werewolf")
	lobby.fireServer("SelectMonster", 1, "Lurker") -- not owned yet
	expect(view().Monster).toBe("Werewolf")
	Profiles.Update(lobby.player(1), function(data)
		data.Coins = 10000
	end)
	lobby.fireServer("ShopBuy", 1, "Monster", "Lurker", "Coins")
	local after = view()
	expect(after.Monsters.Lurker).toBe(true)
	expect(after.Coins).toBe(1)
	lobby.fireServer("SelectMonster", 1, "Lurker")
	expect(view().Monster).toBe("Lurker")
end)
