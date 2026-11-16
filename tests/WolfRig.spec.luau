-- The werewolf rig and its animation data (built by build/BuildWolfRig.luau).
local Config = require(game.ReplicatedStorage.Shared.Config)
local WolfAnimData = require(game.ReplicatedStorage.Shared.WolfAnimData)

runBuilder("build/BuildWolfRig.luau")
local ServerStorage = game:GetService("ServerStorage")
local Rigs = ServerStorage.Rigs

local function jointMap(rig)
	local motors, connected = {}, { Root = true }
	local links = {}
	for _, instance in rig:GetDescendants() do
		if instance:IsA("Motor6D") or instance:IsA("Weld") then
			table.insert(links, instance)
			if instance:IsA("Motor6D") then
				motors[instance.Name] = instance
			end
		end
	end
	-- Flood fill from Root along Part0 -> Part1.
	local changed = true
	while changed do
		changed = false
		for _, link in links do
			if connected[link.Part0.Name] and not connected[link.Part1.Name] then
				connected[link.Part1.Name] = true
				changed = true
			end
		end
	end
	return motors, connected
end

local function lowestPoint(rig)
	local lowest = math.huge
	for _, part in rig:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Root" then
			lowest = math.min(lowest, part.CFrame.Position.Y - part.Size.Y / 2)
		end
	end
	return lowest
end

local function highestPoint(rig)
	local highest = -math.huge
	for _, part in rig:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Root" then
			highest = math.max(highest, part.CFrame.Position.Y + part.Size.Y / 2)
		end
	end
	return highest
end

test("both rigs exist and every part hangs off the Root", function()
	for _, name in { "Wolf", "Pup" } do
		local rig = Rigs:FindFirstChild(name)
		expect(rig ~= nil and rig.PrimaryPart.Name == "Root").toBe(true)
		local _, connected = jointMap(rig)
		local parts = 0
		for _, part in rig:GetChildren() do
			if part:IsA("BasePart") then
				parts += 1
				if not connected[part.Name] then
					error(name .. ": part not attached to the rig: " .. part.Name)
				end
				expect(part.CanCollide).toBe(false)
				expect(part.Massless).toBe(true)
				expect(part.Anchored).toBe(false)
			end
		end
		expect(parts).toBe(29)
	end
end)

test("the rig has one Motor6D per animation joint", function()
	local motors = jointMap(Rigs.Wolf)
	for _, joint in WolfAnimData.Joints do
		if not motors[joint] then
			error("missing joint " .. joint)
		end
		expect(motors[joint].Part1.Name).toBe(joint)
	end
end)

test("joints line up: Part0 * C0 == Part1 * C1 in the bind pose", function()
	for _, name in { "Wolf", "Pup" } do
		local motors = jointMap(Rigs[name])
		for joint, motor in motors do
			local a = (motor.Part0.CFrame * motor.C0).Position
			local b = (motor.Part1.CFrame * motor.C1).Position
			if (a - b).Magnitude > 0.001 then
				error(name .. ": joint " .. joint .. " is misaligned")
			end
		end
	end
end)

test("feet on the ground, yellow neon eyes, pup is the scaled-down wolf", function()
	local wolf, pup = Rigs.Wolf, Rigs.Pup
	expect(lowestPoint(wolf)).toBeNear(-3, 0.01)
	expect(lowestPoint(pup)).toBeNear(-3, 0.01)
	local wolfHeight = highestPoint(wolf) + 3
	local pupHeight = highestPoint(pup) + 3
	expect(wolfHeight > 8).toBe(true) -- taller than an R6 character (5 studs)
	expect(pupHeight / wolfHeight).toBeNear(Config.Pup.Scale, 0.01)
	for _, eye in { wolf.LeftEye, wolf.RightEye } do
		expect(eye.Material).toBe(Enum.Material.Neon)
		expect(eye.Color).toEqual(Config.WolfRig.Eye)
	end
	-- Eyes sit on the front (-Z) of the head, and the rig is left / right symmetric.
	expect(wolf.LeftEye.CFrame.Position.Z < wolf.Head.CFrame.Position.Z).toBe(true)
	expect(wolf.LeftUpperArm.CFrame.Position.X).toBeNear(-wolf.RightUpperArm.CFrame.Position.X, 0.001)
end)

test("animation data is well formed", function()
	for name, animation in WolfAnimData.Animations do
		expect(animation.Length > 0).toBe(true)
		for joint, track in animation.Tracks do
			if not table.find(WolfAnimData.Joints, joint) then
				error(name .. " animates unknown joint " .. joint)
			end
			local last = -1
			for _, key in track do
				if key[1] < last or key[1] < 0 or key[1] > animation.Length + 1e-6 then
					error(name .. "." .. joint .. " has a bad key time " .. key[1])
				end
				last = key[1]
				expect(#key >= 4).toBe(true)
			end
			if animation.Loop and #track > 1 then
				-- Looping tracks must end where they start, or they pop.
				for index = 2, 7 do
					expect((track[1][index] or 0)).toBeNear(track[#track][index] or 0, 1e-6)
				end
			end
		end
	end
	for _, required in { "Walk", "Run", "Attack", "Maul", "Howl" } do
		expect(WolfAnimData.Animations[required] ~= nil).toBe(true)
		expect(Config.Animations[WolfAnimData.ConfigKeys[required]]).toBe(0) -- placeholder until published
	end
	expect(WolfAnimData.Animations.Maul.Length).toBe(Config.Wolf.Sprint.MaulDuration)
end)

test("sampling interpolates between keys", function()
	local howl = WolfAnimData.Animations.Howl
	local rx0 = WolfAnimData.sample(howl, "Head", 0)
	local rxMid = WolfAnimData.sample(howl, "Head", 0.25)
	local rxUp = WolfAnimData.sample(howl, "Head", 0.5)
	expect(rx0).toBe(6)
	expect(rxUp).toBe(58)
	expect(rxMid > rx0 and rxMid < rxUp).toBe(true)
	-- Looping animations wrap around.
	local walk = WolfAnimData.Animations.Walk
	expect((WolfAnimData.sample(walk, "LeftUpperLeg", 0.8 + 0.4))).toBeNear(-22, 1e-6)
	-- Position offsets shrink with the pup's scale.
	local run = WolfAnimData.Animations.Run
	expect(WolfAnimData.pose(run, "Torso", 0, 0.5).Position.Z).toBeNear(-0.2, 1e-6)
end)

test("KeyframeSequences are ready to publish", function()
	local folder = ServerStorage.WolfAnimations
	for name, animation in WolfAnimData.Animations do
		local sequence = folder:FindFirstChild("Wolf" .. name)
		expect(sequence ~= nil and sequence:IsA("KeyframeSequence")).toBe(true)
		expect(sequence.Loop).toBe(animation.Loop)
		local keyframes = sequence:GetChildren()
		expect(#keyframes).toBe(#WolfAnimData.keyTimes(animation))
		for _, keyframe in keyframes do
			local rootPose = keyframe:FindFirstChild("Root")
			expect(rootPose ~= nil).toBe(true)
			-- Pose tree follows the rig: Root > Torso > Chest > Head
			expect(rootPose.Torso.Chest.Head:IsA("Pose")).toBe(true)
			expect(rootPose.Torso.Chest.LeftUpperArm.LeftLowerArm:IsA("Pose")).toBe(true)
			expect(rootPose.Torso.RightUpperLeg.RightLowerLeg:IsA("Pose")).toBe(true)
		end
	end
end)
