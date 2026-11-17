--!strict
--[[
	BuildLobbyUI — (re)builds the Lobby place's ScreenGuis in StarterGui:
	  QueueUI  status of the player's queue + the host's Start button
	  MenuUI   left: Shop / Roles / Monster / Settings
	           right: News / Codes / Pass / Daily Spin
	           and one window that shows the page picked
	Run it in the Lobby place in Studio. Idempotent. Scripts only fill these in.
]]

local StarterGui = game:GetService("StarterGui")

local rgb = Color3.fromRGB

local Colors = {
	Panel = rgb(24, 26, 38),
	PanelLight = rgb(44, 48, 68),
	Text = rgb(255, 255, 255),
	SubText = rgb(200, 205, 220),
	Accent = rgb(80, 160, 255),
	Start = rgb(90, 200, 110),
}

local TITLE_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local BODY_FONT = Font.fromEnum(Enum.Font.GothamMedium)

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function maxTextSize(parent: Instance, size: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = size
	constraint.Parent = parent
end

local function screenGui(name: string, displayOrder: number): ScreenGui
	local old = StarterGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = StarterGui
	return gui
end

local function frame(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2, color: Color3, transparency: number): Frame
	local instance = Instance.new("Frame")
	instance.Name = name
	instance.Size = size
	instance.Position = position
	instance.AnchorPoint = anchor
	instance.BackgroundColor3 = color
	instance.BackgroundTransparency = transparency
	instance.BorderSizePixel = 0
	instance.Parent = parent
	return instance
end

local function label(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2, font: Font, maxSize: number): TextLabel
	local instance = Instance.new("TextLabel")
	instance.Name = name
	instance.Size = size
	instance.Position = position
	instance.AnchorPoint = anchor
	instance.BackgroundTransparency = 1
	instance.FontFace = font
	instance.Text = ""
	instance.TextColor3 = Colors.Text
	instance.TextScaled = true
	instance.TextWrapped = true
	instance.Parent = parent
	maxTextSize(instance, maxSize)
	return instance
end

local function button(name: string, parent: Instance, size: UDim2, color: Color3): TextButton
	local instance = Instance.new("TextButton")
	instance.Name = name
	instance.Size = size
	instance.BackgroundColor3 = color
	instance.BorderSizePixel = 0
	instance.FontFace = TITLE_FONT
	instance.Text = name
	instance.TextColor3 = Colors.Text
	instance.TextScaled = true
	instance.Parent = parent
	corner(instance, 12)
	maxTextSize(instance, 22)
	return instance
end

--------------------------------------------------------------------------------
-- QueueUI
--------------------------------------------------------------------------------

local function buildQueueUI()
	local gui = screenGui("QueueUI", 2)
	local panel = frame("Panel", gui, UDim2.new(0, 420, 0, 96), UDim2.new(0.5, 0, 1, -24), Vector2.new(0.5, 1), Colors.Panel, 0.15)
	corner(panel, 16)
	panel.Visible = false
	label("StatusLabel", panel, UDim2.new(1, -24, 0, 30), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0), TITLE_FONT, 24)
	local hint = label("HintLabel", panel, UDim2.new(1, -24, 0, 20), UDim2.new(0.5, 0, 0, 40), Vector2.new(0.5, 0), BODY_FONT, 16)
	hint.TextColor3 = Colors.SubText
	local start = button("StartButton", panel, UDim2.new(0, 160, 0, 30), Colors.Start)
	start.Position = UDim2.new(0.5, 0, 1, -6)
	start.AnchorPoint = Vector2.new(0.5, 1)
	start.Visible = false
end

--------------------------------------------------------------------------------
-- MenuUI
--------------------------------------------------------------------------------

local function sideBar(name: string, parent: Instance, left: boolean, pages: { string })
	local bar = frame(
		name,
		parent,
		UDim2.new(0, 120, 0, #pages * 62),
		UDim2.new(if left then 0 else 1, if left then 12 else -12, 0.5, 0),
		Vector2.new(if left then 0 else 1, 0.5),
		Colors.Panel,
		1
	)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	for order, page in pages do
		local item = button(page, bar, UDim2.new(1, 0, 0, 52), Colors.PanelLight)
		item.LayoutOrder = order
		item:SetAttribute("Page", page)
	end
end

local function buildMenuUI()
	local gui = screenGui("MenuUI", 3)
	sideBar("LeftBar", gui, true, { "Shop", "Role", "Monster", "Settings" })
	sideBar("RightBar", gui, false, { "News", "Codes", "Pass", "Spin" })

	local window = frame("Window", gui, UDim2.new(0.6, 0, 0.7, 0), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), Colors.Panel, 0.05)
	corner(window, 18)
	window.Visible = false
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, 560)
	limit.Parent = window
	label("Title", window, UDim2.new(1, -120, 0, 40), UDim2.new(0, 20, 0, 12), Vector2.new(0, 0), TITLE_FONT, 32).TextXAlignment =
		Enum.TextXAlignment.Left
	local close = button("CloseButton", window, UDim2.new(0, 90, 0, 36), Colors.PanelLight)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.AnchorPoint = Vector2.new(1, 0)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -32, 1, -76)
	body.Position = UDim2.new(0.5, 0, 0, 62)
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 6
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = window
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui

	-- A plain paragraph.
	local text = label("Text", templates, UDim2.new(1, -8, 0, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), BODY_FONT, 20)
	text.TextScaled = false
	text.TextSize = 20
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Visible = false

	-- One role card: name, description, price, level.
	local row = frame("RoleRow", templates, UDim2.new(1, -8, 0, 96), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Colors.PanelLight, 0)
	corner(row, 12)
	row.Visible = false
	label("NameLabel", row, UDim2.new(0.6, 0, 0, 28), UDim2.new(0, 12, 0, 8), Vector2.new(0, 0), TITLE_FONT, 22).TextXAlignment =
		Enum.TextXAlignment.Left
	local desc = label("DescLabel", row, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 0, 38), Vector2.new(0, 0), BODY_FONT, 15)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = Colors.SubText
	local price = label("PriceLabel", row, UDim2.new(0.5, 0, 0, 22), UDim2.new(1, -12, 0, 10), Vector2.new(1, 0), BODY_FONT, 16)
	price.TextXAlignment = Enum.TextXAlignment.Right
	price.TextColor3 = rgb(255, 220, 110)
	local level = label("LevelLabel", row, UDim2.new(0.4, 0, 0, 18), UDim2.new(1, -12, 1, -6), Vector2.new(1, 1), BODY_FONT, 14)
	level.TextXAlignment = Enum.TextXAlignment.Right
	level.TextColor3 = rgb(255, 170, 90)
end

buildQueueUI()
buildMenuUI()
print("[BuildLobbyUI] done")
