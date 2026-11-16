--!strict
--[[
	BuildWolfRig — builds the werewolf from Parts (GDD §8.1): blocky, gray,
	glowing yellow eyes, big hunched shoulders and claws.

	Creates, idempotently:
	  ServerStorage.Rigs.Wolf            Motor6D rig (PrimaryPart "Root")
	  ServerStorage.Rigs.Pup             the same rig scaled down (GDD §8.2)
	  ServerStorage.WolfAnimations.*     KeyframeSequences made from
	                                     Shared.WolfAnimData, ready to publish

	At night the game welds a clone of the rig onto the wolf player's
	HumanoidRootPart and hides the R6 body, so movement, collisions and door
	sizes stay those of a normal character.

	Rig space: origin = HumanoidRootPart centre, front = -Z, ground = y -3.
	Each Motor6D is named after the part it moves (= the animation joint name).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildWolfRig: ReplicatedStorage.Shared is missing (import src/ first)")
local Config = (require :: any)((Shared :: any).Config:Clone())
local WolfAnimData = (require :: any)((Shared :: any).WolfAnimData:Clone())

local GROUND = Vector3.new(0, -3, 0)

type PartSpec = {
	Name: string,
	Size: Vector3,
	Center: Vector3,
	Color: string, -- key of Config.WolfRig
	Parent: string,
	Pivot: Vector3?, -- joint position; nil = rigidly welded to the parent
}

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function spec(name: string, size: Vector3, center: Vector3, color: string, parent: string, pivot: Vector3?): PartSpec
	return { Name = name, Size = size, Center = center, Color = color, Parent = parent, Pivot = pivot }
end

local SPECS: { PartSpec } = {
	spec("Torso", V(2.6, 2.0, 1.8), V(0, 0.6, 0.1), "Belly", "Root", V(0, -0.4, 0.1)),
	spec("Chest", V(4.4, 2.8, 2.8), V(0, 2.9, -0.5), "Fur", "Torso", V(0, 1.6, 0)),
	spec("Head", V(2.0, 1.9, 2.0), V(0, 4.3, -2.0), "Fur", "Chest", V(0, 3.9, -1.5)),
	spec("Snout", V(1.1, 0.9, 1.3), V(0, 3.95, -3.4), "FurDark", "Head"),
	spec("Nose", V(0.45, 0.35, 0.25), V(0, 4.25, -4.1), "Nose", "Head"),
	spec("Tail", V(0.7, 0.7, 2.2), V(0, 0.5, 2.0), "FurDark", "Torso", V(0, 0.5, 1.0)),
}

-- Left / right pairs: `side` is -1 for left, +1 for right.
local SIDES: { [string]: number } = { Left = -1, Right = 1 }
for prefix, side in SIDES do
	local function add(name: string, size: Vector3, center: Vector3, color: string, parent: string, pivot: Vector3?)
		local function mirrored(point: Vector3): Vector3
			return V(point.X * side, point.Y, point.Z)
		end
		local parentName = if parent == "Chest" or parent == "Torso" or parent == "Head" then parent else prefix .. parent
		table.insert(SPECS, spec(prefix .. name, size, mirrored(center), color, parentName, if pivot then mirrored(pivot) else nil))
	end

	add("Ear", V(0.5, 0.9, 0.4), V(0.7, 5.6, -1.6), "FurDark", "Head")
	add("Eye", V(0.45, 0.3, 0.12), V(0.5, 4.6, -3.02), "Eye", "Head")
	add("Shoulder", V(1.9, 1.5, 2.2), V(3.0, 4.0, -0.6), "FurDark", "Chest")
	add("UpperArm", V(1.4, 2.6, 1.4), V(3.0, 2.3, -0.6), "Fur", "Chest", V(3.0, 3.5, -0.6))
	add("LowerArm", V(1.3, 2.6, 1.3), V(3.0, -0.2, -0.6), "FurDark", "UpperArm", V(3.0, 1.0, -0.6))
	for claw = 1, 3 do
		add("Claw" .. claw, V(0.25, 0.9, 0.25), V(3.0 + (claw - 2) * 0.42, -1.9, -1.0), "Claw", "LowerArm")
	end
	add("UpperLeg", V(1.3, 1.5, 1.5), V(0.8, -0.95, 0.1), "Fur", "Torso", V(0.8, -0.3, 0.1))
	add("LowerLeg", V(1.2, 1.3, 1.3), V(0.8, -2.35, 0.1), "FurDark", "UpperLeg", V(0.8, -1.7, 0.1))
	add("Foot", V(1.3, 0.5, 2.0), V(0.8, -2.75, -0.3), "FurDark", "LowerLeg")
end

--------------------------------------------------------------------------------

local function resetFolder(name: string): Folder
	local old = ServerStorage:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ServerStorage
	return folder
end

local function buildRig(name: string, scale: number, parent: Instance): Model
	-- Scale around the ground point so the feet stay on the floor.
	local function place(point: Vector3): Vector3
		return GROUND + (point - GROUND) * scale
	end

	local rig = Instance.new("Model")
	rig.Name = name
	rig:SetAttribute("Scale", scale)

	local centers: { [string]: Vector3 } = { Root = Vector3.new(0, 0, 0) }
	local parts: { [string]: BasePart } = {}

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Transparency = 1
	parts.Root = root

	for _, item in SPECS do
		local part = Instance.new("Part")
		part.Name = item.Name
		part.Size = item.Size * scale
		part.Color = Config.WolfRig[item.Color]
		part.Material = if item.Color == "Eye" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		parts[item.Name] = part
		centers[item.Name] = place(item.Center)
		part.CFrame = CFrame.new(centers[item.Name])
	end

	for _, part in parts do
		-- A costume, not a body: it must never collide, block rays or add weight.
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.Parent = rig
	end
	rig.PrimaryPart = root

	for _, item in SPECS do
		local parentPart = parts[item.Parent]
		local childPart = parts[item.Name]
		assert(parentPart, `BuildWolfRig: {item.Name} has unknown parent {item.Parent}`)
		if item.Pivot then
			local pivot = place(item.Pivot)
			local motor = Instance.new("Motor6D")
			motor.Name = item.Name
			motor.Part0 = parentPart
			motor.Part1 = childPart
			motor.C0 = CFrame.new(pivot - centers[item.Parent])
			motor.C1 = CFrame.new(pivot - centers[item.Name])
			motor.Parent = parentPart
		else
			local weld = Instance.new("Weld")
			weld.Name = item.Name
			weld.Part0 = parentPart
			weld.Part1 = childPart
			weld.C0 = CFrame.new(centers[item.Name] - centers[item.Parent])
			weld.Parent = parentPart
		end
	end

	-- For the published animations (the fallback animator does not need it).
	local controller = Instance.new("AnimationController")
	controller.Parent = rig
	local animator = Instance.new("Animator")
	animator.Parent = controller

	rig.Parent = parent
	return rig
end

-- Pose tree mirroring the joint tree: a Pose is named after the part it moves.
local function buildKeyframeSequence(name: string, animation: any, parent: Instance)
	local children: { [string]: { string } } = {}
	for _, item in SPECS do
		if item.Pivot then
			children[item.Parent] = children[item.Parent] or {}
			table.insert(children[item.Parent], item.Name)
		end
	end

	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = animation.Loop
	sequence.Priority = (Enum.AnimationPriority :: any)[animation.Priority]

	local function addPoses(partName: string, poseParent: Instance, t: number)
		local names: { string } = children[partName] or {}
		for _, childName in names do
			local pose = Instance.new("Pose")
			pose.Name = childName
			pose.CFrame = WolfAnimData.pose(animation, childName, t)
			pose.Weight = 1
			pose.Parent = poseParent
			addPoses(childName, pose, t)
		end
	end

	for _, t in WolfAnimData.keyTimes(animation) do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = t
		local rootPose = Instance.new("Pose")
		rootPose.Name = "Root"
		rootPose.Weight = 0
		rootPose.Parent = keyframe
		addPoses("Root", rootPose, t)
		keyframe.Parent = sequence
	end

	sequence.Parent = parent
end

local rigs = resetFolder("Rigs")
buildRig("Wolf", 1, rigs)
buildRig("Pup", Config.Pup.Scale, rigs)

local animations = resetFolder("WolfAnimations")
local count = 0
for name, animation in WolfAnimData.Animations do
	buildKeyframeSequence("Wolf" .. name, animation, animations)
	count += 1
end

print(string.format("[BuildWolfRig] done: 2 rigs (%d parts each), %d animations", #SPECS + 1, count))
