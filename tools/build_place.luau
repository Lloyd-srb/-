--[[
	Offline place builder (Lune). Usage, from the repo root:
	    lune run tools/build_place.luau

	Loads src/ into an in-memory DataModel, runs the builder scripts in build/
	and writes out/WolfVillage.rbxl. This proves that the repo alone can rebuild
	the world, and gives a place file that opens in Roblox Studio without the
	Studio MCP connection. out/ is not committed.
]]

local fs = require("@lune/fs")

local Harness = require("./lib/Harness")
local roblox = Harness.roblox

local BUILDERS = { "build/BuildVillage.luau", "build/BuildLighting.luau", "build/BuildUI.luau", "build/BuildSettings.luau", "build/BuildWolfRig.luau" }

local loaded = Harness.load("src")
for _, builder in BUILDERS do
	Harness.runBuilder(loaded, builder)
end

-- Ship the builder scripts inside the place too, so they can be run from
-- Studio's command bar without any tooling:
--     require(game.ServerStorage.Builders.BuildWolfMesh)
local builders = roblox.Instance.new("Folder")
builders.Name = "Builders"
builders.Parent = loaded.game:GetService("ServerStorage")
for _, entry in fs.readDir("build") do
	local name = entry:match("^(.+)%.luau$")
	if name then
		local source = fs.readFile("build/" .. entry)
		-- A ModuleScript must return exactly one value.
		local lastLine = source:gsub("%s+$", ""):match("([^\n]*)$") or ""
		if not lastLine:match("^return") then
			source ..= "\nreturn true\n"
		end
		local module = roblox.Instance.new("ModuleScript")
		module.Name = name
		module.Source = source
		module.Parent = builders
	end
end

if not fs.isDir("out") then
	fs.writeDir("out")
end
fs.writeFile("out/WolfVillage.rbxl", roblox.serializePlace(loaded.game))
print(`wrote out/WolfVillage.rbxl ({#loaded.scripts} scripts)`)

-- Optional: dump every part as "name,x,y,z,sx,sy,sz,lookx,lookz,r,g,b,alpha"
-- for a quick top-down layout check.
local dumpPath = "out/parts.csv"
local lines = {}
for _, instance in loaded.game:GetService("Workspace"):GetDescendants() do
	if instance:IsA("BasePart") then
		local cf, size, color = instance.CFrame, instance.Size, instance.Color
		local look, up = cf.LookVector, cf.UpVector
		local ok, transparency = pcall(function()
			return instance.Transparency
		end)
		table.insert(
			lines,
			string.format(
				"%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%.2f",
				instance.Name,
				instance.ClassName,
				cf.X, cf.Y, cf.Z,
				size.X, size.Y, size.Z,
				look.X, look.Z, up.X, up.Y,
				math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255),
				if ok then transparency else 0
			)
		)
	end
end
fs.writeFile(dumpPath, table.concat(lines, "\n"))
print(`wrote {dumpPath} ({#lines} parts)`)
