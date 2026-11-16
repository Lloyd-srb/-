--!strict
--[[
	Prompts — creates "hold E" ProximityPrompts (PC / mobile / console).
	The English text is the fallback; clients localize it from the LocKey
	attribute (see PromptController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)

local Prompts = {}

function Prompts.create(parent: Instance, name: string, locKey: string, holdDuration: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = if Strings[locKey] then Strings[locKey].en else locKey
	prompt.ObjectText = ""
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = Config.Human.InteractDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("LocKey", locKey)
	prompt.Parent = parent
	return prompt
end

return Prompts
