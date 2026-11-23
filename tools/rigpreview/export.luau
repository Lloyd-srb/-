--[[
	Dumps a rig built by build/BuildWolfRig.luau (rest pose) to JSON for render.py.
	Usage: lune run tools/rigpreview/export.luau <RigName> <out.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Harness = require("../lib/Harness")

local loaded = Harness.load("src")
Harness.runBuilder(loaded, "build/BuildWolfRig.luau")
local rig = loaded.game.ServerStorage.Rigs[process.args[1] or "Lurker"]
local parts = {}
for _, part in rig:GetDescendants() do
	if part:IsA("BasePart") and part.Transparency < 1 then
		local p, s, c = part.CFrame.Position, part.Size, part.Color
		table.insert(parts, {
			name = part.Name,
			x = p.X, y = p.Y, z = p.Z,
			sx = s.X, sy = s.Y, sz = s.Z,
			color = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
			neon = tostring(part.Material):find("Neon") ~= nil,
		})
	end
end
fs.writeFile(process.args[2] or "rig.json", serde.encode("json", parts))
