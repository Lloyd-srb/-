--[[
	Role ability simulations (GDD §9): the real server scripts on the fake
	engine. Each test forces a set of roles, then plays them out:
	  1. Sheriff + Killer (+ a wolf): stun shots, knife kills, shot kills the Killer
	  2. Seer + Bodyguard (+ a wolf): night vision, dash stun, pass-through, walls
	  3. Doctor + Monk + Engineer (wolf is a bot): blessing, revive, doors
	  4. Chief + Villager: tie-break and flashlight
]]

local BOT_A, BOT_B, BOT_C, BOT_D, BOT_E = -1004, -1005, -1006, -1007, -1008

local function start(scale, roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = {
			TimerScale = scale,
			MinPlayers = 3,
			FillWithBots = true,
			UnlockAllRoles = false,
			ForceRoles = roles,
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

-- Puts a member's body at `position`, looking along -Z (or +Z with `backwards`).
local function place(svc, id, position, backwards)
	local root = svc.Match.RootOf(id)
	root.CFrame = CFrame.new(position) * (if backwards then CFrame.Angles(0, math.pi, 0) else CFrame.new())
end

local function use(server, id, ability, argument)
	server.fireServer("AbilityUse", id, ability, argument)
end

local function lastState(server, id, name)
	local found = nil
	for _, args in server.sent("AbilityState", id) do
		if args[1].Name == name then
			found = args[1]
		end
	end
	return found
end

local function count(server, remote, to, kind)
	local n = 0
	for _, args in server.sent(remote, to) do
		if kind == nil or args[1].Kind == kind then
			n += 1
		end
	end
	return n
end

local function alive(svc, id)
	return svc.Match.Roster.Members[id].Alive
end

test("Sheriff and Killer", function()
	local server, svc = start(0.02, { [1] = "Sheriff", [2] = "Wolf", [3] = "Killer" })
	local roster = svc.Match.Roster

	waitFor(server, "Day", 1)
	expect(lastState(server, 1, "Shoot").UsesLeft).toBe(1)
	expect(lastState(server, 3, "Stab").UsesLeft).toBe(1)
	expect(lastState(server, 2, "Shoot")).toBeNil() -- nobody else is told about these

	-------------------------------------------------- day 1: stun shot
	place(svc, 2, Vector3.new(60, 3, 0))
	place(svc, 3, Vector3.new(-60, 3, 0))
	place(svc, 1, Vector3.new(0, 3, 40))
	place(svc, BOT_A, Vector3.new(0, 3, 30))
	use(server, 1, "Shoot", "garbage") -- bad aim: ignored, not spent
	use(server, 1, "Shoot", Vector3.new(0 / 0, 0, 0))
	expect(lastState(server, 1, "Shoot").UsesLeft).toBe(1)
	use(server, 3, "Shoot", Vector3.new(0, 0, -1)) -- not the Sheriff
	expect(count(server, "Effect", "all", "Shot")).toBe(0)

	use(server, 1, "Shoot", Vector3.new(0, 0, -1))
	expect(svc.Combat.IsStunned(BOT_A)).toBe(true)
	expect(svc.Match.HumanoidOf(BOT_A).WalkSpeed).toBe(0)
	expect(alive(svc, BOT_A)).toBe(true) -- a stun, not a kill
	expect(count(server, "Effect", "all", "Shot")).toBe(1) -- everyone sees the tracer
	expect(lastState(server, 1, "Shoot").UsesLeft).toBe(0)
	use(server, 1, "Shoot", Vector3.new(0, 0, -1)) -- one shot per day
	expect(count(server, "Effect", "all", "Shot")).toBe(1)

	-------------------------------------------------- day 1: knife
	place(svc, 3, Vector3.new(40, 3, 0))
	use(server, 3, "Stab") -- nobody in reach: not spent
	expect(lastState(server, 3, "Stab").UsesLeft).toBe(1)
	place(svc, BOT_B, Vector3.new(40, 3, -4))
	use(server, 3, "Stab")
	expect(alive(svc, BOT_B)).toBe(false)
	expect(roster.Members[BOT_B].DeathCause).toBe("Killer")
	expect(roster.KillerKills).toBe(1)
	expect(roster.Members[BOT_B].DiedAtNight).toBe(false)
	expect(svc.Match.BodyOf(BOT_B).HumanoidRootPart:FindFirstChild("RevivePrompt")).toBeNil() -- day deaths stay dead
	place(svc, BOT_C, Vector3.new(40, 3, -4))
	use(server, 3, "Stab") -- one kill per day
	expect(alive(svc, BOT_C)).toBe(true)
	use(server, 1, "Stab") -- not the Killer
	expect(alive(svc, BOT_C)).toBe(true)

	-------------------------------------------------- night 1
	waitFor(server, "Night", 1)
	expect(lastState(server, 1, "Shoot").UsesLeft).toBe(1) -- a new shot for the night
	expect(svc.Wolf.IsTransformed(2)).toBe(true)
	-- Out on the plaza (z = 60 is inside a house: nobody gets in there with the door shut).
	place(svc, 2, Vector3.new(0, 3, 30))
	place(svc, 1, Vector3.new(0, 3, 40))
	use(server, 1, "Shoot", Vector3.new(0, 0, -1))
	expect(svc.Combat.IsStunned(2)).toBe(true) -- a werewolf is only stunned
	expect(server.humanoid(2).WalkSpeed).toBe(0)
	-- A stunned wolf cannot attack.
	place(svc, BOT_D, Vector3.new(0, 3, 27))
	server.fireServer("WolfAttack", 2)
	expect(alive(svc, BOT_D)).toBe(true)
	expect(roster.PupsCreated).toBe(0)

	-- The Killer's knife kills a werewolf too.
	place(svc, BOT_D, Vector3.new(100, 3, 100)) -- out of the way
	place(svc, 3, Vector3.new(0, 3, 26), true) -- facing +Z, towards the wolf
	use(server, 3, "Stab")
	expect(alive(svc, 2)).toBe(false)
	expect(roster.KillerKills).toBe(2)
	expect(roster.Members[2].DiedAtNight).toBe(true)
	-- Wolves all gone but the Killer lives and many villagers remain: the game goes on.
	expect(svc.Match.Winner).toBeNil()

	-------------------------------------------------- day 2: the Sheriff kills the Killer
	waitFor(server, "Day", 2)
	place(svc, 1, Vector3.new(0, 3, 40))
	place(svc, 3, Vector3.new(0, 3, 30))
	use(server, 1, "Shoot", Vector3.new(0, 0, -1))
	expect(alive(svc, 3)).toBe(false)
	expect(roster.Members[3].DeathCause).toBe("Sheriff")
	expect(server.last("GameOver", "all")[1].Winner).toBe("Village")
	server.waitForPhase("GameOver", 10)
end)

test("Seer and Bodyguard", function()
	local server, svc = start(0.02, { [1] = "Seer", [2] = "Bodyguard", [3] = "Wolf" })
	server.Config.Abilities.Bodyguard.Cooldown = 0.3

	waitFor(server, "Day", 1)
	-------------------------------------------------- day: no vision, dash stuns nobody
	use(server, 1, "See")
	expect(count(server, "Highlight", 1, "Seer")).toBe(0) -- night only

	place(svc, 2, Vector3.new(0, 3, 40))
	place(svc, 3, Vector3.new(0, 3, 30)) -- the wolf, still human by day
	use(server, 2, "Dash")
	local dashStart = server.last("DashStart", 2)[1]
	expect(dashStart.Direction).toEqual(Vector3.new(0, 0, -1))
	expect(dashStart.Duration).toBeNear(23 / server.Config.Abilities.Bodyguard.DashSpeed, 1e-6)
	expect(#server.sent("DashStart", "all")).toBe(0)
	expect(svc.Combat.IsStunned(3)).toBe(false)
	-- Passing through people while dashing, solid again afterwards.
	local root = svc.Match.RootOf(2)
	expect(root.CollisionGroup).toBe("Dash")
	use(server, 2, "Dash") -- cooldown
	expect(#server.sent("DashStart", 2)).toBe(1)
	task.wait(0.5)
	expect(root.CollisionGroup).toBe("Characters")

	-- A wall 5 studs ahead cuts the dash short.
	server.blockSight(true, 5)
	use(server, 2, "Dash")
	server.blockSight(false)
	expect(server.last("DashStart", 2)[1].Duration).toBeNear(4 / server.Config.Abilities.Bodyguard.DashSpeed, 1e-6)

	-------------------------------------------------- night
	waitFor(server, "Night", 1)
	expect(svc.Wolf.IsTransformed(3)).toBe(true)

	-- Bob hides; the Seer sees everyone else, white, for 5 seconds.
	local houseId = server.last("HouseAssigned", 2)[1]
	local bed = server.game.Workspace.Map.Houses[string.format("House%02d", houseId)].Bed.Frame.PromptAnchor.HidePrompt
	server.trigger(bed, 2)
	expect(svc.Hiding.IsHidden(2)).toBe(true)
	use(server, 1, "See")
	local seen = nil
	for _, args in server.sent("Highlight", 1) do
		if args[1].Kind == "Seer" then
			seen = args[1]
		end
	end
	expect(seen.Duration).toBe(server.Config.Abilities.Seer.Duration)
	expect(table.find(seen.Ids, 1)).toBeNil() -- not yourself
	expect(table.find(seen.Ids, 2)).toBeNil() -- hidden players stay hidden
	expect(table.find(seen.Ids, 3) ~= nil).toBe(true) -- the wolf shows as just another survivor
	expect(#seen.Ids).toBe(10) -- the wolf + 9 bots
	expect(count(server, "Highlight", 3, "Seer")).toBe(0)
	use(server, 1, "See") -- once per night
	expect(count(server, "Highlight", 1, "Seer")).toBe(1)

	-- Hidden players cannot use abilities.
	use(server, 2, "Dash")
	local dashes = #server.sent("DashStart", 2)
	server.fireServer("HideExit", 2)

	-- Dash into a werewolf: stunned for 5 seconds.
	task.wait(0.35)
	place(svc, 2, Vector3.new(0, 3, 40))
	place(svc, 3, Vector3.new(1.5, 3, 28)) -- just off the dash line
	use(server, 2, "Dash")
	expect(#server.sent("DashStart", 2)).toBe(dashes + 1)
	expect(svc.Combat.IsStunned(3)).toBe(true)

	server.removePlayer(3)
	server.waitForPhase("GameOver", 10)
end)

test("Doctor, Monk and Engineer", function()
	local server, svc = start(0.02, { [1] = "Doctor", [2] = "Monk", [3] = "Engineer", [BOT_A] = "Wolf" })
	local roster = svc.Match.Roster
	local function door(houseId)
		return server.game.Workspace.Map.Houses[string.format("House%02d", houseId)].Door
	end
	local function standAtDoor(id, houseId)
		place(svc, id, door(houseId).CFrame.Position + Vector3.new(0, 0, 0))
	end

	waitFor(server, "Day", 1)
	-------------------------------------------------- day 1: blessing
	expect(lastState(server, 2, "Bless").UsesLeft).toBe(1)
	use(server, 2, "Bless", 999) -- nobody
	use(server, 1, "Bless", 3) -- not the Monk
	expect(svc.Role.IsBlessed(3)).toBe(false)
	use(server, 2, "Bless", 3)
	expect(svc.Role.IsBlessed(3)).toBe(true)
	expect(server.last("Effect", 2)[1]).toEqual({ Kind = "Blessed", Name = "Cara" })
	expect(#server.sent("Effect", 3)).toBe(0) -- the blessed player is not told
	use(server, 2, "Bless", 2) -- one blessing per morning
	expect(svc.Role.IsBlessed(2)).toBe(false)

	-------------------------------------------------- day 1: reinforcing a door
	local prompt5 = door(5).PromptAnchor.ReinforcePrompt
	expect(prompt5.Enabled).toBe(true)
	expect(prompt5:GetAttribute("Audience")).toBe("Role:Engineer")
	standAtDoor(1, 5)
	server.trigger(prompt5, 1) -- not the Engineer
	expect(door(5):GetAttribute("Reinforced")).toBe(false)
	place(svc, 3, Vector3.new(0, 3, 0))
	server.trigger(prompt5, 3) -- too far away
	expect(door(5):GetAttribute("Reinforced")).toBe(false)
	standAtDoor(3, 5)
	server.trigger(prompt5, 3)
	expect(door(5):GetAttribute("Reinforced")).toBe(true)
	expect(door(5):GetAttribute("MaxHP")).toBe(200)
	standAtDoor(3, 6)
	server.trigger(door(6).PromptAnchor.ReinforcePrompt, 3) -- one per day
	expect(door(6):GetAttribute("Reinforced")).toBe(false)

	-------------------------------------------------- night 1
	waitFor(server, "Night", 1)
	expect(door(5):GetAttribute("HP")).toBe(200) -- a day reinforcement lasts through the night
	use(server, 2, "Bless", 1) -- no blessing at night
	expect(svc.Role.IsBlessed(1)).toBe(false)

	-- The Engineer reinforces their own door from inside.
	local own = server.last("HouseAssigned", 3)[1]
	standAtDoor(3, own)
	server.trigger(door(own).PromptAnchor.ReinforcePrompt, 3)
	expect(door(own):GetAttribute("HP")).toBe(200)

	-- The wolf (a bot here) attacks: first victim becomes the pup...
	expect(svc.Combat.Damage(BOT_B, 100, "Wolf", BOT_A)).toBe("Converted")
	-- ...the blessing saves Cara once, and both sides are told...
	expect(svc.Combat.Damage(3, 100, "Wolf", BOT_A)).toBe("Blocked")
	expect(server.last("Effect", 3)[1]).toEqual({ Kind = "Blocked" })
	expect(svc.Role.IsBlessed(3)).toBe(false)
	expect(alive(svc, 3)).toBe(true)
	-- ...and two bots die where they stand.
	place(svc, BOT_C, Vector3.new(30, 3, 0))
	place(svc, BOT_D, Vector3.new(-30, 3, 0))
	expect(svc.Combat.Damage(BOT_C, 100, "Wolf", BOT_A)).toBe("Killed")
	expect(svc.Combat.Damage(BOT_D, 100, "Wolf", BOT_A)).toBe("Killed")
	local corpseC = svc.Match.BodyOf(BOT_C)
	local reviveC = corpseC.HumanoidRootPart.RevivePrompt
	local reviveD = svc.Match.BodyOf(BOT_D).HumanoidRootPart.RevivePrompt
	expect(reviveC:GetAttribute("Audience")).toBe("Role:Doctor")

	-- Only the Doctor, only up close.
	place(svc, 2, Vector3.new(31, 3, 0))
	server.trigger(reviveC, 2)
	expect(alive(svc, BOT_C)).toBe(false)
	place(svc, 1, Vector3.new(0, 3, 0))
	server.trigger(reviveC, 1)
	expect(alive(svc, BOT_C)).toBe(false)

	place(svc, 1, Vector3.new(31, 3, 0))
	server.trigger(reviveC, 1)
	expect(alive(svc, BOT_C)).toBe(true)
	expect(corpseC.Parent).toBeNil() -- the corpse is replaced by a living body
	local newBody = svc.Match.CharacterOf(BOT_C)
	expect(newBody ~= nil and newBody:GetAttribute("Corpse") == nil).toBe(true)
	expect((newBody.HumanoidRootPart.CFrame.Position - Vector3.new(30, 0, 0)).Magnitude < 5).toBe(true)
	expect(svc.Combat.Health(BOT_C)).toBe(100)
	expect(lastState(server, 1, "Revive").UsesLeft).toBe(0)

	-- One revive per game without a First aid.
	place(svc, 1, Vector3.new(-31, 3, 0))
	server.trigger(reviveD, 1)
	expect(alive(svc, BOT_D)).toBe(false)

	-------------------------------------------------- day 2
	waitFor(server, "Day", 2)
	expect(door(5):GetAttribute("Reinforced")).toBe(false) -- gone every morning
	expect(door(5):GetAttribute("MaxHP")).toBe(100)
	expect(lastState(server, 2, "Bless").UsesLeft).toBe(1) -- a new morning, a new blessing

	-- End: exile the pup and the wolf.
	svc.Match.Exile(BOT_B)
	svc.Match.Exile(BOT_A)
	expect(server.last("GameOver", "all")[1].Winner).toBe("Village")
	server.waitForPhase("GameOver", 10)
end)

test("Chief and Villager", function()
	local server, svc = start(0.004, { [1] = "Chief", [2] = "Villager", [3] = "Doctor", [BOT_A] = "Wolf" })
	server.Config.Abilities.Villager.ToggleCooldown = 0

	waitFor(server, "Day", 1)
	-- The villager's flashlight: a real light everyone can see, toggled on / off.
	use(server, 2, "Flashlight")
	local character = svc.Match.CharacterOf(2)
	local light = character.HumanoidRootPart.Flashlight
	expect(light.Enabled).toBe(true)
	expect(character:GetAttribute("FlashlightOn")).toBe(true)
	use(server, 2, "Flashlight")
	expect(light.Enabled).toBe(false)
	use(server, 1, "Flashlight") -- not a villager
	expect(svc.Match.CharacterOf(1).HumanoidRootPart:FindFirstChild("Flashlight")).toBeNil()

	-- Day 2: nobody rings the bell, the meeting is forced. 2 votes against 2:
	-- the Chief's side wins ("Ahem!").
	server.waitForPhase("Meeting", 10)
	server.fireServer("VoteSelect", 1, BOT_C) -- the Chief's vote counts twice
	server.fireServer("VoteSelect", 2, BOT_D)
	server.fireServer("VoteSelect", 3, BOT_D)
	local counts = server.last("VoteCounts", "all")[1]
	for _, entry in counts do
		expect(entry.Pending).toBe(2)
	end
	local closed = server.waitFor("vote result", function()
		return server.last("VoteClosed", "all")
	end)[1]
	expect(closed.Resolution).toBe("ChiefTieBreak")
	expect(closed.ExiledId).toBe(BOT_C)

	svc.Match.Exile(BOT_A)
	expect(server.last("GameOver", "all")[1].Winner).toBe("Village")
	server.waitForPhase("GameOver", 10)
end)
