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

local function paint(ghost: Instance)
	local visible = not ClientState.Alive
	for _, instance in ghost:GetDescendants() do
		if instance:IsA("BasePart") and instance.Name ~= "HumanoidRootPart" then
			instance.Transparency = if visible then GHOST_TRANSPARENCY else 1
		elseif instance:IsA("Decal") then
			instance.Transparency = if visible then GHOST_TRANSPARENCY else 1
		end
	end
end

local function paintAll()
	for _, ghost in CollectionService:GetTagged("Ghost") do
		paint(ghost)
	end
end

function GhostController.Start()
	CollectionService:GetInstanceAddedSignal("Ghost"):Connect(function(ghost: Instance)
		-- Parts may still be arriving: paint now and once more a moment later.
		paint(ghost)
		task.delay(0.5, paint, ghost)
	end)
	ClientState.Changed:Connect(function(key: string)
		if key == "Alive" then
			paintAll()
		end
	end)
	paintAll()
end

return GhostController
