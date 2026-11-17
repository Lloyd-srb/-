local Config = require(game.ReplicatedStorage.Shared.Config)
local Rng = require(game.ReplicatedStorage.Shared.Rng)
local RoleAssignment = require(game.ServerScriptService.Logic.RoleAssignment)

local STARTER = { Villager = true, Sheriff = true, Doctor = true }
local ALL = {}
for _, roleId in Config.RoleOrder do
	ALL[roleId] = true
end

local function candidates(count, picks, usable)
	local list = {}
	for id = 1, count do
		list[id] = { Id = id, Picks = picks, Usable = usable }
	end
	return list
end

local function summarize(result)
	local counts, total = {}, 0
	for _, roleId in result do
		counts[roleId] = (counts[roleId] or 0) + 1
		total += 1
	end
	return counts, total
end

local function specialCount(counts)
	local n = 0
	for roleId, count in counts do
		if Config.Roles[roleId].Kind == "Special" then
			n += count
		end
	end
	return n
end

test("Casual, 12 new players: 1 wolf, unique Sheriff/Doctor, the rest villagers", function()
	for seed = 1, 200 do
		local result = RoleAssignment.assign(
			candidates(12, { "Villager", "Sheriff", "Doctor" }, STARTER),
			RoleAssignment.composition(12),
			Rng.seeded(seed)
		)
		local counts, total = summarize(result)
		expect(total).toBe(12)
		expect(counts.Wolf).toBe(1)
		expect((counts.Sheriff or 0) <= 1).toBe(true)
		expect((counts.Doctor or 0) <= 1).toBe(true)
		expect(1 + (counts.Sheriff or 0) + (counts.Doctor or 0) + (counts.Villager or 0)).toBe(12)
	end
end)

test("Casual, everyone owns everything: no duplicates, at most 6 special roles", function()
	for seed = 1, 200 do
		local result = RoleAssignment.assign(
			candidates(12, { "Seer", "Chief", "Bodyguard" }, ALL),
			RoleAssignment.composition(12),
			Rng.seeded(seed)
		)
		local counts, total = summarize(result)
		expect(total).toBe(12)
		expect(counts.Wolf).toBe(1)
		expect(specialCount(counts)).toBe(6)
		for roleId, count in counts do
			if roleId ~= "Villager" then
				expect(count).toBe(1)
			end
		end
		-- Killer and Fool do not use special slots; they replace villagers.
		expect((counts.Killer or 0) + (counts.Fool or 0) + (counts.Villager or 0)).toBe(5)
	end
end)

test("roles follow the player count: 8 to 12", function()
	local expected = { [8] = 4, [9] = 4, [10] = 5, [11] = 5, [12] = 6 }
	for players, special in expected do
		local composition = RoleAssignment.composition(players)
		expect(composition.Wolves).toBe(1)
		expect(composition.SpecialSlots).toBe(special)
		expect(composition.MaxSolo).toBe(if players >= 11 then 2 else 1)
		for seed = 1, 60 do
			local result = RoleAssignment.assign(
				candidates(players, { "Killer", "Fool", "Seer" }, ALL),
				composition,
				Rng.seeded(seed * players)
			)
			local counts, total = summarize(result)
			expect(total).toBe(players)
			expect(counts.Wolf).toBe(1)
			expect(specialCount(counts) <= special).toBe(true)
			local solo = (counts.Killer or 0) + (counts.Fool or 0)
			-- Killer and Fool together only with 11-12 players (owner, 17 Nov 2026).
			expect(solo).toBe(if players >= 11 then 2 else 1)
			expect((counts.Killer or 0) <= 1 and (counts.Fool or 0) <= 1).toBe(true)
		end
	end
end)

test("a player gets one of their own picks when it is free", function()
	for seed = 1, 100 do
		local list = {
			{ Id = 1, Picks = { "Seer", "Monk", "Engineer" }, Usable = ALL },
			{ Id = 2, Picks = { "Chief", "Bodyguard", "Doctor" }, Usable = ALL },
			{ Id = 3, Picks = { "Killer", "Fool", "Sheriff" }, Usable = ALL },
		}
		local result = RoleAssignment.assign(list, RoleAssignment.composition(12), Rng.seeded(seed))
		for _, candidate in list do
			local roleId = result[candidate.Id]
			if roleId ~= "Wolf" then
				expect(table.find(candidate.Picks, roleId) ~= nil).toBe(true)
			end
		end
	end
end)

test("owner rule: a player whose picks are gone never gets the Killer or Fool unpicked", function()
	for seed = 1, 200 do
		-- Everyone owns everything but picks the same three village roles, so
		-- most of them fall back. Killer / Fool are free, yet nobody picked them.
		local list = candidates(12, { "Seer", "Monk", "Engineer" }, ALL)
		local result = RoleAssignment.assign(list, RoleAssignment.composition(12), Rng.seeded(seed))
		for _, roleId in result do
			expect(roleId ~= "Killer" and roleId ~= "Fool").toBe(true)
		end
	end
end)

test("the wolf is spread evenly (random, not chosen)", function()
	local wolfCount = {}
	for seed = 1, 1200 do
		local result = RoleAssignment.assign(
			candidates(12, { "Villager", "Sheriff", "Doctor" }, STARTER),
			RoleAssignment.composition(12),
			Rng.seeded(seed * 7919)
		)
		for id, roleId in result do
			if roleId == "Wolf" then
				wolfCount[id] = (wolfCount[id] or 0) + 1
			end
		end
	end
	for id = 1, 12 do
		expect(wolfCount[id]).toBeNear(100, 45)
	end
end)

test("forced debug role is honoured", function()
	local result = RoleAssignment.assign(
		candidates(3, { "Villager", "Sheriff", "Doctor" }, STARTER),
		RoleAssignment.composition(12),
		Rng.seeded(5),
		{ [2] = "Wolf" }
	)
	expect(result[2]).toBe("Wolf")
	expect(result[1] ~= "Wolf" and result[3] ~= "Wolf").toBe(true)
end)

test("usableRoles applies ownership and level gates", function()
	local usable = RoleAssignment.usableRoles({ Chief = true, Killer = true }, 5)
	expect(usable.Villager).toBe(true)
	expect(usable.Chief).toBe(true)
	expect(usable.Killer).toBeNil() -- owned but needs level 20
	expect(usable.Seer).toBeNil() -- not owned
end)

test("validatePicks rejects bad input", function()
	expect(RoleAssignment.validatePicks({ "Villager", "Sheriff", "Doctor" }, STARTER)).toBe(true)
	expect(RoleAssignment.validatePicks({ "Villager", "Sheriff" }, STARTER)).toBe(false)
	expect(RoleAssignment.validatePicks({ "Villager", "Sheriff", "Sheriff" }, STARTER)).toBe(false)
	expect(RoleAssignment.validatePicks({ "Villager", "Sheriff", "Killer" }, STARTER)).toBe(false)
	expect(RoleAssignment.validatePicks({ "Villager", "Sheriff", "Wolf" }, ALL)).toBe(false)
	expect(RoleAssignment.validatePicks({ "Villager", "Sheriff", "Hacker" }, ALL)).toBe(false)
end)

test("defaultPicks returns 3 usable roles", function()
	local picks = RoleAssignment.defaultPicks(STARTER, Rng.seeded(1))
	expect(#picks).toBe(3)
	expect(RoleAssignment.validatePicks(picks, STARTER)).toBe(true)
end)
