--!strict
--[[
	MenuController — the lobby's side menus (GDD §3).
	  Left:  Shop · Roles · Monster · Settings
	  Right: News · Codes · Pass · Daily Spin
	Roles shows every role with its description, coin price, Robux / Diamond
	price and level needed. Shop, Codes, Pass and Daily Spin come with the
	data and economy milestone (9).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)

local MenuController = {}

local window: Frame
local title: TextLabel
local body: ScrollingFrame
local textTemplate: TextLabel
local roleTemplate: Frame
local openPage: string? = nil

local function clear()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function addText(text: string, order: number)
	local paragraph = textTemplate:Clone()
	paragraph.Text = text
	paragraph.LayoutOrder = order
	paragraph.Visible = true
	paragraph.Parent = body
end

local function addRole(roleId: string, order: number)
	local def = Config.Roles[roleId]
	local row = roleTemplate:Clone()
	row.LayoutOrder = order;
	(row:WaitForChild("NameLabel") :: TextLabel).Text = Loc.format("Role." .. roleId .. ".Name");
	(row:WaitForChild("DescLabel") :: TextLabel).Text = Loc.format("Role." .. roleId .. ".Desc");
	(row:WaitForChild("PriceLabel") :: TextLabel).Text = if def.Free
		then Loc.format("Menu.Free")
		else Loc.format("Menu.Price", { coins = def.CoinPrice, robux = def.RobuxPrice });
	(row:WaitForChild("LevelLabel") :: TextLabel).Text = if def.RequiredLevel > 1
		then Loc.format("Menu.Level", { level = def.RequiredLevel })
		else ""
	row.Visible = true
	row.Parent = body
end

local PAGES: { [string]: () -> () } = {
	Role = function()
		for order, roleId in Config.RoleOrder do
			addRole(roleId, order)
		end
	end,
	Monster = function()
		addText(Loc.format("Menu.Werewolf"), 1)
		addText(Loc.format("Menu.MonsterInfo"), 2)
	end,
	Settings = function()
		addText(Loc.format("Menu.SettingsInfo"), 1)
	end,
	News = function()
		addText(Loc.format("News.Body"), 1)
	end,
}

local function open(page: string)
	if openPage == page and window.Visible then
		window.Visible = false
		openPage = nil
		return
	end
	openPage = page
	clear()
	title.Text = Loc.format("Menu." .. page)
	local fill = PAGES[page]
	if fill then
		fill()
	else
		addText(Loc.format("Menu.Soon"), 1)
	end
	window.Visible = true
end

function MenuController.Start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MenuUI")
	window = gui:WaitForChild("Window") :: Frame
	title = window:WaitForChild("Title") :: TextLabel
	body = window:WaitForChild("Body") :: ScrollingFrame
	local templates = gui:WaitForChild("Templates")
	textTemplate = templates:WaitForChild("Text") :: TextLabel
	roleTemplate = templates:WaitForChild("RoleRow") :: Frame
	local close = window:WaitForChild("CloseButton") :: TextButton
	close.Text = Loc.format("Menu.Close")
	close.Activated:Connect(function()
		window.Visible = false
		openPage = nil
	end)

	for _, barName in { "LeftBar", "RightBar" } do
		for _, item in gui:WaitForChild(barName):GetChildren() do
			local page = item:GetAttribute("Page")
			if item:IsA("TextButton") and type(page) == "string" then
				item.Text = Loc.format("Menu." .. page)
				item.Activated:Connect(function()
					open(page)
				end)
			end
		end
	end
end

return MenuController
