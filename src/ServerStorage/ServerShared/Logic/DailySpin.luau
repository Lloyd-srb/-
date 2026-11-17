--!strict
--[[
	DailySpin — pure Daily Spin rules (GDD §13.3).

	Everyone gets one free spin per day (the day turns at
	Config.DailySpin.ResetHourUtc, UTC). Extra spins come from the Season Pass
	(levels 10, 20, ... 50) and are kept until used. The free spin is used
	first. Timestamps are os.time() seconds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

export type Prize = {
	Kind: string, -- "Coins" | "Diamonds" | "Role" | "Skin"
	Amount: number?,
	Id: string?,
	ConvertedFrom: string?, -- set when an owned prize was swapped for another
}

export type SpinState = { LastFreeDay: number, Extra: number }

local DAY = 86400

local DailySpin = {}

-- Which spin day `now` falls on.
function DailySpin.dayOf(now: number): number
	return math.floor((now - Config.DailySpin.ResetHourUtc * 3600) / DAY)
end

-- When the next free spin comes (os.time seconds).
function DailySpin.nextFreeAt(now: number): number
	return (DailySpin.dayOf(now) + 1) * DAY + Config.DailySpin.ResetHourUtc * 3600
end

function DailySpin.freeReady(state: SpinState, now: number): boolean
	return state.LastFreeDay < DailySpin.dayOf(now)
end

function DailySpin.canSpin(state: SpinState, now: number): boolean
	return DailySpin.freeReady(state, now) or state.Extra > 0
end

-- Uses up one spin (free first). Returns "Free" / "Extra", or nil if none is left.
function DailySpin.use(state: SpinState, now: number): string?
	if DailySpin.freeReady(state, now) then
		state.LastFreeDay = DailySpin.dayOf(now)
		return "Free"
	elseif state.Extra > 0 then
		state.Extra -= 1
		return "Extra"
	end
	return nil
end

-- Rolls a prize and swaps duplicates (Killer owned -> 2,500 coins, spin skin
-- owned -> 200 diamonds).
function DailySpin.roll(rng: Rng.Rng, ownedRoles: { [string]: boolean }, ownedSkins: { [string]: boolean }): Prize
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

return DailySpin
