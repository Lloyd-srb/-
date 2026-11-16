--!strict
--[[
	RoleSelectController — the role-selection screen (GDD §4).
	Shows every role with its description. Roles the player may use can be
	selected; the others show why they are locked. Exactly 3 must be chosen.
	The server validates the picks again.
	The ScreenGui is built by build/BuildUI.luau (StarterGui.RoleSelectUI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOCKED_TRANSPARENCY = 0.55

local RoleSelectController = {}

local gui: ScreenGui
local grid: Instance
local counter: TextLabel
local confirmButton: TextButton
local statusLabel: TextLabel
local cardTemplate: GuiButton

local cards: { [string]: GuiButton } = {}
local usable: { [string]: boolean } = {}
local selected: { string } = {}
local pickCount = Config.RoleSelect.PickCount
local confirmed = false

local function refresh()
	for roleId, card in cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = table.find(selected, roleId) ~= nil
		end
	end
	counter.Text = Loc.format("RoleSelect.Count", { count = #selected, max = pickCount })
	confirmButton.Visible = not confirmed and #selected == pickCount
	statusLabel.Visible = confirmed
end

local function toggle(roleId: string)
	if confirmed or not usable[roleId] then
		return
	end
	local index = table.find(selected, roleId)
	if index then
		table.remove(selected, index)
	elseif #selected < pickCount then
		table.insert(selected, roleId)
	end
	refresh()
end

local function build(options: any)
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	table.clear(usable)
	table.clear(selected)
	confirmed = false
	pickCount = if type(options.PickCount) == "number" then options.PickCount else Config.RoleSelect.PickCount
	local level = if type(options.Level) == "number" then options.Level else 1
	for _, roleId in options.Usable do
		if type(roleId) == "string" then
			usable[roleId] = true
		end
	end

	for order, roleId in Config.RoleOrder do
		local def = Config.Roles[roleId]
		local card = cardTemplate:Clone()
		card.Name = roleId
		card.LayoutOrder = order
		local nameLabel = card:WaitForChild("NameLabel") :: TextLabel
		local descLabel = card:WaitForChild("DescLabel") :: TextLabel
		local lockLabel = card:WaitForChild("LockLabel") :: TextLabel
		nameLabel.Text = Loc.format("Role." .. roleId .. ".Name")
		descLabel.Text = Loc.format("Role." .. roleId .. ".Desc")
		if not usable[roleId] then
			-- Locked: say whether it is the level gate or ownership.
			card.BackgroundTransparency = LOCKED_TRANSPARENCY
			card.AutoButtonColor = false
			lockLabel.Text = if level < def.RequiredLevel
				then Loc.format("RoleSelect.Locked", { level = def.RequiredLevel })
				else Loc.format("RoleSelect.NotOwned")
			lockLabel.Visible = true
		end
		card.Visible = true
		card.Parent = grid
		card.Activated:Connect(function()
			toggle(roleId)
		end)
		cards[roleId] = card
	end

	-- With exactly 3 usable roles (new players) there is nothing to choose.
	local count = 0
	for _ in usable do
		count += 1
	end
	if count == pickCount then
		for _, roleId in Config.RoleOrder do
			if usable[roleId] then
				table.insert(selected, roleId)
			end
		end
	end
	refresh()
	gui.Enabled = true
end

function RoleSelectController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = playerGui:WaitForChild("RoleSelectUI") :: ScreenGui
	local panel = gui:WaitForChild("Panel")
	grid = panel:WaitForChild("Grid")
	counter = panel:WaitForChild("Counter") :: TextLabel
	confirmButton = panel:WaitForChild("ConfirmButton") :: TextButton
	statusLabel = panel:WaitForChild("StatusLabel") :: TextLabel
	cardTemplate = gui:WaitForChild("Templates"):WaitForChild("RoleCard") :: GuiButton;

	(panel:WaitForChild("Title") :: TextLabel).Text = Loc.format("Phase.RoleSelect");
	(panel:WaitForChild("Hint") :: TextLabel).Text = Loc.format("RoleSelect.Hint")
	confirmButton.Text = Loc.format("Vote.Confirm")
	statusLabel.Text = Loc.format("RoleSelect.Waiting")

	confirmButton.Activated:Connect(function()
		if not confirmed and #selected == pickCount then
			Remotes.get("RolePicks"):FireServer(selected)
		end
	end)

	Remotes.get("RoleOptions").OnClientEvent:Connect(function(options: any)
		if type(options) == "table" and type(options.Usable) == "table" then
			build(options)
		end
	end)
	Remotes.get("RolePicksAck").OnClientEvent:Connect(function(picks: any)
		if type(picks) == "table" then
			table.clear(selected)
			for _, roleId in picks do
				if type(roleId) == "string" then
					table.insert(selected, roleId)
				end
			end
			confirmed = true
			refresh()
		end
	end)
	-- The screen closes when day 1 begins.
	Remotes.get("PhaseChanged").OnClientEvent:Connect(function(phase: any)
		if type(phase) == "table" and phase.Phase ~= "RoleSelect" and phase.Phase ~= "Waiting" then
			gui.Enabled = false
		end
	end)
end

return RoleSelectController
