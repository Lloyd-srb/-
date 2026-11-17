--!strict
--[[
	ScoreboardController — the end-of-match screen (GDD §7).
	Every player's face, name and role (revealed now), alive / dead, won / lost,
	like counts and one Like button per row (not on your own row). Then the
	MVP badge and this player's own reward.
	The ScreenGui is built by build/BuildUI.luau (StarterGui.ScoreboardUI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HEADSHOT_URL = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"
local WIN_COLOR = Color3.fromRGB(120, 230, 140)
local LOSE_COLOR = Color3.fromRGB(230, 120, 120)

local ScoreboardController = {}

local localPlayer = Players.LocalPlayer
local gui: ScreenGui
local list: Instance
local rowTemplate: Frame
local rewardLabel: TextLabel
local detailLabel: TextLabel

local rows: { [number]: Frame } = {}
local myLike: number? = nil
local likesOpen = false

local function refreshButtons()
	for id, row in rows do
		local button = row:FindFirstChild("LikeButton")
		if button and button:IsA("TextButton") then
			button.Visible = likesOpen and id ~= localPlayer.UserId
			button.Text = Loc.format(if myLike == id then "End.Liked" else "End.Like")
		end
	end
end

local function textOf(row: Frame, name: string): TextLabel
	return row:WaitForChild(name) :: TextLabel
end

local function onScoreboard(data: any)
	if type(data) ~= "table" or type(data.Rows) ~= "table" then
		return
	end
	for _, row in rows do
		row:Destroy()
	end
	table.clear(rows)
	likesOpen = true
	myLike = nil
	rewardLabel.Text = ""
	detailLabel.Text = ""

	for order, entry in data.Rows do
		if type(entry) ~= "table" or type(entry.Id) ~= "number" then
			continue
		end
		local id = entry.Id
		local row = rowTemplate:Clone()
		row.Name = "Row" .. id
		row.LayoutOrder = order
		local name = tostring(entry.Name)
		textOf(row, "NameLabel").Text = if id == localPlayer.UserId then Loc.format("End.You", { name = name }) else name
		textOf(row, "RoleLabel").Text = Loc.format("Role." .. tostring(entry.Role) .. ".Name")
		local status = textOf(row, "StatusLabel")
		status.Text = Loc.format(if entry.Alive then "End.Alive" else "End.Dead")
			.. " · "
			.. Loc.format(if entry.Won then "End.Won" else "End.Lost")
		status.TextColor3 = if entry.Won then WIN_COLOR else LOSE_COLOR
		textOf(row, "MvpLabel").Text = Loc.format("End.Mvp")
		local headshot = row:WaitForChild("Headshot") :: ImageLabel
		headshot.Image = if id > 0 then string.format(HEADSHOT_URL, id) else ""
		local button = row:WaitForChild("LikeButton") :: TextButton
		button.Activated:Connect(function()
			if likesOpen and id ~= localPlayer.UserId then
				myLike = id
				Remotes.get("Like"):FireServer(id)
				refreshButtons()
			end
		end)
		row.Visible = true
		row.Parent = list
		rows[id] = row
	end
	refreshButtons()
	gui.Enabled = true
end

local function onCounts(list: any)
	if type(list) ~= "table" then
		return
	end
	for _, row in rows do
		textOf(row, "LikeCount").Text = "0"
	end
	for _, entry in list do
		local row = if type(entry) == "table" then rows[entry.Id] else nil
		if row then
			textOf(row, "LikeCount").Text = tostring(entry.Count)
		end
	end
end

local function onResults(data: any)
	likesOpen = false
	refreshButtons()
	local mvp = if type(data) == "table" then data.MvpId else nil
	for id, row in rows do
		textOf(row, "MvpLabel").Visible = id == mvp
	end
end

local function onReward(summary: any)
	if type(summary) ~= "table" then
		return
	end
	local text = Loc.format("End.Reward", { coins = summary.Coins, exp = summary.Exp, pass = summary.PassExp })
	if summary.IsMvp then
		text ..= "   " .. Loc.format("End.MvpBonus")
	end
	rewardLabel.Text = text
	local detail = Loc.format("End.RewardDetail", {
		nights = summary.NightsSurvived,
		tasks = summary.TasksCompleted,
		role = Loc.format("Role." .. tostring(summary.MasteryRole) .. ".Name"),
		points = summary.MasteryPoints,
	})
	if type(summary.Diamonds) == "number" and summary.Diamonds > 0 then
		detail ..= "\n" .. Loc.format("End.Diamonds", { diamonds = summary.Diamonds })
	end
	detailLabel.Text = detail
end

function ScoreboardController.Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	gui = playerGui:WaitForChild("ScoreboardUI") :: ScreenGui
	local panel = gui:WaitForChild("Panel")
	list = panel:WaitForChild("List")
	rewardLabel = panel:WaitForChild("RewardLabel") :: TextLabel
	detailLabel = panel:WaitForChild("DetailLabel") :: TextLabel
	rowTemplate = gui:WaitForChild("Templates"):WaitForChild("Row") :: Frame;
	(panel:WaitForChild("Hint") :: TextLabel).Text = Loc.format("End.LikeHint")

	Remotes.get("GameOver").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.EndingKey) == "string" then
			(panel:WaitForChild("Title") :: TextLabel).Text = Loc.format(data.EndingKey)
		end
	end)
	Remotes.get("Scoreboard").OnClientEvent:Connect(onScoreboard)
	Remotes.get("LikeCounts").OnClientEvent:Connect(onCounts)
	Remotes.get("Results").OnClientEvent:Connect(onResults)
	Remotes.get("RewardSummary").OnClientEvent:Connect(onReward)
end

return ScoreboardController
