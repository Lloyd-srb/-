--[[
	Owner's additions of 18 Nov 2026 on the fake engine:
	  - Plague Doctor: red potion (3 uses), night only: a body gets up at once,
	    a living person dies the next morning
	  - Thief: by day, steal one random item (never a role item), once a day
	  - the stream: fetch water -> water the carrots -> Boots (+3 speed for good)
	  - fishing: 10 s at the stream -> a Fish; a fish on the ground glows like
	    a person for the wolf side at night, for nobody else
]]

local Rng = require(game.ReplicatedStorage.Shared.Rng)
local DailyTask = require(game.ServerScriptService.Logic.DailyTask)

local BOT_A, BOT_B, BOT_C = -1004, -1005, -1006

local function start(scale, roles, forceTask)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = {
			TimerScale = scale,
			MinPlayers = 3,
			FillWithBots = true,
			UnlockAllRoles = false,
			ForceRoles = roles,
			ForceTask = forceTask,
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
local function place(svc, id, position)
	svc.Match.RootOf(id).CFrame = CFrame.new(position)
end

local function itemOf(svc, id, kind)
	for _, item in svc.Inventory.Items(id) do
		if item.Kind == kind then
			return item
		end
	end
	return nil
end

local function useItem(server, svc, id, kind)
	local item = itemOf(svc, id, kind)
	assert(item, id .. " has no " .. kind)
	server.fireServer("ItemUse", id, item.Id, Vector3.new(0, 0, -1))
end

local function lastEffect(server, id)
	local last = server.last("Effect", id)
	return last and last[1]
end

local function alive(svc, id)
	return svc.Match.Roster.Members[id].Alive
end

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

test("rules: the water task is the stream first, then a carrot plot; fishing is one catch", function()
	local world = { BrokenDoors = {}, Plots = { 1, 2, 3 }, Trees = { 10, 11 }, WaterSpots = { 1001 }, FishingSpots = { 2001 } }
	local kinds = DailyTask.availableKinds(world)
	expect(table.find(kinds, "WaterCarrots") ~= nil).toBe(true)
	expect(table.find(kinds, "Fishing") ~= nil).toBe(true)
	-- No stream on the map: neither is offered.
	local dry = DailyTask.availableKinds({ BrokenDoors = {}, Plots = { 1 }, Trees = { 10 } })
	expect(table.find(dry, "WaterCarrots")).toBeNil()
	expect(table.find(dry, "Fishing")).toBeNil()

	local water = DailyTask.make("WaterCarrots", world, Rng.seeded(2))
	expect(water.Required).toBe(2)
	expect(DailyTask.mark(water, 2)).toBe(false) -- a plot before any water
	expect(DailyTask.mark(water, 1001)).toBe(true)
	expect(DailyTask.mark(water, 1001)).toBe(false) -- already carrying water
	local _, complete = DailyTask.mark(water, 3)
	expect(complete).toBe(true)
	expect(DailyTask.perk("WaterCarrots")).toBe("Boots")
	expect(DailyTask.reward("WaterCarrots")).toBeNil()

	local fishing = DailyTask.make("Fishing", world, Rng.seeded(2))
	local _, caught = DailyTask.mark(fishing, 2001)
	expect(caught).toBe(true)
	expect(DailyTask.reward("Fishing")).toBe("Fish")
end)

--------------------------------------------------------------------------------
-- Plague Doctor
--------------------------------------------------------------------------------

test("Plague Doctor: 3 doses, 1 by day + 1 by night; the poisoned die the next night and never get up", function()
	local server, svc = start(0.02, { [1] = "PlagueDoctor", [2] = "Villager", [3] = "Sheriff", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	local potion = itemOf(svc, 1, "Potion")
	expect(potion ~= nil).toBe(true)
	expect(potion.Uses).toBe(3)
	expect(itemOf(svc, 2, "Potion")).toBeNil() -- only the Plague Doctor has it
	expect(svc.Inventory.IsRoleItem("Potion")).toBe(true)

	-- Nobody in front: nothing used.
	place(svc, 1, Vector3.new(200, 3, 200))
	useItem(server, svc, 1, "Potion")
	expect(lastEffect(server, 1).Kind).toBe("PotionNoTarget")
	expect(itemOf(svc, 1, "Potion").Uses).toBe(3)

	-- By day: poison the bot in front. Still alive all day.
	place(svc, 1, Vector3.new(40, 3, 40))
	place(svc, BOT_B, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Potion")
	expect(lastEffect(server, 1)).toEqual({ Kind = "Poisoned", Name = svc.Match.Roster.Members[BOT_B].Name })
	expect(itemOf(svc, 1, "Potion").Uses).toBe(2)
	expect(alive(svc, BOT_B)).toBe(true)
	expect(#server.sent("Effect", 2)).toBe(0) -- nobody else learns of it

	-- Only once by day.
	place(svc, BOT_C, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Potion")
	expect(lastEffect(server, 1).Kind).toBe("PotionUsed")
	expect(itemOf(svc, 1, "Potion").Uses).toBe(2)

	-- Night falls: the poisoned bot dies. Nobody can raise that body.
	waitFor(server, "Night", 1)
	server.waitFor("poison", function()
		return not alive(svc, BOT_B)
	end, 3)
	expect(svc.Match.Roster.Members[BOT_B].DeathCause).toBe("Poison")
	local poisonedBody = svc.Match.BodyOf(BOT_B)
	expect(poisonedBody ~= nil).toBe(true)
	expect(poisonedBody.HumanoidRootPart:FindFirstChild("RevivePrompt")).toBeNil() -- not even the Doctor
	local bodyAt = poisonedBody.HumanoidRootPart.CFrame.Position
	place(svc, 1, bodyAt + Vector3.new(0, 0, 3))
	svc.Match.RootOf(1).CFrame = CFrame.new(bodyAt + Vector3.new(0, 0, 3)) * CFrame.Angles(0, math.pi, 0) -- face away from everyone
	useItem(server, svc, 1, "Potion")
	expect(alive(svc, BOT_B)).toBe(false)
	expect(itemOf(svc, 1, "Potion").Uses).toBe(2)

	-- Any other body gets up at once.
	place(svc, BOT_C, Vector3.new(-40, 3, -40))
	expect(svc.Combat.Damage(BOT_C, 1000, "Killer", 3)).toBe("Killed")
	expect(alive(svc, BOT_C)).toBe(false)
	place(svc, 1, Vector3.new(-40, 3, -36))
	useItem(server, svc, 1, "Potion")
	expect(alive(svc, BOT_C)).toBe(true)
	expect(lastEffect(server, 1).Kind).toBe("PotionRevived")
	expect(itemOf(svc, 1, "Potion").Uses).toBe(1)

	-- Only once by night.
	place(svc, 2, Vector3.new(-40, 3, -40))
	useItem(server, svc, 1, "Potion")
	expect(lastEffect(server, 1).Kind).toBe("PotionUsed")
	expect(itemOf(svc, 1, "Potion").Uses).toBe(1)

	-- The potion is a role item: nobody else can hold it.
	expect(svc.Inventory.CanTake(2, "Potion")).toBe(false)
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

--------------------------------------------------------------------------------
-- Thief
--------------------------------------------------------------------------------

test("Thief: by day, one random item a day; never a role item; not at night", function()
	local server, svc = start(0.02, { [1] = "Thief", [2] = "Villager", [3] = "PlagueDoctor", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	local prompt = svc.Match.RootOf(2):FindFirstChild("StealPrompt")
	expect(prompt ~= nil).toBe(true)
	expect(prompt:GetAttribute("Audience")).toBe("Role:Thief")
	expect(prompt:GetAttribute("OwnerId")).toBe(2)
	expect(prompt.Enabled).toBe(true)
	expect(svc.Match.RootOf(1):FindFirstChild("StealPrompt"):GetAttribute("OwnerId")).toBe(1)

	-- Nothing to take: the try is free.
	place(svc, 1, Vector3.new(0, 3, 0))
	place(svc, 2, Vector3.new(0, 3, -3))
	server.trigger(prompt, 1)
	expect(lastEffect(server, 1).Kind).toBe("StealNothing")

	-- Only the potion (a role item): nothing is taken.
	local doctorPrompt = svc.Match.RootOf(3):FindFirstChild("StealPrompt")
	place(svc, 3, Vector3.new(0, 3, 3))
	server.trigger(doctorPrompt, 1)
	expect(itemOf(svc, 3, "Potion") ~= nil).toBe(true)
	expect(itemOf(svc, 1, "Potion")).toBeNil()

	-- Bob has an apple: the Thief takes it; Bob is not told.
	svc.Inventory.Give(2, "Apple")
	server.trigger(prompt, 3) -- not the Thief
	expect(svc.Inventory.Count(2, "Apple")).toBe(1)
	place(svc, 1, Vector3.new(60, 3, 0))
	server.trigger(prompt, 1) -- too far
	expect(svc.Inventory.Count(2, "Apple")).toBe(1)
	place(svc, 1, Vector3.new(0, 3, 0))
	local bobEffects = #server.sent("Effect", 2)
	server.trigger(prompt, 1)
	expect(svc.Inventory.Count(2, "Apple")).toBe(0)
	expect(svc.Inventory.Count(1, "Apple")).toBe(1)
	expect(lastEffect(server, 1)).toEqual({ Kind = "Stolen", Item = "Apple" })
	expect(#server.sent("Effect", 2)).toBe(bobEffects)

	-- One a day.
	svc.Inventory.Give(2, "Cross")
	server.trigger(prompt, 1)
	expect(svc.Inventory.Count(2, "Cross")).toBe(1)

	-- Night: the prompts close.
	waitFor(server, "Night", 1)
	expect(prompt.Enabled).toBe(false)
	server.trigger(prompt, 1)
	expect(svc.Inventory.Count(2, "Cross")).toBe(1)

	-- A new day, a new steal.
	waitFor(server, "Day", 2)
	if alive(svc, 2) and alive(svc, 1) then
		local again = svc.Match.RootOf(2):FindFirstChild("StealPrompt")
		expect(again.Enabled).toBe(true)
		place(svc, 1, Vector3.new(0, 3, 0))
		place(svc, 2, Vector3.new(0, 3, -3))
		server.trigger(again, 1)
		expect(svc.Inventory.Count(2, "Cross")).toBe(0)
		expect(svc.Inventory.Count(1, "Cross")).toBe(1)
	end
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

--------------------------------------------------------------------------------
-- The stream: water -> Boots, fishing -> Fish -> bait
--------------------------------------------------------------------------------

local function anchorPosition(prompt)
	local anchor = prompt.Parent
	if anchor:IsA("Attachment") then
		return (anchor.Parent.CFrame * anchor.CFrame).Position
	end
	return anchor.CFrame.Position
end

local function doStep(server, svc, id, prompt)
	svc.Match.RootOf(id).CFrame = CFrame.new(anchorPosition(prompt) + Vector3.new(2, 0, 0))
	return server.trigger(prompt, id)
end

local function promptFor(server, kind, target)
	for _, prompt in server.game.Workspace:GetDescendants() do
		if prompt:IsA("ProximityPrompt") and prompt.Name == kind .. "Prompt" and prompt:GetAttribute("TargetId") == target then
			return prompt
		end
	end
	error("no prompt for " .. kind .. " " .. target)
end

test("water the carrots: water from the stream first, then a plot; Boots = +3 speed for good (human form)", function()
	local server, svc = start(0.02, { [1] = "Villager", [2] = "Doctor", [3] = "Sheriff", [BOT_A] = "Wolf" }, "WaterCarrots")
	waitFor(server, "Day", 1)
	local task = server.last("TaskChanged", 1)[1]
	expect(task.Kind).toBe("WaterCarrots")
	local base = server.Config.Human.WalkSpeed
	expect(svc.Move.Speed(1)).toBe(base)

	local water = promptFor(server, "WaterCarrots", DailyTask.WaterBase + 1)
	expect(water:GetAttribute("Audience")).toBe("Task:WaterCarrots")
	local plot = promptFor(server, "WaterCarrots", 4)
	doStep(server, svc, 1, plot) -- no water yet
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(0)
	doStep(server, svc, 1, water)
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(0)
	doStep(server, svc, 1, plot)
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(1)
	expect(svc.Match.Roster.Members[1].HasBoots).toBe(true)
	expect(svc.Move.Speed(1)).toBe(base + 3)
	local boots = false
	for _, args in server.sent("Effect", 1) do
		boots = boots or args[1].Kind == "Boots"
	end
	expect(boots).toBe(true)
	-- Boots are not an item: nothing to drop, steal or lose.
	expect(#svc.Inventory.Items(1)).toBe(0)
	-- Bob did not do it.
	expect(svc.Move.Speed(2)).toBe(base)

	-- The next day the boots are still on.
	waitFor(server, "Day", 2)
	if alive(svc, 1) then
		expect(svc.Move.Speed(1)).toBe(base + 3)
	end
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

test("fishing: a Fish; on the ground it glows like a person for the wolf side at night only", function()
	local server, svc = start(0.02, { [1] = "Villager", [2] = "Wolf", [3] = "Sheriff" }, "Fishing")
	waitFor(server, "Day", 1)
	local spot = promptFor(server, "Fishing", DailyTask.FishingBase + 1)
	expect(spot.HoldDuration).toBe(server.Config.Tasks.Fishing.Hold)
	expect(server.Config.Tasks.Fishing.Hold).toBe(10)
	doStep(server, svc, 1, spot)
	expect(svc.Inventory.Count(1, "Fish")).toBe(1)

	-- Put it down by day: no glow yet.
	place(svc, 1, Vector3.new(30, 3, 30))
	useItem(server, svc, 1, "Fish")
	expect(svc.Inventory.Count(1, "Fish")).toBe(0)
	expect(#svc.Inventory.Baits()).toBe(1)
	local function baitGlow(id)
		local found = nil
		for _, args in server.sent("Highlight", id) do
			if args[1].Kind == "Bait" then
				found = args[1]
			end
		end
		return found
	end
	expect(baitGlow(2)).toBeNil()

	waitFor(server, "Night", 1)
	server.waitFor("bait glow", function()
		local glow = baitGlow(2)
		return glow ~= nil and #glow.Spots == 1
	end, 5)
	local glow = baitGlow(2)
	expect(typeof(glow.Spots[1])).toBe("Vector3")
	expect((glow.Spots[1] - Vector3.new(30, glow.Spots[1].Y, 30)).Magnitude < 1).toBe(true)
	expect(baitGlow(1)).toBeNil() -- villagers never see it
	expect(baitGlow(3)).toBeNil()

	-- Gone after the night.
	waitFor(server, "Day", 2)
	expect(#svc.Inventory.Baits()).toBe(0)
	expect(#baitGlow(2).Spots).toBe(0)
	svc.Match.Exile(2)
	server.waitForPhase("GameOver", 10)
end)

--------------------------------------------------------------------------------
-- The map and the shop
--------------------------------------------------------------------------------

test("map: a stream with a bridge in the village's top-right corner, water and fishing spots on it", function()
	local server = startServer({ Players = {}, Debug = { Enabled = false } })
	local CollectionService = server.game:GetService("CollectionService")
	local water = CollectionService:GetTagged("WaterSpot")
	local fishing = CollectionService:GetTagged("FishingSpot")
	expect(#water).toBe(1)
	expect(#fishing).toBe(1)
	local map = server.game.Workspace.Map
	local stream = map:FindFirstChild("Stream", true)
	expect(stream ~= nil).toBe(true)
	expect(stream:FindFirstChild("Bridge", true) ~= nil).toBe(true)
	local deck = stream:FindFirstChild("Deck", true)
	expect(deck.CanCollide).toBe(true)
	-- Top right of the village: +X and -Z of the centre (the map's "north" is -Z).
	local at = water[1].CFrame.Position
	expect(at.X > 0).toBe(true)
	expect(at.Z < 0).toBe(true)
end)

test("Plague Doctor and Thief: village side, for sale, with icons and text", function()
	local server = startServer({ Players = {}, Debug = { Enabled = false } })
	local Config = server.Config
	local Strings = server.require(server.game.ReplicatedStorage.Shared.Strings)
	local RoleIcons = server.require(server.game.ReplicatedStorage.Shared.RoleIcons)
	for _, roleId in { "PlagueDoctor", "Thief" } do
		local def = Config.Roles[roleId]
		expect(def.Faction).toBe("Village")
		expect(def.Free).toBe(false)
		expect(table.find(Config.RoleOrder, roleId) ~= nil).toBe(true)
		expect(RoleIcons.Designs[roleId] ~= nil).toBe(true)
		expect(Strings["Role." .. roleId .. ".Name"] ~= nil).toBe(true)
		expect(Strings["Role." .. roleId .. ".Desc"] ~= nil).toBe(true)
	end
	for _, item in { "Potion", "Fish" } do
		expect(Strings["Item." .. item .. ".Name"] ~= nil).toBe(true)
		expect(Config.ItemLook[item] ~= nil).toBe(true)
	end
	expect(Config.Boots.SpeedBonus).toBe(3)
end)
