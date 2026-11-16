--!strict
--[[
	WolfPack — pure wolf-pup rules (GDD §8.2).

	- The first player the wolf kills at night becomes the pup (one pup per game).
	  If the wolf kills nobody on a night, the next night's first kill counts.
	- When the main wolf is exiled / dead / gone, the pup becomes a full wolf at
	  the start of the 2nd night after that.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WolfPack = {}

-- Should this wolf kill turn the victim into the pup instead of killing them?
function WolfPack.shouldConvert(killerIsMainWolf: boolean, isNight: boolean, pupsCreated: number): boolean
	return killerIsMainWolf and isNight and pupsCreated < Config.Pup.MaxPerGame
end

--[[
	Called at the start of every night.
	`nightNumber`      the night that is starting (1, 2, 3, ...)
	`nightsWhenLost`   how many nights had already started when the main wolf was lost
	                   (lost during the day after night 2, or during night 2 -> 2)
]]
function WolfPack.shouldPromote(nightNumber: number, nightsWhenLost: number?): boolean
	if nightsWhenLost == nil then
		return false
	end
	return nightNumber - nightsWhenLost >= Config.Pup.PromotionNights
end

return WolfPack
