local Logic = game.ServerScriptService.Logic
local HidingState = require(Logic.HidingState)
local SpeedStack = require(Logic.SpeedStack)

test("speed: base, multipliers and overrides", function()
	local stack = SpeedStack.new(20)
	expect(SpeedStack.speed(stack)).toBe(20)
	stack.Modifiers.Sprint = { Multiplier = 1.5 }
	expect(SpeedStack.speed(stack)).toBe(30)
	stack.Modifiers.Apple = { Multiplier = 1.3 }
	expect(SpeedStack.speed(stack)).toBeNear(39, 1e-9)
	stack.Modifiers.Maul = { Override = 0 }
	expect(SpeedStack.speed(stack)).toBe(0) -- a freeze beats every boost
	stack.Modifiers.Maul = nil
	stack.Modifiers.Sprint = nil
	stack.Modifiers.Apple = nil
	expect(SpeedStack.speed(stack)).toBe(20)
end)

test("speed: jump lock", function()
	local stack = SpeedStack.new(16)
	expect(SpeedStack.canJump(stack)).toBe(true)
	stack.Modifiers.Meeting = { Override = 0, NoJump = true }
	expect(SpeedStack.canJump(stack)).toBe(false)
end)

test("hiding: one player per spot", function()
	local state = HidingState.new()
	local bed = HidingState.spotKey(3, "Bed")
	expect(HidingState.hide(state, 1, bed)).toBe(true)
	expect(HidingState.hide(state, 2, bed)).toBe(false) -- occupied
	expect(HidingState.hide(state, 1, HidingState.spotKey(3, "Wardrobe"))).toBe(false) -- already hidden
	expect(HidingState.isHidden(state, 1)).toBe(true)
	expect(HidingState.leave(state, 1)).toBe(bed)
	expect(HidingState.hide(state, 2, bed)).toBe(true)
end)

test("hiding: searched out = cannot hide again until the night ends", function()
	local state = HidingState.new()
	local bed = HidingState.spotKey(3, "Bed")
	local wardrobe = HidingState.spotKey(3, "Wardrobe")
	HidingState.hide(state, 1, bed)
	expect(HidingState.search(state, wardrobe)).toBeNil() -- empty spot
	expect(HidingState.search(state, bed)).toBe(1)
	expect(HidingState.isHidden(state, 1)).toBe(false)
	expect(HidingState.hide(state, 1, wardrobe)).toBe(false)
	expect(HidingState.hide(state, 1, bed)).toBe(false)
	-- Leaving on your own does not lock you out.
	HidingState.hide(state, 2, bed)
	HidingState.leave(state, 2)
	expect(HidingState.hide(state, 2, wardrobe)).toBe(true)
	-- Next night everybody may hide again.
	HidingState.reset(state)
	expect(HidingState.hiddenIds(state)).toEqual({})
	expect(HidingState.hide(state, 1, bed)).toBe(true)
end)
