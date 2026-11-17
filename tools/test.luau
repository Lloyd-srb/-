--[[
	Offline test runner (Lune). Usage, from the repo root:
	    lune run tools/test.luau

	Loads src/ into an in-memory DataModel and runs every tests/*.spec.luau.
	Spec files get: game, workspace, require, test(name, fn), expect(value),
	runBuilder(path), startServer(options).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local FakeEngine = require("./lib/FakeEngine")
local Harness = require("./lib/Harness")
local Places = require("./lib/Places")

local passed, failed = 0, 0
local failures: { string } = {}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	for key, item in value do
		table.insert(parts, tostring(key) .. "=" .. show(item))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function expect(actual: any)
	local matchers = {}
	function matchers.toBe(expected: any)
		if actual ~= expected then
			error(`expected {show(expected)}, got {show(actual)}`, 2)
		end
	end
	function matchers.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected {show(expected)}, got {show(actual)}`, 2)
		end
	end
	function matchers.toBeNil()
		if actual ~= nil then
			error(`expected nil, got {show(actual)}`, 2)
		end
	end
	function matchers.toBeTruthy()
		if not actual then
			error(`expected a truthy value, got {show(actual)}`, 2)
		end
	end
	function matchers.toBeNear(expected: number, tolerance: number)
		if math.abs(actual - expected) > tolerance then
			error(`expected {expected} ± {tolerance}, got {show(actual)}`, 2)
		end
	end
	return matchers
end

local specs = {}
for _, entry in fs.readDir("tests") do
	if entry:match("%.spec%.luau$") then
		table.insert(specs, entry)
	end
end
table.sort(specs)

for _, spec in specs do
	-- A fresh DataModel per spec file so module state never leaks between files.
	local loaded = Harness.load("src")
	local function test(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, `{spec} > {name}\n      {tostring(err)}`)
		end
	end

	local chunk = luau.load(fs.readFile("tests/" .. spec), {
		debugName = spec,
		environment = loaded.env(nil, {
			test = test,
			expect = expect,
			runBuilder = function(path: string)
				return Harness.runBuilder(loaded, path)
			end,
			-- Runs the real server scripts on a fake engine (see FakeEngine).
			-- Every call gets its own DataModel, so one spec can run several matches.
			startServer = function(options)
				return FakeEngine.start(Harness.load("src"), options)
			end,
			-- Runs a builder against another loaded place (e.g. the lobby).
			runBuilderIn = function(other, path: string)
				return Harness.runBuilder(other, path)
			end,
			-- The Lobby place's sources (for its pure rules).
			loadLobby = function()
				return Harness.load(Places.Lobby.Roots)
			end,
			-- The Lobby place's server on its own fake engine.
			startLobby = function(options)
				options.Builders = options.Builders or { "build/lobby/BuildLobby.luau" }
				options.AutoLoadCharacters = true
				return FakeEngine.start(Harness.load(Places.Lobby.Roots), options)
			end,
			task = require("@lune/task"),
			readJson = function(path: string)
				return require("@lune/serde").decode("json", fs.readFile(path))
			end,
		}),
	})
	local ok, err = pcall(chunk)
	if not ok then
		failed += 1
		table.insert(failures, `{spec} (failed to load)\n      {tostring(err)}`)
	end
end

for _, failure in failures do
	print("FAIL  " .. failure)
end
print(`\n{passed} passed, {failed} failed ({#specs} spec files)`)
-- Always exit explicitly: simulated matches may still have timers running.
process.exit(if failed > 0 then 1 else 0)
