--!strict
--[[
	Ragdoll — turns a character into a corpse lying where it died (GDD §6.4).
	The body stays in the world (the Doctor can revive it, milestone 4) and is
	flagged with the "Corpse" attribute / tag so it no longer counts as a
	living character.
]]

local Ragdoll = {}

function Ragdoll.apply(body: Model)
	body:SetAttribute("Corpse", true)
	body:AddTag("Corpse")

	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = false
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local joints = 0
	for _, motor in body:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 45
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -30
			socket.TwistUpperAngle = 30
			socket.Parent = motor.Part0
			motor.Enabled = false
			joints += 1
		end
	end

	-- Jointless bodies (debug bots) are simply laid on their back.
	local root = body:FindFirstChild("HumanoidRootPart")
	if joints == 0 and root and root:IsA("BasePart") then
		body:PivotTo(CFrame.new(root.CFrame.Position - Vector3.new(0, 2, 0)) * CFrame.Angles(math.rad(90), 0, 0))
	end

	-- The dead player's client must not keep simulating (and moving) the body.
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end
end

return Ragdoll
