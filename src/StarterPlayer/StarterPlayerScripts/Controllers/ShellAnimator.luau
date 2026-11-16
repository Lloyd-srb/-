--!strict
--[[
	ShellAnimator — animates every werewolf rig this client can see.

	This is the fallback animator used until the owner publishes the
	KeyframeSequences (Config.Animations ids are 0): it plays the same data
	(Shared.WolfAnimData) by posing the rig's Motor6Ds locally each frame.
	  - Attack / Maul / Howl are started by the server (shell attributes
	    "Anim" + "AnimAt").
	  - Idle / Walk / Run follow the character's actual speed.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local WolfAnimData = require(ReplicatedStorage.Shared.WolfAnimData)

local BLEND_RATE = 14 -- higher = snappier transitions between animations
local MOVING_SPEED = 1

type Joint = { Motor: Motor6D, Base: CFrame, Current: CFrame }
type Rig = { Scale: number, Joints: { [string]: Joint } }

local ShellAnimator = {}

local rigs: { [Instance]: Rig } = {}

local function register(shell: Instance)
	if rigs[shell] then
		return
	end
	local scale = shell:GetAttribute("Scale")
	local rig: Rig = { Scale = if type(scale) == "number" then scale else 1, Joints = {} }
	for _, motor in shell:GetDescendants() do
		if motor:IsA("Motor6D") and table.find(WolfAnimData.Joints, motor.Name) then
			rig.Joints[motor.Name] = { Motor = motor, Base = motor.C0, Current = CFrame.new() }
		end
	end
	rigs[shell] = rig
end

-- Which animation, and at what time, should this shell show right now?
local function currentAnimation(shell: Instance): (WolfAnimData.Animation, number)
	local animations = WolfAnimData.Animations
	local name = shell:GetAttribute("Anim")
	local startedAt = shell:GetAttribute("AnimAt")
	if type(name) == "string" and type(startedAt) == "number" then
		local oneShot = animations[name]
		local elapsed = workspace:GetServerTimeNow() - startedAt
		if oneShot and not oneShot.Loop and elapsed >= 0 and elapsed < oneShot.Length then
			return oneShot, elapsed
		end
	end

	local speed = 0
	local character = shell.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end
	local now = os.clock()
	if speed > Config.WolfRig.RunSpeedThreshold then
		return animations.Run, now
	elseif speed > MOVING_SPEED then
		return animations.Walk, now
	end
	return animations.Idle, now
end

local function step(deltaTime: number)
	local blend = 1 - math.exp(-deltaTime * BLEND_RATE)
	for shell, rig in rigs do
		local animation, t = currentAnimation(shell)
		for name, joint in rig.Joints do
			local target = WolfAnimData.pose(animation, name, t, rig.Scale)
			joint.Current = joint.Current:Lerp(target, blend)
			joint.Motor.C0 = joint.Base * joint.Current
		end
	end
end

function ShellAnimator.Start()
	CollectionService:GetInstanceAddedSignal("WolfShell"):Connect(function(shell: Instance)
		-- Wait a moment so the whole rig has replicated before reading its joints.
		task.delay(0.2, register, shell)
	end)
	CollectionService:GetInstanceRemovedSignal("WolfShell"):Connect(function(shell: Instance)
		rigs[shell] = nil
	end)
	for _, shell in CollectionService:GetTagged("WolfShell") do
		register(shell)
	end
	RunService.RenderStepped:Connect(step)
end

return ShellAnimator
