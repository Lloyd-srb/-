--!strict
--[[
	WinConditions — pure end-of-game rules (GDD §7).

	Village : the whole wolf side (wolf + pup) is gone, and no Killer is alive.
	Wolf    : living non-wolves <= living wolf side.
	Killer  : wolves all gone and at most 1 other player left with the Killer,
	          OR the game ends by wolf parity while the living Killer has more
	          kills than the wolf side.
	Fool    : is voted out (everyone else loses).
	FireManiac: has poured oil on every house; wins the next morning if alive
	          (owner, 18 Nov 2026; checked by ArsonService). Like the Fool, a
	          living Fire Maniac does not stop the village from winning.

	GDD examples: 2 wolves + 2 villagers + killer -> continue;
	              2 wolves + 1 villager + killer -> over, compare kill counts.
]]

export type Winner = "Village" | "Wolf" | "Killer" | "Fool" | "FireManiac"

export type Snapshot = {
	WolfSideAlive: number, -- wolf + pup
	KillerAlive: boolean,
	OthersAlive: number, -- every living player who is neither wolf side nor the Killer
	WolfKills: number, -- kills by wolf + pup
	KillerKills: number,
}

local WinConditions = {}

-- Called after every death, exile or leave. nil = the game goes on.
function WinConditions.evaluate(s: Snapshot): Winner?
	local nonWolves = s.OthersAlive + (if s.KillerAlive then 1 else 0)

	if s.WolfSideAlive == 0 then
		if not s.KillerAlive then
			return "Village"
		elseif s.OthersAlive <= 1 then
			return "Killer"
		end
		return nil -- villagers still have to deal with the Killer
	end

	if nonWolves <= s.WolfSideAlive then
		if s.KillerAlive and s.KillerKills > s.WolfKills then
			return "Killer"
		end
		return "Wolf"
	end

	return nil
end

-- The Fool wins only by being voted out (not by being killed).
function WinConditions.onExile(exiledRole: string): Winner?
	if exiledRole == "Fool" then
		return "Fool"
	end
	return nil
end

--[[
	The main wolf left the game ([default] §7):
	no pup -> the village wins at once; with a pup -> same as the wolf being
	exiled (the game goes on and the pup's promotion countdown starts).
]]
function WinConditions.onWolfLeft(pupAlive: boolean): Winner?
	if not pupAlive then
		return "Village"
	end
	return nil
end

-- Morning check for the Fire Maniac: every house oiled, and still alive.
function WinConditions.fireManiacWins(oiled: number, houses: number, alive: boolean): boolean
	return alive and houses > 0 and oiled >= houses
end

function WinConditions.didWin(faction: string, winner: Winner): boolean
	return faction == winner
end

return WinConditions
