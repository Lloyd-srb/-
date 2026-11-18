--[[
	Role icons (round faces for every role, the werewolf and the pup) and the
	role reveal screen at the start of a match.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local RoleIcons = require(game.ReplicatedStorage.Shared.RoleIcons)
local Strings = require(game.ReplicatedStorage.Shared.Strings)

local function everyIcon()
	local list = { "Wolf", "Pup" }
	for _, roleId in Config.RoleOrder do
		table.insert(list, roleId)
	end
	return list
end

test("icons: one design for every role, the werewolf and the pup", function()
	for _, roleId in everyIcon() do
		local design = RoleIcons.Designs[roleId]
		expect(design ~= nil).toBe(true)
		expect(#design >= 6).toBe(true)
		for _, shape in design do
			expect(typeof(shape.Color)).toBe("Color3")
			expect(shape.X >= -10 and shape.X <= 110 and shape.Y >= -10 and shape.Y <= 110).toBe(true)
			expect(shape.W > 0 and shape.H > 0).toBe(true)
			expect((shape.R or 0) >= 0 and (shape.R or 0) <= 0.5).toBe(true)
		end
		expect(Strings["Role." .. roleId .. ".Name"] ~= nil).toBe(true)
	end
	-- Wolf-side icons get the yellow ring, solo roles their own colours.
	expect(RoleIcons.factionOf("Pup", Config.Roles)).toBe("Wolf")
	expect(RoleIcons.RingColors[RoleIcons.factionOf("Killer", Config.Roles)] ~= nil).toBe(true)
	expect(RoleIcons.RingColors[RoleIcons.factionOf("Fool", Config.Roles)] ~= nil).toBe(true)
end)

test("icons: built as round GUI (a clipped circle of shapes, no images)", function()
	local icon = RoleIcons.create("Sheriff", 120, Color3.new(1, 1, 1))
	expect(icon:IsA("Frame")).toBe(true)
	expect(icon:GetAttribute("RoleId")).toBe("Sheriff")
	local face = icon:FindFirstChild("Face")
	expect(face:IsA("CanvasGroup")).toBe(true)
	expect(face:FindFirstChildOfClass("UICorner").CornerRadius).toEqual(UDim.new(0.5, 0))
	local shapes = 0
	for _, child in face:GetChildren() do
		if child:IsA("Frame") then
			shapes += 1
		end
	end
	expect(shapes).toBe(#RoleIcons.Designs.Sheriff)
	expect(icon:FindFirstChildOfClass("UIStroke") ~= nil).toBe(true)
	-- No ImageLabels anywhere: nothing to upload.
	expect(icon:FindFirstChildWhichIsA("ImageLabel", true)).toBeNil()
end)

test("reveal reel: random icons, never the same twice in a row, ending on your role", function()
	local pool = { "Wolf", table.unpack(Config.RoleOrder) }
	local seed = 0
	local function nextInt(low, high)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return low + seed % (high - low + 1)
	end
	for _, final in pool do
		local reel = RoleIcons.reel(final, pool, 24, nextInt)
		expect(#reel).toBe(24)
		expect(reel[24]).toBe(final)
		expect(reel[23] ~= final).toBe(true) -- it really stops, not slides on the same icon
		for index = 2, #reel do
			expect(reel[index] ~= reel[index - 1]).toBe(true)
			expect(table.find(pool, reel[index]) ~= nil).toBe(true)
		end
	end
end)

test("reveal screen: RoleRollUI has what RoleRollController looks up", function()
	runBuilder("build/BuildUI.luau")
	local gui = game:GetService("StarterGui").RoleRollUI
	expect(gui.Enabled).toBe(false)
	expect(gui.ResetOnSpawn).toBe(false)
	local panel = gui.Panel
	expect(panel:IsA("CanvasGroup")).toBe(true)
	expect(panel.Window.ClipsDescendants).toBe(true)
	expect(panel.Window.Strip:IsA("Frame")).toBe(true)
	expect(panel.Window.Marker:FindFirstChildOfClass("UIStroke") ~= nil).toBe(true)
	expect(panel.TitleLabel:IsA("TextLabel")).toBe(true)
	expect(panel.DescLabel:IsA("TextLabel")).toBe(true)
	-- Above the HUD and the vote screen.
	expect(gui.DisplayOrder > game:GetService("StarterGui").VoteUI.DisplayOrder).toBe(true)
	expect(Strings["RoleRoll.YouAre"].en).toBe("You are {role}!")
	expect(Config.Sounds.RoleRollTick ~= nil and Config.Sounds.RoleReveal ~= nil).toBe(true)
end)
