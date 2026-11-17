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
