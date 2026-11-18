--!strict
--[[
	SpeedStack — pure walk-speed maths. Several systems change a character's
	speed at once (wolf form, sprint, apple, stun, meeting freeze). Each one
	adds a named modifier instead of writing WalkSpeed directly.

	final speed = lowest Override if any modifier has one,
	              otherwise (Base + every Add) x every Multiplier.
]]

export type Modifier = {
	Multiplier: number?,
	Add: number?, -- e.g. +3 from the boots
	Override: number?, -- e.g. 0 while frozen
	NoJump: boolean?,
}

export type Stack = {
	Base: number,
	Modifiers: { [string]: Modifier },
}

local SpeedStack = {}

function SpeedStack.new(base: number): Stack
	return { Base = base, Modifiers = {} }
end

function SpeedStack.speed(stack: Stack): number
	local override: number? = nil
	local multiplier = 1
	local add = 0
	for _, modifier in stack.Modifiers do
		add += modifier.Add or 0
		if modifier.Override ~= nil then
			override = if override == nil then modifier.Override else math.min(override, modifier.Override)
		end
		if modifier.Multiplier ~= nil then
			multiplier *= modifier.Multiplier
		end
	end
	if override ~= nil then
		return override
	end
	return (stack.Base + add) * multiplier
end

function SpeedStack.canJump(stack: Stack): boolean
	for _, modifier in stack.Modifiers do
		if modifier.NoJump then
			return false
		end
	end
	return true
end

return SpeedStack
