--!strict
--[[
	Likes — pure rules for the end scoreboard (GDD §7).
	Every player has one like to give to someone else (never themselves) and
	may move it while the scoreboard is open. Most likes = MVP.
]]

export type State = { [number]: number } -- voter id -> liked id

local Likes = {}

function Likes.new(): State
	return {}
end

function Likes.give(state: State, voter: number, target: number): boolean
	if voter == target then
		return false
	end
	state[voter] = target
	return true
end

function Likes.counts(state: State): { [number]: number }
	local counts: { [number]: number } = {}
	for _, target in state do
		counts[target] = (counts[target] or 0) + 1
	end
	return counts
end

return Likes
