--!strict
--[[
	ProfileLogic — pure rules for a player's saved profile (GDD §13):
	the data layout, cleaning up whatever comes back from the DataStore,
	rewards, the Season Pass, buying, equipping, the Daily Spin, purchase
	receipts and the view sent to the player's own client.

	Nothing here touches the DataStore or Roblox services: Profiles (the
	store) and the lobby / match services call these functions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Logic.Progression)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Shop = require(ReplicatedStorage.Shared.Logic.Shop)

local DailySpin = require(script.Parent.DailySpin)

export type Data = {
	Schema: number,
	Coins: number,
	Diamonds: number,
	Exp: number,
	Roles: { [string]: boolean }, -- bought / won roles (free roles are implicit)
	Skins: { [string]: boolean },
	Titles: { [string]: boolean },
	Equipped: { [string]: string }, -- "Gun" | "Knife" | "Wolf" | "Title" -> id
	Mastery: { [string]: number }, -- mastery points per role
	Pass: { Exp: number, Premium: boolean, FreeClaimed: number, PremiumClaimed: number },
	Spin: { LastFreeDay: number, Extra: number },
	Codes: { [string]: boolean }, -- redeemed codes
	Receipts: { string }, -- recent Robux purchase ids, oldest first
}

export type Reward = {
	Kind: string, -- "Coins" | "Diamonds" | "Spin" | "Title" | "Skin" | "Role" | "Premium" | "None"
	Amount: number?,
	Id: string?,
	ConvertedFrom: string?,
}

export type MatchGrant = {
	Coins: number,
	Exp: number,
	PassExp: number,
	MasteryRole: string,
	MasteryPoints: number,
}

local SCHEMA = 1
local EQUIP_SLOTS = { "Gun", "Knife", "Wolf", "Title" }

local ProfileLogic = {}

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function ProfileLogic.template(): Data
	return {
		Schema = SCHEMA,
		Coins = 0,
		Diamonds = 0,
		Exp = 0,
		Roles = {},
		Skins = {},
		Titles = {},
		Equipped = {},
		Mastery = {},
		Pass = { Exp = 0, Premium = false, FreeClaimed = 0, PremiumClaimed = 0 },
		Spin = { LastFreeDay = -1, Extra = 0 },
		Codes = {},
		Receipts = {},
	}
end

local function amount(value: any, default: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	return value
end

local function count(value: any): number
	return math.max(0, math.floor(amount(value, 0)))
end

local function flags(value: any): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(value) == "table" then
		for key, flag in value do
			if type(key) == "string" and flag == true then
				result[key] = true
			end
		end
	end
	return result
end

--[[
	Turns whatever the DataStore returned (nil for a new player, or data saved
	by an older version) into a complete, well-typed profile. Unknown fields
	are dropped; missing ones get their defaults.
]]
function ProfileLogic.reconcile(raw: any): Data
	local data = ProfileLogic.template()
	if type(raw) ~= "table" then
		return data
	end
	data.Coins = count(raw.Coins)
	data.Diamonds = count(raw.Diamonds)
	data.Exp = count(raw.Exp)
	data.Roles = flags(raw.Roles)
	data.Skins = flags(raw.Skins)
	data.Titles = flags(raw.Titles)
	data.Codes = flags(raw.Codes)
	if type(raw.Equipped) == "table" then
		for _, slot in EQUIP_SLOTS do
			local id = raw.Equipped[slot]
			if type(id) == "string" then
				data.Equipped[slot] = id
			end
		end
	end
	if type(raw.Mastery) == "table" then
		for roleId, points in raw.Mastery do
			if type(roleId) == "string" then
				data.Mastery[roleId] = count(points)
			end
		end
	end
	if type(raw.Pass) == "table" then
		data.Pass.Exp = count(raw.Pass.Exp)
		data.Pass.Premium = raw.Pass.Premium == true
		data.Pass.FreeClaimed = count(raw.Pass.FreeClaimed)
		data.Pass.PremiumClaimed = count(raw.Pass.PremiumClaimed)
	end
	if type(raw.Spin) == "table" then
		data.Spin.LastFreeDay = math.floor(amount(raw.Spin.LastFreeDay, -1))
		data.Spin.Extra = count(raw.Spin.Extra)
	end
	if type(raw.Receipts) == "table" then
		for _, id in raw.Receipts do
			if type(id) == "string" then
				table.insert(data.Receipts, id)
			end
		end
	end
	return data
end

--------------------------------------------------------------------------------
-- Questions
--------------------------------------------------------------------------------

function ProfileLogic.level(data: Data): number
	return Progression.playerLevel(data.Exp)
end

function ProfileLogic.ownsRole(data: Data, roleId: string): boolean
	local def = Config.Roles[roleId]
	return (def ~= nil and def.Free) or data.Roles[roleId] == true
end

-- Every role this player owns, free ones included.
function ProfileLogic.ownedRoles(data: Data): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for _, roleId in Config.RoleOrder do
		if ProfileLogic.ownsRole(data, roleId) then
			owned[roleId] = true
		end
	end
	return owned
end

function ProfileLogic.wallet(data: Data): Shop.Wallet
	return {
		Coins = data.Coins,
		Diamonds = data.Diamonds,
		Level = ProfileLogic.level(data),
		Roles = ProfileLogic.ownedRoles(data),
		Skins = data.Skins,
		Premium = data.Pass.Premium,
	}
end

-- The equipped skin for a slot, if it is still a known skin of that slot.
function ProfileLogic.equippedSkin(data: Data, slot: string): string?
	local id = data.Equipped[slot]
	local def = if id then Config.Skins[id] else nil
	if id and def and def.Slot == slot and data.Skins[id] then
		return id
	end
	return nil
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------

local claimPass: (data: Data) -> { Reward }

-- Gives one reward. Returns what was really given ("None" for something
-- already owned that has no replacement).
function ProfileLogic.applyReward(data: Data, reward: Reward): Reward
	local kind = reward.Kind
	local value = count(reward.Amount)
	if kind == "Coins" then
		data.Coins += value
	elseif kind == "Diamonds" then
		data.Diamonds += value
	elseif kind == "Spin" then
		data.Spin.Extra += math.max(1, value)
	elseif kind == "Title" and reward.Id then
		if data.Titles[reward.Id] then
			return { Kind = "None" }
		end
		data.Titles[reward.Id] = true
	elseif kind == "Skin" and reward.Id and Config.Skins[reward.Id] then
		if data.Skins[reward.Id] then
			return { Kind = "None" }
		end
		data.Skins[reward.Id] = true
	elseif kind == "Role" and reward.Id and Config.Roles[reward.Id] and reward.Id ~= "Wolf" then
		if ProfileLogic.ownsRole(data, reward.Id) then
			return { Kind = "None" }
		end
		data.Roles[reward.Id] = true
	elseif kind == "Premium" then
		if data.Pass.Premium then
			return { Kind = "None" }
		end
		ProfileLogic.unlockPremium(data)
	else
		return { Kind = "None" }
	end
	return reward
end

--------------------------------------------------------------------------------
-- Season Pass (GDD §13.2). Rewards are given automatically when a level is
-- reached; buying Premium later also gives the premium rewards of every
-- level already reached ([ASSUMED], OWNER_TODO 17: premium players get both tracks).
--------------------------------------------------------------------------------

function ProfileLogic.passLevel(data: Data): number
	return Progression.passLevel(data.Pass.Exp)
end

function claimPass(data: Data): { Reward }
	local given: { Reward } = {}
	local level = ProfileLogic.passLevel(data)
	for passLevel = data.Pass.FreeClaimed + 1, level do
		for _, reward in Progression.passRewards(passLevel, "Free") do
			table.insert(given, ProfileLogic.applyReward(data, reward :: any))
		end
	end
	data.Pass.FreeClaimed = math.max(data.Pass.FreeClaimed, level)
	if data.Pass.Premium then
		for passLevel = data.Pass.PremiumClaimed + 1, level do
			for _, reward in Progression.passRewards(passLevel, "Premium") do
				table.insert(given, ProfileLogic.applyReward(data, reward :: any))
			end
		end
		data.Pass.PremiumClaimed = math.max(data.Pass.PremiumClaimed, level)
	end
	return given
end
ProfileLogic.claimPass = claimPass

function ProfileLogic.addPassExp(data: Data, exp: number): { Reward }
	data.Pass.Exp += count(exp)
	return claimPass(data)
end

-- Premium: +10 levels at once and the premium track (GDD §13.2).
function ProfileLogic.unlockPremium(data: Data): { Reward }
	if data.Pass.Premium then
		return {}
	end
	data.Pass.Premium = true
	data.Pass.Exp = Progression.passExpAfterBonusLevels(data.Pass.Exp, Config.SeasonPass.PremiumBonusLevels)
	return claimPass(data)
end

--------------------------------------------------------------------------------
-- End of a match (GDD §13). Returns the diamonds from new mastery levels and
-- the Season Pass rewards reached.
--------------------------------------------------------------------------------

function ProfileLogic.grantMatch(data: Data, grant: MatchGrant): (number, { Reward })
	data.Coins += count(grant.Coins)
	data.Exp += count(grant.Exp)
	local before = data.Mastery[grant.MasteryRole] or 0
	local after = before + count(grant.MasteryPoints)
	data.Mastery[grant.MasteryRole] = after
	local diamonds = Progression.masteryDiamonds(before, after)
	data.Diamonds += diamonds
	return diamonds, ProfileLogic.addPassExp(data, grant.PassExp)
end

--------------------------------------------------------------------------------
-- Buying with Coins / Diamonds (Robux goes through receipts, below)
--------------------------------------------------------------------------------

local function give(data: Data, offer: Shop.Offer): { Reward }
	if offer.Kind == "Role" then
		return { ProfileLogic.applyReward(data, { Kind = "Role", Id = offer.Id }) }
	elseif offer.Kind == "Skin" then
		return { ProfileLogic.applyReward(data, { Kind = "Skin", Id = offer.Id }) }
	elseif offer.Kind == "Premium" then
		local rewards = ProfileLogic.unlockPremium(data)
		table.insert(rewards, 1, { Kind = "Premium" })
		return rewards
	elseif offer.Kind == "Coins" then
		return { ProfileLogic.applyReward(data, { Kind = "Coins", Amount = offer.Gives }) }
	end
	return {}
end

-- Returns (ok, reason, rewards). Reasons come from Shop.check.
function ProfileLogic.buy(data: Data, kind: string, id: string, currency: string): (boolean, string?, { Reward })
	if currency ~= "Coins" and currency ~= "Diamonds" then
		return false, "WrongCurrency", {}
	end
	local ok, reason = Shop.check(ProfileLogic.wallet(data), kind, id, currency)
	local offer = Shop.offer(kind, id)
	if not ok or not offer then
		return false, reason, {}
	end
	if currency == "Coins" then
		data.Coins -= offer.Coins :: number
	else
		data.Diamonds -= offer.Gems :: number
	end
	return true, nil, give(data, offer)
end

--[[
	A Robux purchase went through: give what the product is. Something
	one-time that is already owned (bought twice in a hurry) gives its price
	as Diamonds instead (Config.Shop.RefundDuplicatesAsDiamonds).
	Returns nil for an unknown product key.
]]
function ProfileLogic.grantProduct(data: Data, productKey: string): { Reward }?
	local offer = Shop.offerForProduct(productKey)
	if not offer then
		return nil
	end
	if offer.OneTime and Shop.owns(ProfileLogic.wallet(data), offer.Kind, offer.Id) then
		if Config.Shop.RefundDuplicatesAsDiamonds and offer.Gems then
			return { ProfileLogic.applyReward(data, { Kind = "Diamonds", Amount = offer.Gems, ConvertedFrom = offer.Id }) }
		end
		return { { Kind = "None" } }
	end
	return give(data, offer)
end

function ProfileLogic.hasReceipt(data: Data, purchaseId: string): boolean
	return table.find(data.Receipts, purchaseId) ~= nil
end

function ProfileLogic.addReceipt(data: Data, purchaseId: string)
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > Config.Data.ReceiptHistory do
		table.remove(data.Receipts, 1)
	end
end

--------------------------------------------------------------------------------
-- Equipping (skins per slot, one title). id = nil takes it off.
--------------------------------------------------------------------------------

function ProfileLogic.equip(data: Data, slot: string, id: string?): boolean
	if not table.find(EQUIP_SLOTS, slot) then
		return false
	end
	if id == nil then
		data.Equipped[slot] = nil
		return true
	end
	if slot == "Title" then
		if not data.Titles[id] then
			return false
		end
	else
		local def = Config.Skins[id]
		if not def or def.Slot ~= slot or not data.Skins[id] then
			return false
		end
	end
	data.Equipped[slot] = id
	return true
end

--------------------------------------------------------------------------------
-- Daily Spin (GDD §13.3)
--------------------------------------------------------------------------------

-- Spins once if a spin is left. Returns the prize given, or nil.
function ProfileLogic.spin(data: Data, now: number, rng: Rng.Rng): Reward?
	if not DailySpin.use(data.Spin, now) then
		return nil
	end
	local prize = DailySpin.roll(rng, ProfileLogic.ownedRoles(data), data.Skins)
	ProfileLogic.applyReward(data, prize :: any)
	return prize :: any
end

--------------------------------------------------------------------------------
-- What the player's own client is told (never receipts or codes).
--------------------------------------------------------------------------------

function ProfileLogic.view(data: Data, now: number): { [string]: any }
	local levelInto, levelNeed = Progression.playerLevelProgress(data.Exp)
	local passInto, passNeed = Progression.passLevelProgress(data.Pass.Exp)
	local equipped: { [string]: any } = {}
	for _, slot in { "Gun", "Knife", "Wolf" } do
		equipped[slot] = ProfileLogic.equippedSkin(data, slot)
	end
	local title = data.Equipped.Title
	if title and data.Titles[title] then
		equipped.Title = title
	end
	return {
		Coins = data.Coins,
		Diamonds = data.Diamonds,
		Level = ProfileLogic.level(data),
		LevelInto = levelInto,
		LevelNeed = levelNeed,
		Roles = ProfileLogic.ownedRoles(data),
		Skins = table.clone(data.Skins),
		Titles = table.clone(data.Titles),
		Equipped = equipped,
		Mastery = table.clone(data.Mastery),
		Pass = {
			Level = ProfileLogic.passLevel(data),
			Into = passInto,
			Need = passNeed,
			Premium = data.Pass.Premium,
		},
		Spin = {
			Free = DailySpin.freeReady(data.Spin, now),
			Extra = data.Spin.Extra,
			NextFreeAt = DailySpin.nextFreeAt(now),
		},
	}
end

return ProfileLogic
