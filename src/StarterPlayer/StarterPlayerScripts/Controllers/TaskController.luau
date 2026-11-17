--!strict
--[[
	TaskController — this player's task of the day (GDD §10).
	Shows the task on the HUD, tells PromptController which "hold E" steps to
	show, and grows this player's own apples on their apple trees (local only:
	nobody else sees them).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local APPLE_COLOR = Color3.fromRGB(225, 35, 35)

local TaskController = {}

local label: TextLabel
local apples: { [number]: BasePart } = {}

local function clearApples()
	for _, apple in apples do
		apple:Destroy()
	end
	table.clear(apples)
end

local function appleSpot(treeId: number): Vector3?
	for _, tree in CollectionService:GetTagged("TaskTree") do
		if tree:GetAttribute("TreeId") == treeId and tree:IsA("Model") and tree.PrimaryPart then
			local spot = tree.PrimaryPart:FindFirstChild("AppleSpot")
			if spot and spot:IsA("Attachment") then
				return spot.WorldPosition
			end
		end
	end
	return nil
end

local function growApples(task: any)
	clearApples()
	if task.Kind ~= "PickApples" or task.Complete then
		return
	end
	for treeId in task.Targets do
		local position = if not task.Done[treeId] then appleSpot(treeId) else nil
		if position then
			local apple = Instance.new("Part")
			apple.Name = "MyApple"
			apple.Shape = Enum.PartType.Ball
			apple.Size = Vector3.new(1.2, 1.2, 1.2)
			apple.Color = APPLE_COLOR
			apple.Material = Enum.Material.SmoothPlastic
			apple.Anchored = true
			apple.CanCollide = false
			apple.CanQuery = false
			apple.CanTouch = false
			apple.CFrame = CFrame.new(position)
			apple.Parent = workspace
			apples[treeId] = apple
		end
	end
end

local function describe(task: any): string
	if task.Complete then
		return Loc.format("Hud.TaskDone")
	end
	local done = 0
	for _ in task.Done do
		done += 1
	end
	local text = Loc.format("Task." .. task.Kind, { done = done, total = task.Required })
	return Loc.format("Hud.Task", { task = text })
end

local function onTask(view: any)
	if type(view) ~= "table" or type(view.Kind) ~= "string" or type(view.Targets) ~= "table" then
		ClientState.set("Task", nil)
		label.Visible = false
		clearApples()
		return
	end
	-- Lists -> sets, for quick lookups by PromptController.
	local targets: { [number]: boolean } = {}
	for _, id in view.Targets do
		targets[id] = true
	end
	local done: { [number]: boolean } = {}
	if type(view.Done) == "table" then
		for _, id in view.Done do
			done[id] = true
		end
	end
	local task = {
		Kind = view.Kind,
		Targets = targets,
		Done = done,
		Required = if type(view.Required) == "number" then view.Required else 1,
		Complete = view.Complete == true,
	}
	ClientState.set("Task", task)
	label.Text = describe(task)
	label.Visible = true
	growApples(task)
end

function TaskController.Start()
	local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Hud")
	label = hud:WaitForChild("TaskLabel") :: TextLabel
	Remotes.get("TaskChanged").OnClientEvent:Connect(onTask)
end

return TaskController
