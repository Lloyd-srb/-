--[[
	Owner's roles of 18 Nov 2026 (second batch) on the fake engine:
	  - Police: handcuffs by day -> locked in their house the coming night
	    (not the main wolf; works on the pup)
	  - Detective: magnifying glass each morning -> white (stayed home) or
	    yellow (was out) aura for 10 s, only for the Detective
	  - Fire Maniac: oil on every house (1 by day + 1 by night) -> wins the
	    next morning
	  - Lovers: each always sees the other with a white aura
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
	svc.Match.RootOf(id).CFrame = CFrame.new(position) -- looking along -Z
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

local function door(server, houseId)
	return server.game.Workspace.Map.Houses[string.format("House%02d", houseId)].Door
end

local function highlights(server, id, kind)
	local list = {}
	for _, args in server.sent("Highlight", id) do
		if args[1].Kind == kind then
			table.insert(list, args[1])
		end
	end
	return list
end

--------------------------------------------------------------------------------

test("Police: handcuffs by day lock someone in tonight; once a day; nothing on the wolf; works on the pup", function()
	local server, svc = start(0.02, { [1] = "Police", [2] = "Villager", [3] = "Sheriff", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	expect(itemOf(svc, 1, "Handcuffs") ~= nil).toBe(true)
	expect(svc.Inventory.IsRoleItem("Handcuffs")).toBe(true)

	place(svc, 1, Vector3.new(40, 3, 40))
	place(svc, 2, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Handcuffs")
	expect(lastEffect(server, 1)).toEqual({ Kind = "Cuffed", Name = "Bob" })
	expect(svc.House.IsCuffed(2)).toBe(true)
	expect(#server.sent("Effect", 2)).toBe(0) -- Bob is not told

	-- Once a day.
	place(svc, 3, Vector3.new(40, 3, 36))
	place(svc, 2, Vector3.new(200, 3, 200))
	useItem(server, svc, 1, "Handcuffs")
	expect(lastEffect(server, 1).Kind).toBe("UsedToday")
	expect(svc.House.IsCuffed(3)).toBe(false)

	-- Night: Bob cannot open his door; Cara can open hers.
	waitFor(server, "Night", 1)
	expect(svc.House.IsLockedTonight(2)).toBe(true)
	local bobHouse = svc.House.Assigned[2]
	local bobDoor = door(server, bobHouse)
	place(svc, 2, bobDoor.CFrame.Position)
	server.trigger(bobDoor.PromptAnchor.OpenPrompt, 2)
	expect(bobDoor:GetAttribute("State")).toBe("Closed")
	expect(lastEffect(server, 2).Kind).toBe("LockedIn")
	local caraDoor = door(server, svc.House.Assigned[3])
	place(svc, 3, caraDoor.CFrame.Position)
	server.trigger(caraDoor.PromptAnchor.OpenPrompt, 3)
	expect(caraDoor:GetAttribute("State")).toBe("Open")
	useItem(server, svc, 1, "Handcuffs") -- not at night
	expect(lastEffect(server, 1).Kind).toBe("DayOnly")

	-- The wolf kills a bot: it becomes the pup.
	expect(svc.Combat.Damage(BOT_B, 100, "Wolf", BOT_A)).toBe("Converted")

	-- Day 2: cuff the wolf (looks the same, does nothing) ... day 3: cuff the pup.
	waitFor(server, "Day", 2)
	expect(svc.House.IsLockedTonight(2)).toBe(false) -- one night only
	place(svc, 1, Vector3.new(40, 3, 40))
	place(svc, BOT_A, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Handcuffs")
	expect(lastEffect(server, 1).Kind).toBe("Cuffed")
	waitFor(server, "Night", 2)
	expect(svc.House.IsLockedTonight(BOT_A)).toBe(false)

	waitFor(server, "Day", 3)
	place(svc, 1, Vector3.new(40, 3, 40))
	place(svc, BOT_B, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Handcuffs")
	waitFor(server, "Night", 3)
	expect(svc.House.IsLockedTonight(BOT_B)).toBe(true)
	-- The pup spends the night inside its house and cannot break its own door.
	local pupHouse = svc.House.Assigned[BOT_B]
	local pupRoot = svc.Match.RootOf(BOT_B)
	expect(svc.House.HouseAt(pupRoot.CFrame.Position)).toBe(pupHouse)
	local pupDoor = door(server, pupHouse)
	local hp = pupDoor:GetAttribute("HP")
	expect(svc.House.HitDoorNear(pupDoor.CFrame.Position, Vector3.new(0, 0, -1), 10, 10, BOT_B) ~= pupHouse).toBe(true)
	expect(pupDoor:GetAttribute("HP")).toBe(hp)

	svc.Match.Exile(BOT_B)
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

test("Detective: each morning, white = stayed home, yellow = was out; 10 s; only the Detective sees it", function()
	local server, svc = start(0.02, { [1] = "Detective", [2] = "Villager", [3] = "Killer", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	expect(itemOf(svc, 1, "Magnifier") ~= nil).toBe(true)

	-- Day 1: no night yet, nothing used.
	place(svc, 1, Vector3.new(40, 3, 40))
	place(svc, 2, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Magnifier")
	expect(lastEffect(server, 1).Kind).toBe("NoNightYet")

	-- Night 1: Bob stays in, Cara (the Killer) walks out of her house.
	waitFor(server, "Night", 1)
	local caraDoor = door(server, svc.House.Assigned[3])
	place(svc, 3, caraDoor.CFrame.Position)
	server.trigger(caraDoor.PromptAnchor.OpenPrompt, 3)
	place(svc, 3, Vector3.new(0, 3, 0)) -- the plaza
	task.wait(server.Config.Abilities.Detective.ScanInterval + 0.3) -- the night is checked every second

	waitFor(server, "Day", 2)
	expect(svc.House.WasOutLastNight(2)).toBe(false)
	expect(svc.House.WasOutLastNight(3)).toBe(true)
	expect(svc.House.WasOutLastNight(BOT_A)).toBe(true) -- the wolf hunts outside

	place(svc, 1, Vector3.new(40, 3, 40))
	place(svc, 2, Vector3.new(40, 3, 36))
	useItem(server, svc, 1, "Magnifier")
	expect(lastEffect(server, 1)).toEqual({ Kind = "StayedHome", Name = "Bob" })
	local white = highlights(server, 1, "StayedHome")
	expect(#white).toBe(1)
	expect(white[1].Ids).toEqual({ 2 })
	expect(white[1].Duration).toBe(10)
	expect(#highlights(server, 2, "StayedHome")).toBe(0) -- nobody else

	-- Once a morning; the next morning again (same person allowed).
	place(svc, 3, Vector3.new(40, 3, 36))
	place(svc, 2, Vector3.new(200, 3, 200))
	useItem(server, svc, 1, "Magnifier")
	expect(lastEffect(server, 1).Kind).toBe("UsedToday")
	expect(#highlights(server, 1, "WasOut")).toBe(0)

	svc.Match.Exile(3)
	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)

test("Fire Maniac: oil next to any wall, 1 by day + 1 by night, all houses = win the next morning", function()
	local server, svc = start(0.02, { [1] = "FireManiac", [2] = "Villager", [3] = "Sheriff", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	expect(itemOf(svc, 1, "OilCan") ~= nil).toBe(true)
	local Arson = server.require(server.game.ServerScriptService.Services.ArsonService)
	local houses = svc.House.Count()
	expect(houses).toBe(12)

	local function promptsOf(houseId)
		local list = {}
		for _, prompt in server.game.Workspace:GetDescendants() do
			if prompt:IsA("ProximityPrompt") and prompt.Name == "OilPrompt" and prompt:GetAttribute("HouseId") == houseId then
				table.insert(list, prompt)
			end
		end
		return list
	end
	local function pour(id, houseId, which)
		local list = promptsOf(houseId)
		local prompt = list[which or 1]
		svc.Match.RootOf(id).CFrame = CFrame.new((prompt.Parent.Parent.CFrame * prompt.Parent.CFrame).Position)
		server.trigger(prompt, id)
		return prompt
	end

	-- Prompts all round every house, close to the wall, only for the Fire Maniac.
	local first = promptsOf(1)
	expect(#first >= 8).toBe(true)
	expect(first[1]:GetAttribute("Audience")).toBe("Role:FireManiac")
	expect(first[1].MaxActivationDistance).toBe(server.Config.Abilities.FireManiac.WallReach)
	local zone = svc.House.ZoneOf(1)
	for _, prompt in first do
		local offset = zone.CFrame:PointToObjectSpace((prompt.Parent.Parent.CFrame * prompt.Parent.CFrame).Position)
		local outsideX = math.abs(offset.X) > zone.Size.X / 2
		local outsideZ = math.abs(offset.Z) > zone.Size.Z / 2
		expect(outsideX or outsideZ).toBe(true) -- on the outside of a wall
	end

	-- Someone else cannot pour; too far does nothing.
	pour(2, 1)
	expect(Arson.IsOiled(1)).toBe(false)
	local far = promptsOf(1)[1]
	place(svc, 1, Vector3.new(0, 3, 0))
	server.trigger(far, 1)
	expect(Arson.IsOiled(1)).toBe(false)

	-- Day 1: one house (from the back wall), then no more today.
	pour(1, 1, #first)
	expect(Arson.IsOiled(1)).toBe(true)
	expect(lastEffect(server, 1).Kind).toBe("OilPoured")
	expect(promptsOf(1)[1].Enabled).toBe(false) -- that house is done
	pour(1, 2)
	expect(Arson.IsOiled(2)).toBe(false)
	expect(lastEffect(server, 1).Kind).toBe("OilUsed")

	-- Night 1: one more.
	waitFor(server, "Night", 1)
	pour(1, 2)
	expect(Arson.IsOiled(2)).toBe(true)
	expect(Arson.OiledCount()).toBe(2)

	-- Skip ahead (as if over many days): allow more pours tonight, oil the rest.
	server.Config.Abilities.FireManiac.UsesPerPhase = 99
	pour(1, 2) -- an oiled house: its prompts are gone, nothing happens
	expect(Arson.OiledCount()).toBe(2)
	for houseId = 3, houses do
		pour(1, houseId, 2)
	end
	expect(Arson.OiledCount()).toBe(houses)
	expect(svc.Match.Winner).toBeNil() -- not yet: the next morning
	server.waitFor("fire maniac wins (next morning)", function()
		return svc.Match.Winner ~= nil
	end, 15)
	local round = server.require(server.game.ServerScriptService.Services.RoundService)
	expect(round.State.Day).toBe(2) -- it happened at the start of day 2
	expect(svc.Match.Winner).toBe("FireManiac")
	expect(server.last("GameOver", "all")[1].EndingKey).toBe("Ending.FireManiac")
	server.waitForPhase("GameOver", 10)
	local rows = server.last("Scoreboard", "all")
	if rows then
		for _, row in rows[1].Rows do
			expect(row.Won).toBe(row.Id == 1)
		end
	end
end)

test("Lovers: each sees the other (white aura) all game; nobody else does", function()
	local server, svc = start(0.02, { [1] = "Lover", [2] = "Villager", [3] = "Sheriff", [BOT_A] = "Wolf" })
	waitFor(server, "Day", 1)
	-- Only player 1 was dealt Lover: a would-be Villager became the partner.
	local lovers = {}
	for _, member in svc.Match.Roster.Members do
		if member.Role == "Lover" then
			table.insert(lovers, member.Id)
		end
	end
	expect(#lovers).toBe(2)
	expect(table.find(lovers, 1) ~= nil).toBe(true)
	local partner = if lovers[1] == 1 then lovers[2] else lovers[1]
	expect(svc.Match.Roster.Members[partner].Faction).toBe("Village")

	local seen = highlights(server, 1, "Lover")
	expect(#seen >= 1).toBe(true)
	expect(seen[#seen].Ids).toEqual({ partner })
	expect(seen[#seen].Duration).toBeNil() -- always on
	if partner > 0 then
		expect(highlights(server, partner, "Lover")[1].Ids).toEqual({ 1 })
	end
	for _, other in { 2, 3 } do
		if other ~= partner then
			expect(#highlights(server, other, "Lover")).toBe(0)
		end
	end
	-- Resent every phase (bodies change at night).
	local before = #highlights(server, 1, "Lover")
	waitFor(server, "Night", 1)
	expect(#highlights(server, 1, "Lover") > before).toBe(true)

	svc.Match.Exile(BOT_A)
	server.waitForPhase("GameOver", 10)
end)
