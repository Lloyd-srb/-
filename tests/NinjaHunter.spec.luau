--[[
	Owner's roles of 24 Nov 2026 on the fake engine:
	  - Ninja: smoke bomb -> invisible 6 s (day and night), 20 s cooldown from
	    the press; takes every outline off; any action but knocking ends it
	  - Hunter: bear traps (max 3 on the ground, 50 s cooldown); whoever steps
	    on one (person or monster) is stunned 2 s and outlined red for the Hunter
]]

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
	task.wait(0.05)
end

local function lastEffect(server, id)
	local last = server.last("Effect", id)
	return last and last[1]
end

-- A visible body part (not the always-invisible root).
local function head(svc, id)
	for _, part in svc.Match.CharacterOf(id):GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			return part
		end
	end
	return svc.Match.CharacterOf(id):FindFirstChild("Head")
end

test("Ninja: smoke bomb hides for a while, takes outlines off, cooldown, any action shows them", function()
	local server, svc = start(0.02, { [1] = "Ninja", [2] = "Seer", [3] = "Villager", [-1004] = "Wolf" })
	local cfg = server.Config.Abilities.Ninja
	cfg.Duration = 0.6
	cfg.Cooldown = 0.8
	waitFor(server, "Day", 1)
	expect(itemOf(svc, 1, "SmokeBomb") ~= nil).toBe(true)
	expect(itemOf(svc, 2, "SmokeBomb")).toBeNil() -- a role item: only the Ninja
	-- (The fake character is only a root: give it a head with a face.)
	local part = Instance.new("Part")
	part.Name = "Head"
	part.Transparency = 0
	part.Parent = svc.Match.CharacterOf(1)
	local faceDecal = Instance.new("Decal")
	faceDecal.Parent = part
	local before = part.Transparency

	-- By day: gone, and every viewer is told to drop outlines on the Ninja.
	useItem(server, svc, 1, "SmokeBomb")
	local body = svc.Match.CharacterOf(1)
	expect(body:GetAttribute("Vanished")).toBe(true)
	expect(part.Transparency).toBe(1)
	expect(faceDecal.Transparency).toBe(1)
	expect(svc.Gear.IsSmoked(1)).toBe(true)
	expect(server.last("Unhighlight", "all")[1].Id).toBe(1)
	local tool = nil
	for _, child in server.player(1).Backpack:GetChildren() do
		if child:GetAttribute("Kind") == "SmokeBomb" then
			tool = child
		end
	end
	expect(type(tool:GetAttribute("ReadyAt"))).toBe("number")

	-- Cooldown: a second press does nothing yet.
	useItem(server, svc, 1, "SmokeBomb")
	expect(lastEffect(server, 1).Kind).toBe("Cooldown")

	-- Time up: back, as before.
	task.wait(cfg.Duration + 0.1)
	expect(body:GetAttribute("Vanished")).toBeNil()
	expect(part.Transparency).toBe(before)
	expect(faceDecal.Transparency).toBe(0)

	-- Any action (here: eating an apple) shows the Ninja at once.
	task.wait(0.2) -- (the cooldown is over)
	cfg.Cooldown = 0
	cfg.Duration = 30
	useItem(server, svc, 1, "SmokeBomb")
	expect(svc.Gear.IsSmoked(1)).toBe(true)
	svc.Inventory.Give(1, "Apple")
	useItem(server, svc, 1, "Apple")
	expect(svc.Gear.IsSmoked(1)).toBe(false)
	expect(part.Transparency).toBe(before)

	-- By night: the Seer's outline skips a Ninja in smoke.
	waitFor(server, "Night", 1)
	task.wait(0.1)
	place(svc, 1, Vector3.new(150, 3, 0))
	useItem(server, svc, 1, "SmokeBomb")
	expect(svc.Gear.IsSmoked(1)).toBe(true)
	-- Knocking on a door is not an action that shows the Ninja ...
	local houses = server.game.Workspace.Map.Houses
	local own = svc.House.Assigned[1]
	local other = if own == 1 then 2 else 1
	server.trigger(houses[string.format("House%02d", other)].Door.PromptAnchor.KnockPrompt, 1)
	expect(svc.Gear.IsSmoked(1)).toBe(true)
	-- ... (any other "hold E", e.g. opening a door, is: checked below)
	server.fireServer("AbilityUse", 2, "See")
	task.wait(0.05)
	local seen = server.last("Highlight", 2)[1]
	expect(seen.Kind).toBe("Seer")
	expect(table.find(seen.Ids, 1) ~= nil).toBe(true) -- like the monster: still outlined
	server.trigger(houses[string.format("House%02d", own)].Door.PromptAnchor.OpenPrompt, 1)
	expect(svc.Gear.IsSmoked(1)).toBe(false)
	svc.Match.Exile(-1004)
	server.waitForPhase("GameOver", 10)
end)

test("Hunter: up to 3 traps; whoever steps on one is stunned 2 s and outlined red for the Hunter", function()
	local server, svc = start(0.02, { [1] = "Hunter", [2] = "Villager", [3] = "Villager", [-1004] = "Wolf" })
	local cfg = server.Config.Abilities.Hunter
	cfg.Cooldown = 0.3
	waitFor(server, "Day", 1)
	expect(itemOf(svc, 1, "BearTrap") ~= nil).toBe(true)

	place(svc, 1, Vector3.new(150, 3, 0))
	useItem(server, svc, 1, "BearTrap")
	local traps = svc.Gear.TrapsOf(1)
	expect(#traps).toBe(1)
	expect(traps[1].Transparency).toBe(0) -- everyone sees it ([owner] 24 Nov 2026)
	expect(traps[1]:GetAttribute("OwnerId")).toBe(1)

	-- Cooldown, then the limit of 3.
	useItem(server, svc, 1, "BearTrap")
	expect(lastEffect(server, 1).Kind).toBe("Cooldown")
	task.wait(0.3)
	cfg.Cooldown = 0
	place(svc, 1, Vector3.new(170, 3, 0))
	useItem(server, svc, 1, "BearTrap")
	place(svc, 1, Vector3.new(190, 3, 0))
	useItem(server, svc, 1, "BearTrap")
	expect(#svc.Gear.TrapsOf(1)).toBe(3)
	place(svc, 1, Vector3.new(210, 3, 0))
	useItem(server, svc, 1, "BearTrap")
	expect(lastEffect(server, 1).Kind).toBe("TrapsFull")
	expect(#svc.Gear.TrapsOf(1)).toBe(3)

	-- The Hunter walks over their own trap: nothing.
	place(svc, 1, Vector3.new(150, 3, 0))
	task.wait(0.3)
	expect(#svc.Gear.TrapsOf(1)).toBe(3)
	place(svc, 1, Vector3.new(230, 3, 0))

	-- Bob steps on one: stunned, the Hunter sees him red, the trap is gone.
	place(svc, 2, Vector3.new(170, 3, 0))
	server.waitFor("trap snaps", function()
		return #svc.Gear.TrapsOf(1) == 2
	end, 2)
	expect(svc.Combat.IsStunned(2)).toBe(true)
	local seen = server.last("Highlight", 1)[1]
	expect(seen.Kind).toBe("Trapped")
	expect(seen.Ids).toEqual({ 2 })
	expect(seen.Duration).toBe(cfg.HighlightSeconds)
	expect(lastEffect(server, 2).Kind).toBe("Trapped")
	place(svc, 2, Vector3.new(260, 3, 0))
	task.wait(cfg.StunDuration + 0.2)
	expect(svc.Combat.IsStunned(2)).toBe(false)

	-- A monster steps on one at night: caught too (traps stay until stepped on).
	waitFor(server, "Night", 1)
	task.wait(0.1)
	place(svc, -1004, Vector3.new(190, 3, 0))
	server.waitFor("monster caught", function()
		return #svc.Gear.TrapsOf(1) == 1
	end, 2)
	expect(svc.Combat.IsStunned(-1004)).toBe(true)
	svc.Match.Exile(-1004)
	server.waitForPhase("GameOver", 10)
end)
