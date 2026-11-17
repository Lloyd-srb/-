--!strict
--[[
	MenuController — the lobby's side menus and wallet (GDD §3, §13).
	  Left:  Shop (skins, coin packs) · Roles (buy) · Monster (werewolf skins) · Settings
	  Right: News · Codes · Pass (Season Pass) · Daily Spin
	Everything shown comes from this player's ProfileView (sent by the server).
	Buttons only ask the server (ShopBuy / Equip / SpinRequest / CodeRedeem);
	buttons the server would refuse are greyed out using the same rules
	(Shared.Logic.Shop).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local GamepadFocus = require(ReplicatedStorage.Shared.GamepadFocus)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Progression = require(ReplicatedStorage.Shared.Logic.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shop = require(ReplicatedStorage.Shared.Logic.Shop)

local TOAST_SECONDS = 3
local SPIN_MIN_SECONDS = 1.6
local SPIN_TICK = 0.08
local DISABLED_TRANSPARENCY = 0.55

local MenuController = {}

local window: Frame
local title: TextLabel
local body: ScrollingFrame
local templates: Instance
local walletBar: Frame
local temporaryLabel: TextLabel
local toast: TextLabel

local openPage: string? = nil
local view: any = nil -- this player's ProfileView
local spinning = false
local toastToken = 0
local codeAnswer: TextLabel? = nil
local spinInfo: TextLabel? = nil

--------------------------------------------------------------------------------
-- Text helpers
--------------------------------------------------------------------------------

local function nameOf(kind: string, id: string?): string
	if kind == "Role" and id then
		return Loc.format("Role." .. id .. ".Name")
	elseif kind == "Skin" and id and Loc.has("Skin." .. id .. ".Name") then
		return Loc.format("Skin." .. id .. ".Name")
	elseif kind == "Title" and id and Loc.has("Title." .. id .. ".Name") then
		return Loc.format("Title." .. id .. ".Name")
	elseif kind == "Premium" then
		return Loc.format("Reward.Premium")
	end
	return tostring(id)
end

local function rewardText(reward: any): string
	if type(reward) ~= "table" then
		return ""
	end
	local kind = reward.Kind
	local text: string
	if kind == "Coins" or kind == "Diamonds" or kind == "Spin" then
		text = Loc.format("Reward." .. kind, { amount = reward.Amount or 1 })
	elseif kind == "Role" or kind == "Skin" or kind == "Title" or kind == "Premium" then
		text = nameOf(kind, reward.Id)
	else
		return ""
	end
	if type(reward.ConvertedFrom) == "string" then
		local thing = if Config.Roles[reward.ConvertedFrom] then nameOf("Role", reward.ConvertedFrom) else nameOf("Skin", reward.ConvertedFrom)
		text = Loc.format("Reward.Converted", { reward = text, thing = thing })
	end
	return text
end

local function rewardsText(list: any): string
	local parts = {}
	if type(list) == "table" then
		for _, reward in list do
			local text = rewardText(reward)
			if text ~= "" then
				table.insert(parts, text)
			end
		end
	end
	return table.concat(parts, ", ")
end

local function formatDuration(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", whole // 3600, (whole // 60) % 60, whole % 60)
end

local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(TOAST_SECONDS, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local function template(name: string): any
	return templates:WaitForChild(name)
end

local function clear()
	codeAnswer, spinInfo = nil, nil
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function addText(text: string, order: number, color: Color3?): TextLabel
	local paragraph = template("Text"):Clone() :: TextLabel
	paragraph.Text = text
	paragraph.LayoutOrder = order
	if color then
		paragraph.TextColor3 = color
	end
	paragraph.Visible = true
	paragraph.Parent = body
	return paragraph
end

local function addRow(order: number, name: string, desc: string, price: string, level: string): Frame
	local row = template("RoleRow"):Clone() :: Frame
	row.LayoutOrder = order;
	(row:WaitForChild("NameLabel") :: TextLabel).Text = name;
	(row:WaitForChild("DescLabel") :: TextLabel).Text = desc;
	(row:WaitForChild("PriceLabel") :: TextLabel).Text = price;
	(row:WaitForChild("LevelLabel") :: TextLabel).Text = level
	row.Visible = true
	row.Parent = body
	return row
end

local function addBar(order: number, into: number, need: number)
	local bar = template("ProgressBar"):Clone() :: Frame
	bar.LayoutOrder = order;
	(bar:WaitForChild("Fill") :: Frame).Size = UDim2.fromScale(math.clamp(if need > 0 then into / need else 0, 0, 1), 1)
	bar.Visible = true
	bar.Parent = body
end

-- One button in a row. `color` = "Coins" / "Diamonds" / "Robux" / "Plain".
local function addButton(row: Frame, text: string, color: string, onClick: (() -> ())?, enabled: boolean)
	local button = template("ActionButton"):Clone() :: TextButton
	button.Text = text
	local tint = button:GetAttribute("Color" .. color)
	if typeof(tint) == "Color3" then
		button.BackgroundColor3 = tint
	end
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = if enabled then 0 else DISABLED_TRANSPARENCY
	button.LayoutOrder = #row:WaitForChild("Buttons"):GetChildren()
	button.Visible = true
	button.Parent = row:WaitForChild("Buttons")
	if onClick and enabled then
		button.Activated:Connect(onClick)
	end
end

local function wallet(): Shop.Wallet?
	if not view then
		return nil
	end
	return {
		Coins = view.Coins,
		Diamonds = view.Diamonds,
		Level = view.Level,
		Roles = view.Roles,
		Skins = view.Skins,
		Premium = view.Pass.Premium,
	}
end

-- A buy button per currency the offer takes, greyed out when not allowed.
local function addBuyButtons(row: Frame, kind: string, id: string)
	local offer = Shop.offer(kind, id)
	local current = wallet()
	if not offer or not current then
		return
	end
	for _, currency in { "Coins", "Diamonds", "Robux" } do
		local price = if currency == "Coins" then offer.Coins else offer.Gems
		if price then
			local allowed = Shop.check(current, kind, id, currency)
			addButton(row, Loc.format("Buy." .. currency, { price = price }), currency, function()
				Remotes.get("ShopBuy"):FireServer(kind, id, currency)
			end, allowed)
		end
	end
end

-- Equip / take off a skin or title this player owns.
local function addEquipButton(row: Frame, slot: string, id: string?)
	local worn = view and view.Equipped[slot]
	if worn == id then
		addButton(row, Loc.format("Menu.Equipped"), "Plain", nil, false)
		if id then
			addButton(row, Loc.format("Menu.Unequip"), "Plain", function()
				Remotes.get("Equip"):FireServer(slot, "")
			end, true)
		end
	else
		addButton(row, Loc.format("Menu.Equip"), "Plain", function()
			Remotes.get("Equip"):FireServer(slot, id or "")
		end, true)
	end
end

local function skinRow(order: number, skinId: string)
	local def = Config.Skins[skinId]
	local owned = view and view.Skins[skinId] == true
	local price = if def.Source == "Shop" and def.Price
		then Loc.format("Buy.Diamonds", { price = def.Price }) .. "  ·  " .. Loc.format("Buy.Robux", { price = def.Price })
		elseif def.Source == "Pass" then Loc.format("Skin.FromPass")
		else Loc.format("Skin.FromSpin")
	local row = addRow(order, nameOf("Skin", skinId), Loc.format("Skin.Slot." .. def.Slot), price, if owned then Loc.format("Menu.Owned") else "")
	if owned then
		addEquipButton(row, def.Slot, skinId)
	elseif def.Source == "Shop" then
		addBuyButtons(row, "Skin", skinId)
	end
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local PAGES: { [string]: () -> () } = {}

function PAGES.Role()
	local current = wallet()
	for order, roleId in Config.RoleOrder do
		local def = Config.Roles[roleId]
		local price = if def.Free
			then Loc.format("Menu.Free")
			else Loc.format("Menu.Price", { coins = def.CoinPrice, robux = def.RobuxPrice })
		local level = if def.RequiredLevel > 1 then Loc.format("Menu.Level", { level = def.RequiredLevel }) else ""
		if view then
			local points = view.Mastery[roleId] or 0
			local per = Config.Mastery.PointsPerMastery
			local mastery = Loc.format("Menu.Mastery", {
				mastery = Progression.masteryLevel(points),
				points = points % per,
				per = per,
			})
			level = if level == "" then mastery else level .. "   ·   " .. mastery
		end
		local row = addRow(order, Loc.format("Role." .. roleId .. ".Name"), Loc.format("Role." .. roleId .. ".Desc"), price, level)
		if current and Shop.owns(current, "Role", roleId) then
			addButton(row, Loc.format("Menu.Owned"), "Plain", nil, false)
		elseif current then
			addBuyButtons(row, "Role", roleId)
		end
	end
end

function PAGES.Shop()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	addText(Loc.format("Shop.Skins"), nextOrder())
	for _, skinId in Config.SkinOrder do
		if Config.Skins[skinId].Slot ~= "Wolf" then
			skinRow(nextOrder(), skinId)
		end
	end
	addText(Loc.format("Shop.CoinPacks"), nextOrder())
	for _, pack in Config.CoinPacks do
		local row = addRow(nextOrder(), Loc.format("Shop.CoinPack", { coins = pack.Coins }), "", "", "")
		addBuyButtons(row, "Coins", tostring(pack.Coins))
	end
end

function PAGES.Monster()
	addText(Loc.format("Menu.Werewolf"), 1)
	local plain = addRow(2, Loc.format("Menu.WolfDefault"), Loc.format("Skin.Slot.Wolf"), "", "")
	if view then
		addEquipButton(plain, "Wolf", nil)
	end
	local order = 2
	for _, skinId in Config.SkinOrder do
		if Config.Skins[skinId].Slot == "Wolf" then
			order += 1
			skinRow(order, skinId)
		end
	end
	addText(Loc.format("Menu.MonsterInfo"), order + 1)
end

function PAGES.Settings()
	addText(Loc.format("Menu.SettingsInfo"), 1)
end

function PAGES.News()
	addText(Loc.format("News.Body"), 1)
end

function PAGES.Codes()
	local box = template("CodeBox"):Clone() :: Frame
	box.LayoutOrder = 1
	local input = box:WaitForChild("Input") :: TextBox
	input.PlaceholderText = Loc.format("Codes.Placeholder")
	local redeem = box:WaitForChild("RedeemButton") :: TextButton
	redeem.Text = Loc.format("Codes.Redeem")
	codeAnswer = box:WaitForChild("ResultLabel") :: TextLabel
	redeem.Activated:Connect(function()
		if input.Text ~= "" then
			Remotes.get("CodeRedeem"):FireServer(input.Text)
		end
	end)
	box.Visible = true
	box.Parent = body
end

local function passLine(level: number, track: string): string
	local parts = {}
	for _, reward in Progression.passRewards(level, track :: any) do
		table.insert(parts, rewardText(reward))
	end
	return table.concat(parts, " + ")
end

function PAGES.Pass()
	if not view then
		return
	end
	local pass = view.Pass
	local cfg = Config.SeasonPass
	addText(Loc.format("Pass.Level", { level = pass.Level }), 1)
	addText(Loc.format("Pass.Progress", { into = pass.Into, need = pass.Need }), 2)
	addBar(3, pass.Into, pass.Need)
	local premium = addRow(4, Loc.format("Reward.Premium"), Loc.format("Pass.Premium"), "", "")
	if pass.Premium then
		addButton(premium, Loc.format("Pass.PremiumOwned"), "Plain", nil, false)
	else
		addBuyButtons(premium, "Premium", "Premium")
	end
	addText(Loc.format("Pass.Info"), 5)

	addText(Loc.format("Pass.Titles"), 6)
	local order = 6
	for _, titleId in Config.Titles do
		if view.Titles[titleId] then
			order += 1
			local row = addRow(order, nameOf("Title", titleId), "", "", "")
			addEquipButton(row, "Title", titleId)
		end
	end

	local reached = Color3.fromRGB(140, 230, 150)
	for level = 1, cfg.MainLevels do
		order += 1
		addText(
			Loc.format("Pass.Row", { level = level, free = passLine(level, "Free"), premium = passLine(level, "Premium") }),
			order,
			if level <= pass.Level then reached else nil
		)
	end
	addText(Loc.format("Pass.After", {
		level = cfg.MainLevels + 1,
		free = passLine(cfg.MainLevels + 1, "Free"),
		premium = passLine(cfg.MainLevels + 1, "Premium"),
	}), order + 1)
end

local function spinLeftText(): string
	if not view then
		return ""
	end
	local lines = {}
	if view.Spin.Free then
		table.insert(lines, Loc.format("Spin.FreeReady"))
	else
		table.insert(lines, Loc.format("Spin.NextFree", { time = formatDuration(view.Spin.NextFreeAt - workspace:GetServerTimeNow()) }))
	end
	if view.Spin.Extra > 0 then
		table.insert(lines, Loc.format("Spin.Extra", { count = view.Spin.Extra }))
	end
	return table.concat(lines, "   ·   ")
end

local function prizeText(prize: any): string
	return rewardText(prize)
end

function PAGES.Spin()
	local panel = template("SpinPanel"):Clone() :: Frame
	panel.LayoutOrder = 1
	local wheel = panel:WaitForChild("WheelLabel") :: TextLabel
	local button = panel:WaitForChild("SpinButton") :: TextButton
	local info = panel:WaitForChild("InfoLabel") :: TextLabel
	spinInfo = info
	wheel.Text = "?"
	button.Text = Loc.format("Spin.Button")
	local canSpin = view ~= nil and (view.Spin.Free or view.Spin.Extra > 0)
	button.AutoButtonColor = canSpin
	button.BackgroundTransparency = if canSpin then 0 else DISABLED_TRANSPARENCY
	button.Activated:Connect(function()
		if spinning or not view or not (view.Spin.Free or view.Spin.Extra > 0) then
			return
		end
		spinning = true
		Remotes.get("SpinRequest"):FireServer()
		task.spawn(function()
			local prizes = Config.DailySpin.Prizes
			local index = 1
			while spinning and wheel.Parent do
				index = index % #prizes + 1
				wheel.Text = prizeText(prizes[index])
				Audio.play("SpinTick")
				task.wait(SPIN_TICK)
			end
		end)
	end)
	panel:SetAttribute("Wheel", true)
	panel.Visible = true
	panel.Parent = body
	info.Text = spinLeftText()

	for order, prize in Config.DailySpin.Prizes do
		addText(Loc.format("Spin.Odds", { prize = prizeText(prize), chance = prize.Weight }), order + 1)
	end
end

local function render()
	local page = openPage
	if not page or spinning then
		return
	end
	local scroll = body.CanvasPosition
	clear()
	title.Text = Loc.format("Menu." .. page)
	local needsProfile = page ~= "News" and page ~= "Settings" and page ~= "Role"
	if needsProfile and not view then
		addText(Loc.format("Menu.Loading"), 1)
	else
		local fill = PAGES[page]
		if fill then
			fill()
		end
	end
	body.CanvasPosition = scroll
end

local function open(page: string)
	if openPage == page and window.Visible then
		window.Visible = false
		openPage = nil
		return
	end
	openPage = page
	body.CanvasPosition = Vector2.zero
	render()
	window.Visible = true
	Audio.play("UIOpen")
	GamepadFocus.offer(body:FindFirstChildWhichIsA("GuiButton", true) or window:FindFirstChild("CloseButton"))
end

--------------------------------------------------------------------------------
-- Server messages
--------------------------------------------------------------------------------

local function onView(newView: any)
	if type(newView) ~= "table" then
		return
	end
	view = newView
	local coins = walletBar:FindFirstChild("CoinsLabel") :: TextLabel?
	local diamonds = walletBar:FindFirstChild("DiamondsLabel") :: TextLabel?
	local level = walletBar:FindFirstChild("LevelLabel") :: TextLabel?
	if coins and diamonds and level then
		coins.Text = Loc.format("Wallet.Coins", { coins = view.Coins })
		diamonds.Text = Loc.format("Wallet.Diamonds", { diamonds = view.Diamonds })
		level.Text = Loc.format("Wallet.Level", { level = view.Level })
	end
	temporaryLabel.Text = Loc.format("Wallet.Temporary")
	temporaryLabel.Visible = view.Temporary == true
	if window.Visible then
		render()
	end
end

local function onShopResult(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.Ok then
		local text = rewardsText(data.Rewards)
		if text == "" and type(data.Kind) == "string" then
			text = nameOf(data.Kind, data.Id)
		end
		showToast(Loc.format("Shop.Bought", { thing = text }))
		Audio.play("Purchase")
	elseif type(data.Reason) == "string" and Loc.has("Shop.Reason." .. data.Reason) then
		showToast(Loc.format("Shop.Reason." .. data.Reason))
	end
end

local function onSpinResult(data: any)
	local started = os.clock()
	task.spawn(function()
		-- Let the wheel turn a little before it stops.
		local wait = SPIN_MIN_SECONDS - (os.clock() - started)
		if wait > 0 then
			task.wait(wait)
		end
		spinning = false
		local text = if type(data) == "table" and data.Ok then Loc.format("Spin.Won", { prize = rewardText(data.Prize) }) else Loc.format("Spin.NoneLeft")
		if type(data) == "table" and data.Ok then
			Audio.play("SpinWin")
		end
		showToast(text)
		render()
		local wheelPanel = body:FindFirstChild("SpinPanel")
		local wheel = wheelPanel and wheelPanel:FindFirstChild("WheelLabel")
		if wheel and wheel:IsA("TextLabel") and type(data) == "table" and data.Ok then
			wheel.Text = rewardText(data.Prize)
		end
	end)
end

local function onCodeResult(data: any)
	if type(data) ~= "table" then
		return
	end
	local text = if data.Ok
		then Loc.format("Codes.Done", { rewards = rewardsText(data.Rewards) })
		elseif type(data.Reason) == "string" and Loc.has("Codes.Reason." .. data.Reason) then Loc.format("Codes.Reason." .. data.Reason)
		else ""
	if codeAnswer then
		codeAnswer.Text = text
	end
	showToast(text)
end

function MenuController.Start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MenuUI")
	window = gui:WaitForChild("Window") :: Frame
	title = window:WaitForChild("Title") :: TextLabel
	body = window:WaitForChild("Body") :: ScrollingFrame
	templates = gui:WaitForChild("Templates")
	walletBar = gui:WaitForChild("WalletBar") :: Frame
	temporaryLabel = gui:WaitForChild("TemporaryLabel") :: TextLabel
	toast = gui:WaitForChild("Toast") :: TextLabel
	local close = window:WaitForChild("CloseButton") :: TextButton
	close.Text = Loc.format("Menu.Close")
	close.Activated:Connect(function()
		GamepadFocus.release(window)
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

	Remotes.get("ProfileView").OnClientEvent:Connect(onView)
	Remotes.get("ShopResult").OnClientEvent:Connect(onShopResult)
	Remotes.get("SpinResult").OnClientEvent:Connect(onSpinResult)
	Remotes.get("CodeResult").OnClientEvent:Connect(onCodeResult)

	-- The next-free-spin clock ticks; when it runs out the free spin is back.
	task.spawn(function()
		while true do
			task.wait(1)
			if view and not view.Spin.Free and workspace:GetServerTimeNow() >= view.Spin.NextFreeAt then
				view.Spin.Free = true
				if openPage == "Spin" then
					render()
				end
			elseif spinInfo and spinInfo.Parent then
				spinInfo.Text = spinLeftText()
			end
		end
	end)
end

return MenuController
