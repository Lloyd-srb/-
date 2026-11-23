--!strict
--[[
	ForestService — builds the walkable forest when the server starts
	(owner, 19 Nov 2026): task trees, bushes and rocks are placed at random
	every match (Logic.ForestLayout), and so is the course of the water
	channel round the village. The channel's water is only put on the map in
	matches where the monster is The Lurker (ShowMoat); the trees always keep
	clear of its course.

	Contract (same as when the map builder made the trees):
	  Workspace.Map.Forest.Trees  Models tagged "TaskTree", attr TreeId;
	                              PrimaryPart (trunk) has attachments
	                              PromptAnchor, AppleSpot, CrateSpot
	  Workspace.Map.Forest.Props  bushes and rocks
	  Workspace.Map.Moat          the channel (only in Lurker matches)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

local ForestLayout = require(script.Parent.Parent.Logic.ForestLayout)

local ForestService = {}

ForestService.Layout = nil :: ForestLayout.Layout?
ForestService.MoatShown = false

local rgb = Color3.fromRGB
local TRUNK = rgb(128, 88, 58)
local ROCK = rgb(150, 152, 160)
local MOAT_WATER = rgb(70, 150, 220)
local MOAT_BED = rgb(40, 70, 90)
local LEAVES = { rgb(92, 176, 88), rgb(70, 156, 96), rgb(118, 192, 84), rgb(84, 168, 120) }

local moatModel: Model? = nil

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function decor(part: Part): Part
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function attachment(name: string, cframe: CFrame, parent: Instance)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cframe
	a.Parent = parent
end

local function folder(name: string, parent: Instance): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function buildTaskTree(parent: Instance, treeId: number, position: Vector3, rng: Rng.Rng)
	local tree = Instance.new("Model")
	tree.Name = string.format("Tree%02d", treeId)
	tree.Parent = parent
	local scale = 0.9 + rng:NextNumber() * 0.35
	local trunkHeight = 9 * scale
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	local trunk = block("Trunk", Vector3.new(2.2 * scale, trunkHeight, 2.2 * scale), base * CFrame.new(0, trunkHeight / 2, 0), TRUNK, tree)
	local leaf = LEAVES[rng:NextInteger(1, #LEAVES)]
	local y = trunkHeight
	for index, size in { { 9, 4.5 }, { 7, 4 }, { 4.5, 3.2 } } do
		local width, height = size[1] * scale, size[2] * scale
		local leaves = decor(block(
			"Leaves" .. index,
			Vector3.new(width, height, width),
			base * CFrame.new(0, y + height / 2 - 0.5, 0) * CFrame.Angles(0, index * 0.5, 0),
			leaf,
			tree
		))
		leaves.CastShadow = true
		y += height - 0.5
	end
	tree.PrimaryPart = trunk
	tree:AddTag("TaskTree")
	tree:SetAttribute("TreeId", treeId)
	attachment("PromptAnchor", CFrame.new(0, -trunkHeight / 2 + 3.5, 0), trunk)
	attachment("AppleSpot", CFrame.new(0, trunkHeight / 2 + 1, -3.4 * scale), trunk)
	attachment("CrateSpot", CFrame.new(4.2 * scale, -trunkHeight / 2 + 1.2, 0), trunk)
end

-- The channel: flat water over the forest floor (people wade through it).
local function buildMoat(path: { Vector3 }): Model
	local cfg = Config.Map.Moat
	local moat = Instance.new("Model")
	moat.Name = "Moat"
	for index = 1, #path - 1 do
		local a, b = path[index], path[index + 1]
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		local frame = CFrame.lookAt(mid, mid + (b - a))
		decor(block("Bed", Vector3.new(cfg.Width + 1, 0.2, length + 1), frame * CFrame.new(0, 0.02, 0), MOAT_BED, moat))
		local water = decor(block("Water", Vector3.new(cfg.Width, 0.3, length + 0.6), frame * CFrame.new(0, 0.2, 0), MOAT_WATER, moat))
		water.Transparency = 0.25
		water.Material = Enum.Material.Glass
	end
	for _, point in path do -- round joints
		local joint = decor(block("Joint", Vector3.new(0.3, cfg.Width, cfg.Width), CFrame.new(point + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), MOAT_WATER, moat))
		joint.Shape = Enum.PartType.Cylinder
		joint.Transparency = 0.25
		joint.Material = Enum.Material.Glass
	end
	return moat
end

-- Builds everything. `seed` = nil: a different forest every time.
function ForestService.Generate(seed: number?)
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	local rng = if seed then Rng.seeded(seed) else Rng.wrap(Random.new())
	local layout = ForestLayout.generate(rng)
	ForestService.Layout = layout

	local forest = folder("Forest", map)
	local trees = folder("Trees", forest)
	local props = folder("Props", forest)
	for treeId, position in layout.Trees do
		buildTaskTree(trees, treeId, position, rng)
	end
	for _, position in layout.Bushes do
		local size = 2.5 + rng:NextNumber() * 2
		decor(block(
			"Bush",
			Vector3.new(size * 1.3, size * 0.8, size * 1.3),
			CFrame.new(position + Vector3.new(0, size * 0.4, 0)) * CFrame.Angles(0, rng:NextNumber() * 3, 0),
			LEAVES[rng:NextInteger(1, #LEAVES)],
			props
		))
	end
	for _, position in layout.Rocks do
		local size = 1.5 + rng:NextNumber() * 2
		block(
			"Rock",
			Vector3.new(size * 1.4, size, size * 1.2),
			CFrame.new(position + Vector3.new(0, size * 0.35, 0)) * CFrame.Angles(rng:NextNumber() * 0.4 - 0.2, rng:NextNumber() * 3, 0),
			ROCK,
			props
		)
	end

	if moatModel then
		moatModel:Destroy()
	end
	moatModel = buildMoat(layout.Moat)
	ForestService.MoatShown = false
	;(moatModel :: Model).Parent = ServerStorage
end

-- The Lurker's passive: the channel appears on the map.
function ForestService.ShowMoat()
	local map = workspace:FindFirstChild("Map")
	if moatModel and map then
		moatModel.Parent = map
		ForestService.MoatShown = true
	end
end

-- Is this position in the channel (only while it is on the map)?
function ForestService.InMoat(position: Vector3): boolean
	local layout = ForestService.Layout
	return ForestService.MoatShown and layout ~= nil and ForestLayout.inMoat(position, layout.Moat)
end

function ForestService.Init()
	local seed = if Config.Debug.Enabled then Config.Debug.ForestSeed else nil
	ForestService.Generate(seed)
end

function ForestService.Start() end

return ForestService
