--!strict
--[[
	BuildUI — (re)builds the Match-place ScreenGuis in StarterGui:
	  Hud     phase name, timer, own role, announcements
	  VoteUI  the meeting vote screen (GDD §6.2)
	  RoleRollUI  the role reveal when the match starts: role icons slide by
	          left to right and stop on your own role ("You are ...")
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

	-- Wolf side only: who is in the pack (filled in by the client).
	local pack = label(
		"PackLabel",
		hud,
		UDim2.new(0, 280, 0, 26),
		UDim2.new(0, 16, 0, 84),
		Vector2.new(0, 0),
		BODY_FONT,
		16
	)
	pack.TextXAlignment = Enum.TextXAlignment.Left
	pack.TextColor3 = rgb(255, 120, 120)
	pack.Visible = false
	textStroke(pack, 2)

	-- Own task of the day (top left, under the role).
	local taskLabel = label(
		"TaskLabel",
		hud,
		UDim2.new(0, 320, 0, 26),
		UDim2.new(0, 16, 0, 112),
		Vector2.new(0, 0),
		BODY_FONT,
		16
	)
	taskLabel.TextXAlignment = Enum.TextXAlignment.Left
	taskLabel.TextColor3 = rgb(190, 235, 160)
	taskLabel.Visible = false
	textStroke(taskLabel, 2)

	-- Short private feedback ("You blessed ...", "Blocked!").
	local toast = label(
		"Toast",
		hud,
		UDim2.new(0.6, 0, 0, 34),
		UDim2.new(0.5, 0, 0.72, 0),
		Vector2.new(0.5, 0.5),
		BODY_FONT,
		26
	)
	toast.Visible = false
	textStroke(toast, 2)

	-- Ghosts, spectators and everyone after the end: back to the lobby (owner, 17 Nov 2026).
	local lobbyButton = Instance.new("TextButton")
	lobbyButton.Name = "LobbyButton"
	lobbyButton.Size = UDim2.new(0, 190, 0, 44)
	lobbyButton.Position = UDim2.new(1, -16, 0, 48)
	lobbyButton.AnchorPoint = Vector2.new(1, 0)
	lobbyButton.BackgroundColor3 = Colors.PanelLight
	lobbyButton.BorderSizePixel = 0
	lobbyButton.FontFace = TITLE_FONT
	lobbyButton.TextColor3 = Colors.Text
	lobbyButton.TextScaled = true
	lobbyButton.Text = ""
	lobbyButton.Visible = false
	lobbyButton.Parent = hud
	corner(lobbyButton, 12)
	maxTextSize(lobbyButton, 20)

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
	-- The Chief's crown (shown on one silhouette once the votes are locked).
	local crown = Instance.new("Frame")
	crown.Name = "Crown"
	crown.Size = UDim2.new(0, 12, 0, 6)
	crown.Position = UDim2.new(0.5, 0, 0, -1)
	crown.AnchorPoint = Vector2.new(0.5, 1)
	crown.BackgroundTransparency = 1
	crown.Visible = false
	crown.Parent = silhouette
	local gold = rgb(255, 205, 60)
	frame("Band", crown, UDim2.new(1, 0, 0, 3), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1), gold, 0)
	for index, x in { 0.15, 0.5, 0.85 } do
		local point = frame("Point" .. index, crown, UDim2.new(0, 4, 0, 4), UDim2.new(x, 0, 0.45, 0), Vector2.new(0.5, 0.5), gold, 0)
		point.Rotation = 45
	end
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

--------------------------------------------------------------------------------

local function buildPickerUI()
	local gui = screenGui("PickerUI", 7)
	gui.Enabled = false

	local panel = frame(
		"Panel",
		gui,
		UDim2.new(0, 420, 0.7, 0),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		Colors.Panel,
		0.05
	)
	corner(panel, 18)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, 560)
	limit.Parent = panel

	label("Title", panel, UDim2.new(1, -40, 0, 40), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0), TITLE_FONT, 28)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -32, 1, -130)
	list.Position = UDim2.new(0.5, 0, 0, 60)
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.Size = UDim2.new(0, 160, 0, 44)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.BackgroundColor3 = Colors.PanelLight
	close.BorderSizePixel = 0
	close.FontFace = TITLE_FONT
	close.Text = "Close"
	close.TextColor3 = Colors.Text
	close.TextScaled = true
	close.Parent = panel
	corner(close, 12)
	maxTextSize(close, 24)

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui
	local option = Instance.new("TextButton")
	option.Name = "Option"
	option.Size = UDim2.new(1, -8, 0, 48)
	option.BackgroundColor3 = Colors.PanelLight
	option.BorderSizePixel = 0
	option.FontFace = BODY_FONT
	option.Text = ""
	option.TextColor3 = Colors.Text
	option.TextScaled = true
	option.Visible = false
	option.Parent = templates
	corner(option, 10)
	maxTextSize(option, 22)
end

--------------------------------------------------------------------------------
-- ScoreboardUI: end of match (GDD §7)
--------------------------------------------------------------------------------

local function buildScoreboardUI()
	local gui = screenGui("ScoreboardUI", 8)
	gui.Enabled = false

	local panel = frame(
		"Panel",
		gui,
		UDim2.new(0.88, 0, 0.86, 0),
		UDim2.new(0.5, 0, 0.53, 0),
		Vector2.new(0.5, 0.5),
		Colors.Panel,
		0.05
	)
	corner(panel, 18)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(900, 700)
	limit.Parent = panel

	label("Title", panel, UDim2.new(1, -40, 0, 44), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0), TITLE_FONT, 34)
	local hint = label("Hint", panel, UDim2.new(1, -40, 0, 22), UDim2.new(0.5, 0, 0, 56), Vector2.new(0.5, 0), BODY_FONT, 16)
	hint.TextColor3 = Colors.SubText

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -32, 1, -190)
	list.Position = UDim2.new(0.5, 0, 0, 84)
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local reward = label("RewardLabel", panel, UDim2.new(1, -40, 0, 30), UDim2.new(0.5, 0, 1, -66), Vector2.new(0.5, 1), TITLE_FONT, 26)
	reward.TextColor3 = rgb(255, 220, 110)
	local detail = label("DetailLabel", panel, UDim2.new(1, -40, 0, 40), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1), BODY_FONT, 18)
	detail.TextColor3 = Colors.SubText

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	templates.Parent = gui

	local row = frame("Row", templates, UDim2.new(1, -8, 0, 52), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Colors.PanelLight, 0)
	row.Visible = false
	corner(row, 10)
	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.Size = UDim2.new(0, 44, 0, 44)
	headshot.Position = UDim2.new(0, 6, 0.5, 0)
	headshot.AnchorPoint = Vector2.new(0, 0.5)
	headshot.BackgroundColor3 = Colors.Panel
	headshot.BorderSizePixel = 0
	headshot.Parent = row
	corner(headshot, 22)
	local name = label("NameLabel", row, UDim2.new(0.3, -60, 1, -12), UDim2.new(0, 58, 0.5, 0), Vector2.new(0, 0.5), BODY_FONT, 20)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local role = label("RoleLabel", row, UDim2.new(0.25, 0, 1, -12), UDim2.new(0.3, 0, 0.5, 0), Vector2.new(0, 0.5), TITLE_FONT, 20)
	role.TextXAlignment = Enum.TextXAlignment.Left
	local status = label("StatusLabel", row, UDim2.new(0.17, 0, 1, -12), UDim2.new(0.55, 0, 0.5, 0), Vector2.new(0, 0.5), BODY_FONT, 18)
	status.TextXAlignment = Enum.TextXAlignment.Left
	local mvp = label("MvpLabel", row, UDim2.new(0, 56, 1, -16), UDim2.new(0.72, 0, 0.5, 0), Vector2.new(0, 0.5), TITLE_FONT, 20)
	mvp.TextColor3 = rgb(255, 210, 70)
	mvp.Visible = false
	local count = label("LikeCount", row, UDim2.new(0, 40, 1, -16), UDim2.new(1, -136, 0.5, 0), Vector2.new(1, 0.5), TITLE_FONT, 22)
	count.Text = "0"
	local like = Instance.new("TextButton")
	like.Name = "LikeButton"
	like.Size = UDim2.new(0, 120, 0, 44) -- 44 px: big enough for a finger
	like.Position = UDim2.new(1, -8, 0.5, 0)
	like.AnchorPoint = Vector2.new(1, 0.5)
	like.BackgroundColor3 = rgb(230, 90, 120)
	like.BorderSizePixel = 0
	like.FontFace = TITLE_FONT
	like.Text = "Like"
	like.TextColor3 = Colors.Text
	like.TextScaled = true
	like.Parent = row
	corner(like, 10)
	maxTextSize(like, 20)
end

--------------------------------------------------------------------------------
-- RoleRollUI: the role reveal at the start (RoleRollController fills it)
--------------------------------------------------------------------------------

local function buildRoleRollUI()
	local gui = screenGui("RoleRollUI", 9)
	gui.Enabled = false

	-- A CanvasGroup so the whole panel can fade in and out at once.
	local panel = Instance.new("CanvasGroup")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0.92, 0, 0.52, 0)
	panel.Position = UDim2.new(0.5, 0, 0.47, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Colors.Panel
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 24)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, 340)
	limit.MinSize = Vector2.new(300, 200)
	limit.Parent = panel

	-- The reel window: icons slide inside it, anything outside is cut off.
	local window = frame("Window", panel, UDim2.new(1, -40, 0.52, 0), UDim2.new(0.5, 0, 0, 18), Vector2.new(0.5, 0), rgb(14, 15, 24), 0)
	window.ClipsDescendants = true
	corner(window, 18)
	frame("Strip", window, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Vector2.new(0, 0), Colors.Panel, 1)

	-- A gold ring that marks the middle of the reel.
	local marker = frame("Marker", window, UDim2.fromOffset(150, 150), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Colors.Panel, 1)
	marker.ZIndex = 50
	local markerRound = Instance.new("UICorner")
	markerRound.CornerRadius = UDim.new(0.5, 0)
	markerRound.Parent = marker
	local ring = Instance.new("UIStroke")
	ring.Color = rgb(255, 205, 60)
	ring.Thickness = 6
	ring.Parent = marker

	local title = label("TitleLabel", panel, UDim2.new(1, -40, 0.2, 0), UDim2.new(0.5, 0, 0.6, 0), Vector2.new(0.5, 0), TITLE_FONT, 46)
	textStroke(title, 2)
	local desc = label("DescLabel", panel, UDim2.new(1, -60, 0.14, 0), UDim2.new(0.5, 0, 0.82, 0), Vector2.new(0.5, 0), BODY_FONT, 20)
	desc.TextColor3 = Colors.SubText
end

--------------------------------------------------------------------------------
-- EyesUI (owner, 18 Nov 2026): the screen goes black for ~3 s at nightfall and
-- in the morning while the living are moved home ("eyes closed").
--------------------------------------------------------------------------------

local function buildEyesUI()
	local gui = screenGui("EyesUI", 20)
	local black = Instance.new("Frame")
	black.Name = "Black"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Visible = false
	black.Parent = gui
end

buildHud()
buildEyesUI()
buildRoleRollUI()
buildVoteUI()
buildPickerUI()
buildScoreboardUI()
print("[BuildUI] done")
