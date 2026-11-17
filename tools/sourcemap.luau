--[[
	Writes a Rojo-style sourcemap per place (sourcemap.json for the Match
	place, sourcemap.lobby.json for the Lobby) so that luau-lsp can resolve
	`require(script.Parent.X)` / `game.ReplicatedStorage...` offline.
	Usage, from the repo root:  lune run tools/sourcemap.luau
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Harness = require("./lib/Harness")
local Places = require("./lib/Places")

local KNOWN = {
	StarterPlayerScripts = "StarterPlayerScripts",
	StarterCharacterScripts = "StarterCharacterScripts",
}

local function child(node, name: string, className: string)
	for _, existing in node.children do
		if existing.name == name then
			return existing
		end
	end
	local created = { name = name, className = className, children = {} }
	table.insert(node.children, created)
	return created
end

for _, place in Places.All do
	local root = { name = "WolfVillage" .. place.Name, className = "DataModel", children = {} }
	for _, sourceRoot in place.Roots do
		Harness.walk(sourceRoot.Dir, function(relative, filePath, className)
			local parts = table.clone(sourceRoot.Prefix or {})
			for _, part in relative do
				table.insert(parts, part)
			end
			local node = root
			for index, part in parts do
				local isLeaf = index == #parts
				if isLeaf and filePath then
					local leaf = child(node, part, className :: string)
					leaf.filePaths = { filePath }
				elseif index == 1 then
					node = child(node, part, part) -- service: class name == name
				else
					node = child(node, part, KNOWN[part] or "Folder")
				end
			end
		end)
	end
	fs.writeFile(place.Sourcemap, serde.encode("json", root, true))
	print("wrote " .. place.Sourcemap)
end
