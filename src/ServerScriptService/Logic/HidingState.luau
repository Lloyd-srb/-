--!strict
--[[
	HidingState — pure hiding rules (GDD §6.4).

	- A player hides under a bed or in a wardrobe; one player per spot.
	- The wolf side can search a spot: an occupant is thrown out (not stunned)
	  and cannot hide anywhere again until that night is over.
]]

export type State = {
	Occupant: { [string]: number }, -- spot key -> member id
	SpotOf: { [number]: string }, -- member id -> spot key
	PulledOut: { [number]: boolean },
}

local HidingState = {}

function HidingState.new(): State
	return { Occupant = {}, SpotOf = {}, PulledOut = {} }
end

function HidingState.spotKey(houseId: number, kind: string): string
	return houseId .. ":" .. kind
end

function HidingState.isHidden(state: State, id: number): boolean
	return state.SpotOf[id] ~= nil
end

function HidingState.canHide(state: State, id: number, spot: string): boolean
	return state.SpotOf[id] == nil and state.Occupant[spot] == nil and not state.PulledOut[id]
end

function HidingState.hide(state: State, id: number, spot: string): boolean
	if not HidingState.canHide(state, id, spot) then
		return false
	end
	state.Occupant[spot] = id
	state.SpotOf[id] = spot
	return true
end

-- The player comes out on their own (or dies / leaves). Returns the spot left.
function HidingState.leave(state: State, id: number): string?
	local spot = state.SpotOf[id]
	if spot then
		state.SpotOf[id] = nil
		state.Occupant[spot] = nil
	end
	return spot
end

-- The wolf searches a spot. Returns who was pulled out, if anyone.
function HidingState.search(state: State, spot: string): number?
	local id = state.Occupant[spot]
	if id then
		HidingState.leave(state, id)
		state.PulledOut[id] = true
	end
	return id
end

-- Everyone currently hidden (for clearing at the end of the night).
function HidingState.hiddenIds(state: State): { number }
	local ids = {}
	for id in state.SpotOf do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- A new night: nobody is hidden, everybody may hide again.
function HidingState.reset(state: State)
	table.clear(state.Occupant)
	table.clear(state.SpotOf)
	table.clear(state.PulledOut)
end

return HidingState
