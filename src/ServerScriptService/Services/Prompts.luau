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

local triggeredHandlers: { (Player) -> () } = {}

-- Called with the player whenever any "hold" prompt is completed (AFK rule).
function Prompts.onTriggered(handler: (Player) -> ())
	table.insert(triggeredHandlers, handler)
end

local actionHandlers: { (Player, ProximityPrompt) -> () } = {}

-- Called with the player and the prompt whenever any "hold" prompt is
-- completed (the Ninja's smoke ends on any action except knocking).
function Prompts.onAction(handler: (Player, ProximityPrompt) -> ())
	table.insert(actionHandlers, handler)
end

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
	prompt.Triggered:Connect(function(player: Player)
		for _, notify in triggeredHandlers do
			notify(player)
		end
		for _, notify in actionHandlers do
			notify(player, prompt)
		end
	end)
	prompt.Parent = parent
	return prompt
end

return Prompts
