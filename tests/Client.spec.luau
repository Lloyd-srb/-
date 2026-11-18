-- Contracts the client relies on: UI built by build/BuildUI.luau, and every
-- text key used in code existing in Shared.Strings (en + th).
local Config = require(game.ReplicatedStorage.Shared.Config)
local Loc = require(game.ReplicatedStorage.Shared.Loc)
local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Strings = require(game.ReplicatedStorage.Shared.Strings)

runBuilder("build/BuildUI.luau")
local StarterGui = game:GetService("StarterGui")

local function path(root, names)
	local current = root
	for _, name in names do
		current = current and current:FindFirstChild(name)
	end
	return current
end

test("Hud has everything HudController looks up", function()
	expect(game:GetService("StarterGui").Hud:FindFirstChild("LobbyButton") ~= nil).toBe(true)
	local hud = StarterGui:FindFirstChild("Hud")
	expect(hud ~= nil).toBe(true)
	for _, names in {
		{ "TopBar", "PhaseLabel" },
		{ "TopBar", "TimerLabel" },
		{ "RoleLabel" },
		{ "PackLabel" },
		{ "Toast" },
		{ "TaskLabel" },
		{ "Announcement" },
		{ "SubAnnouncement" },
	} do
		local found = path(hud, names)
		expect(found ~= nil and found:IsA("TextLabel")).toBe(true)
	end
end)

test("VoteUI has everything VoteController looks up", function()
	local gui = StarterGui:FindFirstChild("VoteUI")
	expect(gui ~= nil and gui.Enabled == false).toBe(true)
	expect(path(gui, { "Panel", "Title" }):IsA("TextLabel")).toBe(true)
	expect(path(gui, { "Panel", "Grid" }) ~= nil).toBe(true)
	expect(path(gui, { "Panel", "ConfirmButton" }):IsA("TextButton")).toBe(true)
	expect(path(gui, { "Panel", "ResultLabel" }):IsA("TextLabel")).toBe(true)

	local card = path(gui, { "Templates", "Card" })
	expect(card:IsA("GuiButton")).toBe(true)
	expect(card:FindFirstChild("NameLabel"):IsA("TextLabel")).toBe(true)
	expect(card:FindFirstChild("Headshot"):IsA("ImageLabel")).toBe(true)
	expect(card:FindFirstChild("Silhouettes") ~= nil).toBe(true)
	expect(card:FindFirstChildOfClass("UIStroke") ~= nil).toBe(true)

	local silhouette = path(gui, { "Templates", "Silhouette" })
	expect(silhouette:IsA("Frame")).toBe(true)
	expect(silhouette:FindFirstChild("Head") ~= nil and silhouette:FindFirstChild("Body") ~= nil).toBe(true)
end)

test("no role screen in the match (picks are made in the Lobby); EyesUI exists", function()
	expect(StarterGui:FindFirstChild("RoleSelectUI")).toBeNil()
	local eyes = StarterGui:FindFirstChild("EyesUI")
	expect(eyes ~= nil).toBe(true)
	expect(eyes.Black:IsA("Frame")).toBe(true)
	expect(eyes.Black.Visible).toBe(false)
	expect(eyes.DisplayOrder > StarterGui.Hud.DisplayOrder).toBe(true)
end)

test("PickerUI has everything RoleController looks up", function()
	local gui = StarterGui:FindFirstChild("PickerUI")
	expect(gui ~= nil and gui.Enabled == false).toBe(true)
	expect(path(gui, { "Panel", "Title" }):IsA("TextLabel")).toBe(true)
	expect(path(gui, { "Panel", "List" }) ~= nil).toBe(true)
	expect(path(gui, { "Panel", "CloseButton" }):IsA("TextButton")).toBe(true)
	expect(path(gui, { "Templates", "Option" }):IsA("TextButton")).toBe(true)
end)

test("ScoreboardUI has everything ScoreboardController looks up", function()
	local gui = StarterGui:FindFirstChild("ScoreboardUI")
	expect(gui ~= nil and gui.Enabled == false).toBe(true)
	for _, name in { "Title", "Hint", "RewardLabel", "DetailLabel" } do
		expect(path(gui, { "Panel", name }):IsA("TextLabel")).toBe(true)
	end
	expect(path(gui, { "Panel", "List" }) ~= nil).toBe(true)
	local row = path(gui, { "Templates", "Row" })
	for _, name in { "NameLabel", "RoleLabel", "StatusLabel", "MvpLabel", "LikeCount" } do
		expect(row:FindFirstChild(name):IsA("TextLabel")).toBe(true)
	end
	expect(row:FindFirstChild("Headshot"):IsA("ImageLabel")).toBe(true)
	expect(row:FindFirstChild("LikeButton"):IsA("TextButton")).toBe(true)
end)

test("every remote the scripts use is declared in Remotes.Names", function()
	local used = {}
	for _, instance in game:GetDescendants() do
		if instance:IsA("LuaSourceContainer") then
			for _, pattern in {
				'Remotes%.get%("(%w+)"%)',
				'Net%.on%("(%w+)"',
				'Net%.fire%([%w_%.]+, "(%w+)"',
				'Net%.fireAll%("(%w+)"',
			} do
				for name in instance.Source:gmatch(pattern) do
					used[name] = instance.Name
				end
			end
		end
	end
	local count = 0
	for name, scriptName in used do
		count += 1
		if not table.find(Remotes.Names, name) then
			error(`{scriptName} uses undeclared remote "{name}"`)
		end
	end
	expect(count >= 10).toBe(true)
end)

test("every text key written in code exists in Strings", function()
	local prefixes = { "Phase", "Morning", "Vote", "Ending", "Role", "Item", "Task", "Prompt", "Chat", "End", "Faction", "Hud", "Ability", "RoleSelect", "Picker", "Effect", "RoleRoll" }
	local checked = 0
	for _, instance in game:GetDescendants() do
		if instance:IsA("LuaSourceContainer") and instance.Name ~= "Strings" then
			for key in instance.Source:gmatch('"([%a]+%.[%w%.]+)"') do
				local prefix = key:match("^(%a+)%.")
				-- Keys ending in "." are prefixes completed at runtime (checked below).
				if table.find(prefixes, prefix) and key:sub(-1) ~= "." then
					checked += 1
					-- A key may also be a prefix completed at runtime ("Morning.Taunt" .. n).
					local known = Strings[key] ~= nil
					if not known then
						for existing in Strings do
							if existing:sub(1, #key) == key then
								known = true
								break
							end
						end
					end
					if not known then
						error(`{instance.Name} uses missing text key "{key}"`)
					end
				end
			end
		end
	end
	expect(checked >= 8).toBe(true)
end)

test("text keys built at runtime all exist", function()
	local function must(key)
		if Strings[key] == nil then
			error("missing text key " .. key)
		end
	end
	for _, winner in { "Village", "Wolf", "Killer", "Fool" } do
		must("Ending." .. winner)
		must("Faction." .. winner)
	end
	for _, roleId in { "Wolf", "Pup", table.unpack(Config.RoleOrder) } do
		must("Role." .. roleId .. ".Name")
		must("Role." .. roleId .. ".Desc")
	end
	for _, phase in { "RoleSelect", "Day", "Night", "MeetingCountdown", "Meeting", "FullMoonWarning", "GameOver", "Waiting" } do
		must("Phase." .. phase)
	end
	for index = 1, 3 do
		must("Morning.Taunt" .. index)
	end
end)

test("every string has English and Thai text", function()
	for key, entry in Strings do
		if type(entry.en) ~= "string" or entry.en == "" or type(entry.th) ~= "string" or entry.th == "" then
			error("incomplete text for " .. key)
		end
	end
end)

test("Loc falls back to Strings and fills parameters", function()
	expect(Loc.format("Phase.FullMoon", { seconds = 10 })).toBe("Full moon in 10 seconds")
	expect(Loc.format("Vote.Exiled", { name = "Qerty" })).toBe("Qerty was exiled.")
	expect(Loc.format("Morning.Safe")).toBe("You're safe... for now...")
	expect(Loc.format("No.Such.Key")).toBe("No.Such.Key")
end)
