--!strict
--[[
	PromptController — client side of the "hold E" prompts.
	- Translates prompt text from the prompt's LocKey attribute.
	- Shows each prompt only to its audience (the server still validates
	  every use):
	    "Owner"  the occupant of that house tonight (open door)
	    "Human"  human form (hide)
	    "Wolf"   wolf / pup form (search)
	  The server marks usable prompts with the "Active" attribute; this script
	  switches Enabled locally for prompts that are not meant for this player.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local PromptController = {}

local watched: { [ProximityPrompt]: boolean } = {}

local function isForMe(prompt: ProximityPrompt, audience: string): boolean
	if not ClientState.Alive then
		return false -- ghosts cannot use anything
	end
	if audience == "Alive" then
		return true
	elseif audience == "Owner" then
		return prompt:GetAttribute("HouseId") == ClientState.HouseId
	elseif audience == "Human" then
		return ClientState.Form == "Human" and ClientState.Alive and not ClientState.Hidden
	elseif audience == "Wolf" then
		return ClientState.Form ~= "Human"
	elseif audience:sub(1, 5) == "Task:" then
		-- Only the steps this player's own task still needs.
		local task = ClientState.Task
		local target = prompt:GetAttribute("TargetId")
		return task ~= nil
			and task.Kind == audience:sub(6)
			and not task.Complete
			and task.Targets[target] == true
			and not task.Done[target]
			and ClientState.Form == "Human"
			and ClientState.Alive
			and not ClientState.Hidden
	elseif audience:sub(1, 5) == "Role:" then
		-- e.g. "Role:Doctor": only that role, in human form, alive, not hiding
		return ClientState.Role == audience:sub(6)
			and ClientState.Form == "Human"
			and ClientState.Alive
			and not ClientState.Hidden
	end
	return true
end

local function filter(prompt: ProximityPrompt)
	local audience = prompt:GetAttribute("Audience")
	if type(audience) ~= "string" then
		return
	end
	local want = prompt:GetAttribute("Active") == true and isForMe(prompt, audience)
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function watch(instance: Instance)
	if not instance:IsA("ProximityPrompt") or watched[instance] then
		return
	end
	watched[instance] = true
	local function refresh()
		filter(instance)
	end
	instance:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	instance:GetAttributeChangedSignal("Active"):Connect(refresh)
	instance:GetAttributeChangedSignal("Audience"):Connect(refresh)
	instance.Destroying:Connect(function()
		watched[instance] = nil
	end)
	filter(instance)
end

local function refreshAll()
	for prompt in watched do
		filter(prompt)
	end
end

function PromptController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local key = prompt:GetAttribute("LocKey")
		if type(key) == "string" and Loc.has(key) then
			prompt.ActionText = Loc.format(key)
		end
	end)

	Remotes.get("HouseAssigned").OnClientEvent:Connect(function(houseId: any)
		ClientState.set("HouseId", if type(houseId) == "number" then houseId else 0)
	end)
	ClientState.Changed:Connect(refreshAll)

	workspace.DescendantAdded:Connect(function(instance: Instance)
		task.defer(watch, instance)
	end)
	for _, instance in workspace:GetDescendants() do
		watch(instance)
	end
end

return PromptController
