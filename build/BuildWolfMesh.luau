--!strict
--[[
	BuildWolfMesh — OPTIONAL. Uses the owner's imported wolf model (the
	"Moonfang Stalker" mesh, source file in assets/wolf/) instead of the block
	rig. Run it in Studio AFTER build/BuildWolfRig.luau; it replaces
	ServerStorage.Rigs.Wolf and .Pup. Idempotent.

	Before running: import the FBX with Studio's 3D Importer (see
	docs/OWNER_TODO.md) and put the imported model at
	ServerStorage.Imports.WolfMesh. Without it this script does nothing and
	the game keeps using the block rig.

	What it does to a copy of the imported model:
	  - scales it to Config.WolfRig.Height (the pup: x Config.Pup.Scale);
	  - adds an invisible "Root" part at HumanoidRootPart height, turned so the
	    model faces the same way as the character (found from the feet bones);
	  - makes every part a costume: no collisions, no mass, welded to Root.
	Animation is done by the client (ShellAnimator + Shared.BoneRetarget).

	NOT VERIFIED OFFLINE: this script needs engine functions (GetBoundingBox,
	ScaleTo, Bone.WorldPosition) that only exist in Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildWolfMesh: ReplicatedStorage.Shared is missing (import src/ first)")
local Config = (require :: any)((Shared :: any).Config:Clone())
local BoneRetarget = (require :: any)((Shared :: any).BoneRetarget:Clone())

local ROOT_HEIGHT = 3 -- HumanoidRootPart centre above the ground (R6)

local MeshCfg = Config.WolfRig.Mesh
local imports = ServerStorage:FindFirstChild("Imports")
local source = imports and imports:FindFirstChild(MeshCfg.ImportName)

local function findBone(rig: Model, short: string): Bone?
	for _, instance in rig:GetDescendants() do
		if instance:IsA("Bone") and (instance.Name == short or instance.Name:sub(-#short - 1) == ":" .. short) then
			return instance
		end
	end
	return nil
end

local function prepare(name: string, scale: number, parent: Instance): Model
	local rig = (source :: Model):Clone()
	rig.Name = name

	-- Size: ground to the top of the head = Config.WolfRig.Height x scale.
	local _, size = rig:GetBoundingBox()
	rig:ScaleTo(rig:GetScale() * (Config.WolfRig.Height * scale) / size.Y)

	-- Facing: the average toe direction of both feet.
	local forward = Vector3.new(0, 0, 0)
	for _, pair in MeshCfg.Feet do
		local foot, toe = findBone(rig, pair[1]), findBone(rig, pair[2])
		assert(foot and toe, `BuildWolfMesh: bones {pair[1]} / {pair[2]} not found in the imported model`)
		forward += toe.WorldPosition - foot.WorldPosition
	end
	forward = Vector3.new(forward.X, 0, forward.Z).Unit

	-- Root sits where the character's HumanoidRootPart will be: above the hips,
	-- 3 studs over the soles, looking the way the model faces.
	local boxCFrame, boxSize = rig:GetBoundingBox()
	local hips = findBone(rig, MeshCfg.Joints.Torso)
	local centre = if hips then hips.WorldPosition else boxCFrame.Position
	local ground = boxCFrame.Position.Y - boxSize.Y / 2
	local rootPosition = Vector3.new(centre.X, ground + ROOT_HEIGHT, centre.Z)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.lookAt(rootPosition, rootPosition + forward)

	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = true -- stun shots hit the costume, not just the small body inside
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Massless = true
	root.Parent = rig
	rig.PrimaryPart = root

	rig:SetAttribute("Scale", scale)
	rig:SetAttribute("RigKind", "Mesh")
	rig.Parent = parent
	return rig
end

if not (source and source:IsA("Model")) then
	print(`[BuildWolfMesh] skipped: ServerStorage.Imports.{MeshCfg.ImportName} not found (the block rig stays in use)`)
else
	local rigs = ServerStorage:FindFirstChild("Rigs")
	if not rigs then
		rigs = Instance.new("Folder")
		rigs.Name = "Rigs"
		rigs.Parent = ServerStorage
	end
	for _, name in { "Wolf", "Pup" } do
		local old = rigs:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local wolf = prepare("Wolf", 1, rigs)
	prepare("Pup", Config.Pup.Scale, rigs)

	-- Report bones the animation mapping expects but the import does not have.
	local missing = {}
	local wanted = {}
	for _, bone in MeshCfg.Joints do
		table.insert(wanted, bone)
	end
	for follower, driver in MeshCfg.Followers do
		table.insert(wanted, follower)
		table.insert(wanted, driver)
	end
	for _, short in wanted do
		if not findBone(wolf, short) and not table.find(missing, short) then
			table.insert(missing, short)
		end
	end
	print(`[BuildWolfMesh] done: Wolf and Pup now use the imported mesh ({#missing} mapped bones missing)`)
	if #missing > 0 then
		warn("[BuildWolfMesh] missing bones: " .. table.concat(missing, ", "))
	end
	-- BoneRetarget is required above only to fail early if the module is absent.
	assert(BoneRetarget.prepare, "BuildWolfMesh: Shared.BoneRetarget is out of date")
end
