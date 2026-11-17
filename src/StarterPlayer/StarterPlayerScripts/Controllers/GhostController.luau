--!strict
--[[
	GhostController — who can see ghosts (GDD §12).
	Ghost bodies are fully transparent for everyone (set by the server). Only
	when this player is dead does this client make ghosts — including its own —
	faintly visible. Living players never see them.
]]

local CollectionService = game:GetService("CollectionService")

local ClientState = require(script.Parent.ClientState)

local GHOST_TRANSPARENCY = 0.6

local GhostController = {}

local function paintPiece(instance: Instance)
	local transparency = if ClientState.Alive then 1 else GHOST_TRANSPARENCY
	if instance:IsA("BasePart") and instance.Name ~= "HumanoidRootPart" then
		instance.Transparency = transparency
	elseif instance:IsA("Decal") then
		instance.Transparency = transparency
	end
end

local function paint(ghost: Instance)
	for _, instance in ghost:GetDescendants() do
		paintPiece(instance)
	end
end

local function paintAll()
	for _, ghost in CollectionService:GetTagged("Ghost") do
		paint(ghost)
	end
end

function GhostController.Start()
	local function track(ghost: Instance)
		-- Parts (hats, hair) may still be arriving.
		paint(ghost)
		ghost.DescendantAdded:Connect(paintPiece)
	end
	CollectionService:GetInstanceAddedSignal("Ghost"):Connect(track)
	for _, ghost in CollectionService:GetTagged("Ghost") do
		track(ghost)
	end
	ClientState.Changed:Connect(function(key: string)
		if key == "Alive" then
			paintAll()
		end
	end)
end

return GhostController
