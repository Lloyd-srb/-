--!strict
--[[
	VoteController — the voting screen (GDD §6.2): every living player's
	headshot and name, with silhouettes under the name for the votes they got.
	Gray = selected but not confirmed, blue = confirmed. The client only knows
	the counts and its own ballot.
	The ScreenGui is built by build/BuildUI.luau (StarterGui.VoteUI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RESULT_SECONDS = 6
local HEADSHOT_URL = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"

local VoteController = {}

local localPlayer = Players.LocalPlayer

local gui: ScreenGui
local grid: Instance
local confirmButton: TextButton
local resultLabel: TextLabel
local cardTemplate: GuiButton
local silhouetteTemplate: Frame

local cards: { [number]: GuiButton } = {}
local myTarget = 0
local myConfirmed = false
local canVote = false

local function setSilhouettes(card: GuiButton, pending: number, confirmed: number)
	local holder = card:WaitForChild("Silhouettes")
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local function add(count: number, color: Color3)
		for _ = 1, count do
			local silhouette = silhouetteTemplate:Clone()
			for _, piece in silhouette:GetChildren() do
				if piece:IsA("Frame") then
					piece.BackgroundColor3 = color
				end
			end
			silhouette.Visible = true
			silhouette.Parent = holder
		end
	end
	add(confirmed, Config.Vote.ConfirmedColor)
	add(pending, Config.Vote.PendingColor)
end

local function refreshSelection()
	for id, card in cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = id == myTarget
			stroke.Color = if myConfirmed then Config.Vote.ConfirmedColor else Config.Vote.PendingColor
		end
	end
	confirmButton.Visible = canVote and myTarget ~= 0 and not myConfirmed
end

local function clearCards()
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
end

local function onOpened(data: any)
	if type(data) ~= "table" or type(data.Candidates) ~= "table" then
		return
	end
	clearCards()
	canVote = false
	for order, candidate in data.Candidates do
		local id, name = candidate.Id, candidate.Name
		if type(id) ~= "number" or type(name) ~= "string" then
			continue
		end
		if id == localPlayer.UserId then
			canVote = true -- only living players are candidates
		end
		local card = cardTemplate:Clone()
		card.Name = "Card" .. id
		card.LayoutOrder = order
		local nameLabel = card:WaitForChild("NameLabel") :: TextLabel
		nameLabel.Text = name
		local headshot = card:WaitForChild("Headshot") :: ImageLabel
		headshot.Image = if id > 0 then string.format(HEADSHOT_URL, id) else ""
		card.Visible = true
		card.Parent = grid
		card.Activated:Connect(function()
			if not canVote or myConfirmed then
				return
			end
			-- Clicking the selected card again clears the selection.
			Remotes.get("VoteSelect"):FireServer(if myTarget == id then 0 else id)
		end)
		cards[id] = card
	end
	resultLabel.Visible = false
	refreshSelection()
	gui.Enabled = true
end

local function onCounts(list: any)
	if type(list) ~= "table" then
		return
	end
	local seen: { [number]: boolean } = {}
	for _, entry in list do
		local card = cards[entry.Id]
		if card then
			seen[entry.Id] = true
			setSilhouettes(card, entry.Pending or 0, entry.Confirmed or 0)
		end
	end
	for id, card in cards do
		if not seen[id] then
			setSilhouettes(card, 0, 0)
		end
	end
end

local function onMine(data: any)
	if type(data) ~= "table" then
		return
	end
	myTarget = if type(data.Target) == "number" then data.Target else 0
	myConfirmed = data.Confirmed == true
	refreshSelection()
end

local function onClosed(data: any)
	if type(data) ~= "table" then
		return
	end
	local text: string
	if data.Resolution == "Cancelled" then
		gui.Enabled = false
		return
	elseif type(data.ExiledName) == "string" then
		text = Loc.format("Vote.Exiled", { name = data.ExiledName })
		if data.Resolution == "ChiefTieBreak" then
			text = Loc.format("Vote.ChiefTieBreak") .. "\n" .. text
		elseif data.Resolution == "RandomTieBreak" then
			text = Loc.format("Vote.RandomTieBreak") .. "\n" .. text
		end
	else
		text = Loc.format("Vote.NoExile")
	end
	confirmButton.Visible = false
	resultLabel.Text = text
	resultLabel.Visible = true
	myTarget = 0
	myConfirmed = false
	task.delay(RESULT_SECONDS, function()
		if resultLabel.Visible then
			gui.Enabled = false
			resultLabel.Visible = false
			clearCards()
		end
	end)
end

function VoteController.Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	gui = playerGui:WaitForChild("VoteUI") :: ScreenGui
	local panel = gui:WaitForChild("Panel")
	grid = panel:WaitForChild("Grid")
	confirmButton = panel:WaitForChild("ConfirmButton") :: TextButton
	resultLabel = panel:WaitForChild("ResultLabel") :: TextLabel
	local templates = gui:WaitForChild("Templates")
	cardTemplate = templates:WaitForChild("Card") :: GuiButton
	silhouetteTemplate = templates:WaitForChild("Silhouette") :: Frame

	local title = panel:WaitForChild("Title") :: TextLabel
	title.Text = Loc.format("Vote.Title")
	confirmButton.Text = Loc.format("Vote.Confirm")

	confirmButton.Activated:Connect(function()
		if canVote and myTarget ~= 0 and not myConfirmed then
			Remotes.get("VoteConfirm"):FireServer()
		end
	end)

	Remotes.get("VoteOpened").OnClientEvent:Connect(onOpened)
	Remotes.get("VoteCounts").OnClientEvent:Connect(onCounts)
	Remotes.get("VoteMine").OnClientEvent:Connect(onMine)
	Remotes.get("VoteClosed").OnClientEvent:Connect(onClosed)
end

return VoteController
