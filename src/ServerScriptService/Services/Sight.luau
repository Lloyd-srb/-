--!strict
--[[
	Sight — server-side line-of-sight check, so melee hits cannot pass through
	walls and closed doors. Characters themselves never block the ray.
]]

local CollectionService = game:GetService("CollectionService")

local Sight = {}

-- True when nothing solid lies between the two points.
function Sight.isClear(from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged("MemberBody")
	params.RespectCanCollide = true
	return workspace:Raycast(from, to - from, params) == nil
end

return Sight
