-- Runs the real builder scripts against an in-memory DataModel and checks the
-- contract the game scripts rely on (tags, attributes, positions).
local Config = require(game.ReplicatedStorage.Shared.Config)
local MapCfg = Config.Map

runBuilder("build/BuildVillage.luau")
runBuilder("build/BuildLighting.luau")

local Map = workspace:FindFirstChild("Map")

local function tagged(tag)
	local list = {}
	for _, instance in Map:GetDescendants() do
		if instance:HasTag(tag) then
			table.insert(list, instance)
		end
	end
	return list
end

local function flatRadius(position)
	return math.sqrt(position.X * position.X + position.Z * position.Z)
end

test("12 houses, each with a unique id and all required parts", function()
	local houses = tagged("House")
	expect(#houses).toBe(MapCfg.HouseCount)
	local seen = {}
	for _, house in houses do
		local id = house:GetAttribute("HouseId")
		expect(seen[id]).toBeNil()
		seen[id] = true
		for _, name in { "Floor", "Door", "Bed", "Wardrobe", "WindowPane", "InteriorZone", "RoofFront", "RoofBack" } do
			expect(house:FindFirstChild(name) ~= nil).toBe(true)
		end
		expect(house.Floor:FindFirstChild("InsideSpawn") ~= nil).toBe(true)
		expect(house.Floor:FindFirstChild("FrontSpawn") ~= nil).toBe(true)
	end
end)

test("every door faces the plaza and carries its HP attributes", function()
	local doors = tagged("Door")
	expect(#doors).toBe(MapCfg.HouseCount)
	for _, door in doors do
		local house = door.Parent
		expect(flatRadius(door.CFrame.Position) < flatRadius(house.Floor.CFrame.Position)).toBe(true)
		expect(door:GetAttribute("HP")).toBe(Config.Door.MaxHP)
		expect(door:GetAttribute("MaxHP")).toBe(Config.Door.MaxHP)
		expect(door:GetAttribute("ClosedCFrame").Position).toEqual(door.CFrame.Position)
		-- The open door swings outwards, towards the plaza.
		expect(flatRadius(door:GetAttribute("OpenCFrame").Position) < flatRadius(door.CFrame.Position)).toBe(true)
		expect(door:FindFirstChild("HPBar") ~= nil).toBe(true)
	end
end)

test("front spawn is outside in front of the door, inside spawn is indoors", function()
	for _, house in tagged("House") do
		local floor = house.Floor
		local front = (floor.CFrame * floor.FrontSpawn.CFrame).Position
		local inside = (floor.CFrame * floor.InsideSpawn.CFrame).Position
		local zone = house.InteriorZone
		local function isInside(point)
			local localPoint = zone.CFrame:PointToObjectSpace(point)
			return math.abs(localPoint.X) <= zone.Size.X / 2
				and math.abs(localPoint.Y) <= zone.Size.Y / 2
				and math.abs(localPoint.Z) <= zone.Size.Z / 2
		end
		expect(isInside(inside)).toBe(true)
		expect(isInside(front)).toBe(false)
		expect(flatRadius(front) < flatRadius(house.Door.CFrame.Position)).toBe(true)
	end
end)

test("two hiding spots per house, inside the house", function()
	local spots = tagged("HidingSpot")
	expect(#spots).toBe(MapCfg.HouseCount * 2)
	for _, spot in spots do
		local kind = spot:GetAttribute("Kind")
		expect(kind == "Bed" or kind == "Wardrobe").toBe(true)
		local primary = spot.PrimaryPart
		for _, name in { "HideSpot", "ExitSpot", "PromptAnchor" } do
			expect(primary:FindFirstChild(name) ~= nil).toBe(true)
		end
		local zone = spot.Parent.InteriorZone
		local exit = zone.CFrame:PointToObjectSpace((primary.CFrame * primary.ExitSpot.CFrame).Position)
		expect(math.abs(exit.X) < zone.Size.X / 2 and math.abs(exit.Z) < zone.Size.Z / 2).toBe(true)
	end
end)

test("one-way windows and gardens: one per house", function()
	expect(#tagged("OneWayWindow")).toBe(MapCfg.HouseCount)
	local plots = tagged("GardenPlot")
	expect(#plots).toBe(MapCfg.HouseCount)
	for _, plot in plots do
		local radius = flatRadius(plot.CFrame.Position)
		expect(radius > MapCfg.HouseRingRadius and radius < MapCfg.FenceRadius).toBe(true)
	end
end)

test("forest: new every match; trees in the walkable forest, never in the moat, the river or the way to the pier", function()
	local ForestLayout = require(game.ServerScriptService.Logic.ForestLayout)
	local Rng = require(game.ReplicatedStorage.Shared.Rng)
	local moatCfg = MapCfg.Moat
	local first = ForestLayout.generate(Rng.seeded(1))
	local second = ForestLayout.generate(Rng.seeded(2))
	expect((first.Trees[1] - second.Trees[1]).Magnitude > 0.01).toBe(true) -- not the same forest
	expect((first.Moat[10] - second.Moat[10]).Magnitude > 0.01).toBe(true) -- nor the same channel
	for seed = 1, 25 do
		local layout = ForestLayout.generate(Rng.seeded(seed))
		local moat = layout.Moat
		-- The channel starts and ends in the river and winds round the village.
		expect(#moat > 60).toBe(true)
		expect(ForestLayout.inRiver(moat[1])).toBe(true)
		expect(ForestLayout.inRiver(moat[#moat])).toBe(true)
		local swept = 0
		for index = 2, #moat - 1 do
			local radius = flatRadius(moat[index])
			expect(radius >= moatCfg.MinRadius - 0.01 and radius <= moatCfg.MaxRadius + 0.01).toBe(true)
			swept += 1
		end
		expect(swept * math.deg(moatCfg.Step) > 270).toBe(true)
		-- The way from the fence to the pier never crosses it.
		for radius = MapCfg.FenceRadius, MapCfg.River.ShoreDistance, 2 do
			local point = Vector3.new(math.sin(MapCfg.River.Angle) * radius, 0, -math.cos(MapCfg.River.Angle) * radius)
			expect(ForestLayout.inMoat(point, moat)).toBe(false)
		end
		expect(#layout.Trees).toBe(MapCfg.TaskTreeCount)
		for _, tree in layout.Trees do
			local radius = flatRadius(tree)
			expect(radius > MapCfg.FenceRadius and radius < MapCfg.ForestOuterRadius).toBe(true)
			expect(ForestLayout.inRiver(tree, 6)).toBe(false)
			expect(ForestLayout.distanceToPath(tree, moat) > moatCfg.Width / 2 + moatCfg.TreeMargin).toBe(true)
		end
		for _, list in { layout.Bushes, layout.Rocks } do
			for _, point in list do
				expect(ForestLayout.inMoat(point, moat)).toBe(false)
				expect(ForestLayout.inRiver(point)).toBe(false)
			end
		end
	end
end)

test("markers: meeting spots around the table, wolf spawn at the centre", function()
	local markers = Map.Markers
	for index = 1, MapCfg.HouseCount do
		local spot = markers:FindFirstChild("MeetingSpot" .. index)
		expect(spot ~= nil).toBe(true)
		expect(flatRadius(spot.CFrame.Position)).toBeNear(MapCfg.MeetingSpotRadius, 0.01)
		-- Standing on the spot, looking 5 studs ahead brings you closer to the table.
		local ahead = spot.CFrame.Position + spot.CFrame.LookVector * 5
		expect(flatRadius(ahead)).toBeNear(MapCfg.MeetingSpotRadius - 5, 0.01)
	end
	expect(flatRadius(markers.WolfSpawn.CFrame.Position) < MapCfg.PlazaRadius).toBe(true)
	expect(#tagged("MeetingBell")).toBe(1)
end)

test("invisible walls close the forest; the fence has gates", function()
	local walls = Map.Boundary:GetChildren()
	expect(#walls >= 32).toBe(true)
	for _, wall in walls do
		expect(wall.Transparency).toBe(1)
		expect(flatRadius(wall.CFrame.Position) >= MapCfg.ForestOuterRadius).toBe(true)
	end
	local gates = 0
	for _, part in Map.Fence:GetChildren() do
		if part.Name == "GateBeam" then
			gates += 1
		end
	end
	expect(gates).toBe(MapCfg.FenceGateCount)
end)

test("lighting starts on the Day preset with no Atmosphere", function()
	local Lighting = game:GetService("Lighting")
	expect(Lighting.ClockTime).toBe(Config.Lighting.Day.ClockTime)
	expect(Lighting.FogEnd).toBe(Config.Lighting.Day.FogEnd)
	expect(Lighting:FindFirstChild("Atmosphere")).toBeNil()
	expect(Lighting:FindFirstChild("PhaseColor") ~= nil).toBe(true)
end)
