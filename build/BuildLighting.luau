--!strict
--[[
	BuildLighting — sets up Lighting for the Match place and applies the Day
	preset from Config.Lighting. Run in Studio after Config exists. Idempotent.

	Night uses classic black distance fog (Lighting.FogColor / FogEnd), which only
	works when there is no Atmosphere instance, so any Atmosphere is removed.
	The lighting service tweens between Config.Lighting.Day and .Night at runtime.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildLighting: ReplicatedStorage.Shared is missing (import src/ first)")
local Config = (require :: any)((Shared :: any).Config:Clone())
local Day = Config.Lighting.Day

for _, name in { "Atmosphere", "PhaseColor", "Sky", "Bloom", "SunRays", "DepthOfField" } do
	local existing = Lighting:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

Lighting.ClockTime = Day.ClockTime
Lighting.Brightness = Day.Brightness
Lighting.Ambient = Day.Ambient
Lighting.OutdoorAmbient = Day.OutdoorAmbient
Lighting.FogColor = Day.FogColor
Lighting.FogStart = Day.FogStart
Lighting.FogEnd = Day.FogEnd
Lighting.ExposureCompensation = Day.ExposureCompensation
Lighting.GlobalShadows = true
Lighting.GeographicLatitude = 30

local color = Instance.new("ColorCorrectionEffect")
color.Name = "PhaseColor"
color.Saturation = Day.Saturation
color.Contrast = Day.Contrast
color.TintColor = Day.TintColor
color.Parent = Lighting

local sky = Instance.new("Sky")
sky.Name = "Sky"
sky.StarCount = 3000
sky.MoonAngularSize = 16 -- big full moon
sky.SunAngularSize = 14
sky.CelestialBodiesShown = true
sky.Parent = Lighting

print("[BuildLighting] done")
