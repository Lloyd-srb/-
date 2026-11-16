--[[
	Harness (Lune) — loads the repo's `src/` tree into an in-memory Roblox
	DataModel so game modules and builder scripts can run without Roblox Studio.

	It mirrors the export layout used by this repo:
	  src/<Service>/<Folders...>/<Name>.luau          -> ModuleScript
	  src/<Service>/<Folders...>/<Name>.server.luau   -> Script
	  src/<Service>/<Folders...>/<Name>.client.luau   -> LocalScript

	This is offline tooling only. Roblox Studio stays the place where the game runs.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = {}

-- Engine methods the game calls at require-time that Lune does not provide.
pcall(roblox.implementMethod, "RunService", "IsStudio", function()
	return false
end)

local KNOWN_CONTAINERS = {
	StarterPlayerScripts = "StarterPlayerScripts",
	StarterCharacterScripts = "StarterCharacterScripts",
}

local function classify(fileName: string): (string?, string?)
	local name = fileName:match("^(.+)%.server%.luau$")
	if name then
		return name, "Script"
	end
	name = fileName:match("^(.+)%.client%.luau$")
	if name then
		return name, "LocalScript"
	end
	name = fileName:match("^(.+)%.luau$")
	if name then
		return name, "ModuleScript"
	end
	return nil, nil
end

local function sorted(list: { string }): { string }
	table.sort(list)
	return list
end

-- Calls visit(kind, pathParts, filePath, className) for every folder / script in src.
function Harness.walk(srcDir: string, visit: (parts: { string }, filePath: string?, className: string?) -> ())
	local function recurse(dir: string, parts: { string })
		for _, entry in sorted(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				local childParts = table.clone(parts)
				table.insert(childParts, entry)
				visit(childParts, nil, nil)
				recurse(path, childParts)
			else
				local name, className = classify(entry)
				if name and className then
					local childParts = table.clone(parts)
					table.insert(childParts, name)
					visit(childParts, path, className)
				end
			end
		end
	end
	recurse(srcDir, {})
end

export type Game = {
	game: any,
	require: (module: any) -> any,
	env: (script: any, extra: { [string]: any }?) -> { [string]: any },
	scripts: { any },
	-- Extra globals given to every module / script loaded afterwards.
	globals: { [string]: any },
}

function Harness.load(srcDir: string): Game
	local game = roblox.Instance.new("DataModel")
	local scripts = {}
	local globals: { [string]: any } = {}

	local function container(parts: { string }): any
		local current = game:GetService(parts[1])
		for i = 2, #parts do
			local child = current:FindFirstChild(parts[i])
			if not child then
				child = roblox.Instance.new(KNOWN_CONTAINERS[parts[i]] or "Folder")
				child.Name = parts[i]
				child.Parent = current
			end
			current = child
		end
		return current
	end

	Harness.walk(srcDir, function(parts, filePath, className)
		if filePath == nil or className == nil then
			container(parts)
			return
		end
		local parentParts = table.clone(parts)
		local name = table.remove(parentParts) :: string
		local instance = roblox.Instance.new(className)
		instance.Name = name
		instance.Source = fs.readFile(filePath)
		instance.Parent = container(parentParts)
		table.insert(scripts, instance)
	end)

	local cache: { [string]: { value: any } } = {}
	local requireModule
	local makeEnv

	function makeEnv(scriptInstance: any, extra: { [string]: any }?): { [string]: any }
		local env: { [string]: any } = {
			script = scriptInstance,
			game = game,
			workspace = game:GetService("Workspace"),
			require = requireModule,
			task = task,
		}
		for key, value in roblox :: any do
			-- Datatypes and Instance/Enum start with an upper-case letter.
			if type(key) == "string" and key:match("^%u") then
				env[key] = value
			end
		end
		for key, value in globals do
			env[key] = value
		end
		if extra then
			for key, value in extra do
				env[key] = value
			end
		end
		return env
	end

	function requireModule(module: any): any
		assert(typeof(module) == "Instance" and module.ClassName == "ModuleScript", "require expects a ModuleScript")
		local key = module:GetFullName()
		local cached = cache[key]
		if cached then
			return cached.value
		end
		local chunk = luau.load(module.Source, { debugName = key, environment = makeEnv(module) })
		local value = chunk()
		cache[key] = { value = value }
		return value
	end

	return { game = game, require = requireModule, env = makeEnv, scripts = scripts, globals = globals }
end

-- Runs a builder script (build/*.luau) against the loaded DataModel.
function Harness.runBuilder(loaded: Game, builderPath: string): any
	local chunk = luau.load(fs.readFile(builderPath), {
		debugName = builderPath,
		environment = loaded.env(nil),
	})
	return chunk()
end

Harness.roblox = roblox

return Harness
