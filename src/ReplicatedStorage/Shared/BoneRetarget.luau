--!strict
--[[
	BoneRetarget — plays the werewolf animation data (WolfAnimData, written for
	the 12-joint block rig) on an imported skinned mesh with its own skeleton
	(e.g. a Mixamo-style rig from Meshy). Pure maths, no Instances, so it is
	fully tested offline against the real skeleton of the imported model.

	Rig space: front = -Z, up = +Y, the character's left = -X (same as the
	block rig and as a Roblox character).

	Three kinds of bones:
	  - joint bones   a WolfAnimData joint drives them. The joint pose is a
	                  rotation in rig-space axes; it is converted to the bone's
	                  own (arbitrarily oriented) local frame.
	  - followers     extra bones the auto-rigger added (claws, mane, snout,
	                  tail...) that hold part of the mesh but sit in the wrong
	                  place in the hierarchy. Each one rigidly follows a chosen
	                  joint-side bone, so the mesh never tears.
	  - level bones   (feet) keep their rest orientation while moving with the
	                  leg, so soles stay flat on the ground.
	  - the rest      keep their rest pose relative to their parent.

	Arms modelled in a T-pose get an automatic "arms down" offset, because the
	animation data assumes arms hanging at rest.
]]

export type BoneDef = {
	Name: string,
	Parent: string?, -- nil = attached to the rig root
	RestLocal: CFrame, -- relative to the parent bone (or to rig space for root bones)
}

export type Mapping = {
	Joints: { [string]: string }, -- animation joint -> bone name
	ArmJoints: { [string]: string }, -- upper-arm joint -> the joint further down the arm
	Followers: { [string]: string }, -- extra bone -> bone it rigidly follows
	Level: { string }, -- bones that keep their rest orientation (feet)
}

export type Prepared = {
	Order: { string },
	Bones: { [string]: BoneDef },
	RestWorld: { [string]: CFrame },
	JointOfBone: { [string]: string },
	RestOffset: { [string]: CFrame }, -- per joint
	FollowDriver: { [string]: string },
	FollowRel: { [string]: CFrame },
	Level: { [string]: boolean },
	CleanOrder: { string },
	DirtyOrder: { string },
	Missing: { string }, -- mapping names that are not in the skeleton
}

local BoneRetarget = {}

local DOWN = Vector3.new(0, -1, 0)

-- Finds a skeleton bone by short name ("Hips" matches "mixamorig:Hips").
function BoneRetarget.resolve(bones: { [string]: BoneDef }, wanted: string): string?
	if bones[wanted] then
		return wanted
	end
	for name in bones do
		if #name > #wanted and name:sub(-#wanted - 1) == ":" .. wanted then
			return name
		end
	end
	return nil
end

-- Rotation that turns `direction` to point straight down (shortest arc).
function BoneRetarget.alignDown(direction: Vector3): CFrame
	local unit = direction.Unit
	local dot = math.clamp(unit:Dot(DOWN), -1, 1)
	local axis = unit:Cross(DOWN)
	if axis.Magnitude < 1e-6 then
		return if dot > 0 then CFrame.new() else CFrame.Angles(0, 0, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Yaw that turns a model whose toes point along `direction` to face -Z.
-- Pass the sum of both feet's (toe - foot) so toe-out cancels.
function BoneRetarget.facingYaw(direction: Vector3): number
	return math.pi - math.atan2(direction.X, direction.Z)
end

--[[
	A joint pose (rotation / offset in rig-space axes about the bone's pivot)
	expressed as the bone's local Transform. `restRotation` is the bone's rest
	world rotation in rig space.
]]
function BoneRetarget.driverTransform(restRotation: CFrame, pose: CFrame): CFrame
	return restRotation:Inverse() * pose * restRotation
end

-- `defs` must list parents before their children.
function BoneRetarget.prepare(defs: { BoneDef }, mapping: Mapping): Prepared
	local bones: { [string]: BoneDef } = {}
	local order: { string } = {}
	local restWorld: { [string]: CFrame } = {}
	for _, def in defs do
		bones[def.Name] = def
		table.insert(order, def.Name)
		local parentWorld = if def.Parent then restWorld[def.Parent] else CFrame.new()
		assert(parentWorld, `BoneRetarget: parent of {def.Name} must be listed first`)
		restWorld[def.Name] = parentWorld * def.RestLocal
	end

	local missing: { string } = {}
	local function find(wanted: string): string?
		local name = BoneRetarget.resolve(bones, wanted)
		if not name then
			table.insert(missing, wanted)
		end
		return name
	end

	local jointBone: { [string]: string } = {}
	local jointOfBone: { [string]: string } = {}
	for joint, wanted in mapping.Joints do
		local name = find(wanted)
		if name then
			jointBone[joint] = name
			jointOfBone[name] = joint
		end
	end

	local restOffset: { [string]: CFrame } = {}
	for joint, lowerJoint in mapping.ArmJoints do
		local upper, lower = jointBone[joint], jointBone[lowerJoint]
		if upper and lower then
			restOffset[joint] = BoneRetarget.alignDown(restWorld[lower].Position - restWorld[upper].Position)
		end
	end

	local followDriver: { [string]: string } = {}
	local followRel: { [string]: CFrame } = {}
	for wantedFollower, wantedDriver in mapping.Followers do
		local follower, driver = find(wantedFollower), find(wantedDriver)
		if follower and driver then
			followDriver[follower] = driver
			followRel[follower] = restWorld[driver]:ToObjectSpace(restWorld[follower])
		end
	end

	local level: { [string]: boolean } = {}
	for _, wanted in mapping.Level do
		local name = find(wanted)
		if name then
			level[name] = true
		end
	end

	-- "Dirty" = a follower or below one: solved after every joint-side bone.
	local dirty: { [string]: boolean } = {}
	local cleanOrder: { string } = {}
	local dirtyOrder: { string } = {}
	for _, name in order do
		local parent = bones[name].Parent
		if followDriver[name] or (parent and dirty[parent]) then
			dirty[name] = true
			table.insert(dirtyOrder, name)
		else
			table.insert(cleanOrder, name)
		end
	end
	for follower, driver in followDriver do
		assert(not dirty[driver], `BoneRetarget: {follower} cannot follow {driver}, which itself follows a bone`)
	end

	table.sort(missing)
	return {
		Order = order,
		Bones = bones,
		RestWorld = restWorld,
		JointOfBone = jointOfBone,
		RestOffset = restOffset,
		FollowDriver = followDriver,
		FollowRel = followRel,
		Level = level,
		CleanOrder = cleanOrder,
		DirtyOrder = dirtyOrder,
		Missing = missing,
	}
end

--[[
	Solves one frame. `poses` maps animation joints to their pose (see
	WolfAnimData.pose). Returns each bone's local Transform and its animated
	world CFrame in rig space.
]]
function BoneRetarget.solve(prepared: Prepared, poses: { [string]: CFrame }): ({ [string]: CFrame }, { [string]: CFrame })
	local transforms: { [string]: CFrame } = {}
	local worlds: { [string]: CFrame } = {}
	local identity = CFrame.new()

	for _, name in prepared.CleanOrder do
		local bone = prepared.Bones[name]
		local base = (if bone.Parent then worlds[bone.Parent] else identity) * bone.RestLocal
		local transform = identity
		local joint = prepared.JointOfBone[name]
		local pose = if joint then poses[joint] else nil
		if joint and pose then
			local offset = prepared.RestOffset[joint]
			local target = if offset then pose * offset else pose
			transform = BoneRetarget.driverTransform(prepared.RestWorld[name].Rotation, target)
		elseif prepared.Level[name] then
			-- Cancel whatever rotation the leg above has picked up.
			transform = base.Rotation:Inverse() * prepared.RestWorld[name].Rotation
		end
		transforms[name] = transform
		worlds[name] = base * transform
	end

	for _, name in prepared.DirtyOrder do
		local bone = prepared.Bones[name]
		local base = (if bone.Parent then worlds[bone.Parent] else identity) * bone.RestLocal
		local transform = identity
		local driver = prepared.FollowDriver[name]
		if driver then
			transform = base:Inverse() * (worlds[driver] * prepared.FollowRel[name])
		end
		transforms[name] = transform
		worlds[name] = base * transform
	end

	return transforms, worlds
end

return BoneRetarget
