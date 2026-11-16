--[[
	Offline preview helper (Lune). Solves the werewolf animations on the
	imported model's real skeleton (tests/fixtures/moonfang_skeleton.json) with
	the game's own BoneRetarget code and writes every bone's animated world
	matrix to a JSON file. tools/wolfmesh/render.py then skins the mesh with it.

	Usage (repo root):  lune run tools/wolfmesh/poses.luau <out.json>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = require("../lib/Harness")
local roblox = Harness.roblox
local CFrame = roblox.CFrame

local loaded = Harness.load("src")
local Shared = loaded.game.ReplicatedStorage.Shared
local Config = loaded.require(Shared.Config)
local WolfAnimData = loaded.require(Shared.WolfAnimData)
local BoneRetarget = loaded.require(Shared.BoneRetarget)

local Skeleton = {}

-- FBX Euler XYZ = Rz * Ry * Rx.
local function fbxRotation(r)
	return CFrame.Angles(0, 0, math.rad(r[3])) * CFrame.Angles(0, math.rad(r[2]), 0) * CFrame.Angles(math.rad(r[1]), 0, 0)
end

-- Loads the fixture into rig space (turned so the model faces -Z).
function Skeleton.load(path: string)
	local data = serde.decode("json", fs.readFile(path))
	local fbxWorld = {}
	local defs = {}
	for _, bone in data.bones do
		local localCFrame = CFrame.new(bone.t[1], bone.t[2], bone.t[3]) * fbxRotation(bone.r)
		fbxWorld[bone.name] = (if bone.parent then fbxWorld[bone.parent] else CFrame.new()) * localCFrame
		table.insert(defs, { Name = bone.name, Parent = bone.parent, RestLocal = localCFrame })
	end
	local bones = {}
	for _, def in defs do
		bones[def.Name] = def
	end
	local forward = roblox.Vector3.new(0, 0, 0)
	for _, pair in Config.WolfRig.Mesh.Feet do
		local foot = fbxWorld[BoneRetarget.resolve(bones, pair[1])]
		local toe = fbxWorld[BoneRetarget.resolve(bones, pair[2])]
		forward += toe.Position - foot.Position
	end
	local yaw = BoneRetarget.facingYaw(forward)
	local turn = CFrame.Angles(0, yaw, 0)
	for _, def in defs do
		if not def.Parent then
			def.RestLocal = turn * def.RestLocal
		end
	end
	return defs, yaw, data
end

local out = process.args[1]
assert(out, "usage: lune run tools/wolfmesh/poses.luau <out.json>")

local defs, yaw, data = Skeleton.load("tests/fixtures/moonfang_skeleton.json")
local prepared = BoneRetarget.prepare(defs, Config.WolfRig.Mesh)
local scale = data.units_height / Config.WolfRig.Height

local SHOTS = {
	{ "TPose", nil, 0 },
	{ "Idle", "Idle", 0 },
	{ "Walk_a", "Walk", 0 },
	{ "Walk_b", "Walk", 0.4 },
	{ "Run_a", "Run", 0 },
	{ "Run_b", "Run", 0.22 },
	{ "Attack_up", "Attack", 0.12 },
	{ "Attack_hit", "Attack", 0.26 },
	{ "Maul", "Maul", 0.6 },
	{ "Howl", "Howl", 1.3 },
}

local result = { yaw = yaw, missing = prepared.Missing, shots = {}, order = {} }
for _, shot in SHOTS do
	local poses = {}
	if shot[2] then
		local animation = WolfAnimData.Animations[shot[2]]
		for _, joint in WolfAnimData.Joints do
			poses[joint] = WolfAnimData.pose(animation, joint, shot[3], scale)
		end
	end
	local _, worlds = BoneRetarget.solve(prepared, poses)
	local matrices = {}
	for name, world in worlds do
		matrices[name] = { world:GetComponents() }
	end
	result.shots[shot[1]] = matrices
	table.insert(result.order, shot[1])
end

fs.writeFile(out, serde.encode("json", result))
print(`wrote {out}: {#SHOTS} poses, yaw {math.deg(yaw)} deg, missing bones: {#prepared.Missing}`)
