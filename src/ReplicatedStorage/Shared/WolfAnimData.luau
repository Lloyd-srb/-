--!strict
--[[
	WolfAnimData — the werewolf animations as plain data.

	One source, two uses:
	  - build/BuildWolfRig.luau turns it into KeyframeSequences (ServerStorage)
	    for the owner to publish (GDD §8.1: walk, run on four legs, attack, maul, howl).
	  - Until published IDs exist, clients play the same data directly on the
	    rig's Motor6Ds (the "fallback" animator), so the game is already playable.

	A track is a list of keys { time, rx, ry, rz [, px, py, pz] } in degrees /
	studs, applied as the joint's transform. A joint is named after the part it
	moves. Rotation signs: +rx swings a hanging limb forward and lifts the
	snout; -rx leans the chest forward; -rz / +rz splays the left / right arm.
]]

export type Key = { number }
export type Animation = {
	Length: number,
	Loop: boolean,
	Priority: string, -- Enum.AnimationPriority name
	Tracks: { [string]: { Key } },
}

local WolfAnimData = {}

WolfAnimData.Joints = {
	"Torso",
	"Chest",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"RightUpperArm",
	"RightLowerArm",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"RightUpperLeg",
	"RightLowerLeg",
	"Tail",
}

-- Resting pose shared by the upright animations.
local REST: { [string]: Key } = {
	Chest = { 0, -8, 0, 0 },
	Head = { 0, 6, 0, 0 },
	LeftUpperArm = { 0, 8, 0, -6 },
	RightUpperArm = { 0, 8, 0, 6 },
	LeftLowerArm = { 0, 12, 0, 0 },
	RightLowerArm = { 0, 12, 0, 0 },
	LeftUpperLeg = { 0, 8, 0, 0 },
	RightUpperLeg = { 0, 8, 0, 0 },
	LeftLowerLeg = { 0, -16, 0, 0 },
	RightLowerLeg = { 0, -16, 0, 0 },
	Tail = { 0, -20, 0, 0 },
}

-- Starts from the resting pose, then overrides the given tracks.
local function withRest(tracks: { [string]: { Key } }): { [string]: { Key } }
	local result: { [string]: { Key } } = {}
	for joint, key in REST do
		result[joint] = { key }
	end
	for joint, track in tracks do
		result[joint] = track
	end
	return result
end

-- Repeating left / right shake: keys every `step` seconds alternating +/- amount on one axis.
local function shake(length: number, step: number, rx: number, ry: number, rz: number, axis: number, amount: number): { Key }
	local track: { Key } = {}
	local sign = 1
	local t = 0
	while t < length do
		local key = { t, rx, ry, rz }
		key[axis + 1] += sign * amount
		table.insert(track, key)
		sign = -sign
		t += step
	end
	table.insert(track, { length, rx, ry, rz })
	return track
end

local Animations: { [string]: Animation } = {}

Animations.Idle = {
	Length = 2.4,
	Loop = true,
	Priority = "Idle",
	Tracks = withRest({
		Chest = { { 0, -8, 0, 0 }, { 1.2, -11, 0, 0 }, { 2.4, -8, 0, 0 } },
		Head = { { 0, 6, 0, 0 }, { 1.2, 9, 0, 0 }, { 2.4, 6, 0, 0 } },
		Tail = { { 0, -20, -10, 0 }, { 1.2, -20, 10, 0 }, { 2.4, -20, -10, 0 } },
	}),
}

-- Two-legged walk.
Animations.Walk = {
	Length = 0.8,
	Loop = true,
	Priority = "Movement",
	Tracks = withRest({
		Torso = { { 0, 0, 0, 0, 0, 0, 0 }, { 0.2, 0, 0, 0, 0, -0.15, 0 }, { 0.4, 0, 0, 0, 0, 0, 0 }, { 0.6, 0, 0, 0, 0, -0.15, 0 }, { 0.8, 0, 0, 0, 0, 0, 0 } },
		Chest = { { 0, -14, 5, 0 }, { 0.4, -14, -5, 0 }, { 0.8, -14, 5, 0 } },
		Head = { { 0, 10, 0, 0 } },
		LeftUpperLeg = { { 0, 32, 0, 0 }, { 0.4, -22, 0, 0 }, { 0.8, 32, 0, 0 } },
		LeftLowerLeg = { { 0, -12, 0, 0 }, { 0.4, -30, 0, 0 }, { 0.8, -12, 0, 0 } },
		RightUpperLeg = { { 0, -22, 0, 0 }, { 0.4, 32, 0, 0 }, { 0.8, -22, 0, 0 } },
		RightLowerLeg = { { 0, -30, 0, 0 }, { 0.4, -12, 0, 0 }, { 0.8, -30, 0, 0 } },
		LeftUpperArm = { { 0, -18, 0, -6 }, { 0.4, 24, 0, -6 }, { 0.8, -18, 0, -6 } },
		RightUpperArm = { { 0, 24, 0, 6 }, { 0.4, -18, 0, 6 }, { 0.8, 24, 0, 6 } },
		LeftLowerArm = { { 0, 18, 0, 0 } },
		RightLowerArm = { { 0, 18, 0, 0 } },
		Tail = { { 0, -15, -12, 0 }, { 0.4, -15, 12, 0 }, { 0.8, -15, -12, 0 } },
	}),
}

-- Four-legged sprint: the whole upper body pitches forward and the arms become front legs.
Animations.Run = {
	Length = 0.44,
	Loop = true,
	Priority = "Movement",
	Tracks = {
		Torso = { { 0, -58, 0, 0, 0, 0, -0.4 }, { 0.22, -54, 0, 0, 0, 0.2, -0.4 }, { 0.44, -58, 0, 0, 0, 0, -0.4 } },
		Chest = { { 0, -12, 0, 0 } },
		Head = { { 0, 60, 0, 0 } },
		LeftUpperArm = { { 0, 120, 0, -4 }, { 0.22, 70, 0, -4 }, { 0.44, 120, 0, -4 } },
		RightUpperArm = { { 0, 108, 0, 4 }, { 0.11, 120, 0, 4 }, { 0.33, 70, 0, 4 }, { 0.44, 108, 0, 4 } },
		LeftLowerArm = { { 0, -60, 0, 0 }, { 0.22, -95, 0, 0 }, { 0.44, -60, 0, 0 } },
		RightLowerArm = { { 0, -68, 0, 0 }, { 0.11, -60, 0, 0 }, { 0.33, -95, 0, 0 }, { 0.44, -68, 0, 0 } },
		LeftUpperLeg = { { 0, 28, 0, 0 }, { 0.22, 93, 0, 0 }, { 0.44, 28, 0, 0 } },
		RightUpperLeg = { { 0, 40, 0, 0 }, { 0.11, 28, 0, 0 }, { 0.33, 93, 0, 0 }, { 0.44, 40, 0, 0 } },
		LeftLowerLeg = { { 0, -20, 0, 0 }, { 0.22, -50, 0, 0 }, { 0.44, -20, 0, 0 } },
		RightLowerLeg = { { 0, -25, 0, 0 }, { 0.11, -20, 0, 0 }, { 0.33, -50, 0, 0 }, { 0.44, -25, 0, 0 } },
		Tail = { { 0, 50, 0, 0 } },
	},
}

-- Right-claw swipe.
Animations.Attack = {
	Length = 0.45,
	Loop = false,
	Priority = "Action",
	Tracks = withRest({
		Chest = { { 0, -8, 0, 0 }, { 0.12, -2, -18, 0 }, { 0.26, -22, 20, 0 }, { 0.45, -8, 0, 0 } },
		Head = { { 0, 6, 0, 0 }, { 0.26, -4, 0, 0 }, { 0.45, 6, 0, 0 } },
		RightUpperArm = { { 0, 60, 0, 10 }, { 0.12, 165, 0, 25 }, { 0.26, 35, 0, -20 }, { 0.45, 8, 0, 6 } },
		RightLowerArm = { { 0, 30, 0, 0 }, { 0.12, 50, 0, 0 }, { 0.26, 10, 0, 0 }, { 0.45, 12, 0, 0 } },
	}),
}

-- Crouched over the victim, tearing (about 3 seconds, GDD §8.1).
Animations.Maul = {
	Length = 3.0,
	Loop = false,
	Priority = "Action",
	Tracks = withRest({
		Torso = { { 0, -35, 0, 0, 0, -0.6, 0 } },
		Chest = shake(3.0, 0.25, -25, 0, 0, 2, 10),
		Head = shake(3.0, 0.2, -15, 0, 0, 2, 28),
		LeftUpperArm = shake(3.0, 0.3, 50, 0, -8, 1, 20),
		RightUpperArm = shake(3.0, 0.3, 50, 0, 8, 1, -20),
		LeftLowerArm = { { 0, 35, 0, 0 } },
		RightLowerArm = { { 0, 35, 0, 0 } },
		LeftUpperLeg = { { 0, 45, 0, 0 } },
		RightUpperLeg = { { 0, 45, 0, 0 } },
		LeftLowerLeg = { { 0, -50, 0, 0 } },
		RightLowerLeg = { { 0, -50, 0, 0 } },
		Tail = { { 0, -10, 0, 0 } },
	}),
}

-- Head back, arms out.
Animations.Howl = {
	Length = 2.6,
	Loop = false,
	Priority = "Action",
	Tracks = withRest({
		Chest = { { 0, -8, 0, 0 }, { 0.5, 14, 0, 0 }, { 2.1, 14, 0, 0 }, { 2.6, -8, 0, 0 } },
		Head = { { 0, 6, 0, 0 }, { 0.5, 58, 0, 0 }, { 1.3, 64, 0, 0 }, { 2.1, 58, 0, 0 }, { 2.6, 6, 0, 0 } },
		LeftUpperArm = { { 0, 8, 0, -6 }, { 0.5, -15, 0, -28 }, { 2.1, -15, 0, -28 }, { 2.6, 8, 0, -6 } },
		RightUpperArm = { { 0, 8, 0, 6 }, { 0.5, -15, 0, 28 }, { 2.1, -15, 0, 28 }, { 2.6, 8, 0, 6 } },
		LeftLowerArm = { { 0, 20, 0, 0 } },
		RightLowerArm = { { 0, 20, 0, 0 } },
		Tail = { { 0, -20, 0, 0 }, { 0.5, -45, 0, 0 }, { 2.1, -45, 0, 0 }, { 2.6, -20, 0, 0 } },
	}),
}

WolfAnimData.Animations = Animations

-- Animation name -> Config.Animations key (published asset id).
WolfAnimData.ConfigKeys = {
	Walk = "WolfWalk",
	Run = "WolfRun",
	Attack = "WolfAttack",
	Maul = "WolfMaul",
	Howl = "WolfHowl",
}

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

-- Interpolated key values { rx, ry, rz, px, py, pz } of a joint at time t.
function WolfAnimData.sample(animation: Animation, joint: string, t: number): (number, number, number, number, number, number)
	local track = animation.Tracks[joint]
	if not track or #track == 0 then
		return 0, 0, 0, 0, 0, 0
	end
	if animation.Loop then
		t = t % animation.Length
	else
		t = math.clamp(t, 0, animation.Length)
	end

	local previous, following = track[1], track[#track]
	for index = 1, #track do
		local key = track[index]
		if key[1] <= t then
			previous = key
		end
		if key[1] >= t then
			following = key
			break
		end
	end

	local span = following[1] - previous[1]
	local alpha = if span > 0 then (t - previous[1]) / span else 0
	alpha = (1 - math.cos(math.pi * alpha)) / 2 -- ease in / out
	return lerp(previous[2], following[2], alpha),
		lerp(previous[3], following[3], alpha),
		lerp(previous[4], following[4], alpha),
		lerp(previous[5] or 0, following[5] or 0, alpha),
		lerp(previous[6] or 0, following[6] or 0, alpha),
		lerp(previous[7] or 0, following[7] or 0, alpha)
end

-- Joint transform at time t. `scale` shrinks position offsets for the pup.
function WolfAnimData.pose(animation: Animation, joint: string, t: number, scale: number?): CFrame
	local rx, ry, rz, px, py, pz = WolfAnimData.sample(animation, joint, t)
	local s = scale or 1
	return CFrame.new(px * s, py * s, pz * s) * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

-- Every distinct key time of an animation, sorted (for building keyframes).
function WolfAnimData.keyTimes(animation: Animation): { number }
	local seen: { [number]: boolean } = { [0] = true, [animation.Length] = true }
	for _, track in animation.Tracks do
		for _, key in track do
			seen[key[1]] = true
		end
	end
	local times = {}
	for t in seen do
		table.insert(times, t)
	end
	table.sort(times)
	return times
end

return WolfAnimData
