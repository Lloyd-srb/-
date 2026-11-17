--!strict
--[[
	BuildLobbyUI — (re)builds the Lobby place's ScreenGuis in StarterGui:
	  QueueUI  status of the player's queue + the host's Start button
	  MenuUI   left: Shop / Roles / Monster / Settings
	           right: News / Codes / Pass / Daily Spin
	           and one window that shows the page picked; a wallet bar on top
	           (coins, diamonds, level); a toast line for results
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
	Coins = rgb(255, 210, 90),
	Diamonds = rgb(120, 220, 255),
	Robux = rgb(60, 180, 90),
	Warning = rgb(255, 150, 90),
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
	local panel = frame("Panel", gui, UDim2.new(0, 420, 0, 112), UDim2.new(0.5, 0, 1, -24), Vector2.new(0.5, 1), Colors.Panel, 0.15)
	corner(panel, 16)
	panel.Visible = false
	label("StatusLabel", panel, UDim2.new(1, -24, 0, 30), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0), TITLE_FONT, 24)
	local hint = label("HintLabel", panel, UDim2.new(1, -24, 0, 20), UDim2.new(0.5, 0, 0, 40), Vector2.new(0.5, 0), BODY_FONT, 16)
	hint.TextColor3 = Colors.SubText
	-- Touch targets are at least 44 px tall.
	local start = button("StartButton", panel, UDim2.new(0, 160, 0, 44), Colors.Start)
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

-- Wallet bar (top: coins, diamonds, level), a warning line when progress
-- cannot be saved, and a toast line for results.
local function buildWallet(gui: ScreenGui)
	local wallet = frame("WalletBar", gui, UDim2.new(0, 460, 0, 44), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0), Colors.Panel, 0.15)
	corner(wallet, 14)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 18)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = wallet
	local items: { { any } } = { { "CoinsLabel", Colors.Coins }, { "DiamondsLabel", Colors.Diamonds }, { "LevelLabel", Colors.Text } }
	for order, item in items do
		local text = label(item[1], wallet, UDim2.new(0, 130, 0, 30), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), TITLE_FONT, 22)
		text.TextColor3 = item[2]
		text.LayoutOrder = order
	end
	local warning = label("TemporaryLabel", gui, UDim2.new(0, 520, 0, 24), UDim2.new(0.5, 0, 0, 58), Vector2.new(0.5, 0), BODY_FONT, 16)
	warning.TextColor3 = Colors.Warning
	warning.Visible = false

	local toast = label("Toast", gui, UDim2.new(0, 560, 0, 34), UDim2.new(0.5, 0, 1, -140), Vector2.new(0.5, 1), TITLE_FONT, 24)
	toast.BackgroundColor3 = Colors.Panel
	toast.BackgroundTransparency = 0.2
	corner(toast, 10)
	toast.Visible = false
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
	local close = button("CloseButton", window, UDim2.new(0, 100, 0, 44), Colors.PanelLight)
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
	local level = label("LevelLabel", row, UDim2.new(0.34, 0, 0, 18), UDim2.new(0, 12, 1, -6), Vector2.new(0, 1), BODY_FONT, 14)
	level.TextXAlignment = Enum.TextXAlignment.Left
	level.TextColor3 = rgb(255, 170, 90)
	-- Buy / equip buttons, bottom right (filled by MenuController).
	local buttons = frame("Buttons", row, UDim2.new(0.62, 0, 0, 44), UDim2.new(1, -10, 1, -8), Vector2.new(1, 1), Colors.Panel, 1)
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Padding = UDim.new(0, 6)
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttons
	row.Size = UDim2.new(1, -8, 0, 136)

	-- One buy / equip button (its colour shows the currency).
	local action = button("ActionButton", templates, UDim2.new(0, 120, 1, 0), Colors.Accent)
	action.Text = ""
	action.Visible = false
	action:SetAttribute("ColorCoins", Colors.Coins)
	action:SetAttribute("ColorDiamonds", Colors.Diamonds)
	action:SetAttribute("ColorRobux", Colors.Robux)
	action:SetAttribute("ColorPlain", Colors.Accent)

	-- Codes page: a text box, a button and the answer.
	local codeBox = frame("CodeBox", templates, UDim2.new(1, -8, 0, 110), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Colors.PanelLight, 0)
	corner(codeBox, 12)
	codeBox.Visible = false
	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.Size = UDim2.new(1, -170, 0, 40)
	input.Position = UDim2.new(0, 12, 0, 12)
	input.BackgroundColor3 = Colors.Panel
	input.BorderSizePixel = 0
	input.FontFace = BODY_FONT
	input.TextSize = 20
	input.TextColor3 = Colors.Text
	input.PlaceholderColor3 = Colors.SubText
	input.ClearTextOnFocus = false
	input.Text = ""
	input.Parent = codeBox
	corner(input, 8)
	local redeem = button("RedeemButton", codeBox, UDim2.new(0, 140, 0, 40), Colors.Start)
	redeem.Position = UDim2.new(1, -12, 0, 12)
	redeem.AnchorPoint = Vector2.new(1, 0)
	local answer = label("ResultLabel", codeBox, UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 0, 62), Vector2.new(0, 0), BODY_FONT, 18)
	answer.TextXAlignment = Enum.TextXAlignment.Left

	-- Daily Spin page: the "wheel" (prizes flick by), the button, spins left.
	local spin = frame("SpinPanel", templates, UDim2.new(1, -8, 0, 170), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Colors.PanelLight, 0)
	corner(spin, 12)
	spin.Visible = false
	local wheel = label("WheelLabel", spin, UDim2.new(1, -24, 0, 60), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0), TITLE_FONT, 40)
	wheel.TextColor3 = Colors.Coins
	local spinButton = button("SpinButton", spin, UDim2.new(0, 200, 0, 44), Colors.Start)
	spinButton.Position = UDim2.new(0.5, 0, 0, 78)
	spinButton.AnchorPoint = Vector2.new(0.5, 0)
	local info = label("InfoLabel", spin, UDim2.new(1, -24, 0, 30), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1), BODY_FONT, 18)
	info.TextColor3 = Colors.SubText

	-- A progress bar (player level / Season Pass level).
	local bar = frame("ProgressBar", templates, UDim2.new(1, -8, 0, 14), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Colors.Panel, 0)
	corner(bar, 7)
	bar.Visible = false
	local fill = frame("Fill", bar, UDim2.new(0, 0, 1, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Colors.Accent, 0)
	corner(fill, 7)

	buildWallet(gui)
end

--------------------------------------------------------------------------------
-- TutorialUI: how to play (owner, 17 Nov 2026) — picture, title, text, Next
--------------------------------------------------------------------------------

local function buildTutorialUI()
	local gui = screenGui("TutorialUI", 10)
	gui.Enabled = false
	local panel = frame("Panel", gui, UDim2.new(0.9, 0, 0.82, 0), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), Colors.Panel, 0.03)
	corner(panel, 22)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(720, 520)
	limit.Parent = panel

	-- The picture: role icons in a row (filled by TutorialController).
	local picture = frame("Picture", panel, UDim2.new(1, -40, 0.36, 0), UDim2.new(0.5, 0, 0, 20), Vector2.new(0.5, 0), Colors.PanelLight, 0)
	corner(picture, 16)
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 14)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = picture

	label("TitleLabel", panel, UDim2.new(1, -40, 0.1, 0), UDim2.new(0.5, 0, 0.4, 0), Vector2.new(0.5, 0), TITLE_FONT, 34)
	local body = label("BodyLabel", panel, UDim2.new(1, -60, 0.3, 0), UDim2.new(0.5, 0, 0.52, 0), Vector2.new(0.5, 0), BODY_FONT, 22)
	body.TextColor3 = Colors.SubText
	body.TextYAlignment = Enum.TextYAlignment.Top
	local page = label("PageLabel", panel, UDim2.new(0, 120, 0, 24), UDim2.new(0, 24, 1, -26), Vector2.new(0, 1), BODY_FONT, 18)
	page.TextXAlignment = Enum.TextXAlignment.Left
	page.TextColor3 = Colors.SubText
	local nextButton = button("NextButton", panel, UDim2.new(0, 180, 0, 48), Colors.Start)
	nextButton.Position = UDim2.new(1, -20, 1, -18)
	nextButton.AnchorPoint = Vector2.new(1, 1)
end

buildQueueUI()
buildMenuUI()
buildTutorialUI()
print("[BuildLobbyUI] done")
