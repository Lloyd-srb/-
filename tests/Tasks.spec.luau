--[[
	Daily tasks (GDD §10): pure rules, then the real server on the fake engine.
]]

local Rng = require(game.ReplicatedStorage.Shared.Rng)
local DailyTask = require(game.ServerScriptService.Logic.DailyTask)

local WORLD = { BrokenDoors = {}, Plots = { 1, 2, 3 }, Trees = { 10, 11, 12, 13, 14 } }

test("rules: repair is only offered after a door was broken", function()
	expect(table.find(DailyTask.availableKinds(WORLD), "RepairDoor")).toBeNil()
	local broken = { BrokenDoors = { 7 }, Plots = WORLD.Plots, Trees = WORLD.Trees }
	expect(table.find(DailyTask.availableKinds(broken), "RepairDoor") ~= nil).toBe(true)
	expect(DailyTask.pick(WORLD, Rng.seeded(1), "RepairDoor").Kind ~= "RepairDoor").toBe(true)
	expect(DailyTask.pick(broken, Rng.seeded(1), "RepairDoor").Targets).toEqual({ 7 })
end)

test("rules: apples on 3 personal trees, chop any 2 different trees", function()
	local apples = DailyTask.make("PickApples", WORLD, Rng.seeded(4))
	expect(#apples.Targets).toBe(3)
	expect(apples.Required).toBe(3)
	local other = table.find(WORLD.Trees, 10) and 10
	for _, tree in WORLD.Trees do
		if not table.find(apples.Targets, tree) then
			other = tree
		end
	end
	expect(DailyTask.mark(apples, other)).toBe(false) -- not one of my trees
	expect(DailyTask.mark(apples, apples.Targets[1])).toBe(true)
	expect(DailyTask.mark(apples, apples.Targets[1])).toBe(false) -- already picked
	DailyTask.mark(apples, apples.Targets[2])
	local _, complete = DailyTask.mark(apples, apples.Targets[3])
	expect(complete).toBe(true)
	expect(DailyTask.reward("PickApples")).toBe("Apple")

	local chop = DailyTask.make("ChopTrees", WORLD, Rng.seeded(4))
	expect(chop.Required).toBe(2)
	DailyTask.mark(chop, 12)
	expect(DailyTask.mark(chop, 12)).toBe(false) -- the same tree twice does not count
	local _, done = DailyTask.mark(chop, 14)
	expect(done).toBe(true)
	expect(DailyTask.mark(chop, 10)).toBe(false) -- nothing more after completion
	expect(DailyTask.reward("ChopTrees")).toBe("Axe")
	expect(DailyTask.reward("PlantCarrot")).toBe("Shovel")
	expect(DailyTask.reward("RepairDoor")).toBeNil()
end)

--------------------------------------------------------------------------------

local function start(scale, forceTask)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = {
			TimerScale = scale,
			MinPlayers = 3,
			FillWithBots = true,
			UnlockAllRoles = false,
			ForceRoles = { [1] = "Villager", [2] = "Doctor", [3] = "Sheriff", [-1004] = "Wolf" },
			ForceTask = forceTask,
		},
	})
	local folder = server.game.ServerScriptService.Services
	local svc = setmetatable({}, {
		__index = function(_, name)
			return server.require(folder[name .. "Service"])
		end,
	})
	return server, svc
end

local function waitFor(server, phase, number)
	server.waitFor(phase .. " " .. number, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == phase and (if phase == "Night" then last[1].Night else last[1].Day) == number
	end, 10)
end

local function anchorPosition(prompt)
	local anchor = prompt.Parent
	if anchor:IsA("Attachment") then
		return (anchor.Parent.CFrame * anchor.CFrame).Position
	end
	return anchor.CFrame.Position
end

-- Walks player `id` next to the prompt and holds E.
local function doStep(server, svc, id, prompt)
	svc.Match.RootOf(id).CFrame = CFrame.new(anchorPosition(prompt) + Vector3.new(2, 0, 0))
	return server.trigger(prompt, id)
end

local function promptFor(server, kind, target)
	for _, prompt in server.game.Workspace:GetDescendants() do
		if prompt:IsA("ProximityPrompt") and prompt.Name == kind .. "Prompt" and prompt:GetAttribute("TargetId") == target then
			return prompt
		end
	end
	error("no prompt for " .. kind .. " " .. target)
end

local function finish(server, svc)
	svc.Match.Exile(-1004)
	server.waitForPhase("GameOver", 10)
end

test("plant carrots: private task, steps checked, shovel reward, lost at night", function()
	local server, svc = start(0.02, "PlantCarrot")
	waitFor(server, "Day", 1)
	for _, id in { 1, 2, 3 } do
		local task = server.last("TaskChanged", id)[1]
		expect(task.Kind).toBe("PlantCarrot")
		expect(#task.Targets).toBe(12)
	end
	expect(#server.sent("TaskChanged", "all")).toBe(0) -- nobody learns other people's tasks
	expect(svc.Task.TaskOf(-1005)).toBeNil() -- bots get no task

	-- Wrong task kind, too far, then right.
	expect(doStep(server, svc, 1, promptFor(server, "ChopTrees", 1))).toBe(true)
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(0)
	local plot = promptFor(server, "PlantCarrot", 4)
	expect(plot:GetAttribute("Audience")).toBe("Task:PlantCarrot")
	svc.Match.RootOf(1).CFrame = CFrame.new(0, 3, 0)
	server.trigger(plot, 1)
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(0)
	doStep(server, svc, 1, plot)
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(1)
	expect(svc.Inventory.Count(1, "Shovel")).toBe(1)
	expect(server.last("TaskChanged", 1)[1].Complete).toBe(true)
	local done = false
	for _, args in server.sent("Effect", 1) do
		if args[1].Kind == "TaskComplete" then
			done = args[1].Coins == 20
		end
	end
	expect(done).toBe(true)
	doStep(server, svc, 1, promptFor(server, "PlantCarrot", 5)) -- already complete
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(1)
	expect(svc.Inventory.Count(1, "Shovel")).toBe(1)

	-- Bob does not finish: at nightfall the task is gone and the prompts close.
	server.waitForPhase("FullMoonWarning", 10)
	expect(server.last("TaskChanged", 2)[1]).toBeNil()
	expect(plot.Enabled).toBe(false)
	doStep(server, svc, 2, plot)
	expect(svc.Match.Roster.Members[2].TasksCompleted).toBe(0)
	finish(server, svc)
end)

test("pick apples on your own three trees, chop two trees", function()
	local server, svc = start(0.02, "PickApples")
	waitFor(server, "Day", 1)
	local task = server.last("TaskChanged", 1)[1]
	expect(#task.Targets).toBe(3)
	-- Somebody else's apple tree does nothing for Alice.
	local notMine = nil
	for treeId = 1, 44 do
		if not table.find(task.Targets, treeId) then
			notMine = treeId
			break
		end
	end
	doStep(server, svc, 1, promptFor(server, "PickApples", notMine))
	expect(#server.last("TaskChanged", 1)[1].Done).toBe(0)
	for index, treeId in task.Targets do
		doStep(server, svc, 1, promptFor(server, "PickApples", treeId))
		expect(#server.last("TaskChanged", 1)[1].Done).toBe(index)
	end
	expect(svc.Inventory.Count(1, "Apple")).toBe(1)
	expect(svc.Match.Roster.Members[1].TasksCompleted).toBe(1)

	svc.Match.Exile(-1004)
	server.waitForPhase("GameOver", 10)

	local server2, svc2 = start(0.02, "ChopTrees")
	waitFor(server2, "Day", 1)
	doStep(server2, svc2, 2, promptFor(server2, "ChopTrees", 7))
	doStep(server2, svc2, 2, promptFor(server2, "ChopTrees", 7)) -- the same tree again
	expect(svc2.Inventory.Count(2, "Axe")).toBe(0)
	doStep(server2, svc2, 2, promptFor(server2, "ChopTrees", 30))
	expect(svc2.Inventory.Count(2, "Axe")).toBe(1)
	local axe = svc2.Inventory.Items(2)[1]
	expect(axe.Uses).toBe(2)
	-- The tool is in Bob's backpack with the same id.
	local tool = server2.player(2).Backpack:FindFirstChildOfClass("Tool")
	expect(tool:GetAttribute("ItemId")).toBe(axe.Id)
	expect(tool:GetAttribute("Kind")).toBe("Axe")
	finish(server2, svc2)
end)

test("repair the door broken last night", function()
	local server, svc = start(0.02, "RepairDoor")
	waitFor(server, "Day", 1)
	-- Nothing was broken yet: day 1 gives another task.
	expect(server.last("TaskChanged", 1)[1].Kind ~= "RepairDoor").toBe(true)

	waitFor(server, "Night", 1)
	for _ = 1, 5 do
		svc.House.DamageDoor(6, server.Config.Wolf.DoorDamage)
	end
	waitFor(server, "Day", 2)
	local task = server.last("TaskChanged", 3)[1]
	expect(task.Kind).toBe("RepairDoor")
	expect(task.Targets).toEqual({ 6 })
	local door = server.game.Workspace.Map.Houses.House06.Door
	expect(door.RepairFront.Enabled).toBe(true)
	doStep(server, svc, 3, promptFor(server, "RepairDoor", 6))
	expect(door.RepairFront.Enabled).toBe(false) -- repaired
	expect(svc.Match.Roster.Members[3].TasksCompleted).toBe(1)
	expect(#svc.Inventory.Items(3)).toBe(0) -- coins only
	-- Someone else with the same task can no longer repair it.
	doStep(server, svc, 2, promptFor(server, "RepairDoor", 6))
	expect(svc.Match.Roster.Members[2].TasksCompleted).toBe(0)
	finish(server, svc)
end)
