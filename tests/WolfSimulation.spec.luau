--[[
	Wolf-side simulations: the real server scripts on the fake engine.
	Covers transformation, attacks, pup conversion, door bashing, abilities,
	highlights privacy, hiding / searching, pup promotion and the wolf win.
]]

local function start(scale, debug)
	debug = debug or {}
	debug.TimerScale = scale
	debug.UnlockAllRoles = false -- starter roles only: no Killer / Fool by chance
	debug.MinPlayers = 3
	debug.FillWithBots = true
	debug.ForceRole = debug.ForceRole or "Wolf"
	debug.ForceRoleUserId = debug.ForceRoleUserId or 1
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = debug,
	})
	local folder = server.game.ServerScriptService.Services
	local svc = {
		Combat = server.require(folder.CombatService),
		Hiding = server.require(folder.HidingService),
		House = server.require(folder.HouseService),
		Match = server.require(folder.MatchService),
		Wolf = server.require(folder.WolfService),
	}
	return server, svc
end

local function waitForDay(server, day)
	server.waitFor("day " .. day, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Day" and last[1].Day == day
	end, 10)
end

local function waitForNight(server, night)
	server.waitFor("night " .. night, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Night" and last[1].Night == night
	end, 10)
end

local function flatRadius(position)
	return math.sqrt(position.X * position.X + position.Z * position.Z)
end

local function rootOf(svc, id)
	return svc.Match.RootOf(id)
end

-- Puts `attackerId` 3 studs from the target. Facing it unless `lookAway`.
-- Puts the attacker next to the target. A target inside a shut house first
-- opens the door (nobody can walk into a shut house: HouseService.IsTrespassing).
local function standBy(svc, attackerId, targetId, lookAway)
	local target = rootOf(svc, targetId).CFrame.Position
	local houseId = svc.House.HouseAt(target)
	local door = if houseId then svc.House.DoorOf(houseId) else nil
	if door and door.State == "Closed" then
		door.State = "Open"
	end
	local offset = if lookAway then Vector3.new(0, 0, -3) else Vector3.new(0, 0, 3)
	rootOf(svc, attackerId).CFrame = CFrame.new(target + offset) -- identity rotation looks along -Z
end

local function attack(server, id)
	server.fireServer("WolfAttack", id)
end

local function lastHighlight(server, viewer, kind)
	local found = nil
	for _, args in server.sent("Highlight", viewer) do
		if args[1].Kind == kind then
			found = args[1]
		end
	end
	return found
end

local function bots(svc)
	local list = {}
	for _, member in svc.Match.Roster.Members do
		if member.IsBot and member.Alive then
			table.insert(list, member.Id)
		end
	end
	table.sort(list)
	return list
end

local function houseModel(server, houseId)
	return server.game.Workspace.Map.Houses[string.format("House%02d", houseId)]
end

test("wolf night: transform, attack rules, pup, door, abilities, highlights, morning", function()
	local server, svc = start(0.02)
	local cfg = server.Config
	cfg.Wolf.AttackCooldown = 0.05
	cfg.Pup.AttackCooldown = 0.05
	cfg.Wolf.Sprint.MaulDuration = 0.25
	local roster = svc.Match.Roster

	waitForDay(server, 1)
	expect(#server.sent("FormChanged")).toBe(0) -- nobody transforms by day
	expect(svc.Match.BodyOf(bots(svc)[1]) ~= nil).toBe(true) -- debug bots have bodies

	waitForNight(server, 1)
	----------------------------------------------------------- transformation
	expect(server.last("FormChanged", 1)[1]).toBe("Wolf")
	expect(#server.sent("FormChanged", 2)).toBe(0)
	expect(#server.sent("FormChanged", "all")).toBe(0)
	local alice = svc.Match.CharacterOf(1)
	expect(alice:GetAttribute("Form")).toBe("Wolf")
	local shell = alice:FindFirstChild("WolfShell")
	expect(shell ~= nil and shell:HasTag("WolfShell")).toBe(true)
	expect(shell:FindFirstChild("LeftEye") ~= nil).toBe(true)
	expect(alice.HumanoidRootPart.Transparency).toBe(1) -- human body hidden
	expect(shell.Chest.Transparency).toBe(0) -- the costume is not
	expect(server.humanoid(1).WalkSpeed).toBe(cfg.Wolf.WalkSpeed)
	expect(server.last("PackChanged", 1)[1]).toEqual({ 1 })
	expect(#server.sent("PackChanged", 2)).toBe(0)

	------------------------------------------------------------- attack rules
	attack(server, 1) -- nobody near the plaza
	expect(roster.WolfKills).toBe(0)
	attack(server, 2) -- a human cannot attack
	expect(roster.WolfKills).toBe(0)

	task.wait(0.06)
	standBy(svc, 1, 2)
	server.blockSight(true) -- a wall in between
	attack(server, 1)
	expect(roster.Members[2].Faction).toBe("Village")
	server.blockSight(false)

	task.wait(0.06)
	standBy(svc, 1, 2, true) -- back turned
	attack(server, 1)
	expect(roster.Members[2].Faction).toBe("Village")

	-- First kill of the night: Bob becomes the pup instead of dying.
	task.wait(0.06)
	standBy(svc, 1, 2)
	attack(server, 1)
	expect(roster.Members[2].Alive).toBe(true)
	expect(roster.Members[2].IsPup).toBe(true)
	expect(roster.PupsCreated).toBe(1)
	expect(roster.WolfKills).toBe(1)
	expect(server.last("RoleAssigned", 2)[1]).toBe("Pup")
	expect(server.last("FormChanged", 2)[1]).toBe("Pup")
	expect(server.humanoid(2).WalkSpeed).toBe(cfg.Pup.WalkSpeed)
	expect(svc.Match.CharacterOf(2):GetAttribute("Corpse")).toBeNil() -- no corpse
	expect(server.last("PackChanged", 1)[1]).toEqual({ 1, 2 })
	expect(server.last("PackChanged", 2)[1]).toEqual({ 1, 2 })
	expect(#server.sent("PackChanged", 3)).toBe(0)
	expect(svc.Match.Winner).toBeNil()

	-- Cooldown: an immediate second swing does nothing.
	standBy(svc, 1, 3)
	attack(server, 1)
	expect(roster.Members[3].Alive).toBe(true)
	task.wait(0.06)
	attack(server, 1)
	expect(roster.Members[3].Alive).toBe(false) -- one hit kills, and only one pup per game
	expect(roster.Members[3].DeathCause).toBe("Wolf")
	expect(svc.Match.BodyOf(3):GetAttribute("Corpse")).toBe(true) -- the body stays where it fell
	expect(svc.Match.CharacterOf(3)).toBeNil()
	expect(roster.WolfKills).toBe(2)
	expect(svc.Match.DeathsThisNight).toBe(1)

	-- The pup needs two hits.
	local botIds = bots(svc)
	local victim = botIds[1]
	standBy(svc, 2, victim)
	attack(server, 2)
	expect(roster.Members[victim].Alive).toBe(true)
	expect(svc.Combat.Health(victim)).toBe(50)
	task.wait(0.06)
	attack(server, 2)
	expect(roster.Members[victim].Alive).toBe(false)
	expect(roster.Members[victim].DeathCause).toBe("Pup")
	expect(roster.Members[2].Kills).toBe(1)

	------------------------------------------------------------ door bashing
	local houseId = svc.House.Assigned[1] -- the wolf's own (empty) house
	local door = houseModel(server, houseId).Door
	local doorCFrame = door.CFrame
	rootOf(svc, 1).CFrame = CFrame.new(doorCFrame.Position + doorCFrame.LookVector * 3)
		* (doorCFrame.Rotation * CFrame.Angles(0, math.pi, 0))
	for hit = 1, 5 do
		task.wait(0.06)
		attack(server, 1)
		expect(door:GetAttribute("HP")).toBe(100 - hit * cfg.Wolf.DoorDamage)
	end
	expect(door:GetAttribute("State")).toBe("Broken")

	--------------------------------------------------------------- abilities
	-- One bot wanders outdoors in the village, another into the forest.
	local outdoors, inForest = botIds[2], botIds[3]
	svc.Match.RootOf(outdoors).CFrame = CFrame.new(0, 3, -20)
	svc.Match.RootOf(inForest).CFrame = CFrame.new(150, 3, 0)

	server.fireServer("WolfAbility", 2, "Sniff") -- the pup has no sniff
	expect(lastHighlight(server, 2, "Sniff")).toBeNil()
	server.fireServer("WolfAbility", 1, "Howl") -- the wolf has no howl
	expect(lastHighlight(server, 1, "Howl")).toBeNil()

	server.fireServer("WolfAbility", 1, "Sniff")
	local sniff = lastHighlight(server, 1, "Sniff")
	table.sort(sniff.Ids)
	local expected = { outdoors, inForest }
	table.sort(expected)
	expect(sniff.Ids).toEqual(expected) -- only players outside houses
	expect(sniff.Duration).toBe(cfg.Wolf.Sniff.Duration)
	expect(lastHighlight(server, 2, "Sniff")).toBeNil() -- the sniffing wolf only
	local sniffCount = #server.sent("Highlight", 1)
	server.fireServer("WolfAbility", 1, "Sniff") -- on cooldown
	local again = 0
	for _, args in server.sent("Highlight", 1) do
		if args[1].Kind == "Sniff" then
			again += 1
		end
	end
	expect(again).toBe(1)
	expect(#server.sent("Highlight", 1) >= sniffCount).toBe(true)
	expect(server.last("AbilityState", 1)[1].Name).toBe("Sniff")

	-- Forest glow reaches the whole wolf side, nobody else.
	server.waitFor("forest highlight", function()
		local forest = lastHighlight(server, 1, "Forest")
		return forest and #forest.Ids == 1 and forest.Ids[1] == inForest
	end)
	expect(lastHighlight(server, 2, "Forest").Ids).toEqual({ inForest })
	expect(#server.sent("Highlight", 3)).toBe(0)
	expect(#server.sent("Highlight", "all")).toBe(0)

	-- Howl: everyone within 40 studs of the pup, shown to the whole pack.
	svc.Match.RootOf(2).CFrame = CFrame.new(0, 3, -10)
	server.fireServer("WolfAbility", 2, "Howl")
	local howl = lastHighlight(server, 1, "Howl")
	expect(howl.Ids).toEqual({ outdoors })
	expect(howl.Duration).toBe(cfg.Pup.Howl.Duration)
	expect(lastHighlight(server, 2, "Howl").Ids).toEqual({ outdoors })

	-- Sprint: speed 30. A kill while sprinting locks the wolf in a maul.
	server.fireServer("WolfAbility", 1, "Sprint")
	expect(server.humanoid(1).WalkSpeed).toBe(cfg.Wolf.Sprint.Speed)
	task.wait(0.06)
	standBy(svc, 1, outdoors)
	attack(server, 1)
	expect(roster.Members[outdoors].Alive).toBe(false)
	expect(svc.Wolf.IsMauling(1)).toBe(true)
	expect(server.humanoid(1).WalkSpeed).toBe(0)
	attack(server, 1) -- cannot attack while mauling
	task.wait(0.32)
	expect(svc.Wolf.IsMauling(1)).toBe(false)
	expect(server.humanoid(1).WalkSpeed).toBe(cfg.Wolf.WalkSpeed)

	----------------------------------------------------------------- morning
	waitForDay(server, 2)
	expect(server.last("FormChanged", 1)[1]).toBe("Human")
	expect(server.last("FormChanged", 2)[1]).toBe("Human")
	expect(svc.Match.CharacterOf(1):FindFirstChild("WolfShell")).toBeNil()
	expect(svc.Match.CharacterOf(1).HumanoidRootPart.Transparency).toBe(0)
	expect(svc.Match.CharacterOf(1):GetAttribute("Form")).toBe("Human")
	expect(server.humanoid(1).WalkSpeed).toBe(cfg.Human.WalkSpeed)
	expect(server.humanoid(2).WalkSpeed).toBe(cfg.Human.WalkSpeed)
	expect(lastHighlight(server, 1, "Forest").Ids).toEqual({})
	expect(svc.Wolf.IsTransformed(1)).toBe(false)
	-- Someone died: the morning message is a red taunt, not "You're safe".
	local taunted = false
	for _, args in server.sent("Announcement", "all") do
		if string.sub(args[1].Key, 1, 13) == "Morning.Taunt" then
			taunted = args[1].Style == "Red"
		end
		expect(args[1].Key ~= "Morning.Safe").toBe(true)
	end
	expect(taunted).toBe(true)
	-- The pup and the wolf wake up in front of a house like everyone else.
	for _, id in { 1, 2 } do
		local position = rootOf(svc, id).CFrame.Position
		expect(svc.House.HouseAt(position)).toBeNil()
		expect(flatRadius(position) < cfg.Map.HouseRingRadius).toBe(true)
	end
	-- Everybody survived-or-not is public; roles still are not.
	for _, entry in server.last("RosterChanged", "all")[1] do
		expect(entry.Role).toBeNil()
		expect(entry.IsPup).toBeNil()
	end

	server.removePlayer(1)
	server.removePlayer(2)
	server.waitForPhase("GameOver", 10)
end)

test("hiding: only the hider knows the spot; the wolf must search; pulled out = no more hiding", function()
	local server, svc = start(0.02)
	server.Config.Wolf.AttackCooldown = 0
	waitForNight(server, 1)

	local bobHouse = houseModel(server, server.last("HouseAssigned", 2)[1])
	local caraHouse = houseModel(server, server.last("HouseAssigned", 3)[1])
	local bed = bobHouse.Bed.Frame.PromptAnchor
	local wardrobe = bobHouse.Wardrobe.Body.PromptAnchor
	expect(bed.HidePrompt.Enabled and bed.SearchPrompt.Enabled).toBe(true)
	expect(bed.HidePrompt:GetAttribute("Audience")).toBe("Human")
	expect(bed.SearchPrompt:GetAttribute("Audience")).toBe("Wolf")
	local insideBobHouse = rootOf(svc, 2).CFrame

	-- Wrong roles: a human cannot search, the wolf cannot hide.
	server.trigger(bed.SearchPrompt, 2)
	rootOf(svc, 1).CFrame = insideBobHouse
	server.trigger(bed.HidePrompt, 1)
	expect(svc.Hiding.IsHidden(1)).toBe(false)
	expect(svc.Hiding.IsHidden(2)).toBe(false)

	-- Cara is in another house: too far from Bob's bed.
	server.trigger(bed.HidePrompt, 3)
	expect(svc.Hiding.IsHidden(3)).toBe(false)

	-- Bob hides under his bed.
	server.trigger(bed.HidePrompt, 2)
	expect(svc.Hiding.IsHidden(2)).toBe(true)
	expect(server.last("HideChanged", 2)[1] ~= nil).toBe(true)
	expect(#server.sent("HideChanged", 1)).toBe(0) -- nobody else is told
	expect(#server.sent("HideChanged", "all")).toBe(0)
	local parked = rootOf(svc, 2)
	expect(parked.Anchored).toBe(true)
	expect(parked.CFrame.Position.Y).toBe(server.Config.Hiding.HoldingHeight) -- body is far from the map
	server.trigger(wardrobe.HidePrompt, 2) -- already hidden
	expect(svc.Hiding.IsHidden(2)).toBe(true)

	-- The wolf breaks in, stands in the room and swings: a hidden player cannot be hit.
	svc.House.DamageDoor(svc.House.HouseAt(insideBobHouse.Position), 1000)
	server.fireServer("WolfAttack", 1)
	expect(svc.Match.Roster.Members[2].Alive).toBe(true)
	expect(svc.Match.Roster.Members[2].IsPup).toBe(false)

	-- Searching the wrong spot finds nothing; the right one throws Bob out.
	server.trigger(wardrobe.SearchPrompt, 1)
	expect(svc.Hiding.IsHidden(2)).toBe(true)
	server.trigger(bed.SearchPrompt, 1)
	expect(svc.Hiding.IsHidden(2)).toBe(false)
	expect(server.last("HideChanged", 2)[1]).toBeNil()
	expect(rootOf(svc, 2).Anchored).toBe(false)
	expect(svc.House.HouseAt(rootOf(svc, 2).CFrame.Position)).toBe(bobHouse:GetAttribute("HouseId"))

	-- Pulled out: no more hiding tonight, in any spot.
	server.trigger(bed.HidePrompt, 2)
	server.trigger(wardrobe.HidePrompt, 2)
	expect(svc.Hiding.IsHidden(2)).toBe(false)

	-- Cara hides, comes out by herself, and may hide again.
	local caraWardrobe = caraHouse.Wardrobe.Body.PromptAnchor
	server.trigger(caraWardrobe.HidePrompt, 3)
	expect(svc.Hiding.IsHidden(3)).toBe(true)
	server.fireServer("HideExit", 3)
	expect(svc.Hiding.IsHidden(3)).toBe(false)
	expect(svc.House.HouseAt(rootOf(svc, 3).CFrame.Position)).toBe(caraHouse:GetAttribute("HouseId"))
	server.trigger(caraWardrobe.HidePrompt, 3)
	expect(svc.Hiding.IsHidden(3)).toBe(true)

	-- Morning: everyone comes out and is warped to the front of their house.
	waitForDay(server, 2)
	expect(svc.Hiding.IsHidden(3)).toBe(false)
	expect(rootOf(svc, 3).Anchored).toBe(false)
	expect(server.last("HideChanged", 3)[1]).toBeNil()
	local position = rootOf(svc, 3).CFrame.Position
	expect(svc.House.HouseAt(position)).toBeNil()
	expect(flatRadius(position) < server.Config.Map.HouseRingRadius).toBe(true)
	expect(bed.HidePrompt.Enabled).toBe(false)

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("pup grows into the wolf two nights after the wolf is gone, then wins", function()
	local server, svc = start(0.004)
	server.Config.Wolf.AttackCooldown = 0
	local roster = svc.Match.Roster

	-- Night 1: Alice bites Bob.
	waitForNight(server, 1)
	standBy(svc, 1, 2)
	attack(server, 1)
	expect(roster.Members[2].IsPup).toBe(true)

	-- Day 2: the village exiles Alice. The pup keeps the game going.
	waitForDay(server, 2)
	server.waitForPhase("Meeting", 10)
	server.fireServer("VoteSelect", 2, 1)
	server.fireServer("VoteSelect", 3, 1)
	server.waitFor("alice exiled", function()
		return not roster.Members[1].Alive
	end)
	expect(svc.Match.Winner).toBeNil()
	expect(roster.MainWolfLostAtNight).toBe(1)

	-- Night 2 (1st night without the wolf): still a pup.
	waitForNight(server, 2)
	expect(server.last("FormChanged", 2)[1]).toBe("Pup")
	expect(roster.Members[2].IsPup).toBe(true)

	-- Night 3 (2nd night): a full werewolf.
	waitForNight(server, 3)
	expect(roster.Members[2].IsPup).toBe(false)
	expect(server.last("RoleAssigned", 2)[1]).toBe("Wolf")
	expect(server.last("FormChanged", 2)[1]).toBe("Wolf")
	expect(server.humanoid(2).WalkSpeed).toBe(server.Config.Wolf.WalkSpeed)

	-- The new wolf hunts until the villagers left equal the wolves.
	local kills = 0
	for _, member in roster.Members do
		if member.Alive and member.Faction ~= "Wolf" and not svc.Match.Winner then
			standBy(svc, 2, member.Id)
			attack(server, 2)
			kills += 1
		end
	end
	expect(svc.Match.Winner).toBe("Wolf")
	expect(roster.PupsCreated).toBe(1) -- still only one pup per game
	local over = server.last("GameOver", "all")[1]
	expect(over.EndingKey).toBe("Ending.Wolf")
	local others = 0
	for _, member in roster.Members do
		if member.Alive and member.Faction ~= "Wolf" then
			others += 1
		end
	end
	expect(others).toBe(1)
	server.waitForPhase("GameOver", 10)
end)
