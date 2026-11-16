local Rng = require(game.ReplicatedStorage.Shared.Rng)
local Zones = require(game.ReplicatedStorage.Shared.Zones)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Logic = game.ServerScriptService.Logic
local DoorState = require(Logic.DoorState)
local NightHousing = require(Logic.NightHousing)
local Roster = require(Logic.Roster)
local WinConditions = require(Logic.WinConditions)

local function roster(roles)
	local r = Roster.new()
	local map = {}
	for id, roleId in roles do
		Roster.add(r, id, "P" .. id, false)
		map[id] = roleId
	end
	Roster.setRoles(r, map)
	return r
end

test("night housing: everyone gets a different house", function()
	for seed = 1, 100 do
		local ids = { 11, 4, 7, 9, 2, 30, 31, 32, 33, 34, 35, 36 }
		local assigned = NightHousing.assign(ids, 12, Rng.seeded(seed))
		local used = {}
		for _, id in ids do
			local house = assigned[id]
			expect(house >= 1 and house <= 12).toBe(true)
			expect(used[house]).toBeNil()
			used[house] = true
		end
	end
end)

test("night housing is random between nights", function()
	local first = NightHousing.assign({ 1, 2, 3 }, 12, Rng.seeded(1))
	local different = false
	for seed = 2, 20 do
		local other = NightHousing.assign({ 1, 2, 3 }, 12, Rng.seeded(seed))
		if other[1] ~= first[1] then
			different = true
		end
	end
	expect(different).toBe(true)
end)

test("door: 5 wolf hits or 10 pup hits break it", function()
	local door = DoorState.new()
	for _ = 1, 4 do
		expect(DoorState.damage(door, Config.Wolf.DoorDamage)).toBe(false)
	end
	expect(DoorState.damage(door, Config.Wolf.DoorDamage)).toBe(true)
	expect(door.State).toBe("Broken")
	expect(DoorState.damage(door, Config.Wolf.DoorDamage)).toBe(false) -- already broken

	local pupDoor = DoorState.new()
	local hits = 0
	repeat
		hits += 1
	until DoorState.damage(pupDoor, Config.Pup.DoorDamage)
	expect(hits).toBe(10)
end)

test("door: can be opened once and never closed during the night", function()
	local door = DoorState.new()
	expect(DoorState.open(door)).toBe(true)
	expect(DoorState.open(door)).toBe(false)
	expect(DoorState.damage(door, 100)).toBe(false) -- an open door takes no damage
	DoorState.beginDay(door)
	expect(door.State).toBe("Closed")
end)

test("door: broken -> repair marks next morning -> normal the next night", function()
	local door = DoorState.new()
	DoorState.damage(door, 100)
	DoorState.beginDay(door)
	expect({ door.State, door.RepairLook, door.HP }).toEqual({ "Closed", true, 100 })
	DoorState.beginNight(door)
	expect({ door.State, door.RepairLook }).toEqual({ "Closed", false })
	DoorState.beginDay(door)
	expect(door.RepairLook).toBe(false)
end)

test("door: repair task clears the marks", function()
	local door = DoorState.new()
	DoorState.damage(door, 100)
	DoorState.beginDay(door)
	expect(DoorState.repair(door)).toBe(true)
	expect(door.RepairLook).toBe(false)
	expect(DoorState.repair(door)).toBe(false)
end)

test("door: engineer reinforcement doubles HP, lasts the night, gone by morning", function()
	local door = DoorState.new()
	-- Reinforced during the day: still there that night.
	expect(DoorState.reinforce(door)).toBe(true)
	DoorState.beginNight(door)
	expect({ door.HP, door.MaxHP }).toEqual({ 200, 200 })
	local hits = 0
	repeat
		hits += 1
	until DoorState.damage(door, Config.Wolf.DoorDamage)
	expect(hits).toBe(10)
	DoorState.beginDay(door)
	expect({ door.HP, door.MaxHP, door.Reinforced }).toEqual({ 100, 100, false })

	-- Reinforced at night on a damaged door: full and doubled.
	DoorState.beginNight(door)
	DoorState.damage(door, 60)
	DoorState.reinforce(door)
	expect({ door.HP, door.MaxHP }).toEqual({ 200, 200 })
	DoorState.damage(door, 200)
	expect(DoorState.reinforce(door)).toBe(false) -- cannot reinforce a broken door
end)

test("roster snapshot counts factions for the win check", function()
	local r = roster({ [1] = "Wolf", [2] = "Villager", [3] = "Sheriff", [4] = "Killer", [5] = "Fool" })
	expect(Roster.snapshot(r)).toEqual({
		WolfSideAlive = 1,
		KillerAlive = true,
		OthersAlive = 3,
		WolfKills = 0,
		KillerKills = 0,
	})
	expect(WinConditions.evaluate(Roster.snapshot(r))).toBeNil()
end)

test("roster: kills are credited to the right side", function()
	local r = roster({ [1] = "Wolf", [2] = "Villager", [3] = "Sheriff", [4] = "Killer", [5] = "Villager" })
	expect(Roster.recordDeath(r, 2, "Wolf", 1, 1)).toBe(true)
	expect(Roster.recordDeath(r, 2, "Wolf", 1, 1)).toBe(false) -- already dead
	Roster.recordDeath(r, 3, "Killer", 1, 4)
	Roster.recordDeath(r, 5, "Exile", 1)
	expect({ r.WolfKills, r.KillerKills }).toEqual({ 1, 1 })
	expect({ r.Members[1].Kills, r.Members[4].Kills }).toEqual({ 1, 1 })
	-- wolf 1 vs killer 1, nobody else: game over, kills tied -> wolf
	expect(WinConditions.evaluate(Roster.snapshot(r))).toBe("Wolf")
end)

test("roster: pup conversion, wolf loss and promotion", function()
	local r = roster({ [1] = "Wolf", [2] = "Doctor", [3] = "Villager", [4] = "Villager", [5] = "Villager" })
	expect(Roster.convertToPup(r, 2, 1)).toBe(true)
	expect(Roster.convertToPup(r, 2, 1)).toBe(false)
	expect({ r.PupsCreated, r.WolfKills }).toEqual({ 1, 1 })
	expect(Roster.pup(r).Id).toBe(2)
	expect(Roster.mainWolf(r).Id).toBe(1)
	expect(Roster.findRole(r, "Doctor")).toBeNil() -- the pup lost its old role
	expect(Roster.snapshot(r).WolfSideAlive).toBe(2)

	-- The wolf is exiled after 2 nights: the pup keeps the game going.
	Roster.recordDeath(r, 1, "Exile", 2)
	expect(r.MainWolfLostAtNight).toBe(2)
	expect(Roster.mainWolf(r)).toBeNil()
	expect(WinConditions.evaluate(Roster.snapshot(r))).toBeNil()

	local promoted = Roster.promotePup(r)
	expect(promoted.Id).toBe(2)
	expect(promoted.Role).toBe("Wolf")
	expect(Roster.mainWolf(r).Id).toBe(2)
	expect(Roster.pup(r)).toBeNil()
	expect(r.MainWolfLostAtNight).toBeNil()
end)

test("roster: nights survived only count for the living", function()
	local r = roster({ [1] = "Wolf", [2] = "Villager", [3] = "Villager" })
	Roster.creditNightSurvived(r)
	Roster.recordDeath(r, 3, "Wolf", 2, 1)
	Roster.creditNightSurvived(r)
	expect({ r.Members[2].NightsSurvived, r.Members[3].NightsSurvived }).toEqual({ 2, 1 })
end)

test("zones: the fence splits village and forest", function()
	expect(Zones.isVillage(Vector3.new(0, 0, 0))).toBe(true)
	expect(Zones.isVillage(Vector3.new(Config.Map.FenceRadius - 1, 50, 0))).toBe(true)
	expect(Zones.isForest(Vector3.new(Config.Map.FenceRadius + 1, 0, 0))).toBe(true)
	local box = CFrame.new(10, 5, 10) * CFrame.Angles(0, math.rad(90), 0)
	expect(Zones.isInsideBox(box, Vector3.new(4, 10, 20), Vector3.new(19, 5, 10))).toBe(true)
	expect(Zones.isInsideBox(box, Vector3.new(4, 10, 20), Vector3.new(10, 5, 19))).toBe(false)
end)
