--!strict
--[[
	Zones — pure position checks shared by server and client.
	The fence circle splits the map into "village" (inside) and "forest"
	(outside), see GDD §5.
]]

local Config = require(script.Parent.Config)

local Zones = {}

-- Horizontal distance from the map centre.
function Zones.flatRadius(position: Vector3): number
	return math.sqrt(position.X * position.X + position.Z * position.Z)
end

function Zones.isVillage(position: Vector3): boolean
	-- World CFrame of an attachment (same value as Attachment.WorldCFrame).
function Zones.worldCFrame(attachment: Attachment): CFrame
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return parent.CFrame * attachment.CFrame
	end
	return attachment.CFrame
end

return Zones.flatRadius(position) < Config.Map.FenceRadius
end

function Zones.isForest(position: Vector3): boolean
	return not Zones.isVillage(position)
end

-- Is `point` inside the box described by a part's CFrame and Size?
function Zones.isInsideBox(cframe: CFrame, size: Vector3, point: Vector3): boolean
	local localPoint = cframe:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= size.X / 2
		and math.abs(localPoint.Y) <= size.Y / 2
		and math.abs(localPoint.Z) <= size.Z / 2
end

-- World CFrame of an attachment (same value as Attachment.WorldCFrame).
function Zones.worldCFrame(attachment: Attachment): CFrame
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return parent.CFrame * attachment.CFrame
	end
	return attachment.CFrame
end

return Zones
