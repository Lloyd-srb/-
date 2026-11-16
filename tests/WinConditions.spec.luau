local WinConditions = require(game.ServerScriptService.Logic.WinConditions)

local function snap(wolves, killerAlive, others, wolfKills, killerKills)
	return {
		WolfSideAlive = wolves,
		KillerAlive = killerAlive,
		OthersAlive = others,
		WolfKills = wolfKills or 0,
		KillerKills = killerKills or 0,
	}
end

test("village wins when the whole wolf side is gone", function()
	expect(WinConditions.evaluate(snap(0, false, 4))).toBe("Village")
end)

test("the game goes on while the pup is alive", function()
	expect(WinConditions.evaluate(snap(1, false, 4))).toBeNil()
end)

test("wolf wins when villagers equal the wolf side", function()
	expect(WinConditions.evaluate(snap(1, false, 2))).toBeNil()
	expect(WinConditions.evaluate(snap(1, false, 1))).toBe("Wolf")
	expect(WinConditions.evaluate(snap(2, false, 2))).toBe("Wolf")
end)

test("GDD example: 2 wolves + 2 villagers + killer = not over", function()
	expect(WinConditions.evaluate(snap(2, true, 2, 3, 5))).toBeNil()
end)

test("GDD example: 2 wolves + 1 villager + killer = over, compare kills", function()
	expect(WinConditions.evaluate(snap(2, true, 1, 3, 5))).toBe("Killer")
	expect(WinConditions.evaluate(snap(2, true, 1, 5, 3))).toBe("Wolf")
	expect(WinConditions.evaluate(snap(2, true, 1, 4, 4))).toBe("Wolf")
end)

test("killer wins with wolves gone and 1 villager left", function()
	expect(WinConditions.evaluate(snap(0, true, 3))).toBeNil()
	expect(WinConditions.evaluate(snap(0, true, 2))).toBeNil()
	expect(WinConditions.evaluate(snap(0, true, 1))).toBe("Killer")
end)

test("fool wins only when exiled", function()
	expect(WinConditions.onExile("Fool")).toBe("Fool")
	expect(WinConditions.onExile("Wolf")).toBeNil()
	expect(WinConditions.onExile("Villager")).toBeNil()
end)

test("wolf leaves: village wins unless a pup is alive", function()
	expect(WinConditions.onWolfLeft(false)).toBe("Village")
	expect(WinConditions.onWolfLeft(true)).toBeNil()
end)
