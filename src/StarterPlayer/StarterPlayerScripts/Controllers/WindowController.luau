--!strict
--[[
	WindowController — one-way windows (GDD §5).
	Window panes are opaque for everybody (that is what the server replicates).
	This client makes a pane see-through only while its own character stands
	inside that house (or, while hiding, its camera is in there), so people
	inside can look out but nobody can look in.
	Panes are only touched when the house changes or a new pane appears.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local ClientState = require(script.Parent.ClientState)

local CHECK_INTERVAL = 0.2
local INSIDE_TRANSPARENCY = 0.75

local WindowController = {}

-- Where "I" am: the body, or the camera while hidden (the body is parked
-- far away then, see HidingService).
local function viewPoint(): Vector3?
	if ClientState.Hidden then
		local camera = workspace.CurrentCamera
		return if camera then camera.CFrame.Position else nil
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.CFrame.Position else nil
end

local function currentHouseId(): number?
	local point = viewPoint()
	if not point then
		return nil
	end
	for _, zone in CollectionService:GetTagged("HouseInterior") do
		if zone:IsA("BasePart") and Zones.isInsideBox(zone.CFrame, zone.Size, point) then
			local id = zone:GetAttribute("HouseId")
			return if type(id) == "number" then id else nil
		end
	end
	return nil
end

local function paint(pane: Instance, inside: number?)
	if pane:IsA("BasePart") then
		local mine = inside ~= nil and pane:GetAttribute("HouseId") == inside
		pane.Transparency = if mine then INSIDE_TRANSPARENCY else 0
	end
end

function WindowController.Start()
	local shown: number? = nil
	CollectionService:GetInstanceAddedSignal("OneWayWindow"):Connect(function(pane: Instance)
		paint(pane, shown)
	end)
	task.spawn(function()
		while true do
			local inside = currentHouseId()
			if inside ~= shown then
				shown = inside
				for _, pane in CollectionService:GetTagged("OneWayWindow") do
					paint(pane, inside)
				end
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return WindowController
