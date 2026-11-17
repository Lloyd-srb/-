--!strict
--[[
	RoleRollController — the role reveal when the match starts.

	A panel in the middle of the screen: round role icons slide from left to
	right, slow down and stop on this player's own role inside the gold ring,
	then "You are <role>!" and the role's description appear.

	It is only a show: the server has already decided the role and sends it
	to this player alone (RoleAssigned). The icons sliding past are picked at
	random on this client and say nothing about anybody else.

	Later changes (bitten into a pup, a pup growing into the werewolf) show the
	new icon straight away, without the slide.
	The ScreenGui is built by build/BuildUI.luau (StarterGui.RoleRollUI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoleIcons = require(ReplicatedStorage.Shared.RoleIcons)

local REEL_LENGTH = 24 -- icons that slide by, the last one is yours
local ROLL_SECONDS = 3.4
local HOLD_SECONDS = 4.5
local FADE_SECONDS = 0.35
local OTHERS_DIM = 0.65 -- icons that are not yours fade back once it stops

local RoleRollController = {}

local gui: ScreenGui
local panel: CanvasGroup
local window: Frame
local strip: Frame
local marker: Frame
local titleLabel: TextLabel
local descLabel: TextLabel

local shownRole: string? = nil
local token = 0
local slide: Tween? = nil
local random = Random.new()

local function pool(): { string }
	local list = { "Wolf" }
	for _, roleId in Config.RoleOrder do
		table.insert(list, roleId)
	end
	return list
end

local function ringColor(roleId: string): Color3
	return RoleIcons.RingColors[RoleIcons.factionOf(roleId, Config.Roles)] or Color3.new(1, 1, 1)
end

local function fade(visible: boolean)
	local tween = TweenService:Create(panel, TweenInfo.new(FADE_SECONDS), { GroupTransparency = if visible then 0 else 1 })
	tween:Play()
	return tween
end

local function play(roleId: string, withReel: boolean)
	token += 1
	local mine = token
	if slide then
		slide:Cancel() -- a newer reveal replaces one still sliding
		slide = nil
	end
	for _, child in strip:GetChildren() do
		child:Destroy()
	end
	titleLabel.Text = ""
	descLabel.Text = ""
	panel.GroupTransparency = 1
	gui.Enabled = true
	fade(true)

	-- Sizes come from the window on this screen (phone or PC).
	while window.AbsoluteSize.Y < 1 and token == mine do
		RunService.RenderStepped:Wait()
	end
	local size = math.floor(window.AbsoluteSize.Y * 0.78)
	local step = size + math.floor(size * 0.24)
	marker.Size = UDim2.fromOffset(size + 18, size + 18)

	local list: { string } = { roleId }
	if withReel then
		list = RoleIcons.reel(roleId, pool(), REEL_LENGTH, function(low: number, high: number): number
			return random:NextInteger(low, high)
		end)
	end
	local icons: { Frame } = {}
	for index, id in list do
		local icon = RoleIcons.create(id, size, ringColor(id))
		-- Later icons wait further left; the strip slides right to bring them in.
		icon.Position = UDim2.new(0.5, -(index - 1) * step, 0.5, 0)
		icon.Parent = strip
		table.insert(icons, icon)
	end
	strip.Position = UDim2.fromOffset(0, 0)

	if withReel then
		local distance = (#list - 1) * step
		local tween = TweenService:Create(
			strip,
			TweenInfo.new(ROLL_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(distance, 0) }
		)
		local lastIndex = 0
		local ticking = RunService.RenderStepped:Connect(function()
			local passed = math.floor((strip.Position.X.Offset + step / 2) / step)
			if passed ~= lastIndex then
				lastIndex = passed
				Audio.play("RoleRollTick")
			end
		end)
		slide = tween
		tween:Play()
		tween.Completed:Wait()
		ticking:Disconnect()
	end
	if token ~= mine then
		return
	end

	-- Stopped: yours stays bright, the ring pulses, the text appears.
	for index, icon in icons do
		local face = icon:FindFirstChild("Face")
		if index < #icons and face and face:IsA("CanvasGroup") then
			face.GroupTransparency = OTHERS_DIM
		end
	end
	Audio.play("RoleReveal")
	local grow = TweenService:Create(marker, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true), {
		Size = UDim2.fromOffset(size + 34, size + 34),
	})
	grow:Play()
	local name = Loc.format("Role." .. roleId .. ".Name")
	titleLabel.Text = Loc.format("RoleRoll.YouAre", { role = name })
	descLabel.Text = Loc.format("Role." .. roleId .. ".Desc")

	task.wait(HOLD_SECONDS)
	if token ~= mine then
		return
	end
	fade(false).Completed:Wait()
	if token == mine then
		gui.Enabled = false
	end
end

function RoleRollController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = playerGui:WaitForChild("RoleRollUI") :: ScreenGui
	panel = gui:WaitForChild("Panel") :: CanvasGroup
	window = panel:WaitForChild("Window") :: Frame
	strip = window:WaitForChild("Strip") :: Frame
	marker = window:WaitForChild("Marker") :: Frame
	titleLabel = panel:WaitForChild("TitleLabel") :: TextLabel
	descLabel = panel:WaitForChild("DescLabel") :: TextLabel

	Remotes.get("RoleAssigned").OnClientEvent:Connect(function(roleId: any)
		if type(roleId) ~= "string" or roleId == shownRole or not RoleIcons.Designs[roleId] then
			return
		end
		-- The first role of the match gets the slide; a later change does not.
		local first = shownRole == nil
		shownRole = roleId
		task.spawn(play, roleId, first)
	end)
end

return RoleRollController
