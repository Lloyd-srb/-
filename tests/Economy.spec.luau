local Config = require(game.ReplicatedStorage.Shared.Config)
local Rng = require(game.ReplicatedStorage.Shared.Rng)
local Progression = require(game.ReplicatedStorage.Shared.Logic.Progression)
local Rewards = require(game.ServerScriptService.Logic.Rewards)
local Loot = require(game.ServerScriptService.Logic.Loot)

local function reward(nights, won, faction, tasks, mvp)
	return Rewards.compute({
		NightsSurvived = nights,
		Won = won,
		Faction = faction,
		TasksCompleted = tasks or 0,
		IsMvp = mvp == true,
	})
end

test("rewards: win full, lose half", function()
	local win = reward(4, true, "Village")
	expect(win.Coins).toBe(80)
	expect(win.Exp).toBe(200)
	expect(win.PassExp).toBe(150)
	expect(win.MasteryPoints).toBe(2)
	local lose = reward(4, false, "Village")
	expect(lose.Coins).toBe(40)
	expect(lose.Exp).toBe(100)
	expect(lose.PassExp).toBe(50)
	expect(lose.MasteryPoints).toBe(1)
end)

test("rewards: killer / fool win +50%, tasks are not halved, MVP +20%", function()
	expect(reward(4, true, "Killer").Coins).toBe(120)
	expect(reward(4, true, "Fool").Exp).toBe(300)
	expect(reward(4, false, "Killer").Coins).toBe(40)
	expect(reward(4, false, "Village", 2).Coins).toBe(80) -- 40 + 2 * 20
	expect(reward(1, true, "Village", 0, true).Coins).toBe(24) -- 20 * 1.2
	expect(reward(4, true, "Village", 2, true).Coins).toBe(144) -- (80 + 40) * 1.2
	expect(reward(4, true, "Village", 0, true).Exp).toBe(240)
end)

test("MVP: most likes, none when nobody liked", function()
	local first = function(tied)
		return tied[1]
	end
	expect(Rewards.pickMvp({ [1] = 2, [2] = 5, [3] = 1 }, first)).toBe(2)
	expect(Rewards.pickMvp({ [1] = 0, [2] = 0 }, first)).toBeNil()
	expect(Rewards.pickMvp({ [4] = 3, [2] = 3 }, first)).toBe(2)
end)

test("player level matches the GDD estimates", function()
	expect(Progression.playerLevel(0)).toBe(1)
	expect(Progression.playerLevel(299)).toBe(1)
	expect(Progression.playerLevel(1200)).toBe(5)
	expect(Progression.playerLevel(2700)).toBe(10)
	expect(Progression.playerLevel(5700)).toBe(20)
end)

test("mastery: 20 points per mastery, 20 diamonds each", function()
	expect(Progression.masteryLevel(19)).toBe(0)
	expect(Progression.masteryLevel(40)).toBe(2)
	expect(Progression.masteryDiamonds(18, 20)).toBe(20)
	expect(Progression.masteryDiamonds(20, 22)).toBe(0)
end)

test("season pass levels: 200 EXP to 60, then 1,000", function()
	expect(Progression.passLevel(0)).toBe(0)
	expect(Progression.passLevel(199)).toBe(0)
	expect(Progression.passLevel(200)).toBe(1)
	expect(Progression.passLevel(11999)).toBe(59)
	expect(Progression.passLevel(12000)).toBe(60)
	expect(Progression.passLevel(12999)).toBe(60)
	expect(Progression.passLevel(13000)).toBe(61)
	for level = 0, 70 do
		expect(Progression.passLevel(Progression.passExpForLevel(level))).toBe(level)
	end
end)

test("premium purchase: +10 levels, progress kept", function()
	local after = Progression.passExpAfterBonusLevels(250, 10) -- Lv1 + 50
	expect(Progression.passLevel(after)).toBe(11)
	expect(after).toBe(2250)
	local across = Progression.passExpAfterBonusLevels(11000, 10) -- Lv55 -> Lv65
	expect(Progression.passLevel(across)).toBe(65)
end)

test("season pass reward table", function()
	expect(Progression.passRewards(1, "Free")).toEqual({ { Kind = "Title", Id = "PassFree" } })
	expect(Progression.passRewards(1, "Premium")).toEqual({ { Kind = "Title", Id = "PassPremium" } })
	expect(Progression.passRewards(7, "Free")).toEqual({ { Kind = "Coins", Amount = 50 } })
	expect(Progression.passRewards(7, "Premium")[1].Kind).toBe("Diamonds")
	for _, level in { 5, 15, 25, 35, 45, 55 } do
		expect(Progression.passRewards(level, "Free")).toEqual({ { Kind = "Diamonds", Amount = 20 } })
		expect(Progression.passRewards(level, "Premium")).toEqual({ { Kind = "Diamonds", Amount = 20 } })
	end
	for _, level in { 10, 20, 30, 40, 50 } do
		expect(Progression.passRewards(level, "Free")).toEqual({ { Kind = "Spin", Amount = 1 } })
	end
	expect(#Progression.passRewards(60, "Free")).toBe(2)
	expect(Progression.passRewards(60, "Premium")).toEqual({ { Kind = "Skin", Id = "WolfPass" } })
	expect(Progression.passRewards(61, "Free")).toEqual({ { Kind = "Coins", Amount = 50 } })
	expect(Progression.passRewards(61, "Premium")).toEqual({ { Kind = "Diamonds", Amount = 10 } })
end)

test("crate: drop rates follow the GDD, gun is rare", function()
	local rng = Rng.seeded(42)
	local counts, rolls = {}, 40000
	for _ = 1, rolls do
		local item = Loot.rollCrate(rng)
		counts[item] = (counts[item] or 0) + 1
	end
	expect(counts.Gun / rolls).toBeNear(0.05, 0.01)
	for _, item in { "FirstAid", "Cross", "Axe", "Shovel", "Flashlight" } do
		expect(counts[item] / rolls).toBeNear(0.19, 0.015)
	end
end)

test("crate spawns on about 30% of mornings", function()
	local rng = Rng.seeded(7)
	local spawned = 0
	for _ = 1, 20000 do
		if Loot.shouldSpawnCrate(rng) then
			spawned += 1
		end
	end
	expect(spawned / 20000).toBeNear(Config.Crate.MorningSpawnChance, 0.015)
end)

test("gun limit: one per player, never the killer", function()
	expect(Loot.canHoldGun("Villager", 0)).toBe(true)
	expect(Loot.canHoldGun("Sheriff", 1)).toBe(false)
	expect(Loot.canHoldGun("Killer", 0)).toBe(false)
end)

test("daily spin: odds and duplicate conversion", function()
	local rng = Rng.seeded(99)
	local counts, rolls = {}, 200000
	for _ = 1, rolls do
		local grant = Loot.rollSpin(rng, {}, {})
		local key = grant.Kind .. tostring(grant.Amount or grant.Id)
		counts[key] = (counts[key] or 0) + 1
	end
	expect(counts.Coins20 / rolls).toBeNear(0.30, 0.01)
	expect(counts.Diamonds50 / rolls).toBeNear(0.08, 0.005)
	expect(counts.RoleKiller / rolls).toBeNear(0.01, 0.003)
	expect(counts.SkinWolfSpin / rolls).toBeNear(0.005, 0.002)

	local sawRoleDup, sawSkinDup = false, false
	for _ = 1, 20000 do
		local grant = Loot.rollSpin(rng, { Killer = true }, { WolfSpin = true })
		expect(grant.Kind ~= "Role" and grant.Kind ~= "Skin").toBe(true)
		if grant.ConvertedFrom == "Killer" then
			expect(grant).toEqual({ Kind = "Coins", Amount = 2500, ConvertedFrom = "Killer" })
			sawRoleDup = true
		elseif grant.ConvertedFrom == "WolfSpin" then
			expect(grant).toEqual({ Kind = "Diamonds", Amount = 200, ConvertedFrom = "WolfSpin" })
			sawSkinDup = true
		end
	end
	expect(sawRoleDup and sawSkinDup).toBe(true)
end)

test("free spin resets at 00:00 UTC", function()
	local day = 86400
	expect(Loot.canFreeSpin(0, 10 * day)).toBe(true)
	expect(Loot.canFreeSpin(10 * day + 5, 10 * day + 80000)).toBe(false)
	expect(Loot.canFreeSpin(10 * day + 80000, 11 * day + 1)).toBe(true)
end)
