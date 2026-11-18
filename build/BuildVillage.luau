--!strict
--[[
	BuildVillage — (re)builds the whole Match-place map under Workspace.Map.

	Run it in Roblox Studio (command bar or the Studio MCP "run code" tool) after
	ReplicatedStorage.Shared.Config and .Rng exist. It is idempotent: the old
	Workspace.Map is destroyed and rebuilt, so never hand-edit the map — change
	this script (or Config.Map) and run it again.

	Layout (GDD §5): 12 houses in a ring around the plaza and meeting table, a
	garden behind every house, a fence (village / forest border), a walkable
	forest with task trees, then a dark outer forest behind invisible walls.

	Contract with the game scripts (tags / attributes / names):
	  Tag "House"          Model, attr HouseId. Children: Floor (attachments
	                       InsideSpawn, FrontSpawn), InteriorZone, Door, Bed, Wardrobe
	  Tag "HouseInterior"  invisible box part, attr HouseId (inside-house checks)
	  Tag "Door"           part, attrs HouseId, HP, MaxHP, ClosedCFrame, OpenCFrame;
	                       children HPBar (BillboardGui), RepairFront/RepairBack (SurfaceGui)
	  Tag "OneWayWindow"   glass part, attr HouseId. Opaque on the server; each
	                       client makes it see-through only while inside that house.
	  Tag "HidingSpot"     Model, attrs HouseId, Kind ("Bed" | "Wardrobe");
	                       PrimaryPart has attachments HideSpot, ExitSpot, PromptAnchor
	  Tag "HouseLamp" / "PlazaLamp"  parts holding a disabled PointLight (night only)
	  Tag "GardenPlot"     soil part, attr HouseId, attachment PromptAnchor
	  Tag "WaterSpot"      part on the stream's bridge, attr SpotId (fetch water task)
	  Tag "FishingSpot"    part on the stream's bridge, attr SpotId (fishing task)
	  Tag "TaskTree"       Model, attr TreeId; PrimaryPart (trunk) has attachments
	                       PromptAnchor, AppleSpot, CrateSpot
	  Tag "MeetingBell"    part with attachment PromptAnchor (call the meeting)
	  Workspace.Map.Markers  attachments MeetingSpot1..N, WolfSpawn, PupSpawn, ItemPile
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Clone before requiring so a rebuild always sees the latest module source
-- (Studio caches required modules for the whole session).
local function fresh(module: Instance): any
	return (require :: any)(module:Clone())
end

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildVillage: ReplicatedStorage.Shared is missing (import src/ first)")
local Config = fresh((Shared :: any).Config)
local Rng = fresh((Shared :: any).Rng)

local MapCfg = Config.Map
local rng = Rng.seeded(MapCfg.Seed)

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

local rgb = Color3.fromRGB

local Palette = {
	Grass = rgb(126, 196, 96),
	ForestFloor = rgb(92, 158, 78),
	DarkGround = rgb(26, 44, 34),
	Plaza = rgb(226, 202, 158),
	Path = rgb(208, 182, 138),
	Wood = rgb(156, 110, 74),
	WoodDark = rgb(112, 76, 50),
	WoodLight = rgb(204, 164, 118),
	Stone = rgb(170, 170, 176),
	White = rgb(245, 242, 235),
	Glass = rgb(38, 46, 66),
	Soil = rgb(120, 82, 56),
	SoilDark = rgb(96, 64, 44),
	Gold = rgb(240, 196, 70),
	Rug = rgb(214, 96, 92),
	Trunk = rgb(128, 88, 58),
	DarkTrunk = rgb(40, 30, 26),
	DarkLeaf = rgb(18, 40, 32),
	Rock = rgb(150, 152, 160),
	Lantern = rgb(255, 214, 140),
	Walls = {
		rgb(250, 236, 208),
		rgb(252, 214, 190),
		rgb(206, 236, 214),
		rgb(204, 226, 246),
		rgb(228, 212, 244),
		rgb(250, 240, 180),
	},
	Roofs = {
		rgb(214, 84, 76),
		rgb(60, 150, 150),
		rgb(232, 142, 62),
		rgb(72, 98, 170),
		rgb(150, 92, 170),
		rgb(86, 158, 92),
	},
	Blankets = {
		rgb(108, 160, 226),
		rgb(238, 130, 150),
		rgb(130, 200, 140),
		rgb(246, 196, 88),
	},
	Leaves = {
		rgb(92, 176, 88),
		rgb(70, 156, 96),
		rgb(118, 192, 84),
		rgb(84, 168, 120),
	},
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local stats = { Parts = 0, Houses = 0, TaskTrees = 0 }

local function newPart(className: string, name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = (Instance.new :: any)(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	stats.Parts += 1
	return part
end

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	return newPart("Part", name, size, cframe, color, parent) :: Part
end

-- Upright cylinder (Roblox cylinders lie along X, so roll them 90 degrees).
local function cylinder(name: string, diameter: number, height: number, position: Vector3, color: Color3, parent: Instance): Part
	local part = block(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Decorative part: no collisions, no queries, no shadows.
local function decor<T>(part: T & BasePart): T
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function invisible<T>(part: T & BasePart): T
	part.Transparency = 1
	part.CastShadow = false
	return part
end

local function folder(name: string, parent: Instance): Folder
	local instance = Instance.new("Folder")
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function model(name: string, parent: Instance): Model
	local instance = Instance.new("Model")
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function attachment(name: string, localCFrame: CFrame, parent: Instance): Attachment
	local instance = Instance.new("Attachment")
	instance.Name = name
	instance.CFrame = localCFrame
	instance.Parent = parent
	return instance
end

-- Point on a circle around the map centre. Angle 0 = -Z, clockwise seen from above.
local function onRing(radius: number, angle: number, y: number?): Vector3
	return Vector3.new(math.sin(angle) * radius, y or 0, -math.cos(angle) * radius)
end

-- Rotation whose front (-Z, LookVector) points from ring angle `angle` to the
-- map centre. Built from a yaw angle instead of CFrame.lookAt so the result is
-- identical in Studio and in the offline tools.
local function yawToCentre(angle: number): CFrame
	return CFrame.Angles(0, math.pi - angle, 0)
end

-- CFrame on the ring, facing the map centre.
local function facingCentre(radius: number, angle: number): CFrame
	return CFrame.new(onRing(radius, angle)) * yawToCentre(angle)
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function range(min: number, max: number): number
	return min + rng:NextNumber() * (max - min)
end

--------------------------------------------------------------------------------
-- Reset
--------------------------------------------------------------------------------

local old = workspace:FindFirstChild("Map")
if old then
	old:Destroy()
end
-- Studio's Baseplate template leftovers.
for _, name in { "Baseplate", "SpawnLocation" } do
	local leftover = workspace:FindFirstChild(name)
	if leftover then
		leftover:Destroy()
	end
end

local Map = folder("Map", workspace)

--------------------------------------------------------------------------------
-- Ground
--------------------------------------------------------------------------------

local function buildGround()
	local ground = folder("Ground", Map)
	local extent = (MapCfg.OuterForestRadius + 40) * 2

	block("OuterGround", Vector3.new(extent, 4, extent), CFrame.new(0, -2.2, 0), Palette.DarkGround, ground)
	cylinder("ForestFloor", (MapCfg.ForestOuterRadius + 3) * 2, 1, Vector3.new(0, -0.6, 0), Palette.ForestFloor, ground)
	cylinder("VillageGrass", MapCfg.FenceRadius * 2, 1, Vector3.new(0, -0.5, 0), Palette.Grass, ground)
	cylinder("Plaza", MapCfg.PlazaRadius * 2, 1, Vector3.new(0, -0.42, 0), Palette.Plaza, ground)
end

--------------------------------------------------------------------------------
-- Plaza: meeting table, markers, lanterns, spawn
--------------------------------------------------------------------------------

local function buildPlaza()
	local plaza = folder("Plaza", Map)

	local tableModel = model("MeetingTable", plaza)
	cylinder("Base", 5, 0.6, Vector3.new(0, 0.38, 0), Palette.WoodDark, tableModel)
	cylinder("Leg", 2.4, 2.6, Vector3.new(0, 1.9, 0), Palette.Wood, tableModel)
	local top = cylinder("Top", 14, 0.9, Vector3.new(0, 3.65, 0), Palette.WoodLight, tableModel)
	cylinder("Trim", 14.6, 0.4, Vector3.new(0, 3.5, 0), Palette.Wood, tableModel)
	tableModel.PrimaryPart = top
	tableModel:AddTag("MeetingTable")

	-- Bell: hold E on it to call the meeting.
	cylinder("BellBase", 1.6, 0.3, Vector3.new(0, 4.25, 0), Palette.WoodDark, tableModel)
	local bell = cylinder("Bell", 1.3, 1.1, Vector3.new(0, 4.95, 0), Palette.Gold, tableModel)
	bell.Material = Enum.Material.Metal
	bell:AddTag("MeetingBell")
	attachment("PromptAnchor", CFrame.new(0, 0, 0), bell)
	block("BellKnob", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 5.75, 0), Palette.Gold, tableModel).Material =
		Enum.Material.Metal

	-- Markers: an invisible, unrotated part at the origin, so each attachment's
	-- local CFrame equals its world CFrame.
	local markers = invisible(decor(block("Markers", Vector3.new(1, 1, 1), CFrame.new(0, 0, 0), Palette.White, Map)))
	for index = 1, MapCfg.HouseCount do
		local angle = (index - 1) / MapCfg.HouseCount * math.pi * 2
		local position = onRing(MapCfg.MeetingSpotRadius, angle, 3)
		attachment("MeetingSpot" .. index, CFrame.new(position) * yawToCentre(angle), markers)
	end
	-- Both spawns stand beside the table, facing away from it.
	attachment("WolfSpawn", CFrame.new(0, 4, 11) * CFrame.Angles(0, math.pi, 0), markers)
	attachment("PupSpawn", CFrame.new(0, 3, -11), markers)
	attachment("ItemPile", CFrame.new(10, 0.5, -10), markers)

	-- Lanterns between the paths (lit only at night by the lighting service).
	for index = 1, 4 do
		local angle = math.rad(45) + (index - 1) * math.rad(90)
		local base = onRing(MapCfg.PlazaRadius - 3, angle)
		block("LanternPost", Vector3.new(0.7, 9, 0.7), CFrame.new(base + Vector3.new(0, 4.6, 0)), Palette.WoodDark, plaza)
		local lamp = block(
			"Lantern",
			Vector3.new(1.6, 1.6, 1.6),
			CFrame.new(base + Vector3.new(0, 9.6, 0)),
			Palette.Lantern,
			plaza
		)
		lamp.Material = Enum.Material.Neon
		lamp:AddTag("PlazaLamp")
		local light = Instance.new("PointLight")
		light.Color = Palette.Lantern
		light.Brightness = 0.9
		light.Range = 26
		light.Enabled = false
		light.Parent = lamp
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MatchSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, -0.35, 20)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = plaza
	stats.Parts += 1
end

--------------------------------------------------------------------------------
-- House
--------------------------------------------------------------------------------

local HOUSE = {
	Width = 20, -- X
	Depth = 18, -- Z (front = -Z, faces the plaza)
	WallHeight = 12,
	Wall = 1,
	Floor = 0.6,
	DoorWidth = 5,
	DoorHeight = 8,
	WindowMinX = 4, -- window opening on the front wall, right of the door
	WindowMaxX = 8,
	WindowSill = 4, -- height above the floor
	RoofRise = 6,
	RoofOverhang = 1,
}

--[[
	Gable roof half. A Roblox WedgePart is tall at its Back (+Z) face and slopes
	down to nothing at its Front (-Z) face. `flip` turns it 180 degrees so two
	wedges meet at the ridge. VISUAL CHECK NEEDED IN STUDIO: if roofs look like
	a "V", swap the flip flags below.
]]
local function roofHalf(name: string, houseCF: CFrame, z: number, flip: boolean, color: Color3, parent: Instance): BasePart
	local size = Vector3.new(
		HOUSE.Width + HOUSE.RoofOverhang * 2,
		HOUSE.RoofRise,
		HOUSE.Depth / 2 + HOUSE.RoofOverhang
	)
	local cframe = houseCF * CFrame.new(0, HOUSE.Floor + HOUSE.WallHeight + HOUSE.RoofRise / 2, z)
	if flip then
		cframe = cframe * CFrame.Angles(0, math.pi, 0)
	end
	return newPart("WedgePart", name, size, cframe, color, parent)
end

local function repairGui(name: string, face: Enum.NormalId, door: Instance): SurfaceGui
	-- Crossed planks shown the morning after the door was broken (GDD §6.4).
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.CanvasSize = Vector2.new(250, 400)
	gui.LightInfluence = 1
	gui.Enabled = false
	gui.Parent = door
	for index, rotation in { 24, -18, 8 } do
		local plank = Instance.new("Frame")
		plank.Name = "Plank" .. index
		plank.AnchorPoint = Vector2.new(0.5, 0.5)
		plank.Position = UDim2.fromScale(0.5, 0.2 + index * 0.17)
		plank.Size = UDim2.fromScale(1.05, 0.11)
		plank.Rotation = rotation
		plank.BackgroundColor3 = Palette.WoodLight
		plank.BorderSizePixel = 0
		plank.Parent = gui
	end
	return gui
end

local function buildDoor(houseModel: Model, houseCF: CFrame, houseId: number, frontZ: number): Part
	local hingeCF = houseCF * CFrame.new(-HOUSE.DoorWidth / 2, HOUSE.Floor + HOUSE.DoorHeight / 2, frontZ)
	local closed = hingeCF * CFrame.new(HOUSE.DoorWidth / 2, 0, 0)
	-- Swings outwards (towards the plaza) so it never blocks the room.
	local open = hingeCF * CFrame.Angles(0, math.rad(100), 0) * CFrame.new(HOUSE.DoorWidth / 2, 0, 0)

	local door = block("Door", Vector3.new(HOUSE.DoorWidth, HOUSE.DoorHeight, 0.5), closed, Palette.Wood, houseModel)
	door.Material = Enum.Material.WoodPlanks
	door:AddTag("Door")
	door:SetAttribute("HouseId", houseId)
	door:SetAttribute("MaxHP", Config.Door.MaxHP)
	door:SetAttribute("HP", Config.Door.MaxHP)
	door:SetAttribute("ClosedCFrame", closed)
	door:SetAttribute("OpenCFrame", open)
	attachment("PromptAnchor", CFrame.new(0, 0, 0), door)

	local bar = Instance.new("BillboardGui")
	bar.Name = "HPBar"
	bar.Size = UDim2.fromScale(4.5, 0.55)
	bar.StudsOffset = Vector3.new(0, HOUSE.DoorHeight / 2 + 1.2, 0)
	bar.MaxDistance = 60
	bar.Enabled = false
	bar.Parent = door
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = rgb(40, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = rgb(230, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back

	repairGui("RepairFront", Enum.NormalId.Front, door)
	repairGui("RepairBack", Enum.NormalId.Back, door)
	return door
end

local function buildBed(houseModel: Model, houseCF: CFrame, houseId: number)
	local bed = model("Bed", houseModel)
	local x = -HOUSE.Width / 2 + HOUSE.Wall + 2.75
	local z = HOUSE.Depth / 2 - HOUSE.Wall - 4.5
	local top = HOUSE.Floor + 2.6 -- underside clearance to hide below

	local frame = block("Frame", Vector3.new(4.5, 0.5, 8), houseCF * CFrame.new(x, top, z), Palette.WoodDark, bed)
	for _, corner in { { -2, -3.75 }, { 2, -3.75 }, { -2, 3.75 }, { 2, 3.75 } } do
		block(
			"Leg",
			Vector3.new(0.5, top - HOUSE.Floor - 0.25, 0.5),
			houseCF * CFrame.new(x + corner[1], HOUSE.Floor + (top - HOUSE.Floor - 0.25) / 2, z + corner[2]),
			Palette.WoodDark,
			bed
		)
	end
	block("Headboard", Vector3.new(4.5, 3, 0.4), houseCF * CFrame.new(x, top + 1.4, z + 3.8), Palette.WoodDark, bed)
	block("Mattress", Vector3.new(4.3, 0.7, 7.6), houseCF * CFrame.new(x, top + 0.6, z - 0.1), Palette.White, bed)
	block("Pillow", Vector3.new(3, 0.5, 1.6), houseCF * CFrame.new(x, top + 1.15, z + 2.6), Palette.White, bed)
	block(
		"Blanket",
		Vector3.new(4.45, 0.25, 4.8),
		houseCF * CFrame.new(x, top + 1.05, z - 1.5),
		Palette.Blankets[(houseId - 1) % #Palette.Blankets + 1],
		bed
	)

	bed.PrimaryPart = frame
	bed:AddTag("HidingSpot")
	bed:SetAttribute("HouseId", houseId)
	bed:SetAttribute("Kind", "Bed")
	attachment("HideSpot", CFrame.new(0, -1.5, 0), frame)
	attachment("ExitSpot", CFrame.new(4.5, 1, -1), frame)
	attachment("PromptAnchor", CFrame.new(0, 1.2, 0), frame)
end

local function buildWardrobe(houseModel: Model, houseCF: CFrame, houseId: number)
	local wardrobe = model("Wardrobe", houseModel)
	local x = HOUSE.Width / 2 - HOUSE.Wall - 3
	local z = HOUSE.Depth / 2 - HOUSE.Wall - 1.6
	local height = 9

	local body = block(
		"Body",
		Vector3.new(5, height, 3),
		houseCF * CFrame.new(x, HOUSE.Floor + height / 2, z),
		Palette.Wood,
		wardrobe
	)
	for _, side in { -1, 1 } do
		block(
			"DoorPanel",
			Vector3.new(2.3, height - 0.8, 0.2),
			houseCF * CFrame.new(x + side * 1.2, HOUSE.Floor + height / 2, z - 1.6),
			Palette.WoodLight,
			wardrobe
		)
		block(
			"Knob",
			Vector3.new(0.3, 0.3, 0.3),
			houseCF * CFrame.new(x + side * 0.3, HOUSE.Floor + height / 2, z - 1.8),
			Palette.Gold,
			wardrobe
		)
	end
	block("Top", Vector3.new(5.4, 0.4, 3.4), houseCF * CFrame.new(x, HOUSE.Floor + height + 0.2, z), Palette.WoodDark, wardrobe)

	wardrobe.PrimaryPart = body
	wardrobe:AddTag("HidingSpot")
	wardrobe:SetAttribute("HouseId", houseId)
	wardrobe:SetAttribute("Kind", "Wardrobe")
	attachment("HideSpot", CFrame.new(0, -1.5, 0), body)
	attachment("ExitSpot", CFrame.new(0, -1.5, -4.5), body)
	attachment("PromptAnchor", CFrame.new(0, 0, -1.6), body)
end

local function buildHouse(parent: Instance, houseId: number, houseCF: CFrame): Model
	local house = model(string.format("House%02d", houseId), parent)
	house:AddTag("House")
	house:SetAttribute("HouseId", houseId)

	local wallColor = Palette.Walls[(houseId - 1) % #Palette.Walls + 1]
	local roofColor = Palette.Roofs[(houseId - 1) % #Palette.Roofs + 1]

	local W, D, H, T, F = HOUSE.Width, HOUSE.Depth, HOUSE.WallHeight, HOUSE.Wall, HOUSE.Floor
	local frontZ = -D / 2 + T / 2
	local wallY = F + H / 2

	local function wall(name: string, sizeX: number, sizeY: number, sizeZ: number, x: number, y: number, z: number): Part
		return block(name, Vector3.new(sizeX, sizeY, sizeZ), houseCF * CFrame.new(x, y, z), wallColor, house)
	end

	-- Floor (also carries the spawn markers).
	local floor = block("Floor", Vector3.new(W, F, D), houseCF * CFrame.new(0, F / 2, 0), Palette.WoodLight, house)
	floor.Material = Enum.Material.WoodPlanks
	house.PrimaryPart = floor
	attachment("InsideSpawn", CFrame.new(0, F / 2 + 3, 1), floor)
	attachment("FrontSpawn", CFrame.new(0, 3, -(D / 2 + 7)), floor)
	block("DoorStep", Vector3.new(7, 0.3, 2.5), houseCF * CFrame.new(0, 0.15, -D / 2 - 1.25), Palette.Stone, house)

	-- Walls.
	wall("BackWall", W, H, T, 0, wallY, D / 2 - T / 2)
	wall("LeftWall", T, H, D - T * 2, -W / 2 + T / 2, wallY, 0)
	wall("RightWall", T, H, D - T * 2, W / 2 - T / 2, wallY, 0)

	-- Front wall with a door opening (centre) and a window opening (right).
	local doorHalf = HOUSE.DoorWidth / 2
	local doorTop = F + HOUSE.DoorHeight
	local winMin, winMax, sill = HOUSE.WindowMinX, HOUSE.WindowMaxX, F + HOUSE.WindowSill
	wall("FrontLeft", W / 2 - doorHalf, H, T, -(W / 2 + doorHalf) / 2, wallY, frontZ)
	wall("FrontTop", W / 2 + doorHalf, H - HOUSE.DoorHeight, T, (W / 2 - doorHalf) / 2, (doorTop + F + H) / 2, frontZ)
	wall("FrontPillar", winMin - doorHalf, HOUSE.DoorHeight, T, (winMin + doorHalf) / 2, F + HOUSE.DoorHeight / 2, frontZ)
	wall("FrontBelowWindow", winMax - winMin, HOUSE.WindowSill, T, (winMin + winMax) / 2, F + HOUSE.WindowSill / 2, frontZ)
	wall("FrontRight", W / 2 - winMax, HOUSE.DoorHeight, T, (W / 2 + winMax) / 2, F + HOUSE.DoorHeight / 2, frontZ)

	-- One-way window (GDD §5): opaque by default; the client of a player who is
	-- inside this house makes it transparent locally.
	local pane = block(
		"WindowPane",
		Vector3.new(winMax - winMin, doorTop - sill, 0.3),
		houseCF * CFrame.new((winMin + winMax) / 2, (sill + doorTop) / 2, frontZ),
		Palette.Glass,
		house
	)
	pane.Material = Enum.Material.Glass
	pane.Reflectance = 0.15
	pane:AddTag("OneWayWindow")
	pane:SetAttribute("HouseId", houseId)
	decor(block(
		"WindowSill",
		Vector3.new(winMax - winMin + 0.8, 0.35, 1.6),
		houseCF * CFrame.new((winMin + winMax) / 2, sill - 0.1, frontZ),
		Palette.White,
		house
	))

	-- Roof.
	roofHalf("RoofFront", houseCF, -(D / 2 + HOUSE.RoofOverhang) / 2, false, roofColor, house)
	roofHalf("RoofBack", houseCF, (D / 2 + HOUSE.RoofOverhang) / 2, true, roofColor, house)
	block("Chimney", Vector3.new(2.4, 5, 2.4), houseCF * CFrame.new(-5, F + H + 4.5, 4), Palette.Stone, house)

	-- House number above the door.
	local sign = decor(block(
		"NumberSign",
		Vector3.new(2.4, 1.6, 0.2),
		houseCF * CFrame.new(0, doorTop + 1.6, -D / 2 - 0.1),
		Palette.WoodDark,
		house
	))
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "Number"
	signGui.Face = Enum.NormalId.Front
	signGui.CanvasSize = Vector2.new(120, 80)
	signGui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(houseId)
	label.TextScaled = true
	label.TextColor3 = Palette.White
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Parent = signGui

	-- Interior.
	decor(block("Rug", Vector3.new(8, 0.1, 6), houseCF * CFrame.new(0, F + 0.05, -1.5), Palette.Rug, house))
	local lamp = decor(block(
		"Lamp",
		Vector3.new(1.4, 0.8, 1.4),
		houseCF * CFrame.new(0, F + H - 0.5, 0),
		Palette.Lantern,
		house
	))
	lamp.Material = Enum.Material.Neon
	lamp:AddTag("HouseLamp")
	local light = Instance.new("PointLight")
	light.Color = Palette.Lantern
	light.Brightness = 0.7
	light.Range = 18
	light.Enabled = false
	light.Parent = lamp

	buildDoor(house, houseCF, houseId, frontZ)
	buildBed(house, houseCF, houseId)
	buildWardrobe(house, houseCF, houseId)

	-- Invisible volume used for "is this player inside house N?" checks.
	local zone = invisible(decor(block(
		"InteriorZone",
		Vector3.new(W - T * 2, H, D - T * 2),
		houseCF * CFrame.new(0, wallY, 0),
		Palette.White,
		house
	)))
	zone:AddTag("HouseInterior")
	zone:SetAttribute("HouseId", houseId)

	return house
end

local function buildGarden(parent: Instance, houseId: number, houseCF: CFrame)
	local gardenCF = houseCF * CFrame.new(0, 0, MapCfg.GardenRingRadius - MapCfg.HouseRingRadius)
	local garden = model(string.format("Garden%02d", houseId), parent)

	local soil = block("Soil", Vector3.new(10, 0.5, 8), gardenCF * CFrame.new(0, 0.25, 0), Palette.Soil, garden)
	soil:AddTag("GardenPlot")
	soil:SetAttribute("HouseId", houseId)
	attachment("PromptAnchor", CFrame.new(0, 1.5, 0), soil)
	garden.PrimaryPart = soil

	for row = -1, 1 do
		decor(block("Furrow", Vector3.new(9, 0.3, 1.2), gardenCF * CFrame.new(0, 0.6, row * 2.4), Palette.SoilDark, garden))
	end
	decor(block("BorderFront", Vector3.new(10.6, 0.8, 0.3), gardenCF * CFrame.new(0, 0.4, -4.15), Palette.Wood, garden))
	decor(block("BorderBack", Vector3.new(10.6, 0.8, 0.3), gardenCF * CFrame.new(0, 0.4, 4.15), Palette.Wood, garden))
	decor(block("BorderLeft", Vector3.new(0.3, 0.8, 8), gardenCF * CFrame.new(-5.15, 0.4, 0), Palette.Wood, garden))
	decor(block("BorderRight", Vector3.new(0.3, 0.8, 8), gardenCF * CFrame.new(5.15, 0.4, 0), Palette.Wood, garden))
end

local function buildHouses()
	local houses = folder("Houses", Map)
	local gardens = folder("Gardens", Map)
	local paths = folder("Paths", Map)

	local pathStart = MapCfg.PlazaRadius - 1
	local pathEnd = MapCfg.HouseRingRadius - HOUSE.Depth / 2 - 2.5
	local pathLength = pathEnd - pathStart

	for houseId = 1, MapCfg.HouseCount do
		local angle = (houseId - 1) / MapCfg.HouseCount * math.pi * 2
		local houseCF = facingCentre(MapCfg.HouseRingRadius, angle)
		buildHouse(houses, houseId, houseCF)
		buildGarden(gardens, houseId, houseCF)
		decor(block(
			"Path" .. houseId,
			Vector3.new(4.5, 0.2, pathLength),
			facingCentre((pathStart + pathEnd) / 2, angle) * CFrame.new(0, 0.02, 0),
			Palette.Path,
			paths
		))
	end
end

--------------------------------------------------------------------------------
-- Fence: the village / forest border, with gates
--------------------------------------------------------------------------------

local function buildFence()
	local fence = folder("Fence", Map)
	local segments = 48
	local step = math.pi * 2 / segments
	local radius = MapCfg.FenceRadius
	local length = 2 * radius * math.sin(step / 2)
	local gateEvery = segments / MapCfg.FenceGateCount

	local function isGate(segment: number): boolean
		-- Gates sit half-way between two houses.
		return (segment - 2) % gateEvery == 0
	end

	for segment = 0, segments - 1 do
		local angle = segment * step
		local gate = isGate(segment)

		-- Post at the start of this segment; taller when it frames a gate.
		local framesGate = gate or isGate((segment - 1) % segments)
		local postHeight = if framesGate then 7 else 4.4
		block(
			"Post",
			Vector3.new(0.8, postHeight, 0.8),
			CFrame.new(onRing(radius / math.cos(step / 2), angle - step / 2, postHeight / 2)),
			Palette.WoodDark,
			fence
		)

		if gate then
			decor(block(
				"GateBeam",
				Vector3.new(length + 0.8, 0.7, 0.9),
				facingCentre(radius, angle) * CFrame.new(0, 7, 0),
				Palette.WoodDark,
				fence
			))
		else
			for _, height in { 1.5, 3.1 } do
				block(
					"Rail",
					Vector3.new(length, 0.5, 0.35),
					facingCentre(radius, angle) * CFrame.new(0, height, 0),
					Palette.WoodLight,
					fence
				)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Forest
--------------------------------------------------------------------------------

-- Random points in a ring, at least `spacing` apart (rejection sampling).
local function scatter(count: number, innerRadius: number, outerRadius: number, spacing: number, taken: { Vector3 }): { Vector3 }
	local points: { Vector3 } = {}
	local attempts = 0
	while #points < count and attempts < count * 200 do
		attempts += 1
		local radius = math.sqrt(range(innerRadius * innerRadius, outerRadius * outerRadius))
		local point = onRing(radius, range(0, math.pi * 2))
		local ok = true
		for _, other in taken do
			if (other - point).Magnitude < spacing then
				ok = false
				break
			end
		end
		if ok then
			table.insert(points, point)
			table.insert(taken, point)
		end
	end
	return points
end

local function buildTaskTree(parent: Instance, treeId: number, position: Vector3)
	local tree = model(string.format("Tree%02d", treeId), parent)
	local scale = range(0.9, 1.25)
	local trunkHeight = 9 * scale
	local spin = CFrame.Angles(0, range(0, math.pi * 2), 0)
	local base = CFrame.new(position) * spin

	local trunk = block(
		"Trunk",
		Vector3.new(2.2 * scale, trunkHeight, 2.2 * scale),
		base * CFrame.new(0, trunkHeight / 2, 0),
		Palette.Trunk,
		tree
	)
	local leaf = pick(Palette.Leaves)
	local y = trunkHeight
	for index, size in { { 9, 4.5 }, { 7, 4 }, { 4.5, 3.2 } } do
		local width, height = size[1] * scale, size[2] * scale
		decor(block(
			"Leaves" .. index,
			Vector3.new(width, height, width),
			base * CFrame.new(0, y + height / 2 - 0.5, 0) * CFrame.Angles(0, index * 0.5, 0),
			leaf,
			tree
		)).CastShadow =
			true
		y += height - 0.5
	end

	tree.PrimaryPart = trunk
	tree:AddTag("TaskTree")
	tree:SetAttribute("TreeId", treeId)
	attachment("PromptAnchor", CFrame.new(0, -trunkHeight / 2 + 3.5, 0), trunk)
	attachment("AppleSpot", CFrame.new(0, trunkHeight / 2 + 1, -3.4 * scale), trunk)
	attachment("CrateSpot", CFrame.new(4.2 * scale, -trunkHeight / 2 + 1.2, 0), trunk)
end

--------------------------------------------------------------------------------
-- Stream and bridge (owner, 18 Nov 2026): north-east forest, for the
-- "fetch water" and "fishing" tasks
--------------------------------------------------------------------------------

local WATER = Color3.fromRGB(70, 150, 220)
local RIVERBED = Color3.fromRGB(95, 85, 70)

-- Builds the stream and returns points along it, so trees keep away.
local function buildStream(): { Vector3 }
	local cfg = MapCfg.Stream
	local stream = folder("Stream", Map)
	-- X = along the stream (tangent), Z = across it (towards the centre).
	local frame = facingCentre(cfg.Radius, cfg.Angle)
	decor(block("Riverbed", Vector3.new(cfg.Length, 0.1, cfg.Width + 2), frame * CFrame.new(0, 0.06, 0), RIVERBED, stream))
	local water = decor(block("Water", Vector3.new(cfg.Length, 0.3, cfg.Width), frame * CFrame.new(0, 0.3, 0), WATER, stream))
	water.Transparency = 0.25
	water.Material = Enum.Material.Glass
	for side = -1, 1, 2 do
		decor(block(
			"Bank",
			Vector3.new(cfg.Length, 0.5, 1.2),
			frame * CFrame.new(0, 0.25, side * (cfg.Width / 2 + 0.6)),
			Palette.Rock,
			stream
		))
	end

	-- The bridge crosses the stream; people walk out on it to reach the water.
	local bridge = model("Bridge", stream)
	local deckLength = cfg.Width + 8
	local deck = block("Deck", Vector3.new(cfg.BridgeWidth, 0.6, deckLength), frame * CFrame.new(0, 1, 0), Palette.Wood, bridge)
	bridge.PrimaryPart = deck
	for side = -1, 1, 2 do
		decor(block(
			"Rail",
			Vector3.new(0.4, 1.2, deckLength),
			frame * CFrame.new(side * (cfg.BridgeWidth / 2 - 0.2), 1.9, 0),
			Palette.WoodDark,
			bridge
		))
		block(
			"Ramp",
			Vector3.new(cfg.BridgeWidth, 0.4, 3),
			frame * CFrame.new(0, 0.5, side * (deckLength / 2 + 1.3)) * CFrame.Angles(side * math.rad(-12), 0, 0),
			Palette.Wood,
			bridge
		)
	end

	-- Task spots in the middle of the bridge: water on one side, fishing on the other.
	local waterSpot = invisible(decor(block("WaterSpot", Vector3.new(1, 1, 1), frame * CFrame.new(-(cfg.BridgeWidth / 2 - 1), 2, 0), WATER, bridge)))
	waterSpot:AddTag("WaterSpot")
	waterSpot:SetAttribute("SpotId", 1)
	attachment("PromptAnchor", CFrame.new(), waterSpot)
	local fishing = invisible(decor(block("FishingSpot", Vector3.new(1, 1, 1), frame * CFrame.new(cfg.BridgeWidth / 2 - 1, 2, 0), WATER, bridge)))
	fishing:AddTag("FishingSpot")
	fishing:SetAttribute("SpotId", 1)
	attachment("PromptAnchor", CFrame.new(), fishing)

	local points: { Vector3 } = {}
	for along = -cfg.Length / 2, cfg.Length / 2, 6 do
		table.insert(points, (frame * CFrame.new(along, 0, 0)).Position)
	end
	return points
end

local function buildForest(streamPoints: { Vector3 })
	local forest = folder("Forest", Map)
	local trees = folder("Trees", forest)
	local props = folder("Props", forest)
	local taken: { Vector3 } = table.clone(streamPoints)

	local inner = MapCfg.FenceRadius + 10
	local outer = MapCfg.ForestOuterRadius - 12
	for treeId, position in scatter(MapCfg.TaskTreeCount, inner, outer, 15, taken) do
		buildTaskTree(trees, treeId, position)
	end
	stats.TaskTrees = #trees:GetChildren()

	for _, position in scatter(34, inner - 4, outer + 6, 7, taken) do
		local size = range(2.5, 4.5)
		decor(block(
			"Bush",
			Vector3.new(size * 1.3, size * 0.8, size * 1.3),
			CFrame.new(position + Vector3.new(0, size * 0.4, 0)) * CFrame.Angles(0, range(0, 3), 0),
			pick(Palette.Leaves),
			props
		))
	end
	for _, position in scatter(22, inner - 4, outer + 6, 7, taken) do
		local size = range(1.5, 3.5)
		block(
			"Rock",
			Vector3.new(size * 1.4, size, size * 1.2),
			CFrame.new(position + Vector3.new(0, size * 0.35, 0)) * CFrame.Angles(range(-0.2, 0.2), range(0, 3), 0),
			Palette.Rock,
			props
		)
	end
end

--------------------------------------------------------------------------------
-- Outer forest and invisible walls
--------------------------------------------------------------------------------

local function buildOuterForest()
	local outerForest = folder("OuterForest", Map)
	local boundary = folder("Boundary", Map)
	local wallRadius = MapCfg.ForestOuterRadius

	-- Invisible walls: a closed polygon around the walkable forest.
	local segments = 40
	local step = math.pi * 2 / segments
	local length = 2 * wallRadius * math.tan(step / 2) + 1
	for segment = 0, segments - 1 do
		local wall = block(
			"Wall",
			Vector3.new(length, 80, 2),
			facingCentre(wallRadius + 1, segment * step) * CFrame.new(0, 38, 0),
			Palette.White,
			boundary
		)
		invisible(wall)
		wall.CanTouch = false
	end

	-- A dark hedge right behind the wall so the edge reads as dense forest.
	local hedgeSegments = 56
	local hedgeStep = math.pi * 2 / hedgeSegments
	local hedgeRadius = wallRadius + 6
	for segment = 0, hedgeSegments - 1 do
		decor(block(
			"Hedge",
			Vector3.new(2 * hedgeRadius * math.tan(hedgeStep / 2) + 2, range(20, 30), 7),
			facingCentre(hedgeRadius, segment * hedgeStep) * CFrame.new(0, 10, 0),
			Palette.DarkLeaf,
			outerForest
		))
	end

	-- Dense dark trees beyond.
	for _, position in scatter(170, wallRadius + 11, MapCfg.OuterForestRadius, 7, {}) do
		local height = range(26, 44)
		local width = range(7, 11)
		local spin = CFrame.Angles(0, range(0, math.pi * 2), 0)
		decor(block(
			"DarkTrunk",
			Vector3.new(2.4, height * 0.45, 2.4),
			CFrame.new(position + Vector3.new(0, height * 0.22, 0)) * spin,
			Palette.DarkTrunk,
			outerForest
		))
		decor(block(
			"DarkLeaves",
			Vector3.new(width, height * 0.7, width),
			CFrame.new(position + Vector3.new(0, height * 0.65, 0)) * spin,
			Palette.DarkLeaf,
			outerForest
		))
	end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

buildGround()
buildPlaza()
buildHouses()
buildFence()
buildForest(buildStream())
buildOuterForest()

stats.Houses = MapCfg.HouseCount
print(string.format(
	"[BuildVillage] done: %d parts, %d houses, %d task trees",
	stats.Parts,
	stats.Houses,
	stats.TaskTrees
))

return stats
