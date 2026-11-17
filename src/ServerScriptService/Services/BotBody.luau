--!strict
--[[
	BotBody — a simple anchored dummy for debug bots (Studio testing only), so
	a lone developer has something to chase, attack and vote out. It has a
	Humanoid and a HumanoidRootPart like a real character, but never moves by
	itself.
]]

local BotBody = {}

local SKIN = Color3.fromRGB(240, 200, 160)
local RING_RADIUS = 22 -- bots wait on a ring inside the plaza

local function part(name: string, size: Vector3, offset: Vector3, color: Color3, parent: Model): Part
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Size = size
	instance.CFrame = CFrame.new(offset)
	instance.Color = color
	instance.Anchored = true
	instance.Material = Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Parent = parent
	return instance
end

-- `at` places the body somewhere specific (a revived bot); otherwise it
-- takes its seat on the ring.
function BotBody.create(name: string, seat: number, seats: number, at: Vector3?): Model
	local body = Instance.new("Model")
	body.Name = name

	local angle = seat / seats * math.pi * 2
	local origin = at or Vector3.new(math.sin(angle) * RING_RADIUS, 3, -math.cos(angle) * RING_RADIUS)
	local shirt = Color3.fromHSV((seat * 0.17) % 1, 0.45, 0.9)

	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), origin, shirt, body)
	root.Transparency = 1
	root.CanCollide = false
	part("Torso", Vector3.new(2, 2, 1), origin, shirt, body)
	part("Head", Vector3.new(1.2, 1.2, 1.2), origin + Vector3.new(0, 1.6, 0), SKIN, body)
	part("Legs", Vector3.new(2, 2, 1), origin + Vector3.new(0, -2, 0), Color3.fromRGB(70, 80, 110), body)
	body.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = name
	humanoid.Parent = body

	body:SetAttribute("IsBot", true)
	body.Parent = workspace
	return body
end

return BotBody
