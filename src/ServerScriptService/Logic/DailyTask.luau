--!strict
--[[
	DailyTask — pure rules for the personal task of the day (GDD §10).

	Every morning each living player gets one random task (replacing the old
	one); it is lost if not finished before night.
	  RepairDoor   repair a door broken last night  (only offered on such days)
	  PlantCarrot  plant at any garden plot         -> Shovel
	  PickApples   3 trees chosen for this player   -> Apple
	  ChopTrees    any 2 different trees            -> Axe
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

export type Task = {
	Kind: string,
	Targets: { number }, -- ids of doors (house ids), plots (house ids) or trees
	Required: number, -- how many different targets must be done
	Done: { [number]: boolean },
	Complete: boolean,
}

export type World = {
	BrokenDoors: { number }, -- houses whose door was broken last night (still unrepaired)
	Plots: { number },
	Trees: { number },
}

local DailyTask = {}

function DailyTask.availableKinds(world: World): { string }
	local kinds: { string } = {}
	for _, kind in Config.Tasks.Kinds do
		if kind ~= "RepairDoor" or #world.BrokenDoors > 0 then
			table.insert(kinds, kind)
		end
	end
	return kinds
end

function DailyTask.make(kind: string, world: World, rng: Rng.Rng): Task
	local targets: { number }
	local required = 1
	if kind == "RepairDoor" then
		targets = table.clone(world.BrokenDoors)
	elseif kind == "PlantCarrot" then
		targets = table.clone(world.Plots)
	elseif kind == "PickApples" then
		-- This player's own apples grow on a few random trees.
		local shuffled = Rng.shuffle(world.Trees, rng)
		required = math.min(Config.Tasks.PickApples.Trees, #shuffled)
		targets = {}
		for index = 1, required do
			targets[index] = shuffled[index]
		end
		table.sort(targets)
	else -- ChopTrees
		targets = table.clone(world.Trees)
		required = math.min(Config.Tasks.ChopTrees.Trees, #targets)
	end
	return { Kind = kind, Targets = targets, Required = required, Done = {}, Complete = false }
end

-- A random task from what is available today. `forced` (debug) wins if available.
function DailyTask.pick(world: World, rng: Rng.Rng, forced: string?): Task
	local kinds = DailyTask.availableKinds(world)
	local kind = if forced and table.find(kinds, forced) then forced else Rng.pick(kinds, rng)
	return DailyTask.make(kind, world, rng)
end

function DailyTask.doneCount(task: Task): number
	local count = 0
	for _ in task.Done do
		count += 1
	end
	return count
end

-- Is `target` a step this task still needs?
function DailyTask.wants(task: Task, target: number): boolean
	return not task.Complete and table.find(task.Targets, target) ~= nil and not task.Done[target]
end

-- Records a step. Returns (accepted, task now complete).
function DailyTask.mark(task: Task, target: number): (boolean, boolean)
	if not DailyTask.wants(task, target) then
		return false, false
	end
	task.Done[target] = true
	if DailyTask.doneCount(task) >= task.Required then
		task.Complete = true
		return true, true
	end
	return true, false
end

-- The item a finished task gives (nil = coins only).
function DailyTask.reward(kind: string): string?
	local cfg = (Config.Tasks :: any)[kind]
	return if cfg then cfg.Reward else nil
end

-- What the owner's client needs to show the task (no other player's data).
function DailyTask.view(task: Task): { [string]: any }
	local done: { number } = {}
	for target in task.Done do
		table.insert(done, target)
	end
	table.sort(done)
	return {
		Kind = task.Kind,
		Targets = task.Targets,
		Required = task.Required,
		Done = done,
		Complete = task.Complete,
	}
end

return DailyTask
