--!strict
--[[
	Loot — pure random-reward rules for the forest crate (GDD §6.1, §11).
	The Daily Spin lives in ServerStorage.ServerShared.Logic.DailySpin (the
	lobby uses it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

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

return Loot
