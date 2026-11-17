--!strict
--[[
	TitleController — draws each player's title (Season Pass reward, GDD
	§13.2) over their head in the lobby, in this viewer's language. The
	server puts the equipped title id on the character as the "Title"
	attribute; titles are public.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)

local TAG_NAME = "TitleTag"
local TITLE_COLOR = Color3.fromRGB(255, 220, 110)

local TitleController = {}

local function refresh(character: Model)
	local old = character:FindFirstChild(TAG_NAME)
	if old then
		old:Destroy()
	end
	local titleId = character:GetAttribute("Title")
	local head = character:FindFirstChild("Head")
	if type(titleId) ~= "string" or not (head and head:IsA("BasePart")) or not Loc.has("Title." .. titleId .. ".Name") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Adornee = head
	tag.Size = UDim2.fromOffset(200, 26)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.MaxDistance = 60
	tag.AlwaysOnTop = false
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = TITLE_COLOR
	text.TextStrokeTransparency = 0.4
	text.Text = Loc.format("Title." .. titleId .. ".Name")
	text.Parent = tag
	tag.Parent = character
end

local function watchCharacter(character: Model)
	character:GetAttributeChangedSignal("Title"):Connect(function()
		refresh(character)
	end)
	task.spawn(function()
		character:WaitForChild("Head", 10)
		refresh(character)
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

function TitleController.Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return TitleController
