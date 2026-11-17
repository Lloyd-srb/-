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

--[[
	Who does a shot hit? Casts a ray and returns the id of the first living
	member's body in its way (nil if it hits scenery, a corpse or nothing).
	Wolf costumes do not stop rays, the character underneath does.
]]
function Sight.firstBody(origin: Vector3, ray: Vector3, exclude: Instance?): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local result = workspace:Raycast(origin, ray, params)
	local instance: Instance? = if result then result.Instance else nil
	while instance do
		if instance:HasTag("MemberBody") then
			local id = instance:GetAttribute("MemberId")
			if instance:GetAttribute("Corpse") or type(id) ~= "number" then
				return nil
			end
			return id
		end
		instance = instance.Parent
	end
	return nil
end

return Sight
