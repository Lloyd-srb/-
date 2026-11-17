--!strict
--[[
	AbilityUses — pure counter for "N times per day / per night / per game"
	limits (GDD §9). A scope is a string such as "Day:2", "Night:3" or "Game";
	a new day or night simply has a new scope, so nothing needs resetting.
]]

export type State = { [string]: number }

local AbilityUses = {}

function AbilityUses.new(): State
	return {}
end

local function key(memberId: number, ability: string, scope: string): string
	return memberId .. "|" .. ability .. "|" .. scope
end

function AbilityUses.used(state: State, memberId: number, ability: string, scope: string): number
	return state[key(memberId, ability, scope)] or 0
end

function AbilityUses.left(state: State, memberId: number, ability: string, scope: string, limit: number): number
	return math.max(0, limit - AbilityUses.used(state, memberId, ability, scope))
end

-- Spends one use if any is left. Returns whether it was spent.
function AbilityUses.tryUse(state: State, memberId: number, ability: string, scope: string, limit: number): boolean
	local index = key(memberId, ability, scope)
	local count = state[index] or 0
	if count >= limit then
		return false
	end
	state[index] = count + 1
	return true
end

return AbilityUses
