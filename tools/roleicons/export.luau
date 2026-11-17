--[[
	Writes the role icon designs (Shared.RoleIcons) to JSON for render.py.
	Usage (repo root):  lune run tools/roleicons/export.luau <out.json>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = require("../lib/Harness")

local loaded = Harness.load("src")
local Shared = loaded.game.ReplicatedStorage.Shared
local Config = loaded.require(Shared.Config)
local RoleIcons = loaded.require(Shared.RoleIcons)

local function color(c)
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end

local order = { "Wolf", "Pup" }
for _, roleId in Config.RoleOrder do
	table.insert(order, roleId)
end

local out = { order = order, icons = {}, rings = {}, names = {} }
for _, roleId in order do
	local shapes = {}
	for _, shape in RoleIcons.Designs[roleId] do
		table.insert(shapes, {
			x = shape.X,
			y = shape.Y,
			w = shape.W,
			h = shape.H,
			r = shape.R or 0,
			rot = shape.Rot or 0,
			t = shape.T or 0,
			color = color(shape.Color),
			stroke = if shape.Stroke then { color = color(shape.Stroke.Color), width = shape.Stroke.Width } else nil,
		})
	end
	out.icons[roleId] = shapes
	out.rings[roleId] = color(RoleIcons.RingColors[RoleIcons.factionOf(roleId, Config.Roles)])
end
local Strings = loaded.require(Shared.Strings)
for _, roleId in order do
	out.names[roleId] = { en = Strings["Role." .. roleId .. ".Name"].en, th = Strings["Role." .. roleId .. ".Name"].th }
end

-- The how-to-play pages (pictures + English text) for the tutorial preview.
local Tutorial = loaded.require(Shared.Tutorial)
out.tutorial = {}
for _, page in Tutorial.Pages do
	table.insert(out.tutorial, {
		icons = page.Icons,
		title = Strings[page.Key .. ".Title"].en,
		body = Strings[page.Key .. ".Body"].en,
	})
end
out.buttons = { nextText = Strings["Tutorial.Next"].en, done = Strings["Tutorial.Done"].en }

fs.writeFile(process.args[1] or "role_icons.json", serde.encode("json", out))
