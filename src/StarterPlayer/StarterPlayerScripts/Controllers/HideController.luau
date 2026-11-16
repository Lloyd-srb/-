--!strict
--[[
	HideController — what a hidden player sees and does (GDD §6.4).
	While hidden, the player's real body is parked far away by the server; the
	camera sits inside the hiding spot looking out, and one button brings the
	player back out.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local EXIT_ACTION = "HideExit"

local HideController = {}

local function attachmentPosition(anchor: BasePart, name: string): Vector3
	local attachment = anchor:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldPosition
	end
	return anchor.Position
end

local function enter(anchor: BasePart)
	ClientState.set("Hidden", true)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		-- Peek out of the spot towards the room.
		camera.CFrame = CFrame.lookAt(attachmentPosition(anchor, "HideSpot"), attachmentPosition(anchor, "ExitSpot"))
	end
	ContextActionService:BindAction(EXIT_ACTION, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			Remotes.get("HideExit"):FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(EXIT_ACTION, Loc.format("Prompt.LeaveHiding"))
	ContextActionService:SetPosition(EXIT_ACTION, UDim2.new(1, -150, 1, -150))
end

local function leave()
	ClientState.set("Hidden", false)
	ContextActionService:UnbindAction(EXIT_ACTION)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function HideController.Start()
	Remotes.get("HideChanged").OnClientEvent:Connect(function(anchor: any)
		if typeof(anchor) == "Instance" and anchor:IsA("BasePart") then
			enter(anchor)
		else
			leave()
		end
	end)
end

return HideController
