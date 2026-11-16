--!strict
--[[
	NightHousing — pure night warp rule (GDD §6.3): everyone who is in the
	village when night falls gets a random house, one house per player (it may
	or may not be the house they had before).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rng = require(ReplicatedStorage.Shared.Rng)

local NightHousing = {}

-- ids -> houseId (1..houseCount). Houses are only shared if ids > houses.
function NightHousing.assign(ids: { number }, houseCount: number, rng: Rng.Rng): { [number]: number }
	local houses: { number } = {}
	for houseId = 1, houseCount do
		houses[houseId] = houseId
	end
	houses = Rng.shuffle(houses, rng)

	local sorted = table.clone(ids)
	table.sort(sorted)

	local assigned: { [number]: number } = {}
	for index, id in sorted do
		assigned[id] = houses[(index - 1) % houseCount + 1]
	end
	return assigned
end

return NightHousing
