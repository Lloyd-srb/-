--[[
	Items, drops and the forest crate (GDD §6.1, §11): the real server on the
	fake engine.
]]

local BOT_A, BOT_B, BOT_C = -1004, -1005, -1006

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

local function place(svc, id, position)
	svc.Match.RootOf(id).CFrame = CFrame.new(position)
end

local function useItem(server, svc, id, kind, aim)
	for _, item in svc.Inventory.Items(id) do
		if item.Kind == kind then
			server.fireServer("ItemUse", id, item.Id, aim)
			return item
		end
	end
	error(id .. " has no " .. kind)
end

local function worldItems(server)
	local list = {}
	for _, model in server.game.Workspace.Items:GetChildren() do
		if model:HasTag("WorldItem") then
			table.insert(list, model)
		end
	end
	return list
end

local function flat(position)
	return math.sqrt(position.X * position.X + position.Z * position.Z)
end

test("using every item", function()
	local server, svc = start(0.02, { [1] = "Villager", [2] = "Doctor", [3] = "Killer", [BOT_A] = "Wolf" })
	local cfg = server.Config
	cfg.Items.Apple.Duration = 0.3
	local Inventory, Combat = svc.Inventory, svc.Combat
	waitFor(server, "Day", 1)

	-- Apple: 30% faster for a while, then eaten.
	Inventory.Give(1, "Apple")
	expect(server.last("Effect", 1)[1]).toEqual({ Kind = "Gained", Item = "Apple" })
	expect(server.player(1).Backpack:FindFirstChild("Apple") ~= nil).toBe(true)
	useItem(server, svc, 1, "Apple")
	expect(server.humanoid(1).WalkSpeed).toBeNear(16 * 1.3, 1e-6)
	expect(Inventory.Count(1, "Apple")).toBe(0)
	expect(server.player(1).Backpack:FindFirstChild("Apple")).toBeNil() -- the tool is gone too
	task.wait(0.4)
	expect(server.humanoid(1).WalkSpeed).toBe(16)

	-- First aid: back to full health.
	Combat.Damage(1, 50, "Pup", nil)
	Inventory.Give(1, "FirstAid")
	useItem(server, svc, 1, "FirstAid")
	expect(Combat.Health(1)).toBe(100)
	expect(Inventory.Count(1, "FirstAid")).toBe(0)

	-- Gun: one per player, never for the Killer, one shot per day.
	expect(Inventory.Give(3, "Gun")).toBeNil()
	expect(Inventory.Give(1, "Gun") ~= nil).toBe(true)
	expect(Inventory.Give(1, "Gun")).toBeNil()
	place(svc, 1, Vector3.new(0, 3, 40))
	place(svc, BOT_B, Vector3.new(0, 3, 30))
	useItem(server, svc, 1, "Gun", "not a direction")
	expect(Combat.IsStunned(BOT_B)).toBe(false)
	useItem(server, svc, 1, "Gun", Vector3.new(0, 0, -1))
	expect(Combat.IsStunned(BOT_B)).toBe(true)
	expect(Inventory.Count(1, "Gun")).toBe(1) -- a gun is kept
	local shots = #server.sent("Effect", "all")
	useItem(server, svc, 1, "Gun", Vector3.new(0, 0, -1))
	expect(#server.sent("Effect", "all")).toBe(shots) -- one shot per day

	-- Axe: two throws, hit or miss.
	Inventory.Give(2, "Axe")
	place(svc, 2, Vector3.new(50, 3, 40))
	useItem(server, svc, 2, "Axe", Vector3.new(1, 0, 0)) -- nobody there: a miss
	expect(Inventory.Items(2)[1].Uses).toBe(1)
	place(svc, BOT_C, Vector3.new(50, 3, 20))
	useItem(server, svc, 2, "Axe", Vector3.new(0, 0, -1))
	expect(Combat.IsStunned(BOT_C)).toBe(true)
	expect(Inventory.Count(2, "Axe")).toBe(0)

	-- Shovel: only used up when it hits.
	Inventory.Give(2, "Shovel")
	place(svc, 2, Vector3.new(-50, 3, 0))
	useItem(server, svc, 2, "Shovel")
	expect(Inventory.Count(2, "Shovel")).toBe(1)
	place(svc, 3, Vector3.new(-50, 3, -3))
	useItem(server, svc, 2, "Shovel")
	expect(Combat.IsStunned(3)).toBe(true)
	expect(Inventory.Count(2, "Shovel")).toBe(0)
	-- A stunned player cannot use items.
	Inventory.Give(3, "Apple")
	useItem(server, svc, 3, "Apple")
	expect(Inventory.Count(3, "Apple")).toBe(1)

	-- Flashlight item.
	Inventory.Give(2, "Flashlight")
	useItem(server, svc, 2, "Flashlight")
	expect(svc.Match.CharacterOf(2):GetAttribute("FlashlightOn")).toBe(true)

	-- Cross: blocks one attack, then breaks.
	Inventory.Give(2, "Cross")
	expect(Combat.Damage(2, 100, "Killer", 3)).toBe("Blocked")
	expect(Inventory.Count(2, "Cross")).toBe(0)
	expect(svc.Match.Roster.Members[2].Alive).toBe(true)

	-- The Doctor spends a First aid on a second revive.
	waitFor(server, "Night", 1)
	Inventory.Give(2, "FirstAid")
	expect(Combat.Damage(BOT_B, 100, "Wolf", BOT_A)).toBe("Converted")
	place(svc, BOT_C, Vector3.new(30, 3, 0))
	expect(Combat.Damage(BOT_C, 100, "Wolf", BOT_A)).toBe("Killed")
	place(svc, -1007, Vector3.new(-30, 3, 0))
	expect(Combat.Damage(-1007, 100, "Wolf", BOT_A)).toBe("Killed")
	place(svc, 2, Vector3.new(31, 3, 0))
	server.trigger(svc.Match.BodyOf(BOT_C).HumanoidRootPart.RevivePrompt, 2)
	expect(svc.Match.Roster.Members[BOT_C].Alive).toBe(true)
	expect(Inventory.Count(2, "FirstAid")).toBe(1) -- the free revive first
	place(svc, 2, Vector3.new(-31, 3, 0))
	server.trigger(svc.Match.BodyOf(-1007).HumanoidRootPart.RevivePrompt, 2)
	expect(svc.Match.Roster.Members[-1007].Alive).toBe(true)
	expect(Inventory.Count(2, "FirstAid")).toBe(0)

	-- End: the Killer and the whole wolf side are voted out.
	svc.Match.Exile(3)
	svc.Match.Exile(BOT_B)
	svc.Match.Exile(BOT_A)
	expect(server.last("GameOver", "all")[1].Winner).toBe("Village")
	server.waitForPhase("GameOver", 10)
end)

test("drops: death on the spot, exile into the forest, leaving into a pile; pick up rules", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Killer" })
	local Inventory = svc.Inventory
	waitFor(server, "Day", 1)

	-- Bob dies by the knife with two items: they fall where he lies and stay.
	Inventory.Give(2, "Apple")
	Inventory.Give(2, "Gun")
	place(svc, 2, Vector3.new(40, 3, 40))
	svc.Combat.Damage(2, 100, "Killer", 3)
	local dropped = worldItems(server)
	expect(#dropped).toBe(2)
	for _, model in dropped do
		local position = model.PrimaryPart.CFrame.Position
		expect((Vector3.new(position.X, 0, position.Z) - Vector3.new(40, 0, 40)).Magnitude <= server.Config.Items.DropSpread + 0.01).toBe(true)
	end
	expect(#Inventory.Items(2)).toBe(0)
	expect(server.player(2).Backpack:FindFirstChildOfClass("Tool")).toBeNil()

	local function dropOf(kind)
		for _, model in worldItems(server) do
			if model:GetAttribute("Kind") == kind then
				return model
			end
		end
		return nil
	end
	-- Dead players cannot pick up; the Killer cannot take a gun; Alice can.
	local gun = dropOf("Gun")
	local prompt = gun.PrimaryPart.PickupPrompt
	expect(prompt:GetAttribute("Audience")).toBe("Human")
	place(svc, 3, gun.PrimaryPart.CFrame.Position)
	server.trigger(prompt, 3)
	expect(Inventory.Count(3, "Gun")).toBe(0)
	expect(gun.Parent ~= nil).toBe(true)
	place(svc, 1, Vector3.new(0, 3, 0))
	server.trigger(prompt, 1) -- too far
	expect(Inventory.Count(1, "Gun")).toBe(0)
	place(svc, 1, gun.PrimaryPart.CFrame.Position)
	server.trigger(prompt, 1)
	expect(Inventory.Count(1, "Gun")).toBe(1)
	expect(gun.Parent).toBeNil()
	place(svc, 3, dropOf("Apple").PrimaryPart.CFrame.Position)
	server.trigger(dropOf("Apple").PrimaryPart.PickupPrompt, 3)
	expect(Inventory.Count(3, "Apple")).toBe(1)

	-- At night the wolf cannot use its gun (paws).
	waitFor(server, "Night", 1)
	place(svc, 1, Vector3.new(0, 3, 40))
	place(svc, BOT_A, Vector3.new(0, 3, 30))
	useItem(server, svc, 1, "Gun", Vector3.new(0, 0, -1))
	expect(svc.Combat.IsStunned(BOT_A)).toBe(false)

	-- Exiled: Cara's apple lands somewhere in the forest.
	waitFor(server, "Day", 2)
	local before = #worldItems(server)
	svc.Match.Exile(3)
	local items = worldItems(server)
	expect(#items).toBe(before + 1)
	local scattered = items[#items].PrimaryPart.CFrame.Position
	expect(flat(scattered) > server.Config.Map.FenceRadius).toBe(true)
	expect(flat(scattered) < server.Config.Map.ForestOuterRadius).toBe(true)

	-- Leaving: Alice's gun goes to the pile in the plaza (and the game ends: she was the wolf).
	before = #worldItems(server)
	server.removePlayer(1)
	items = worldItems(server)
	expect(#items).toBe(before + 1)
	local pile = items[#items].PrimaryPart.CFrame.Position
	expect(flat(pile) < server.Config.Map.PlazaRadius).toBe(true)
	server.waitForPhase("GameOver", 10)
end)

test("crate: appears under a forest tree in the morning, gives one item", function()
	local server, svc = start(0.02, { [1] = "Killer", [2] = "Villager", [3] = "Doctor", [BOT_A] = "Wolf" })
	server.Config.Crate.MorningSpawnChance = 1
	waitFor(server, "Day", 1)
	local crate = server.game.Workspace.Items:FindFirstChild("Crate")
	expect(crate ~= nil and crate:HasTag("Crate")).toBe(true)
	local spot = crate.PrimaryPart.CFrame.Position
	expect(flat(spot) > server.Config.Map.FenceRadius).toBe(true) -- in the forest

	-- Only guns in this crate: the Killer may not take one, so it stays on the ground.
	server.Config.Crate.Loot = { { Item = "Gun", Weight = 1 } }
	place(svc, 1, spot)
	server.trigger(crate.PrimaryPart.OpenPrompt, 1)
	expect(crate.Parent).toBeNil()
	expect(svc.Inventory.Count(1, "Gun")).toBe(0)
	expect(#worldItems(server)).toBe(1)

	-- Next morning another crate; this one gives Bob its item directly.
	server.Config.Crate.Loot = { { Item = "Cross", Weight = 1 } }
	waitFor(server, "Day", 2)
	local second = server.game.Workspace.Items:FindFirstChild("Crate")
	place(svc, 2, second.PrimaryPart.CFrame.Position)
	server.trigger(second.PrimaryPart.OpenPrompt, 2)
	expect(svc.Inventory.Count(2, "Cross")).toBe(1)
	svc.Match.Exile(1) -- the Killer
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)
