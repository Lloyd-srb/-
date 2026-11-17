--[[
	Sounds (GDD §6.5): world sounds reach only the players close enough to
	hear them (a far-away client must not learn where the wolf attacks), a
	hidden player hears from their hiding spot, and sounds without an ID yet
	are not sent at all.
]]

local function start(roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = { TimerScale = 0.02, MinPlayers = 3, FillWithBots = true, UnlockAllRoles = false, ForceRoles = roles },
	})
	local folder = server.game.ServerScriptService.Services
	local svc = setmetatable({}, {
		__index = function(_, name)
			return server.require(folder[name .. "Service"])
		end,
	})
	return server, svc
end

local function soundsFor(server, id)
	local keys = {}
	for _, args in server.sent("Sound", id) do
		table.insert(keys, args[1].Key)
	end
	return keys
end

local function heard(server, id, key)
	return table.find(soundsFor(server, id), key) ~= nil
end

test("audio: a door hit is heard near the door only; a hidden player hears it from the hiding spot", function()
	local server, svc = start({ [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	server.Config.Sounds.DoorHit = 11
	server.Config.Sounds.DoorBreak = 12
	server.waitFor("night", function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Night"
	end, 10)
	local houseId = server.last("HouseAssigned", 2)[1]
	local house = server.game.Workspace.Map.Houses[string.format("House%02d", houseId)]
	-- Bob hides under his bed: his body is parked far away.
	server.trigger(house.Bed.Frame.PromptAnchor.HidePrompt, 2)
	expect(svc.Hiding.IsHidden(2)).toBe(true)
	svc.Match.RootOf(1).CFrame = CFrame.new(house.Door.CFrame.Position + Vector3.new(0, 0, 6))
	svc.Match.RootOf(3).CFrame = CFrame.new(900, 3, 900) -- far away

	svc.House.DamageDoor(houseId, 1)
	expect(heard(server, 1, "DoorHit")).toBe(true) -- the wolf at the door
	expect(heard(server, 2, "DoorHit")).toBe(true) -- Bob, from under his bed
	expect(heard(server, 3, "DoorHit")).toBe(false) -- Cara is too far
	expect(server.last("Sound", "all")).toBeNil() -- never sent to everyone

	svc.House.DamageDoor(houseId, 1000)
	expect(heard(server, 2, "DoorBreak")).toBe(true)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("audio: a sound without an ID yet is not sent; the night howl reaches everyone", function()
	local server = start({ [1] = "Wolf", [2] = "Villager", [3] = "Doctor" })
	server.Config.Sounds.WolfHowl = 21
	server.Config.Sounds.DoorOpen = 0
	server.waitFor("night", function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Night"
	end, 10)
	task.wait(0.05)
	expect(server.last("Sound", "all")[1].Key).toBe("WolfHowl")
	expect(server.last("Sound", "all")[1].At).toBeNil()
	-- Bob opens his own door: DoorOpen has no ID, so nothing is sent.
	local houseId = server.last("HouseAssigned", 2)[1]
	local house = server.game.Workspace.Map.Houses[string.format("House%02d", houseId)]
	server.trigger(house.Door.PromptAnchor.OpenPrompt, 2)
	expect(heard(server, 2, "DoorOpen")).toBe(false)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("audio: every sound key the code uses is in Config.Sounds", function()
	local Config = require(game.ReplicatedStorage.Shared.Config)
	local used = 0
	for _, instance in game:GetDescendants() do
		if instance:IsA("LuaSourceContainer") then
			for _, pattern in {
				'AudioService%.At%("(%w+)"',
				'AudioService%.To%([%w_]+, "(%w+)"',
				'AudioService%.All%("(%w+)"',
				'Audio%.play%("(%w+)"',
				'Audio%.loop%("(%w+)"',
			} do
				for key in instance.Source:gmatch(pattern) do
					used += 1
					if Config.Sounds[key] == nil then
						error(`{instance.Name} plays unknown sound "{key}"`)
					end
				end
			end
			-- Lookup tables of sound names (EFFECT_SOUNDS, STEP_SOUNDS).
			for block in instance.Source:gmatch("_SOUNDS: [^\n]-= (%b{})") do
				for key in block:gmatch('"(%w+)"') do
					used += 1
					if Config.Sounds[key] == nil then
						error(`{instance.Name} plays unknown sound "{key}"`)
					end
				end
			end
		end
	end
	expect(used >= 15).toBe(true)
	for key in Config.Audio.Radius do
		expect(Config.Sounds[key] ~= nil).toBe(true)
	end
	for key in Config.Audio.Volume do
		expect(Config.Sounds[key] ~= nil).toBe(true)
	end
end)
