--[[
	Skins bought in the lobby show up in the match (GDD §13 Shop): the
	werewolf's colours, the gun's shot, the Killer's slash. Cosmetic only.
]]

local function start(roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = { TimerScale = 0.02, MinPlayers = 3, FillWithBots = true, UnlockAllRoles = false, ForceRoles = roles },
	})
	local Profiles = server.require(server.game.ServerStorage.ServerShared.Profiles)
	for id = 1, 3 do
		server.waitFor("profile " .. id, function()
			return Profiles.Get(server.player(id)) ~= nil
		end, 3)
	end
	return server, Profiles
end

local function wear(server, Profiles, id, slot, skinId)
	Profiles.Update(server.player(id), function(data)
		data.Skins[skinId] = true
		data.Equipped[slot] = skinId
	end)
end

test("skins: the werewolf wears its skin's colours; the shot has the gun skin's colour", function()
	local server, Profiles = start({ [1] = "Wolf", [2] = "Sheriff", [3] = "Killer" })
	wear(server, Profiles, 1, "Wolf", "WolfShadow")
	wear(server, Profiles, 2, "Gun", "GunGold")
	local Config = server.Config

	server.waitFor("night", function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Night"
	end, 10)
	local shell = server.player(1).Character:FindFirstChild("WolfShell")
	expect(shell ~= nil).toBe(true)
	local painted = 0
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Paint") == "Fur" then
			expect(part.Color).toEqual(Config.Skins.WolfShadow.Paint.Fur)
			painted += 1
		end
	end
	expect(painted > 0).toBe(true)

	server.fireServer("AbilityUse", 2, "Shoot", Vector3.new(1, 0, 0))
	task.wait(0.05)
	local shot = server.last("Effect", "all")[1]
	expect(shot.Kind).toBe("Shot")
	expect(shot.Color).toEqual(Config.Skins.GunGold.Color)

	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("skins: without one, the default look", function()
	local server = start({ [1] = "Wolf", [2] = "Sheriff", [3] = "Doctor" })
	server.waitFor("day", function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Day"
	end, 10)
	server.fireServer("AbilityUse", 2, "Shoot", Vector3.new(1, 0, 0))
	task.wait(0.05)
	expect(server.last("Effect", "all")[1].Color).toEqual(server.Config.DefaultLook.Gun)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)

test("skins: the Killer's slash has the knife skin's colour; only people close by see it", function()
	local server, Profiles = start({ [1] = "Wolf", [2] = "Villager", [3] = "Killer" })
	wear(server, Profiles, 3, "Knife", "KnifeGold")
	server.waitFor("day", function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == "Day"
	end, 10)
	server.root(3).CFrame = CFrame.new(40, 3, 0)
	server.root(2).CFrame = CFrame.new(40, 3, -4) -- in front of the Killer
	server.root(1).CFrame = CFrame.new(400, 3, 0) -- far away
	server.fireServer("AbilityUse", 3, "Stab")
	task.wait(0.05)
	local slash = server.last("Effect", 3)[1]
	expect(slash.Kind).toBe("Slash")
	expect(slash.Color).toEqual(server.Config.Skins.KnifeGold.Color)
	local farAway = server.last("Effect", 1)
	expect(farAway == nil or farAway[1].Kind ~= "Slash").toBe(true)
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
end)
