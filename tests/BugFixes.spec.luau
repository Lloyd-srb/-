--[[
	Regression tests for bugs found while reviewing milestones 1-4.
	Each test names the bug it guards against.
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

local function house(server, houseId)
	return server.game.Workspace.Map.Houses[string.format("House%02d", houseId)]
end

-- A point in a house's own frame (x right, z towards the back, y up from the floor).
local function housePoint(model, x, y, z)
	return (model.Floor.CFrame * CFrame.new(x, y, z)).Position
end

test("bug: hide / search worked through the back wall (prompts ignore walls)", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Night", 1)
	local bobHouse = house(server, server.last("HouseAssigned", 2)[1])
	local caraHouse = house(server, server.last("HouseAssigned", 3)[1])
	local bed = bobHouse.Bed.Frame.PromptAnchor
	server.trigger(bed.HidePrompt, 2)
	expect(svc.Hiding.IsHidden(2)).toBe(true)
	expect(server.player(2).ReplicationFocus).toBe(bed.Parent) -- the spot stays loaded for the hider

	-- The wolf stands outside, right behind the back wall next to the bed.
	local outside = housePoint(bobHouse, -6, 3, 11)
	expect(svc.House.HouseAt(outside)).toBeNil()
	expect((outside - bed.Parent.CFrame.Position).Magnitude < 14).toBe(true) -- close enough for the old check
	svc.Match.RootOf(1).CFrame = CFrame.new(outside)
	server.trigger(bed.SearchPrompt, 1)
	expect(svc.Hiding.IsHidden(2)).toBe(true) -- not found from outside

	-- From inside the room the search works (after breaking in: the door is
	-- the only way into a shut house).
	svc.House.DamageDoor(bobHouse:GetAttribute("HouseId"), 1000)
	svc.Match.RootOf(1).CFrame = CFrame.new(housePoint(bobHouse, -2, 3, 2))
	server.trigger(bed.SearchPrompt, 1)
	expect(svc.Hiding.IsHidden(2)).toBe(false)
	expect(server.last("HideChanged", 2)[1]).toBeNil() -- the hider is told they are out

	-- A villager outside cannot slip into a bed through the wall either.
	local caraBed = caraHouse.Bed.Frame.PromptAnchor
	svc.Match.RootOf(3).CFrame = CFrame.new(housePoint(caraHouse, -6, 3, 11))
	server.trigger(caraBed.HidePrompt, 3)
	expect(svc.Hiding.IsHidden(3)).toBe(false)

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: a dead wolf's body turned back into a person in the morning (revealing them)", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Killer", [3] = "Doctor" })
	waitFor(server, "Night", 1)
	svc.Combat.Damage(1, 100, "Killer", 2)
	expect(svc.Match.Roster.Members[1].Alive).toBe(false)
	waitFor(server, "Day", 2)
	local corpse = svc.Match.BodyOf(1)
	expect(corpse:FindFirstChild("WolfShell") ~= nil).toBe(true)
	expect(corpse:GetAttribute("Form")).toBe("Wolf")
	server.removePlayer(2)
	server.removePlayer(3)
end)

test("bug: resetting left a living player with no body forever (and must not heal)", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Day", 1)
	expect(server.humanoid(2).NameOcclusion).toBe(Enum.NameOcclusion.OccludeAll) -- no names through walls
	expect(svc.Combat.Damage(2, 50, "Pup", nil)).toBe("Hurt")
	local before = server.player(2).Character
	svc.Match.RootOf(2).CFrame = CFrame.new(40, 3, 10)

	server.killHumanoid(2)
	local after = server.player(2).Character
	expect(after ~= nil and after ~= before).toBe(true)
	expect(svc.Match.Roster.Members[2].Alive).toBe(true)
	expect((svc.Match.RootOf(2).CFrame.Position - Vector3.new(40, 5, 10)).Magnitude < 0.01).toBe(true)
	expect(svc.Combat.Health(2)).toBe(50) -- still hurt
	expect(server.humanoid(2).Health).toBe(50)
	expect(after:HasTag("MemberBody")).toBe(true)

	-- A corpse's humanoid dying is not a reset.
	svc.Combat.Damage(3, 100, "Killer", nil)
	local corpse = svc.Match.BodyOf(3)
	server.killHumanoid(3)
	expect(svc.Match.BodyOf(3)).toBe(corpse)
	expect(svc.Match.Roster.Members[3].Alive).toBe(false)

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: instance streaming unloaded the house around a hiding player", function()
	-- Every Roblox place already has this object under TextChatService.
	Instance.new("ChannelTabsConfiguration").Parent = game:GetService("TextChatService")
	runBuilder("build/BuildSettings.luau")
	expect(workspace.StreamingEnabled).toBe(false)
	local TextChatService = game:GetService("TextChatService")
	expect(TextChatService.CreateDefaultTextChannels).toBe(false) -- no channel where ghosts reach the living
	expect(TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration").Enabled).toBe(true)
	expect(game:GetService("Players").CharacterAutoLoads).toBe(false)
end)

--------------------------------------------------------------------------------
-- Found in the code review of 17 Nov 2026
--------------------------------------------------------------------------------

local function toolIds(server, playerId)
	local ids = {}
	local backpack = server.player(playerId):FindFirstChildOfClass("Backpack")
	for _, child in (if backpack then backpack:GetChildren() else {}) do
		if child.ClassName == "Tool" then
			table.insert(ids, child:GetAttribute("ItemId"))
		end
	end
	table.sort(ids)
	return ids
end

test("bug: items vanished from the hotbar after a respawn in place", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Day", 1)
	local apple = svc.Inventory.Give(2, "Apple")
	local shovel = svc.Inventory.Give(2, "Shovel")
	expect(#toolIds(server, 2)).toBe(2)

	server.killHumanoid(2) -- a new body comes with a new, empty Backpack
	expect(svc.Match.Roster.Members[2].Alive).toBe(true)
	local expected = { apple.Id, shovel.Id }
	table.sort(expected)
	expect(toolIds(server, 2)).toEqual(expected)

	-- Still usable afterwards.
	server.fireServer("ItemUse", 2, apple.Id)
	expect(svc.Inventory.Count(2, "Apple")).toBe(0)

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: a ghost's hat that loads late floated around visible to the living", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Killer" })
	waitFor(server, "Day", 1)
	svc.Combat.Damage(2, 100, "Killer", 3)
	server.waitFor("ghost body", function()
		local character = server.player(2).Character
		return character and character:HasTag("Ghost")
	end, 5)
	local ghost = server.player(2).Character

	local hat = Instance.new("Accessory")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Parent = hat
	server.addDescendant(ghost, hat)
	expect(handle.Transparency).toBe(1)
	expect(handle.CanQuery).toBe(false) -- cannot stop a shot either
	expect(handle.CollisionGroup).toBe("Ghosts")

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

--------------------------------------------------------------------------------
-- Found in the full audit of 17 Nov 2026
--------------------------------------------------------------------------------

test("bug: a cheater could walk through a wall into a shut house and kill the person inside", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Night", 1)
	local houseId = server.last("HouseAssigned", 2)[1]
	local inside = svc.Match.RootOf(2).CFrame.Position
	expect(svc.House.HouseAt(inside)).toBe(houseId)

	-- The wolf "appears" inside Bob's shut house (no broken door, nobody opened it).
	svc.Match.RootOf(1).CFrame = CFrame.new(inside + Vector3.new(0, 0, 2)) * CFrame.Angles(0, math.pi, 0)
	expect(svc.House.IsTrespassing(1)).toBe(true)
	expect(svc.House.IsTrespassing(2)).toBe(false) -- Bob lives here tonight
	server.fireServer("WolfAttack", 1)
	task.wait(0.05)
	expect(svc.Match.Roster.Members[2].Alive).toBe(true)

	-- Once the door is broken, getting in is fair.
	svc.House.DamageDoor(houseId, 1000)
	expect(svc.House.IsTrespassing(1)).toBe(false)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: someone who slipped into another house at night stayed locked in all day", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Night", 1)
	-- Cara has a house tonight; pretend she was in the forest at nightfall
	-- (no house) and then walked in through Bob's broken door.
	local houseId = server.last("HouseAssigned", 2)[1]
	svc.House.Assigned[3] = nil
	svc.House.DamageDoor(houseId, 1000)
	svc.Match.RootOf(3).CFrame = svc.Match.RootOf(2).CFrame + Vector3.new(2, 0, 0)
	expect(svc.House.HouseAt(svc.Match.RootOf(3).CFrame.Position)).toBe(houseId)

	waitFor(server, "Day", 2)
	expect(svc.House.HouseAt(svc.Match.RootOf(3).CFrame.Position)).toBeNil() -- out in front of it
	expect(svc.House.HouseAt(svc.Match.RootOf(2).CFrame.Position)).toBeNil()
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: health bars over heads told everyone who the pup had bitten", function()
	local server = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Day", 1)
	expect(server.humanoid(2).HealthDisplayType).toBe(Enum.HumanoidHealthDisplayType.AlwaysOff)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: a flashlight left on shone out of the werewolf (giving away who it is)", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Day", 1)
	local item = svc.Inventory.Give(1, "Flashlight")
	server.fireServer("ItemUse", 1, item.Id)
	task.wait(0.05)
	local light = server.player(1).Character:FindFirstChild("Flashlight", true)
	expect(light.Enabled).toBe(true)
	waitFor(server, "Night", 1)
	expect(svc.Wolf.IsTransformed(1)).toBe(true)
	expect(light.Enabled).toBe(false)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("bug: the meeting bell could be rung from anywhere on the map", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	waitFor(server, "Day", 2)
	local bellPart = server.game.Workspace.Map.Plaza.MeetingTable.Bell
	local prompt = bellPart.PromptAnchor.CallMeeting
	server.waitFor("bell to unlock", function()
		return prompt.Enabled
	end, 10)
	svc.Match.RootOf(2).CFrame = CFrame.new(300, 3, 300) -- far away
	server.trigger(prompt, 2)
	task.wait(0.05)
	expect(server.phase()).toBe("Day")
	svc.Match.RootOf(2).CFrame = CFrame.new(bellPart.CFrame.Position + Vector3.new(0, 0, 4))
	server.trigger(prompt, 2)
	server.waitForPhase("MeetingCountdown", 3)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("remotes: a client spamming an intent is cut off after its rate limit", function()
	local server = startServer({ Players = { { Id = 1, Name = "Ann" } }, Debug = { MinPlayers = 99 } })
	local Net = server.require(server.game.ServerStorage.ServerShared.Net)
	local handled = 0
	-- A lobby intent nobody listens to on this server (one listener only).
	Net.on("StartRequest", function()
		handled += 1
	end, 5, 10)
	for _ = 1, 40 do
		server.fireServer("StartRequest", 1)
	end
	task.wait(0.05)
	expect(handled).toBe(5)
end)
