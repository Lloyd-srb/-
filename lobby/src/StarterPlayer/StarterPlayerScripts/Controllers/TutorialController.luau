--!strict
--[[
	TutorialController — how to play (owner, 17 Nov 2026).
	Pages from Shared.Tutorial: a picture made of role icons, a title, a few
	lines, and "Next"; the last page says "Got it!". Opens by itself the
	first time a player comes to the lobby (their saved profile says they
	have not read it yet) and again from the News page.
	The ScreenGui is built by build/lobby/BuildLobbyUI.luau (TutorialUI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GamepadFocus = require(ReplicatedStorage.Shared.GamepadFocus)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoleIcons = require(ReplicatedStorage.Shared.RoleIcons)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)

local TutorialController = {}

local gui: ScreenGui
local picture: Frame
local titleLabel: TextLabel
local bodyLabel: TextLabel
local pageLabel: TextLabel
local nextButton: TextButton

local ICON_GAP = 14 -- matches the UIListLayout padding in BuildLobbyUI

local page = 1
local askedByServer = false

local function show(index: number)
	page = index
	local data = Tutorial.Pages[index]
	for _, child in picture:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- As big as the picture allows, in height and in width (5 icons on a phone).
	local count = #data.Icons
	local byWidth = (picture.AbsoluteSize.X - 24 - (count - 1) * ICON_GAP) / count
	local size = math.max(36, math.floor(math.min(picture.AbsoluteSize.Y * 0.72, byWidth)))
	for order, roleId in data.Icons do
		local ring = RoleIcons.RingColors[RoleIcons.factionOf(roleId, Config.Roles)]
		local icon = RoleIcons.create(roleId, size, ring)
		icon.LayoutOrder = order
		icon.Parent = picture
	end
	titleLabel.Text = Loc.format(data.Key .. ".Title")
	bodyLabel.Text = Loc.format(data.Key .. ".Body")
	pageLabel.Text = Loc.format("Tutorial.Page", { page = index, count = #Tutorial.Pages })
	nextButton.Text = Loc.format(if index == #Tutorial.Pages then "Tutorial.Done" else "Tutorial.Next")
end

function TutorialController.Open()
	gui.Enabled = true
	task.defer(function()
		show(1) -- after the layout has a size
		GamepadFocus.offer(nextButton)
	end)
end

local function close()
	GamepadFocus.release(gui)
	gui.Enabled = false
	Remotes.get("TutorialDone"):FireServer()
end

function TutorialController.Start()
	gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("TutorialUI") :: ScreenGui
	local panel = gui:WaitForChild("Panel")
	picture = panel:WaitForChild("Picture") :: Frame
	titleLabel = panel:WaitForChild("TitleLabel") :: TextLabel
	bodyLabel = panel:WaitForChild("BodyLabel") :: TextLabel
	pageLabel = panel:WaitForChild("PageLabel") :: TextLabel
	nextButton = panel:WaitForChild("NextButton") :: TextButton

	nextButton.Activated:Connect(function()
		if page < #Tutorial.Pages then
			show(page + 1)
		else
			close()
		end
	end)

	-- New players: open once, the first time their profile arrives.
	Remotes.get("ProfileView").OnClientEvent:Connect(function(view: any)
		if not askedByServer and type(view) == "table" and view.TutorialSeen == false then
			askedByServer = true
			TutorialController.Open()
		end
	end)
end

return TutorialController
