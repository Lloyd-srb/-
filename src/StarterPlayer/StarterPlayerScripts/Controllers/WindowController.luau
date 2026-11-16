--!strict
--[[
	WindowController — one-way windows (GDD §5).
	Window panes are opaque for everybody (that is what the server replicates).
	This client makes a pane see-through only while its own character stands
	inside that house, so people inside can look out but nobody can look in.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local CHECK_INTERVAL = 0.2
local INSIDE_TRANSPARENCY = 0.75

local WindowController = {}

local function currentHouseId(): number?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	for _, zone in CollectionService:GetTagged("HouseInterior") do
		if zone:IsA("BasePart") and Zones.isInsideBox(zone.CFrame, zone.Size, root.CFrame.Position) then
			local id = zone:GetAttribute("HouseId")
			return if type(id) == "number" then id else nil
		end
	end
	return nil
end

function WindowController.Start()
	task.spawn(function()
		while true do
			local inside = currentHouseId()
			for _, pane in CollectionService:GetTagged("OneWayWindow") do
				if pane:IsA("BasePart") then
					local mine = inside ~= nil and pane:GetAttribute("HouseId") == inside
					pane.Transparency = if mine then INSIDE_TRANSPARENCY else 0
				end
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return WindowController
