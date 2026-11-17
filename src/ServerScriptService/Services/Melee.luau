--!strict
--[[
	Melee — server-side target picking for close-range attacks (wolf claws,
	the Killer's knife, later the shovel). The client only says "I swing";
	the server chooses who, if anyone, is hit: the nearest valid member in
	front of the attacker, within range, with nothing solid in between.
	Hidden players and corpses can never be hit.
]]

local Roster = require(script.Parent.Parent.Logic.Roster)

local HidingService = require(script.Parent.HidingService)
local MatchService = require(script.Parent.MatchService)
local Sight = require(script.Parent.Sight)

local Melee = {}

function Melee.findTarget(
	attackerId: number,
	range: number,
	minDot: number,
	canHit: (member: Roster.Member) -> boolean
): Roster.Member?
	local attackerRoot = MatchService.RootOf(attackerId)
	if not attackerRoot then
		return nil
	end
	local origin = attackerRoot.CFrame.Position
	local look = attackerRoot.CFrame.LookVector
	local best: Roster.Member? = nil
	local bestDistance = range
	for _, member in Roster.alive(MatchService.Roster) do
		if member.Id == attackerId or HidingService.IsHidden(member.Id) or not canHit(member) then
			continue
		end
		local root = MatchService.RootOf(member.Id)
		if root then
			local offset = root.CFrame.Position - origin
			local distance = offset.Magnitude
			local facing = distance < 1 or offset.Unit:Dot(look) >= minDot
			if distance <= bestDistance and facing and Sight.isClear(origin, root.CFrame.Position) then
				best = member
				bestDistance = distance
			end
		end
	end
	return best
end

return Melee
