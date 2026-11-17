--[[
	Saved profiles (DataStore with session locking) and Robux receipts, on the
	fake engine. Each simulation has its own DataStores unless two share an
	"Experience" (like the Lobby and Match servers of one game).
]]

local STORE = "Profiles_v1"

local function boot(options)
	options = options or {}
	local server = startServer({
		Players = options.Players or {},
		Experience = options.Experience,
		Debug = { Enabled = false },
	})
	local shared = server.game.ServerStorage.ServerShared
	server.Profiles = server.require(shared.Profiles)
	server.Purchases = server.require(shared.Purchases)
	server.ProfileLogic = server.require(shared.Logic.ProfileLogic)
	server.Config.Data.LoadRetryDelay = 0.05
	server.Config.Data.MaxAttempts = 1
	return server
end

local function loaded(server, id)
	local player = server.player(id)
	server.waitFor("profile " .. id, function()
		return server.Profiles.Get(player) ~= nil
	end, 3)
	return server.Profiles.Get(player), player
end

local function addCoins(server, id, amount)
	server.Profiles.Update(server.player(id), function(data)
		data.Coins += amount
	end)
end

test("profiles: a new player starts fresh; leaving saves and lets go of the lock", function()
	local server = boot({ Players = { { Id = 1, Name = "Ann" } } })
	local data = loaded(server, 1)
	expect(data.Coins).toBe(0)
	expect(server.savedRecord(STORE, "Player_1").Session ~= nil).toBe(true) -- locked while here
	addCoins(server, 1, 70)
	server.removePlayer(1)
	server.waitFor("saved", function()
		local record = server.savedRecord(STORE, "Player_1")
		return record and record.Session == nil
	end, 3)
	expect(server.savedRecord(STORE, "Player_1").Data.Coins).toBe(70)
end)

test("profiles: the next server waits until the last one has let go (lobby -> match)", function()
	local lobby = boot({ Experience = "handoff", Players = { { Id = 5, Name = "Eve" } } })
	loaded(lobby, 5)
	addCoins(lobby, 5, 300)

	local match = boot({ Experience = "handoff" })
	match.addPlayer(5, "Eve")
	task.wait(0.3)
	expect(match.Profiles.Get(match.player(5))).toBeNil() -- still locked by the lobby

	lobby.removePlayer(5) -- the teleport: the lobby saves and lets go
	local data = loaded(match, 5)
	expect(data.Coins).toBe(300)
	expect(match.Profiles.IsTemporary(match.player(5))).toBe(false)
end)

test("profiles: a crashed server's lock goes stale; a server that lost its lock stops saving", function()
	local first = boot({ Experience = "steal" })
	first.setSavedRecord(STORE, "Player_7", {
		Data = { Coins = 40 },
		Session = { Job = "crashed-server", Place = 1, At = os.time() - 10000 },
	})
	first.addPlayer(7, "Gil")
	expect(loaded(first, 7).Coins).toBe(40) -- stale lock: taken at once

	-- A second server that cannot wait any longer takes the lock over.
	local second = boot({ Experience = "steal" })
	second.Config.Data.LoadTimeout = 0.2
	second.addPlayer(7, "Gil")
	loaded(second, 7)
	addCoins(second, 7, 5)
	expect(second.Profiles.SaveNow(second.player(7))).toBe(true)

	-- The first server must not overwrite it: it stops and sends the player off.
	addCoins(first, 7, 1000)
	expect(first.Profiles.SaveNow(first.player(7))).toBe(false)
	expect(first.kicked(7) ~= nil).toBe(true)
	expect(first.savedRecord(STORE, "Player_7").Data.Coins).toBe(45)
end)

test("profiles: broken saved data is cleaned up when loaded", function()
	local server = boot()
	server.setSavedRecord(STORE, "Player_9", {
		Data = { Coins = "lots", Exp = -50, Diamonds = 12.5, Roles = { Chief = true, Seer = "yes" }, Pass = { Exp = 400 } },
	})
	server.addPlayer(9, "Ivy")
	local data = loaded(server, 9)
	expect(data.Coins).toBe(0)
	expect(data.Exp).toBe(0)
	expect(data.Diamonds).toBe(12)
	expect(data.Roles).toEqual({ Chief = true })
	expect(data.Pass.Exp).toBe(400)
	expect(data.Pass.Premium).toBe(false)
	expect(data.Spin.LastFreeDay).toBe(-1)
end)

test("profiles: DataStore down = temporary profile, nothing saved, purchases wait", function()
	local server = boot()
	server.Config.Products.DevProducts.Coins500 = 111
	server.dataStoreDown(true)
	server.addPlayer(3, "Cid")
	local data, player = loaded(server, 3)
	expect(server.Profiles.IsTemporary(player)).toBe(true)
	data.Coins = 10
	expect(server.processReceipt(3, 111, "t1")).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
	expect(data.Coins).toBe(10)
	server.removePlayer(3)
	task.wait(0.1)
	expect(server.savedRecord(STORE, "Player_3")).toBeNil()
end)

test("profiles: server shutdown saves everyone and lets go", function()
	local server = boot({ Players = { { Id = 1, Name = "Ann" }, { Id = 2, Name = "Bo" } } })
	loaded(server, 1)
	loaded(server, 2)
	addCoins(server, 2, 9)
	server.close()
	expect(server.savedRecord(STORE, "Player_2").Data.Coins).toBe(9)
	expect(server.savedRecord(STORE, "Player_2").Session).toBeNil()
	expect(server.savedRecord(STORE, "Player_1").Session).toBeNil()
end)

--------------------------------------------------------------------------------
-- Robux receipts
--------------------------------------------------------------------------------

test("receipts: given once per purchase id, only answered 'granted' once saved", function()
	local server = boot({ Players = { { Id = 4, Name = "Dee" } } })
	local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local products = server.Config.Products.DevProducts
	products.Coins500 = 111
	products.RoleChief = 222
	local data = loaded(server, 4)

	expect(server.processReceipt(4, 111, "p1")).toBe(Granted)
	expect(data.Coins).toBe(500)
	expect(server.processReceipt(4, 111, "p1")).toBe(Granted) -- Roblox asked again
	expect(data.Coins).toBe(500)
	expect(server.savedRecord(STORE, "Player_4").Data.Coins).toBe(500)

	-- The save fails: not confirmed, and the retry does not give it twice.
	server.failDataStoreCalls(1)
	expect(server.processReceipt(4, 111, "p2")).toBe(NotYet)
	expect(data.Coins).toBe(1000)
	expect(server.processReceipt(4, 111, "p2")).toBe(Granted)
	expect(data.Coins).toBe(1000)
	expect(server.savedRecord(STORE, "Player_4").Data.Coins).toBe(1000)

	-- A role; bought again in a hurry = its price back as Diamonds.
	expect(server.processReceipt(4, 222, "p3")).toBe(Granted)
	expect(data.Roles.Chief).toBe(true)
	expect(server.processReceipt(4, 222, "p4")).toBe(Granted)
	expect(data.Diamonds).toBe(99)

	-- Unknown product, or a player who is not on this server: wait.
	expect(server.processReceipt(4, 999, "p5")).toBe(NotYet)
	expect(server.processReceipt(77, 111, "p6")).toBe(NotYet)
	expect(#server.savedRecord(STORE, "Player_4").Data.Receipts).toBe(4)
end)

test("receipts: only the most recent purchase ids are kept", function()
	local server = boot({ Players = { { Id = 6, Name = "Fay" } } })
	server.Config.Products.DevProducts.Coins500 = 111
	server.Config.Data.ReceiptHistory = 3
	local data = loaded(server, 6)
	for index = 1, 5 do
		server.processReceipt(6, 111, "r" .. index)
	end
	expect(data.Receipts).toEqual({ "r3", "r4", "r5" })
	expect(data.Coins).toBe(2500)
end)
