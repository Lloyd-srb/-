--!strict
--[[
	Aim — which way is this player pointing? Used for the stun gun (Sheriff and
	gun item) and the thrown axe.
	  - mouse / touch: towards what is under the pointer (last tap on mobile)
	  - gamepad: towards what is in the middle of the screen
	Returns a unit direction from the character's shooting height.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Aim = {}

local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4
end

function Aim.direction(range: number): Vector3?
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not character or not (root and root:IsA("BasePart")) then
		return nil
	end
	local screenPoint = if usingGamepad() then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * (range * 2), params)
	local target = if hit then hit.Position else ray.Origin + ray.Direction * range
	local muzzle = root.Position + Vector3.new(0, Config.Abilities.Sheriff.MuzzleHeight, 0)
	local direction = target - muzzle
	return if direction.Magnitude > 1e-3 then direction.Unit else nil
end

return Aim
