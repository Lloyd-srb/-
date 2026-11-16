--[[
	The imported wolf model ("Moonfang Stalker", Mixamo-style skeleton + extra
	auto-rig bones). tests/fixtures/moonfang_skeleton.json is that model's real
	skeleton, exported from the FBX in assets/wolf/. These tests run the game's
	retargeting code on it: the animations written for the block rig must pose
	this skeleton sensibly and never leave an extra bone behind.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local WolfAnimData = require(game.ReplicatedStorage.Shared.WolfAnimData)
local BoneRetarget = require(game.ReplicatedStorage.Shared.BoneRetarget)

local Mesh = Config.WolfRig.Mesh
local data = readJson("tests/fixtures/moonfang_skeleton.json")

-- FBX Euler XYZ = Rz * Ry * Rx.
local function fbxRotation(r)
	return CFrame.Angles(0, 0, math.rad(r[3])) * CFrame.Angles(0, math.rad(r[2]), 0) * CFrame.Angles(math.rad(r[1]), 0, 0)
end

-- The skeleton as the game sees it: in rig space, turned to face -Z.
local function loadSkeleton()
	local world, defs, byName = {}, {}, {}
	for _, bone in data.bones do
		local localCFrame = CFrame.new(bone.t[1], bone.t[2], bone.t[3]) * fbxRotation(bone.r)
		world[bone.name] = (if bone.parent then world[bone.parent] else CFrame.new()) * localCFrame
		local def = { Name = bone.name, Parent = bone.parent, RestLocal = localCFrame }
		table.insert(defs, def)
		byName[bone.name] = def
	end
	local forward = Vector3.new(0, 0, 0)
	for _, pair in Mesh.Feet do
		forward += world[BoneRetarget.resolve(byName, pair[2])].Position - world[BoneRetarget.resolve(byName, pair[1])].Position
	end
	local yaw = BoneRetarget.facingYaw(forward)
	for _, def in defs do
		if not def.Parent then
			def.RestLocal = CFrame.Angles(0, yaw, 0) * def.RestLocal
		end
	end
	return defs, yaw
end

local defs, yaw = loadSkeleton()
local prepared = BoneRetarget.prepare(defs, Mesh)
local scale = data.units_height / Config.WolfRig.Height

local function bone(short)
	return BoneRetarget.resolve(prepared.Bones, short)
end

local function solve(animationName, t)
	local poses = {}
	if animationName then
		for _, joint in WolfAnimData.Joints do
			poses[joint] = WolfAnimData.pose(WolfAnimData.Animations[animationName], joint, t, scale)
		end
	end
	return BoneRetarget.solve(prepared, poses)
end

local function near(a, b, tolerance)
	return (a - b).Magnitude <= tolerance
end

local SAMPLES = {
	{ "Idle", 0.7 },
	{ "Walk", 0.1 },
	{ "Walk", 0.5 },
	{ "Run", 0.05 },
	{ "Run", 0.3 },
	{ "Attack", 0.12 },
	{ "Attack", 0.26 },
	{ "Maul", 0.9 },
	{ "Howl", 1.3 },
}

test("the fixture is the model we analysed", function()
	expect(#data.bones).toBe(56)
	expect(data.units_height).toBeNear(2.39, 0.01)
end)

test("every bone named in the mapping exists; no extra bone is left unassigned", function()
	expect(prepared.Missing).toEqual({})
	for _, joint in WolfAnimData.Joints do
		if joint ~= "Tail" then -- the tail is carried by a follower bone
			expect(Mesh.Joints[joint] ~= nil).toBe(true)
		end
	end
	for _, def in defs do
		if def.Name:sub(1, 5) == "Bone_" and Mesh.Followers[def.Name] == nil then
			error("extra bone without a follower rule: " .. def.Name)
		end
	end
end)

test("facing is detected from the feet: the model is turned to face -Z, left = -X", function()
	expect(math.deg(yaw)).toBeNear(180, 5)
	local rest = prepared.RestWorld
	expect(rest[bone("LeftToeBase")].Position.Z < rest[bone("LeftFoot")].Position.Z).toBe(true) -- toes forward
	expect(rest[bone("headfront")].Position.Z < rest[bone("Head")].Position.Z).toBe(true) -- snout forward
	expect(rest[bone("LeftHand")].Position.X < 0).toBe(true) -- same side convention as the block rig
	expect(rest[bone("RightHand")].Position.X > 0).toBe(true)
end)

test("with no animation the model keeps its rest (T) pose exactly", function()
	local transforms, worlds = solve(nil, 0)
	for name, world in worlds do
		expect(near(world.Position, prepared.RestWorld[name].Position, 1e-4)).toBe(true)
		expect(near(transforms[name].Position, Vector3.new(0, 0, 0), 1e-4)).toBe(true)
	end
end)

test("idle: the T-pose arms hang down by the sides, symmetric", function()
	local rest = prepared.RestWorld
	local _, worlds = solve("Idle", 0)
	for _, side in { "Left", "Right" } do
		local shoulder = worlds[bone(side .. "Arm")].Position
		local hand = worlds[bone(side .. "Hand")].Position
		local armLength = (rest[bone(side .. "Hand")].Position - rest[bone(side .. "Arm")].Position).Magnitude
		expect(shoulder.Y - hand.Y > armLength * 0.8).toBe(true) -- hand well below the shoulder
		expect(math.abs(hand.X - shoulder.X) < armLength * 0.35).toBe(true) -- not sticking out sideways
	end
	expect(worlds[bone("LeftHand")].Position.X).toBeNear(-worlds[bone("RightHand")].Position.X, 0.08)
	expect(worlds[bone("LeftHand")].Position.Y).toBeNear(worlds[bone("RightHand")].Position.Y, 0.08)
end)

test("claws, mane, snout, tail and toe claws stay glued to their body part in every pose", function()
	for _, sample in SAMPLES do
		local _, worlds = solve(sample[1], sample[2])
		for follower, driver in prepared.FollowDriver do
			local relative = worlds[driver]:ToObjectSpace(worlds[follower])
			local expected = prepared.FollowRel[follower]
			if not near(relative.Position, expected.Position, 1e-3) or not near(relative.LookVector, expected.LookVector, 1e-3) then
				error(`{follower} drifted from {driver} in {sample[1]} at {sample[2]}`)
			end
		end
	end
end)

test("the Transforms handed to Roblox reproduce the solved pose (forward kinematics)", function()
	for _, sample in SAMPLES do
		local transforms, worlds = solve(sample[1], sample[2])
		local check = {}
		for _, name in prepared.Order do
			local def = prepared.Bones[name]
			check[name] = (if def.Parent then check[def.Parent] else CFrame.new()) * def.RestLocal * transforms[name]
			if not near(check[name].Position, worlds[name].Position, 1e-3) then
				error(`{name} mismatch in {sample[1]}`)
			end
		end
	end
end)

test("feet stay flat on the ground", function()
	for _, sample in { { "Idle", 0 }, { "Attack", 0.26 }, { "Maul", 0.9 }, { "Howl", 1.3 }, { "Run", 0.1 } } do
		local _, worlds = solve(sample[1], sample[2])
		for _, side in { "Left", "Right" } do
			local name = bone(side .. "Foot")
			expect(near(worlds[name].UpVector, prepared.RestWorld[name].UpVector, 1e-3)).toBe(true)
		end
	end
	-- Standing poses keep the feet at ground height.
	for _, sample in { { "Idle", 0 }, { "Attack", 0.26 }, { "Howl", 1.3 } } do
		local _, worlds = solve(sample[1], sample[2])
		local foot = bone("LeftFoot")
		expect(worlds[foot].Position.Y).toBeNear(prepared.RestWorld[foot].Position.Y, 0.03)
	end
end)

test("walk: legs alternate, left leg forward first", function()
	local _, first = solve("Walk", 0)
	local _, second = solve("Walk", 0.4)
	local left, right = bone("LeftFoot"), bone("RightFoot")
	expect(first[left].Position.Z < first[right].Position.Z - 0.1).toBe(true) -- forward is -Z
	expect(second[left].Position.Z > second[right].Position.Z + 0.1).toBe(true)
end)

test("run: on all fours (hands down near the ground, head still looking ahead)", function()
	local _, worlds = solve("Run", 0)
	local rest = prepared.RestWorld
	expect(worlds[bone("LeftHand")].Position.Y < rest[bone("Hips")].Position.Y).toBe(true) -- wrists below hip height
	expect(worlds[bone("LeftHand")].Position.Z < rest[bone("Hips")].Position.Z - 0.4).toBe(true) -- and in front
	expect(worlds[bone("Head")].Position.Z < rest[bone("Head")].Position.Z - 0.3).toBe(true) -- body pitched forward
	expect(worlds[bone("Head")].Position.Y < rest[bone("Head")].Position.Y).toBe(true)
end)

test("attack: the right claw rises above the head, then swipes down", function()
	local _, up = solve("Attack", 0.12)
	local _, hit = solve("Attack", 0.26)
	local hand, head = bone("RightHand"), bone("Head")
	expect(up[hand].Position.Y > up[head].Position.Y).toBe(true)
	expect(hit[hand].Position.Y < up[hand].Position.Y - 0.5).toBe(true)
	expect(up[bone("LeftHand")].Position.Y < up[head].Position.Y).toBe(true) -- the other arm stays down
end)

test("howl: the snout points up", function()
	local _, worlds = solve("Howl", 1.3)
	local snout = worlds[bone("headfront")].Position - worlds[bone("Head")].Position
	expect(snout.Unit.Y > 0.7).toBe(true)
end)

test("helpers", function()
	local rotation = CFrame.Angles(0.4, 1.1, -0.7)
	local identity = BoneRetarget.driverTransform(rotation, CFrame.new())
	expect(near(identity.LookVector, Vector3.new(0, 0, -1), 1e-6)).toBe(true)
	local down = BoneRetarget.alignDown(Vector3.new(-1, 0, 0)) * Vector3.new(-1, 0, 0)
	expect(near(down, Vector3.new(0, -1, 0), 1e-5)).toBe(true)
	expect(near(BoneRetarget.alignDown(Vector3.new(0, -2, 0)).LookVector, Vector3.new(0, 0, -1), 1e-6)).toBe(true)
	expect(math.deg(BoneRetarget.facingYaw(Vector3.new(0, 0, 1)))).toBeNear(180, 1e-6)
	expect(math.deg(BoneRetarget.facingYaw(Vector3.new(0, 0, -1)))).toBeNear(0, 1e-6)
	expect(BoneRetarget.resolve({ ["mixamorig:Hips"] = {} }, "Hips")).toBe("mixamorig:Hips")
	expect(BoneRetarget.resolve({ Hips = {} }, "Hips")).toBe("Hips")
	expect(BoneRetarget.resolve({ Hips = {} }, "Tail")).toBeNil()
end)
