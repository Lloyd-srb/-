--[[
	Offline place builder (Lune). Usage, from the repo root:
	    lune run tools/build_place.luau

	For each place (Match, Lobby; see tools/lib/Places.luau): loads its
	sources into an in-memory DataModel, runs its builder scripts and writes
	an .rbxl to out/. This proves that the repo alone can rebuild the world,
	and gives place files that open in Roblox Studio without the Studio MCP
	connection. out/ is not committed.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Harness = require("./lib/Harness")
local Places = require("./lib/Places")
local roblox = Harness.roblox

-- The builders also travel inside the place, so they can be run from
-- Studio's command bar:  require(game.ServerStorage.Builders.BuildWolfMesh)
local function shipBuilders(game: any, dirs: { string })
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Builders"
	folder.Parent = game:GetService("ServerStorage")
	for _, dir in dirs do
		for _, entry in fs.readDir(dir) do
			local name = entry:match("^(.+)%.luau$")
			if name then
				local source = fs.readFile(dir .. "/" .. entry)
				-- A ModuleScript must return exactly one value.
				local lastLine = source:gsub("%s+$", ""):match("([^\n]*)$") or ""
				if not lastLine:match("^return") then
					source ..= "\nreturn true\n"
				end
				local module = roblox.Instance.new("ModuleScript")
				module.Name = name
				module.Source = source
				module.Parent = folder
			end
		end
	end
end

if not fs.isDir("out") then
	fs.writeDir("out")
end

for _, place in Places.All do
	local loaded = Harness.load(place.Roots)
	for _, builder in place.Builders do
		Harness.runBuilder(loaded, builder)
	end
	shipBuilders(loaded.game, place.BuilderDirs)
	fs.writeFile(place.Out, roblox.serializePlace(loaded.game))
	print(`wrote {place.Out} ({#loaded.scripts} scripts)`)

	if place.Name == "Match" then
		-- The forest is made at runtime (random each match): add one example,
		-- with the Lurker's channel shown, for the top-down picture only.
		local forest = loaded.require(loaded.game.ServerScriptService.Services.ForestService)
		forest.Generate(tonumber(process.env.FOREST_SEED) or 7)
		forest.ShowMoat()
		-- A dump of every part for a quick top-down layout check (tools/wolfmesh-style renders).
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
		fs.writeFile("out/parts.csv", table.concat(lines, "\n"))
		print(`wrote out/parts.csv ({#lines} parts)`)
	end
end
