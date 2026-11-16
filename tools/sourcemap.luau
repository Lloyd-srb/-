--[[
	Writes sourcemap.json (Rojo sourcemap format) from src/ so that luau-lsp can
	resolve `require(script.Parent.X)` / `game.ReplicatedStorage...` offline.
	Usage, from the repo root:  lune run tools/sourcemap.luau
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Harness = require("./lib/Harness")

local KNOWN = {
	StarterPlayerScripts = "StarterPlayerScripts",
	StarterCharacterScripts = "StarterCharacterScripts",
}

local root = { name = "WolfVillage", className = "DataModel", children = {} }

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

Harness.walk("src", function(parts, filePath, className)
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

fs.writeFile("sourcemap.json", serde.encode("json", root, true))
print("wrote sourcemap.json")
