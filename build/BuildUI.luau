--!strict
--[[
	BuildUI — (re)builds the Match-place ScreenGuis in StarterGui:
	  Hud     phase name, timer, own role, announcements
	  VoteUI  the meeting vote screen (GDD §6.2)
	Run in Studio (command bar / MCP). Idempotent. Scripts only fill these in;
	they never create layout, so all UI is rebuildable from this file.
]]

local StarterGui = game:GetService("StarterGui")

local rgb = Color3.fromRGB

local Colors = {
	Panel = rgb(24, 26, 38),
	PanelLight = rgb(44, 48, 68),
	Text = rgb(255, 255, 255),
	SubText = rgb(200, 205, 220),
	Accent = rgb(80, 160, 255),
	Stroke = rgb(0, 0, 0),
}

local TITLE_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local BODY_FONT = Font.fromEnum(Enum.Font.GothamMedium)

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function textStroke(parent: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.Stroke
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function maxTextSize(parent: Instance, size: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = size
	constraint.Parent = parent
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

--------------------------------------------------------------------------------
-- Hud
--------------------------------------------------------------------------------

local function buildHud()
	local hud = screenGui("Hud", 1)

	local topBar = frame(
		"TopBar",
		hud,
		UDim2.new(0, 280, 0, 72),
		UDim2.new(0.5, 0, 0, 44),
		Vector2.new(0.5, 0),
		Colors.Panel,
		0.25
	)
	corner(topBar, 14)
	label("PhaseLabel", topBar, UDim2.new(1, -16, 0.42, 0), UDim2.new(0.5, 0, 0.06, 0), Vector2.new(0.5, 0), BODY_FONT, 20)
	label("TimerLabel", topBar, UDim2.new(1, -16, 0.52, 0), UDim2.new(0.5, 0, 0.46, 0), Vector2.new(0.5, 0), TITLE_FONT, 34)

	local role = label(
		"RoleLabel",
		hud,
		UDim2.new(0, 240, 0, 34),
		UDim2.new(0, 16, 0, 48),
		Vector2.new(0, 0),
		BODY_FONT,
		20
	)
	role.TextXAlignment = Enum.TextXAlignment.Left
	role.Visible = false
	textStroke(role, 2)

	local announcement = label(
		"Announcement",
		hud,
		UDim2.new(0.86, 0, 0, 64),
		UDim2.new(0.5, 0, 0.24, 0),
		Vector2.new(0.5, 0.5),
		TITLE_FONT,
		46
	)
	announcement.Visible = false
	textStroke(announcement, 3)

	local sub = label(
		"SubAnnouncement",
		hud,
		UDim2.new(0.7, 0, 0, 56),
		UDim2.new(0.5, 0, 0.24, 44),
		Vector2.new(0.5, 0),
		BODY_FONT,
		22
	)
	sub.TextColor3 = Colors.SubText
	sub.Visible = false
	textStroke(sub, 2)
end

--------------------------------------------------------------------------------
-- VoteUI
--------------------------------------------------------------------------------

local function buildSilhouetteTemplate(parent: Instance)
	-- A tiny "person": round head + rounded body. Color is set by the client
	-- (gray = selected, blue = confirmed).
	local silhouette = frame(
		"Silhouette",
		parent,
		UDim2.new(0, 16, 0, 20),
		UDim2.new(0, 0, 0, 0),
		Vector2.new(0, 0),
		Colors.Text,
		1
	)
	silhouette.Visible = false
	local head = frame("Head", silhouette, UDim2.new(0, 9, 0, 9), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0), Colors.Text, 0)
	corner(head, 5)
	local body = frame("Body", silhouette, UDim2.new(0, 15, 0, 10), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1), Colors.Text, 0)
	corner(body, 5)
end

local function buildCardTemplate(parent: Instance)
	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.Size = UDim2.new(0, 132, 0, 176)
	card.BackgroundColor3 = Colors.PanelLight
	card.BorderSizePixel = 0
	card.AutoButtonColor = true
	card.Text = ""
	card.Visible = false
	card.Parent = parent
	corner(card, 12)

	local selection = Instance.new("UIStroke")
	selection.Name = "Selection"
	selection.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	selection.Thickness = 4
	selection.Color = Colors.Accent
	selection.Enabled = false
	selection.Parent = card

	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.Size = UDim2.new(0, 84, 0, 84)
	headshot.Position = UDim2.new(0.5, 0, 0, 10)
	headshot.AnchorPoint = Vector2.new(0.5, 0)
	headshot.BackgroundColor3 = Colors.Panel
	headshot.BorderSizePixel = 0
	headshot.Parent = card
	corner(headshot, 42)

	label("NameLabel", card, UDim2.new(1, -10, 0, 24), UDim2.new(0.5, 0, 0, 98), Vector2.new(0.5, 0), BODY_FONT, 18)

	local silhouettes = frame(
		"Silhouettes",
		card,
		UDim2.new(1, -12, 0, 44),
		UDim2.new(0.5, 0, 0, 126),
		Vector2.new(0.5, 0),
		Colors.Panel,
		1
	)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, 16, 0, 20)
	layout.CellPadding = UDim2.new(0, 2, 0, 2)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = silhouettes
end

local function buildVoteUI()
	local gui = screenGui("VoteUI", 5)
	gui.Enabled = false

	local panel = frame(
		"Panel",
		gui,
		UDim2.new(0.8, 0, 0.78, 0),
		UDim2.new(0.5, 0, 0.54, 0),
		Vector2.new(0.5, 0.5),
		Colors.Panel,
		0.08
	)
	corner(panel, 18)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(980, 640)
	limit.Parent = panel

	label("Title", panel, UDim2.new(1, -40, 0, 46), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0), TITLE_FONT, 36)

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, -32, 1, -140)
	grid.Position = UDim2.new(0.5, 0, 0, 66)
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.CanvasSize = UDim2.new(0, 0, 0, 0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = panel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 132, 0, 176)
	gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local confirm = Instance.new("TextButton")
	confirm.Name = "ConfirmButton"
	confirm.Size = UDim2.new(0, 220, 0, 52)
	confirm.Position = UDim2.new(0.5, 0, 1, -14)
	confirm.AnchorPoint = Vector2.new(0.5, 1)
	confirm.BackgroundColor3 = Colors.Accent
	confirm.BorderSizePixel = 0
	confirm.FontFace = TITLE_FONT
	confirm.Text = "Confirm"
	confirm.TextColor3 = Colors.Text
	confirm.TextScaled = true
	confirm.Visible = false
	confirm.Parent = panel
	corner(confirm, 14)
	maxTextSize(confirm, 28)

	local result = label(
		"ResultLabel",
		panel,
		UDim2.new(1, -40, 0, 110),
		UDim2.new(0.5, 0, 1, -8),
		Vector2.new(0.5, 1),
		TITLE_FONT,
		38
	)
	result.Visible = false
	textStroke(result, 3)

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	buildCardTemplate(templates)
	buildSilhouetteTemplate(templates)
end

buildHud()
buildVoteUI()
print("[BuildUI] done")
