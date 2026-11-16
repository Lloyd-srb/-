--!strict
--[[
	LightingService — day / night look (GDD §6.5): bright by day, dark with
	black distance fog at night. Tweens between Config.Lighting presets and
	switches the lanterns and house lamps on for the night.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)

local RoundService = require(script.Parent.RoundService)

local MIDNIGHT = 24

local LightingService = {}

local isNightLook = false

local function setLamps(enabled: boolean)
	for _, tag in { "HouseLamp", "PlazaLamp" } do
		for _, lamp in CollectionService:GetTagged(tag) do
			local light = lamp:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = enabled
			end
		end
	end
end

local function apply(night: boolean)
	if night == isNightLook then
		return
	end
	isNightLook = night

	local preset = if night then Config.Lighting.Night else Config.Lighting.Day
	local info = TweenInfo.new(Config.Lighting.TransitionTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Always move the clock forwards: afternoon -> midnight (24), then 0 -> afternoon.
	Lighting.ClockTime = Lighting.ClockTime % MIDNIGHT
	local clockGoal = if night then MIDNIGHT else preset.ClockTime
	local tween = TweenService:Create(Lighting, info, {
		ClockTime = clockGoal,
		Brightness = preset.Brightness,
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		FogColor = preset.FogColor,
		FogStart = preset.FogStart,
		FogEnd = preset.FogEnd,
		ExposureCompensation = preset.ExposureCompensation,
	})
	tween:Play()

	local color = Lighting:FindFirstChild("PhaseColor")
	if color and color:IsA("ColorCorrectionEffect") then
		TweenService:Create(color, info, {
			Saturation = preset.Saturation,
			Contrast = preset.Contrast,
			TintColor = preset.TintColor,
		}):Play()
	end

	setLamps(night)
end

function LightingService.Init()
	if Lighting:FindFirstChildOfClass("Atmosphere") then
		warn("[LightingService] an Atmosphere overrides the night fog: run build/BuildLighting.luau in Studio")
	end
end

function LightingService.Start()
	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Night" then
			apply(true)
		elseif state.Phase == "Day" then
			apply(false)
		end
	end)
end

return LightingService
