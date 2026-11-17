--[[
	Profile rules (GDD §13): Season Pass claiming, Premium, buying, receipts,
	equipping, Daily Spin, codes. Pure functions, no DataStore.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local Rng = require(game.ReplicatedStorage.Shared.Rng)
local Shop = require(game.ReplicatedStorage.Shared.Logic.Shop)
local Logic = game.ServerStorage.ServerShared.Logic
local ProfileLogic = require(Logic.ProfileLogic)
local Codes = require(Logic.Codes)

local function fresh()
	return ProfileLogic.template()
end

local function kinds(rewards)
	local list = {}
	for _, reward in rewards do
		table.insert(list, reward.Kind .. ":" .. tostring(reward.Amount or reward.Id))
	end
	return list
end

test("pass: rewards are given once, level by level (free track)", function()
	local data = fresh()
	expect(#ProfileLogic.addPassExp(data, 150)).toBe(0) -- level 0 still
	expect(kinds(ProfileLogic.addPassExp(data, 50))).toEqual({ "Title:PassFree" })
	expect(data.Titles.PassFree).toBe(true)
	local rewards = ProfileLogic.addPassExp(data, 200 * 4) -- levels 2-5
	expect(kinds(rewards)).toEqual({ "Coins:50", "Coins:50", "Coins:50", "Diamonds:20" })
	expect(data.Coins).toBe(150)
	expect(data.Diamonds).toBe(20)
	expect(data.Pass.FreeClaimed).toBe(5)
	expect(#ProfileLogic.claimPass(data)).toBe(0) -- nothing twice
	ProfileLogic.addPassExp(data, 200 * 5) -- to level 10: a Daily Spin
	expect(data.Spin.Extra).toBe(1)
end)

test("pass: premium = +10 levels and every premium reward reached so far", function()
	local data = fresh()
	ProfileLogic.addPassExp(data, 200 * 3 + 120) -- level 3, 120 into level 4
	local rewards = ProfileLogic.unlockPremium(data)
	expect(ProfileLogic.passLevel(data)).toBe(13)
	expect(data.Pass.Exp).toBe(200 * 13 + 120) -- progress kept
	expect(data.Titles.PassPremium).toBe(true)
	expect(data.Pass.PremiumClaimed).toBe(13)
	expect(data.Pass.FreeClaimed).toBe(13)
	-- premium levels 1-13: title, then diamonds every level (level 5 = 20, level 10 = spin)
	local premiumDiamonds = 0
	for _, reward in rewards do
		if reward.Kind == "Diamonds" then
			premiumDiamonds += reward.Amount
		end
	end
	expect(premiumDiamonds > 0).toBe(true)
	expect(#ProfileLogic.unlockPremium(data)).toBe(0) -- only once
end)

test("pass: level 60 skins, and after 60 every 1,000 EXP", function()
	local data = fresh()
	data.Pass.Premium = true
	ProfileLogic.addPassExp(data, 200 * 60)
	expect(data.Skins.KnifePass and data.Skins.GunPass and data.Skins.WolfPass).toBe(true)
	local coins, diamonds = data.Coins, data.Diamonds
	expect(kinds(ProfileLogic.addPassExp(data, 1000))).toEqual({ "Coins:50", "Diamonds:10" })
	expect(data.Coins - coins).toBe(50)
	expect(data.Diamonds - diamonds).toBe(10)
end)

test("match grant: coins, EXP, mastery diamonds and pass EXP in one go", function()
	local data = fresh()
	local diamonds, rewards = ProfileLogic.grantMatch(data, {
		Coins = 80,
		Exp = 200,
		PassExp = 250,
		MasteryRole = "Doctor",
		MasteryPoints = 21,
	})
	expect(diamonds).toBe(20)
	expect(data.Coins).toBe(80)
	expect(data.Exp).toBe(200)
	expect(data.Mastery.Doctor).toBe(21)
	expect(kinds(rewards)).toEqual({ "Title:PassFree" })
end)

test("shop: roles need the coins, the level, and are bought once", function()
	local data = fresh()
	data.Coins = 1500
	local ok, reason = ProfileLogic.buy(data, "Role", "Chief", "Coins")
	expect(ok).toBe(false)
	expect(reason).toBe("Level") -- level 5 needed
	data.Exp = Config.PlayerLevel.ExpPerLevel * 4 -- level 5
	ok = ProfileLogic.buy(data, "Role", "Chief", "Coins")
	expect(ok).toBe(true)
	expect(data.Coins).toBe(300)
	expect(data.Roles.Chief).toBe(true)
	ok, reason = ProfileLogic.buy(data, "Role", "Chief", "Coins")
	expect(reason).toBe("Owned")
	ok, reason = ProfileLogic.buy(data, "Role", "Bodyguard", "Coins")
	expect(reason).toBe("Funds")
	expect(select(2, ProfileLogic.buy(data, "Role", "Villager", "Coins"))).toBe("NotForSale")
	expect(select(2, ProfileLogic.buy(data, "Role", "Wolf", "Diamonds"))).toBe("NotForSale")
	expect(select(2, ProfileLogic.buy(data, "Role", "Bodyguard", "Robux"))).toBe("WrongCurrency") -- not here
	data.Diamonds = 99
	expect(ProfileLogic.buy(data, "Role", "Bodyguard", "Diamonds")).toBe(true) -- Diamonds = Robux price
	expect(data.Diamonds).toBe(0)
end)

test("shop: skins and coin packs for Diamonds; premium with Diamonds", function()
	local data = fresh()
	data.Diamonds = 1000
	expect(select(2, ProfileLogic.buy(data, "Skin", "GunGold", "Coins"))).toBe("WrongCurrency")
	expect(ProfileLogic.buy(data, "Skin", "GunGold", "Diamonds")).toBe(true)
	expect(data.Skins.GunGold).toBe(true)
	expect(select(2, ProfileLogic.buy(data, "Skin", "WolfSpin", "Diamonds"))).toBe("NotForSale") -- spin only
	expect(ProfileLogic.buy(data, "Coins", "500", "Diamonds")).toBe(true)
	expect(data.Coins).toBe(500)
	local before = data.Diamonds
	local ok, _, rewards = ProfileLogic.buy(data, "Premium", "Premium", "Diamonds")
	expect(ok).toBe(true)
	expect(data.Pass.Premium).toBe(true)
	expect(rewards[1].Kind).toBe("Premium")
	expect(ProfileLogic.passLevel(data)).toBe(10)
	expect(before - Config.SeasonPass.PremiumRobuxPrice <= data.Diamonds).toBe(true)
end)

test("shop: Robux needs a product id (0 = the owner has not made it yet)", function()
	local wallet = ProfileLogic.wallet(fresh())
	wallet.Level = 99
	expect(select(2, Shop.check(wallet, "Role", "Seer", "Robux"))).toBe("NoProduct")
	Config.Products.DevProducts.RoleSeer = 1234
	expect(Shop.check(wallet, "Role", "Seer", "Robux")).toBe(true)
	Config.Products.DevProducts.RoleSeer = 0
	expect(Shop.offerForProduct("Coins2600").Gives).toBe(2600)
	expect(Shop.offerForProduct("SkinWolfShadow").Gems).toBe(199)
	expect(Shop.offerForProduct("RoleFool").Coins).toBe(5000)
	expect(Shop.offerForProduct("Nonsense")).toBeNil()
end)

test("receipts: a one-time product bought twice gives its price back as Diamonds", function()
	local data = fresh()
	expect(kinds(ProfileLogic.grantProduct(data, "SkinGunGold"))).toEqual({ "Skin:GunGold" })
	expect(kinds(ProfileLogic.grantProduct(data, "SkinGunGold"))).toEqual({ "Diamonds:99" })
	expect(kinds(ProfileLogic.grantProduct(data, "Coins1200"))).toEqual({ "Coins:1200" })
	expect(kinds(ProfileLogic.grantProduct(data, "Coins1200"))).toEqual({ "Coins:1200" }) -- packs stack
	expect(ProfileLogic.grantProduct(data, "Mystery")).toBeNil()
end)

test("equip: only owned things, in their own slot", function()
	local data = fresh()
	expect(ProfileLogic.equip(data, "Gun", "GunGold")).toBe(false)
	data.Skins.GunGold = true
	expect(ProfileLogic.equip(data, "Wolf", "GunGold")).toBe(false)
	expect(ProfileLogic.equip(data, "Gun", "GunGold")).toBe(true)
	expect(ProfileLogic.equippedSkin(data, "Gun")).toBe("GunGold")
	expect(ProfileLogic.equip(data, "Title", "PassFree")).toBe(false)
	data.Titles.PassFree = true
	expect(ProfileLogic.equip(data, "Title", "PassFree")).toBe(true)
	expect(ProfileLogic.equip(data, "Gun", nil)).toBe(true)
	expect(ProfileLogic.equippedSkin(data, "Gun")).toBeNil()
	expect(ProfileLogic.equip(data, "Hat", nil)).toBe(false)
end)

test("daily spin: one free spin a day, then the Pass's extra spins", function()
	local data = fresh()
	local rng = Rng.seeded(7)
	local day = 86400 * 1000
	expect(ProfileLogic.spin(data, day + 10, rng) ~= nil).toBe(true)
	expect(ProfileLogic.spin(data, day + 20, rng)).toBeNil()
	data.Spin.Extra = 1
	expect(ProfileLogic.spin(data, day + 30, rng) ~= nil).toBe(true)
	expect(ProfileLogic.spin(data, day + 40, rng)).toBeNil()
	expect(ProfileLogic.spin(data, day + 86400, rng) ~= nil).toBe(true) -- next day
	expect(data.Coins + data.Diamonds > 0 or next(data.Roles) ~= nil or next(data.Skins) ~= nil).toBe(true)
end)

test("daily spin: winning the Killer you already have = 2,500 coins", function()
	local data = fresh()
	data.Roles.Killer = true
	local rng = Rng.seeded(3)
	for index = 1, 3000 do
		data.Spin.Extra = 1
		local prize = ProfileLogic.spin(data, index, rng)
		expect(prize.Kind ~= "Role").toBe(true)
	end
end)

test("codes: any case, once per player, not after expiry", function()
	local list = {
		HELLO = { Rewards = { { Kind = "Coins", Amount = 100 }, { Kind = "Spin", Amount = 1 } } },
		OLD = { Rewards = { { Kind = "Diamonds", Amount = 5 } }, Expires = 1000 },
	}
	local data = fresh()
	local ok, rewards = Codes.redeem(data, "  hello ", 500, list)
	expect(ok).toBe(true)
	expect(#rewards).toBe(2)
	expect(data.Coins).toBe(100)
	expect(data.Spin.Extra).toBe(1)
	expect(select(2, Codes.redeem(data, "HELLO", 500, list))).toBe("Used")
	expect(select(2, Codes.redeem(data, "nope", 500, list))).toBe("Unknown")
	expect(select(2, Codes.redeem(data, "OLD", 2000, list))).toBe("Expired")
	expect(Codes.redeem(data, "old", 999, list)).toBe(true)
	expect(select(2, Codes.redeem(data, string.rep("A", 500), 1, list))).toBe("Unknown")
	expect(select(2, Codes.redeem(data, 42, 1, list))).toBe("Unknown")
	expect(Codes.normalize("wolf village")).toBeNil()
end)

test("view: what the client sees (no receipts, no codes)", function()
	local data = fresh()
	data.Receipts = { "secret" }
	data.Codes.HELLO = true
	data.Exp = 450
	local view = ProfileLogic.view(data, 86400 * 5 + 100)
	expect(view.Level).toBe(2)
	expect(view.LevelInto).toBe(150)
	expect(view.Receipts).toBeNil()
	expect(view.Codes).toBeNil()
	expect(view.Roles.Villager and view.Roles.Sheriff and view.Roles.Doctor).toBe(true)
	expect(view.Spin.Free).toBe(true)
	expect(view.Spin.NextFreeAt).toBe(86400 * 6)
end)
