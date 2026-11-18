--[[
	The Lobby's shop, wardrobe, Daily Spin and codes on the fake engine, and a
	reward travelling Lobby -> Match -> Lobby through the shared DataStore.
]]

local function open(count, experience)
	local list = {}
	for id = 1, count do
		table.insert(list, { Id = id, Name = "P" .. id })
	end
	local server = startLobby({ Players = list, Experience = experience })
	local shared = server.game.ServerStorage.ServerShared
	server.Profiles = server.require(shared.Profiles)
	server.Config.Data.LoadRetryDelay = 0.05
	return server
end

local function view(server, id)
	server.waitFor("profile view " .. id, function()
		return server.last("ProfileView", id) ~= nil
	end, 3)
	task.wait(0.05) -- let queued updates arrive
	return server.last("ProfileView", id)[1]
end

local function change(server, id, fn)
	server.Profiles.Update(server.player(id), fn)
end

local function shopResult(server, id)
	task.wait(0.1)
	return server.last("ShopResult", id)[1]
end

test("lobby shop: wallet sent; a role for coins; level gate; Robux opens Roblox's window", function()
	local server = open(1)
	local first = view(server, 1)
	expect(first.Coins).toBe(0)
	expect(first.Level).toBe(1)
	change(server, 1, function(data)
		data.Coins = 5300
	end)
	server.fireServer("ShopBuy", 1, "Role", "Chief", "Coins")
	expect(shopResult(server, 1).Reason).toBe("Level")
	change(server, 1, function(data)
		data.Exp = 1200 -- level 5
	end)
	server.fireServer("ShopBuy", 1, "Role", "Chief", "Coins")
	local result = shopResult(server, 1)
	expect(result.Ok).toBe(true)
	local now = view(server, 1)
	expect(now.Coins).toBe(300)
	expect(now.Roles.Chief).toBe(true)

	-- Robux: no product id yet = refused; with one, Roblox's window opens.
	server.fireServer("ShopBuy", 1, "Role", "Bodyguard", "Robux")
	expect(shopResult(server, 1).Reason).toBe("NoProduct")
	server.Config.Products.DevProducts.RoleBodyguard = 4321
	server.fireServer("ShopBuy", 1, "Role", "Bodyguard", "Robux")
	task.wait(0.1)
	expect(server.purchasePrompts()[1].ProductId).toBe(4321)
	expect(server.processReceipt(1, 4321, "buy-1")).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
	local granted = shopResult(server, 1)
	expect(granted.Ok and granted.Robux).toBe(true)
	expect(view(server, 1).Roles.Bodyguard).toBe(true)

	-- Bad requests do nothing.
	server.fireServer("ShopBuy", 1, "Role", { "Chief" }, "Coins")
	server.fireServer("ShopBuy", 1, "Role", "Seer", "Gold")
	expect(shopResult(server, 1).Reason).toBe("WrongCurrency")
end)

test("lobby wardrobe: equip owned things only; the title shows over the head", function()
	local server = open(1)
	view(server, 1)
	server.fireServer("Equip", 1, "Title", "PassFree")
	expect(shopResult(server, 1).Reason).toBe("NotOwned")
	change(server, 1, function(data)
		data.Titles.PassFree = true
		data.Skins.WolfShadow = true
	end)
	server.fireServer("Equip", 1, "Title", "PassFree")
	task.wait(0.1)
	expect(server.player(1).Character:GetAttribute("Title")).toBe("PassFree")
	server.fireServer("Equip", 1, "Wolf", "WolfShadow")
	expect(view(server, 1).Equipped.Wolf).toBe("WolfShadow")
	server.fireServer("Equip", 1, "Title", "")
	task.wait(0.1)
	expect(server.player(1).Character:GetAttribute("Title")).toBeNil()
end)

test("lobby: one free Daily Spin a day; a code works once", function()
	local server = open(1)
	expect(view(server, 1).Spin.Free).toBe(true)
	server.fireServer("SpinRequest", 1)
	task.wait(0.1)
	expect(server.last("SpinResult", 1)[1].Ok).toBe(true)
	expect(view(server, 1).Spin.Free).toBe(false)
	server.fireServer("SpinRequest", 1)
	task.wait(0.1)
	expect(server.last("SpinResult", 1)[1].Ok).toBe(false)

	server.fireServer("CodeRedeem", 1, " wolfvillage ")
	task.wait(0.1)
	local answer = server.last("CodeResult", 1)[1]
	expect(answer.Ok).toBe(true)
	expect(answer.Rewards[1].Kind).toBe("Coins")
	server.fireServer("CodeRedeem", 1, "WOLFVILLAGE")
	task.wait(0.1)
	expect(server.last("CodeResult", 1)[1].Reason).toBe("Used")
end)

test("the code list is not where players can read it", function()
	local server = open(0)
	expect(server.game.ReplicatedStorage.Shared.Config:FindFirstChild("CodeList")).toBeNil()
	expect(server.game.ServerStorage.ServerShared:FindFirstChild("CodeList") ~= nil).toBe(true)
	expect(server.Config.Codes).toBeNil()
end)

test("a match reward is saved and back in the lobby (Lobby -> Match -> Lobby)", function()
	local lobby = open(1, "round-trip")
	view(lobby, 1)
	lobby.removePlayer(1) -- off to the match

	local match = startServer({ Players = {}, Experience = "round-trip", Debug = { Enabled = false } })
	match.Config.Data.LoadRetryDelay = 0.05
	local player = match.addPlayer(1, "P1")
	local profiles = match.require(match.game.ServerScriptService.Services.ProfileService)
	match.waitFor("match profile", function()
		return profiles.Get(player) ~= nil
	end, 3)
	profiles.Grant(player, { Coins = 120, Exp = 300, PassExp = 150, MasteryRole = "Doctor", MasteryPoints = 2 })
	match.removePlayer(1) -- back to the lobby

	lobby.addPlayer(1, "P1")
	lobby.waitFor("lobby profile again", function()
		local last = lobby.last("ProfileView", 1)
		return last and last[1].Coins == 120
	end, 3)
	local back = lobby.last("ProfileView", 1)[1]
	expect(back.Level).toBe(2)
	expect(back.Mastery.Doctor).toBe(2)
end)

test("codes: too many wrong guesses in a row = a short wait (no guessing codes by brute force)", function()
	local server = open(1)
	view(server, 1)
	server.Config.CodeMaxWrong = 3
	for index = 1, 3 do
		server.fireServer("CodeRedeem", 1, "GUESS" .. index)
		task.wait(0.05)
	end
	expect(server.last("CodeResult", 1)[1].Reason).toBe("Unknown")
	server.fireServer("CodeRedeem", 1, "WOLFVILLAGE") -- even a real code waits now
	task.wait(0.1)
	expect(server.last("CodeResult", 1)[1].Reason).toBe("TooMany")
end)

test("how to play: a new player has not read it; after Got it! it is remembered", function()
	local server = open(1)
	expect(view(server, 1).TutorialSeen).toBe(false)
	server.fireServer("TutorialDone", 1)
	task.wait(0.1)
	expect(view(server, 1).TutorialSeen).toBe(true)
end)
