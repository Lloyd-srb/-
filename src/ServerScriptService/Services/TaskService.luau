--!strict
--[[
	TaskService — the personal task of the day (GDD §10).

	Each morning every living player gets one random task, replacing the old
	one; it is lost at nightfall if unfinished. A finished task is worth
	+20 coins at the end of the match (win or lose) and some give an item.
	Tasks are private: only the owner is told what their task is.

	Every task step is a "hold E" prompt. The prompts exist for everyone but
	each client only shows the ones its own task needs; the server checks the
	task, the target, the distance and the phase again.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local DailyTask = require(Logic.DailyTask)
local Roster = require(Logic.Roster)

local HidingService = require(script.Parent.HidingService)
local HouseService = require(script.Parent.HouseService)
local InventoryService = require(script.Parent.InventoryService)
local AudioService = require(script.Parent.AudioService)
local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)
local WolfService = require(script.Parent.WolfService)

local REACH_SLACK = 4
local STEP_SOUNDS: { [string]: string } = { ChopTrees = "TreeChop", PlantCarrot = "Digging", RepairDoor = "Reinforce" }

type StepPrompt = { Prompt: ProximityPrompt, Kind: string, Target: number }

local TaskService = {}

local tasks: { [number]: DailyTask.Task } = {}
local prompts: { StepPrompt } = {}
local plots: { number } = {}
local trees: { number } = {}
local rng = Rng.wrap(Random.new())

function TaskService.TaskOf(id: number): DailyTask.Task?
	return tasks[id]
end

local function isTaskTime(): boolean
	local phase = RoundService.State.Phase
	return phase == "Day" or phase == "MeetingCountdown"
end

local function send(id: number)
	local player = MatchService.PlayerOf(id)
	local task = tasks[id]
	if player then
		Net.fire(player, "TaskChanged", if task then DailyTask.view(task) else nil)
	end
end

local function setPromptsActive(active: boolean)
	for _, step in prompts do
		step.Prompt:SetAttribute("Active", active)
		step.Prompt.Enabled = active
	end
end

--------------------------------------------------------------------------------
-- Steps
--------------------------------------------------------------------------------

local function onStep(player: Player, step: StepPrompt)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or not isTaskTime() then
		return
	end
	if WolfService.IsTransformed(member.Id) or HidingService.IsHidden(member.Id) then
		return
	end
	local task = tasks[member.Id]
	if not task or task.Kind ~= step.Kind or not DailyTask.wants(task, step.Target) then
		return
	end
	local root = MatchService.RootOf(member.Id)
	local anchor = step.Prompt.Parent
	local position = if anchor and anchor:IsA("Attachment")
		then Zones.worldCFrame(anchor).Position
		elseif anchor and anchor:IsA("BasePart") then anchor.CFrame.Position
		else nil
	if not root or not position then
		return
	end
	if (root.CFrame.Position - position).Magnitude > step.Prompt.MaxActivationDistance + REACH_SLACK then
		return
	end
	if step.Kind == "RepairDoor" and not HouseService.RepairDoor(step.Target) then
		return -- someone else repaired it first
	end

	local stepSound = STEP_SOUNDS[step.Kind]
	if stepSound then
		AudioService.At(stepSound, position)
	end
	local _, complete = DailyTask.mark(task, step.Target)
	if complete then
		member.TasksCompleted += 1
		local reward = DailyTask.reward(task.Kind)
		if reward then
			InventoryService.Give(member.Id, reward)
		end
		Net.fire(player, "Effect", { Kind = "TaskComplete", Coins = Config.Tasks.CoinReward })
	end
	send(member.Id)
end

local function addPrompt(parent: Instance, kind: string, target: number, locKey: string, hold: number)
	local prompt = Prompts.create(parent, kind .. "Prompt", locKey, hold)
	prompt:SetAttribute("Audience", "Task:" .. kind)
	prompt:SetAttribute("TargetId", target)
	local step: StepPrompt = { Prompt = prompt, Kind = kind, Target = target }
	prompt.Triggered:Connect(function(player: Player)
		onStep(player, step)
	end)
	table.insert(prompts, step)
end

--------------------------------------------------------------------------------
-- Morning / night
--------------------------------------------------------------------------------

local function assignAll()
	local world: DailyTask.World = {
		BrokenDoors = HouseService.DoorsNeedingRepair(),
		Plots = plots,
		Trees = trees,
	}
	local forced = if Config.Debug.Enabled then Config.Debug.ForceTask else nil
	table.clear(tasks)
	for _, member in Roster.alive(MatchService.Roster) do
		if not member.IsBot then
			tasks[member.Id] = DailyTask.pick(world, rng, forced)
			send(member.Id)
		end
	end
end

local function clearAll()
	local ids: { number } = {}
	for id in tasks do
		table.insert(ids, id)
	end
	table.clear(tasks)
	for _, id in ids do
		send(id)
	end
end

function TaskService.Init()
	for _, plot in CollectionService:GetTagged("GardenPlot") do
		local houseId = plot:GetAttribute("HouseId")
		if type(houseId) == "number" then
			table.insert(plots, houseId)
			addPrompt(plot:FindFirstChild("PromptAnchor") or plot, "PlantCarrot", houseId, "Prompt.Plant", Config.Tasks.PlantCarrot.Hold)
		end
	end
	for _, tree in CollectionService:GetTagged("TaskTree") do
		local treeId = tree:GetAttribute("TreeId")
		local trunk = if tree:IsA("Model") then tree.PrimaryPart else nil
		if type(treeId) == "number" and trunk then
			table.insert(trees, treeId)
			local anchor = trunk:FindFirstChild("PromptAnchor") or trunk
			addPrompt(anchor, "PickApples", treeId, "Prompt.PickApple", Config.Tasks.PickApples.HoldPerTree)
			addPrompt(anchor, "ChopTrees", treeId, "Prompt.Chop", Config.Tasks.ChopTrees.HoldPerTree)
		end
	end
	for _, door in CollectionService:GetTagged("Door") do
		local houseId = door:GetAttribute("HouseId")
		if type(houseId) == "number" then
			addPrompt(door:FindFirstChild("PromptAnchor") or door, "RepairDoor", houseId, "Prompt.Repair", Config.Tasks.RepairDoor.Hold)
		end
	end
	table.sort(plots)
	table.sort(trees)
end

function TaskService.Start()
	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Day" then
			assignAll()
			setPromptsActive(true)
		elseif state.Phase == "MeetingCountdown" then
			setPromptsActive(true)
		else
			-- The meeting, nightfall and night: unfinished tasks are lost at nightfall.
			setPromptsActive(false)
			if state.Phase == "FullMoonWarning" or state.Phase == "Night" or state.Phase == "GameOver" then
				clearAll()
			end
		end
	end)
	MatchService.MemberDied:Connect(function(member: Roster.Member)
		if tasks[member.Id] then
			tasks[member.Id] = nil
			send(member.Id)
		end
	end)
	MatchService.SyncRequested:Connect(function(player: Player)
		if tasks[player.UserId] then
			send(player.UserId)
		end
	end)
end

return TaskService
