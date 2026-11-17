--!strict
--[[
	Flashlight — the light shared by the Villager's flashlight (GDD §9) and the
	flashlight item (GDD §11). A real SpotLight on the character, so everyone
	sees where the beam points.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Flashlight = {}

-- Turns the character's flashlight on / off. Returns the new state.
function Flashlight.toggle(character: Model): boolean?
	local holder = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not holder then
		return nil
	end
	local light = holder:FindFirstChild("Flashlight")
	if not light then
		local cfg = Config.Items.Flashlight
		local spot = Instance.new("SpotLight")
		spot.Name = "Flashlight"
		spot.Face = Enum.NormalId.Front
		spot.Range = cfg.Range
		spot.Angle = cfg.Angle
		spot.Brightness = cfg.Brightness
		spot.Shadows = true
		spot.Enabled = false
		spot.Parent = holder
		light = spot
	end
	if light and light:IsA("SpotLight") then
		light.Enabled = not light.Enabled
		character:SetAttribute("FlashlightOn", light.Enabled)
		return light.Enabled
	end
	return nil
end

return Flashlight
