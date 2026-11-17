--!strict
--[[
	MoveService — the only place that writes Humanoid.WalkSpeed / jump.
	Other services set a base speed (human 16, wolf 20) and add or remove
	named modifiers (meeting freeze, sprint, maul, stun, apple...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SpeedStack = require(script.Parent.Parent.Logic.SpeedStack)

local MatchService = require(script.Parent.MatchService)

local MoveService = {}

local stacks: { [number]: SpeedStack.Stack } = {}

local function stackOf(id: number): SpeedStack.Stack
	local stack = stacks[id]
	if not stack then
		stack = SpeedStack.new(Config.Human.WalkSpeed)
		stacks[id] = stack
	end
	return stack
end

local function apply(id: number)
	local humanoid = MatchService.HumanoidOf(id)
	if not humanoid then
		return
	end
	local stack = stackOf(id)
	humanoid.WalkSpeed = SpeedStack.speed(stack)
	local canJump = SpeedStack.canJump(stack)
	humanoid.JumpPower = if canJump then Config.Human.JumpPower else 0
	humanoid.JumpHeight = if canJump then Config.Human.JumpHeight else 0
end

function MoveService.SetBase(id: number, speed: number)
	stackOf(id).Base = speed
	apply(id)
end

function MoveService.SetModifier(id: number, key: string, modifier: SpeedStack.Modifier)
	stackOf(id).Modifiers[key] = modifier
	apply(id)
end

function MoveService.ClearModifier(id: number, key: string)
	local stack = stackOf(id)
	if stack.Modifiers[key] ~= nil then
		stack.Modifiers[key] = nil
		apply(id)
	end
end

-- Removes one modifier from everybody (e.g. the meeting freeze).
function MoveService.ClearModifierForAll(key: string)
	for id in stacks do
		MoveService.ClearModifier(id, key)
	end
end

-- Re-applies the current speed to a new body (after a revive).
function MoveService.Refresh(id: number)
	apply(id)
end

function MoveService.Speed(id: number): number
	return SpeedStack.speed(stackOf(id))
end

function MoveService.Init() end
function MoveService.Start() end

return MoveService
