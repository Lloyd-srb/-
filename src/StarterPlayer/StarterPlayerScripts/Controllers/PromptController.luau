--!strict
--[[
	PromptController — client side of the "hold E" prompts.
	- Translates prompt text from the prompt's LocKey attribute.
	- At night, shows the "open door" prompt only on the player's own house
	  (the server still validates the request).
]]

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PromptController = {}

local myHouseId = 0
local watched: { [ProximityPrompt]: boolean } = {}

-- The server enables every closed door's prompt at night ("Active"). Locally,
-- only the prompt of the player's own house stays visible.
local function filterDoorPrompt(prompt: ProximityPrompt)
	local houseId = prompt:GetAttribute("HouseId")
	if type(houseId) ~= "number" then
		return
	end
	local want = prompt:GetAttribute("Active") == true and houseId == myHouseId
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function watchDoor(door: Instance)
	local prompt = door:FindFirstChild("OpenPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		if not watched[prompt] then
			watched[prompt] = true
			local function refresh()
				filterDoorPrompt(prompt)
			end
			prompt:GetPropertyChangedSignal("Enabled"):Connect(refresh)
			prompt:GetAttributeChangedSignal("Active"):Connect(refresh)
		end
		filterDoorPrompt(prompt)
	end
end

local function refreshDoors()
	for _, door in CollectionService:GetTagged("Door") do
		watchDoor(door)
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
		myHouseId = if type(houseId) == "number" then houseId else 0
		refreshDoors()
	end)

	CollectionService:GetInstanceAddedSignal("Door"):Connect(function(door: Instance)
		task.defer(watchDoor, door)
	end)
	refreshDoors()
end

return PromptController
