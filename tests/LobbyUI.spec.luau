-- Contracts the Lobby place's client relies on: the UI made by
-- build/lobby/BuildLobbyUI.luau and the pad signs made by BuildLobby.
local lobby = loadLobby()
runBuilderIn(lobby, "build/lobby/BuildLobby.luau")
runBuilderIn(lobby, "build/lobby/BuildLobbyUI.luau")
local StarterGui = lobby.game:GetService("StarterGui")
local Strings = lobby.require(lobby.game.ReplicatedStorage.Shared.Strings)

test("QueueUI has what PadController looks up", function()
	local panel = StarterGui.QueueUI.Panel
	expect(panel.StatusLabel:IsA("TextLabel")).toBe(true)
	expect(panel.HintLabel:IsA("TextLabel")).toBe(true)
	expect(panel.StartButton:IsA("TextButton")).toBe(true)
end)

test("every pad has a sign with Title / Count / Status", function()
	local pads = lobby.game.Workspace.Lobby.Pads
	for id = 1, 4 do
		local sign = pads["PadSign" .. id].Sign
		for _, name in { "Title", "Count", "Status" } do
			expect(sign:FindFirstChild(name):IsA("TextLabel")).toBe(true)
		end
	end
end)

test("MenuUI: left Shop / Role / Monster / Settings, right News / Codes / Pass / Spin, all translated", function()
	local gui = StarterGui.MenuUI
	local left, right = {}, {}
	for _, item in gui.LeftBar:GetChildren() do
		if item:IsA("TextButton") then
			left[item.LayoutOrder] = item:GetAttribute("Page")
		end
	end
	for _, item in gui.RightBar:GetChildren() do
		if item:IsA("TextButton") then
			right[item.LayoutOrder] = item:GetAttribute("Page")
		end
	end
	expect(left).toEqual({ "Shop", "Role", "Monster", "Settings" })
	expect(right).toEqual({ "News", "Codes", "Pass", "Spin" })
	for _, page in { "Shop", "Role", "Monster", "Settings", "News", "Codes", "Pass", "Spin" } do
		expect(Strings["Menu." .. page] ~= nil).toBe(true)
	end
	local window = gui.Window
	for _, name in { "Title", "Body", "CloseButton" } do
		expect(window:FindFirstChild(name) ~= nil).toBe(true)
	end
	local row = gui.Templates.RoleRow
	for _, name in { "NameLabel", "DescLabel", "PriceLabel", "LevelLabel" } do
		expect(row:FindFirstChild(name):IsA("TextLabel")).toBe(true)
	end
	expect(gui.Templates.Text:IsA("TextLabel")).toBe(true)
end)

test("MenuUI: wallet bar, toast, buy buttons, code box and spin panel exist", function()
	local gui = StarterGui.MenuUI
	for _, name in { "CoinsLabel", "DiamondsLabel", "LevelLabel" } do
		expect(gui.WalletBar:FindFirstChild(name):IsA("TextLabel")).toBe(true)
	end
	expect(gui.TemporaryLabel:IsA("TextLabel")).toBe(true)
	expect(gui.Toast:IsA("TextLabel")).toBe(true)
	local templates = gui.Templates
	expect(templates.RoleRow.Buttons:IsA("Frame")).toBe(true)
	expect(templates.ActionButton:IsA("TextButton")).toBe(true)
	for _, currency in { "Coins", "Diamonds", "Robux", "Plain" } do
		expect(typeof(templates.ActionButton:GetAttribute("Color" .. currency))).toBe("Color3")
	end
	expect(templates.CodeBox.Input:IsA("TextBox")).toBe(true)
	expect(templates.CodeBox.RedeemButton:IsA("TextButton")).toBe(true)
	expect(templates.CodeBox.ResultLabel:IsA("TextLabel")).toBe(true)
	expect(templates.SpinPanel.WheelLabel:IsA("TextLabel")).toBe(true)
	expect(templates.SpinPanel.SpinButton:IsA("TextButton")).toBe(true)
	expect(templates.SpinPanel.InfoLabel:IsA("TextLabel")).toBe(true)
	expect(templates.ProgressBar.Fill:IsA("Frame")).toBe(true)
end)

local Config = lobby.require(lobby.game.ReplicatedStorage.Shared.Config)
local Remotes = lobby.require(lobby.game.ReplicatedStorage.Shared.Remotes)

test("lobby scripts: every remote is declared, every text key exists", function()
	local prefixes = { "Lobby", "Menu", "News", "Wallet", "Buy", "Shop", "Skin", "Pass", "Reward", "Spin", "Codes", "Title", "Role" }
	local remotes, keys = 0, 0
	for _, instance in lobby.game:GetDescendants() do
		if instance:IsA("LuaSourceContainer") and instance.Name ~= "Strings" then
			for _, pattern in { 'Remotes%.get%("(%w+)"%)', 'Net%.on%("(%w+)"', 'Net%.fire%([%w_%.]+, "(%w+)"', 'Net%.fireAll%("(%w+)"' } do
				for name in instance.Source:gmatch(pattern) do
					remotes += 1
					if not table.find(Remotes.Names, name) then
						error(`{instance.Name} uses undeclared remote "{name}"`)
					end
				end
			end
			for key in instance.Source:gmatch('"([%a]+%.[%w%.]+)"') do
				local prefix = key:match("^(%a+)%.")
				if table.find(prefixes, prefix) and key:sub(-1) ~= "." then
					keys += 1
					if Strings[key] == nil then
						error(`{instance.Name} uses missing text key "{key}"`)
					end
				end
			end
		end
	end
	expect(remotes >= 8).toBe(true)
	expect(keys >= 20).toBe(true)
end)

test("lobby: text keys built at runtime all exist (skins, titles, reasons, rewards)", function()
	local function must(key)
		if Strings[key] == nil then
			error("missing text key " .. key)
		end
	end
	for skinId, def in Config.Skins do
		must("Skin." .. skinId .. ".Name")
		must("Skin.Slot." .. def.Slot)
	end
	for _, titleId in Config.Titles do
		must("Title." .. titleId .. ".Name")
	end
	for _, reason in { "NotForSale", "Owned", "Level", "Funds", "WrongCurrency", "NoProduct", "Unsaved", "NotOwned" } do
		must("Shop.Reason." .. reason)
	end
	for _, reason in { "Unknown", "Used", "Expired" } do
		must("Codes.Reason." .. reason)
	end
	for _, kind in { "Coins", "Diamonds", "Spin" } do
		must("Reward." .. kind)
	end
	for _, currency in { "Coins", "Diamonds", "Robux" } do
		must("Buy." .. currency)
	end
	for _, page in { "Shop", "Role", "Monster", "Settings", "News", "Codes", "Pass", "Spin" } do
		must("Menu." .. page)
	end
	-- Every skin and title a reward can give is a known one.
	expect(Config.Skins[Config.DailySpin.Prizes[10].Id] ~= nil).toBe(true)
	expect(table.find(Config.Titles, Config.SeasonPass.FreeTitle) ~= nil).toBe(true)
	expect(table.find(Config.Titles, Config.SeasonPass.PremiumTitle) ~= nil).toBe(true)
end)

test("how to play: every page has a picture (known icons), a title and text; the screen exists", function()
	local Tutorial = lobby.require(lobby.game.ReplicatedStorage.Shared.Tutorial)
	local RoleIcons = lobby.require(lobby.game.ReplicatedStorage.Shared.RoleIcons)
	expect(#Tutorial.Pages >= 4).toBe(true)
	for _, page in Tutorial.Pages do
		expect(Strings[page.Key .. ".Title"] ~= nil).toBe(true)
		expect(Strings[page.Key .. ".Body"] ~= nil).toBe(true)
		expect(#page.Icons >= 1).toBe(true)
		for _, roleId in page.Icons do
			expect(RoleIcons.Designs[roleId] ~= nil).toBe(true)
		end
	end
	for _, key in { "Tutorial.Next", "Tutorial.Done", "Tutorial.Open", "Tutorial.Page" } do
		expect(Strings[key] ~= nil).toBe(true)
	end
	local panel = StarterGui.TutorialUI.Panel
	expect(StarterGui.TutorialUI.Enabled).toBe(false)
	for _, name in { "TitleLabel", "BodyLabel", "PageLabel" } do
		expect(panel[name]:IsA("TextLabel")).toBe(true)
	end
	expect(panel.Picture:IsA("Frame")).toBe(true)
	expect(panel.NextButton:IsA("TextButton")).toBe(true)
	expect(StarterGui.TutorialUI.DisplayOrder > StarterGui.MenuUI.DisplayOrder).toBe(true)
end)
