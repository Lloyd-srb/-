--!strict
--[[
	ShellAnimator — animates every werewolf rig this client can see.

	This is the fallback animator used until the owner publishes the
	KeyframeSequences (Config.Animations ids are 0): it plays the same data
	(Shared.WolfAnimData) by posing the rig locally each frame.
	  - Attack / Maul / Howl are started by the server (shell attributes
	    "Anim" + "AnimAt").
	  - Idle / Walk / Run follow the character's actual speed.
	  - Swim when the shell is "Submerged" (The Lurker in the water channel).
	  - The Lurker invisible ("Vanished"): its own player still sees it faintly.

	Two kinds of rig are supported:
	  - the block rig (build/BuildWolfRig.luau): one Motor6D per joint;
	  - an imported skinned mesh (build/BuildWolfMesh.luau): Bones, driven
	    through Shared.BoneRetarget.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BoneRetarget = require(ReplicatedStorage.Shared.BoneRetarget)
local Config = require(ReplicatedStorage.Shared.Config)
local WolfAnimData = require(ReplicatedStorage.Shared.WolfAnimData)

local BLEND_RATE = 14 -- higher = snappier transitions between animations
local MOVING_SPEED = 1

type Rig = {
	Scale: number,
	Current: { [string]: CFrame }, -- blended pose per joint
	Motors: { [string]: { Motor: Motor6D, Base: CFrame } }?, -- block rig
	Bones: { [string]: Bone }?, -- skinned mesh
	Prepared: BoneRetarget.Prepared?,
}

local ShellAnimator = {}

local rigs: { [Instance]: Rig } = {}

-- Reads the skeleton of an imported mesh into rig space (the shell's Root part).
local function readSkeleton(shell: Model, root: BasePart): ({ BoneRetarget.BoneDef }, { [string]: Bone })
	local defs: { BoneRetarget.BoneDef } = {}
	local bones: { [string]: Bone } = {}
	-- GetDescendants lists parents before their children.
	for _, instance in shell:GetDescendants() do
		if instance:IsA("Bone") and not bones[instance.Name] then
			local parent = instance.Parent
			local def: BoneRetarget.BoneDef
			if parent and parent:IsA("Bone") then
				def = { Name = instance.Name, Parent = parent.Name, RestLocal = instance.CFrame }
			else
				local holder = if parent and parent:IsA("BasePart") then parent.CFrame else root.CFrame
				def = { Name = instance.Name, Parent = nil, RestLocal = root.CFrame:ToObjectSpace(holder * instance.CFrame) }
			end
			table.insert(defs, def)
			bones[instance.Name] = instance
		end
	end
	return defs, bones
end

local function register(shell: Instance)
	if rigs[shell] or not shell:IsA("Model") then
		return
	end
	local scale = shell:GetAttribute("Scale")
	local rig: Rig = { Scale = if type(scale) == "number" then scale else 1, Current = {} }

	local motors = {}
	local found = false
	for _, motor in shell:GetDescendants() do
		if motor:IsA("Motor6D") and table.find(WolfAnimData.Joints, motor.Name) then
			motors[motor.Name] = { Motor = motor, Base = motor.C0 }
			found = true
		end
	end

	if found then
		rig.Motors = motors
	else
		local root = shell.PrimaryPart
		if not root then
			return
		end
		local defs, bones = readSkeleton(shell, root)
		if #defs == 0 then
			return
		end
		local prepared = BoneRetarget.prepare(defs, Config.WolfRig.Mesh)
		if #prepared.Missing > 0 then
			warn("[ShellAnimator] wolf mesh is missing bones: " .. table.concat(prepared.Missing, ", "))
		end
		rig.Bones = bones
		rig.Prepared = prepared
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

	-- The Lurker in the water slithers (one-shot attacks above still win).
	if shell:GetAttribute("Submerged") then
		return animations.Swim, os.clock()
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

local VANISHED_SELF = 0.75 -- how see-through the invisible Lurker looks to its own player

local function step(deltaTime: number)
	local blend = 1 - math.exp(-deltaTime * BLEND_RATE)
	local me = Players.LocalPlayer.Character
	for shell, rig in rigs do
		-- Swimming is silent: mute the footsteps under a submerged Lurker.
		local character = shell.Parent
		local body = character and character:FindFirstChild("HumanoidRootPart")
		local running = body and body:FindFirstChild("Running")
		if running and running:IsA("Sound") then
			if shell:GetAttribute("Submerged") then
				if running:GetAttribute("DryVolume") == nil then
					running:SetAttribute("DryVolume", running.Volume)
				end
				running.Volume = 0
			elseif running:GetAttribute("DryVolume") ~= nil then
				running.Volume = running:GetAttribute("DryVolume") :: number
				running:SetAttribute("DryVolume", nil)
			end
		end
		-- Invisible to everyone else; faintly visible to itself (local only).
		if me and shell.Parent == me and me:GetAttribute("Vanished") then
			for _, part in shell:GetDescendants() do
				if part:IsA("BasePart") and part.Transparency >= 1 and part:GetAttribute("ShellTransparency") ~= nil then
					local original = part:GetAttribute("ShellTransparency") :: number
					if original < 1 then
						part.Transparency = math.max(original, VANISHED_SELF)
					end
				end
			end
		end
		local animation, t = currentAnimation(shell)
		for _, joint in WolfAnimData.Joints do
			local target = WolfAnimData.pose(animation, joint, t, rig.Scale)
			rig.Current[joint] = (rig.Current[joint] or CFrame.new()):Lerp(target, blend)
		end

		if rig.Motors then
			for joint, entry in rig.Motors do
				entry.Motor.C0 = entry.Base * rig.Current[joint]
			end
		elseif rig.Bones and rig.Prepared then
			local transforms = BoneRetarget.solve(rig.Prepared, rig.Current)
			for name, bone in rig.Bones do
				local transform = transforms[name]
				if transform then
					bone.Transform = transform
				end
			end
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
