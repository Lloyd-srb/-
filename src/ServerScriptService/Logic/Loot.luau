--!strict
--[[
	Loot — pure random-reward rules: forest crate (GDD §6.1, §11) and
	Daily Spin (GDD §13.3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

export type Grant = {
	Kind: "Coins" | "Diamonds" | "Role" | "Skin",
	Amount: number?,
	Id: string?,
	-- Set when the rolled prize was already owned and got converted.
	ConvertedFrom: string?,
}

local Loot = {}

--------------------------------------------------------------------------------
-- Crate
--------------------------------------------------------------------------------

-- Every morning: 30% chance that one crate appears under a random forest tree.
function Loot.shouldSpawnCrate(rng: Rng.Rng): boolean
	return rng:NextNumber() < Config.Crate.MorningSpawnChance
end

function Loot.rollCrate(rng: Rng.Rng): string
	return Rng.weighted(Config.Crate.Loot, rng).Item
end

-- One gun per player; some roles (Killer) can never hold one.
function Loot.canHoldGun(roleId: string, gunsHeld: number): boolean
	if Config.GunForbiddenRoles[roleId] then
		return false
	end
	return gunsHeld < Config.Items.Gun.MaxPerPlayer
end

--------------------------------------------------------------------------------
-- Daily Spin
--------------------------------------------------------------------------------

local SECONDS_PER_DAY = 86400

-- Free spin resets at 00:00 UTC. Timestamps are os.time() seconds.
function Loot.canFreeSpin(lastSpinTime: number, now: number): boolean
	return math.floor(now / SECONDS_PER_DAY) > math.floor(lastSpinTime / SECONDS_PER_DAY)
end

-- Rolls a prize and converts duplicates (Killer -> 2,500 coins, spin skin -> 200 diamonds).
function Loot.rollSpin(rng: Rng.Rng, ownedRoles: { [string]: boolean }, ownedSkins: { [string]: boolean }): Grant
	local prize: any = Rng.weighted(Config.DailySpin.Prizes, rng)

	if prize.Kind == "Role" then
		if ownedRoles[prize.Id] then
			return { Kind = "Coins", Amount = Config.DailySpin.DuplicateRoleCoins, ConvertedFrom = prize.Id }
		end
		return { Kind = "Role", Id = prize.Id }
	elseif prize.Kind == "Skin" then
		if ownedSkins[prize.Id] then
			return { Kind = "Diamonds", Amount = Config.DailySpin.DuplicateSkinDiamonds, ConvertedFrom = prize.Id }
		end
		return { Kind = "Skin", Id = prize.Id }
	end

	return { Kind = prize.Kind, Amount = prize.Amount }
end

return Loot
