--[[
	FakeEngine (Lune) — just enough of the Roblox engine to run the real server
	scripts (ServerScriptService.Main and its services) outside Studio:
	fake players with characters, RemoteEvents, ProximityPrompts, tags, tweens.

	It does NOT simulate physics, replication, UI or the client. Its purpose is
	to catch logic and ordering mistakes in the round flow before Studio does.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = require("./Harness")

local FakeEngine = {}

-- State of the simulation that is currently running (one at a time).
local sim: any = nil

local function newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(handler)
		table.insert(handlers, handler)
		return {
			Disconnect = function()
				local index = table.find(handlers, handler)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, handler in table.clone(handlers) do
			task.spawn(handler, ...)
		end
	end
	return signal
end

-- Lune hands out a new userdata per reference, so signals are stored by a
-- stable string key instead of by instance.
local function signalFor(key: string)
	local signal = sim.signals[key]
	if not signal then
		signal = newSignal()
		sim.signals[key] = signal
	end
	return signal
end

local function promptKey(prompt: any): string
	local id = prompt:GetAttribute("SimId")
	if not id then
		sim.promptCount += 1
		id = sim.promptCount
		prompt:SetAttribute("SimId", id)
	end
	return "Prompt:" .. id
end

local function players(): { any }
	local list = {}
	for _, child in sim.game:GetService("Players"):GetChildren() do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end

local installed = false
local function install()
	if installed then
		return
	end
	installed = true

	roblox.implementMethod("RunService", "IsServer", function()
		return true
	end)
	roblox.implementMethod("Instance", "WaitForChild", function(self, name)
		return self:FindFirstChild(name)
	end)
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return os.clock()
	end)
	roblox.implementMethod("CollectionService", "GetTagged", function(_, tag)
		local found = {}
		for _, instance in sim.game:GetDescendants() do
			if instance:HasTag(tag) then
				table.insert(found, instance)
			end
		end
		return found
	end)
	roblox.implementMethod("TweenService", "Create", function(_, instance, _info, goal)
		return {
			Play = function()
				for property, value in goal do
					instance[property] = value
				end
			end,
		}
	end)
	--[[
		Raycast stand-in. There is no physics here, so "solid things" are:
		  - a wall, when a test calls server.blockSight(true) (it stands
		    `sim.wallDistance` studs from the origin, default 0);
		  - every member body (tag MemberBody) that is not excluded, as a
		    sphere of radius 2.5 around its HumanoidRootPart.
		The closest one along the ray is returned.
	]]
	local BODY_RADIUS = 2.5
	roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
		local length = direction.Magnitude
		if length < 1e-9 then
			return nil
		end
		local unit = direction.Unit
		local best = nil
		if sim.blockRays then
			local distance = math.min(sim.wallDistance or 0, length)
			best = { Instance = sim.game:GetService("Workspace"), Distance = distance, Position = origin + unit * distance }
		end
		local excluded = (params and params.FilterDescendantsInstances) or {}
		for _, body in sim.game:GetDescendants() do
			if body:HasTag("MemberBody") then
				local skip = false
				for _, exclude in excluded do
					if body == exclude or body:IsDescendantOf(exclude) then
						skip = true
						break
					end
				end
				local root = body:FindFirstChild("HumanoidRootPart")
				if not skip and root then
					local offset = root.CFrame.Position - origin
					local t = offset:Dot(unit)
					local miss = (offset - unit * t).Magnitude
					if t >= 0 and t <= length and miss <= BODY_RADIUS and (best == nil or t < best.Distance) then
						best = { Instance = root, Distance = t, Position = origin + unit * t }
					end
				end
			end
		end
		return best
	end)
	roblox.implementMethod("Model", "PivotTo", function(self, cframe)
		local root = self:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = cframe
		end
	end)

	roblox.implementProperty("Players", "PlayerAdded", function()
		return signalFor("PlayerAdded")
	end)
	roblox.implementProperty("Players", "PlayerRemoving", function()
		return signalFor("PlayerRemoving")
	end)
	roblox.implementMethod("Players", "GetPlayers", function()
		return players()
	end)
	roblox.implementMethod("Players", "GetPlayerByUserId", function(_, userId)
		for _, player in players() do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end)

	roblox.implementProperty("Player", "CharacterAdded", function(self)
		return signalFor("CharacterAdded:" .. self.UserId)
	end)
	roblox.implementMethod("Player", "GetJoinData", function()
		return {}
	end)
	roblox.implementMethod("Player", "LoadCharacterAsync", function(self)
		-- Like Roblox: the old character is removed first. A corpse has been
		-- detached by the game (Player.Character = nil, which this runtime
		-- cannot store), so it stays.
		local old = self.Character
		if old and not old:GetAttribute("Corpse") then
			old:Destroy()
		end
		local character = roblox.Instance.new("Model")
		character.Name = self.Name
		local humanoid = roblox.Instance.new("Humanoid")
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
		humanoid.Parent = character
		local root = roblox.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = roblox.CFrame.new(0, 3, 20) -- the plaza spawn
		root.Parent = character
		if not self:FindFirstChildOfClass("Backpack") then
			roblox.Instance.new("Backpack").Parent = self
		end
		local regen = roblox.Instance.new("Script")
		regen.Name = "Health"
		regen.Parent = character
		character.Parent = sim.game:GetService("Workspace")
		self.Character = character
		signalFor("CharacterAdded:" .. self.UserId):Fire(character)
	end)

	roblox.implementProperty("RemoteEvent", "OnServerEvent", function(self)
		return signalFor("Remote:" .. self.Name)
	end)
	-- Servers from earlier simulations may still be winding down: only record
	-- what the current simulation's own remotes send.
	local function isCurrent(remote): boolean
		return remote:IsDescendantOf(sim.game)
	end
	roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
		if isCurrent(self) then
			table.insert(sim.log, { Remote = self.Name, To = player.UserId, Args = { ... } })
		end
	end)
	roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
		if isCurrent(self) then
			table.insert(sim.log, { Remote = self.Name, To = "all", Args = { ... } })
		end
	end)

	roblox.implementMethod("Humanoid", "UnequipTools", function() end)

	-- TextChatService: channels keep their delivery callback on the side.
	roblox.implementProperty("TextChannel", "ShouldDeliverCallback", function(self)
		return sim.callbacks[self:GetFullName()]
	end, function(self, callback)
		sim.callbacks[self:GetFullName()] = callback
	end)
	roblox.implementMethod("TextChannel", "AddUserAsync", function(self, userId)
		local source = roblox.Instance.new("TextSource")
		source.Name = tostring(userId)
		source.UserId = userId
		source.CanSend = true
		source.Parent = self
		return source, true
	end)

	roblox.implementProperty("Humanoid", "Died", function(self)
		return signalFor("Died:" .. self:GetFullName())
	end)

	roblox.implementProperty("ProximityPrompt", "Triggered", function(self)
		return signalFor(promptKey(self))
	end)
end

local function fakeRandom()
	local object = {}
	function object:NextInteger(min, max)
		return math.random(min, max)
	end
	function object:NextNumber()
		return math.random()
	end
	return object
end

export type Options = {
	Players: { { Id: number, Name: string } },
	Debug: { [string]: any }?,
	Builders: { string }?,
}

--[[
	Builds the map, adds the players, then runs ServerScriptService.Main.
	Returns a handle to drive and inspect the running server.
]]
function FakeEngine.start(loaded: Harness.Game, options: Options)
	install()
	sim = { game = loaded.game, signals = {}, log = {}, promptCount = 0, callbacks = {} }
	local game = loaded.game

	loaded.globals.Random = { new = fakeRandom }
	loaded.globals.TweenInfo = {
		new = function(...)
			return { ... }
		end,
	}
	loaded.globals.RaycastParams = {
		new = function()
			return {}
		end,
	}
	loaded.globals.warn = function(...)
		print("[warn]", ...)
	end

	for _, builder in options.Builders or { "build/BuildVillage.luau", "build/BuildLighting.luau", "build/BuildWolfRig.luau" } do
		Harness.runBuilder(loaded, builder)
	end

	local Config = loaded.require(game.ReplicatedStorage.Shared.Config)
	Config.Debug.Enabled = true
	for key, value in options.Debug or {} do
		Config.Debug[key] = value
	end

	local server = { Config = Config, game = game, require = loaded.require }

	function server.addPlayer(id: number, name: string)
		local player = roblox.Instance.new("Player")
		player.Name = name
		player.DisplayName = name
		player.UserId = id
		player.Parent = game:GetService("Players")
		signalFor("PlayerAdded"):Fire(player)
		return player
	end

	function server.player(id: number)
		return game:GetService("Players"):GetPlayerByUserId(id)
	end

	function server.removePlayer(id: number)
		local player = server.player(id)
		signalFor("PlayerRemoving"):Fire(player)
		player.Parent = nil
	end

	-- Client -> server remote call.
	function server.fireServer(remoteName: string, playerId: number, ...)
		signalFor("Remote:" .. remoteName):Fire(server.player(playerId), ...)
	end

	-- A player finishes holding a ProximityPrompt (only if it is enabled).
	function server.trigger(prompt: any, playerId: number): boolean
		if not prompt.Enabled then
			return false
		end
		signalFor(promptKey(prompt)):Fire(server.player(playerId))
		return true
	end

	-- Everything the server sent on a remote. `to` = a UserId, "all", or nil for both.
	function server.sent(remoteName: string, to: (number | string)?): { { any } }
		local list = {}
		for _, entry in sim.log do
			if entry.Remote == remoteName and (to == nil or entry.To == to) then
				table.insert(list, entry.Args)
			end
		end
		return list
	end

	function server.last(remoteName: string, to: (number | string)?): { any }?
		local list = server.sent(remoteName, to)
		return list[#list]
	end

	function server.root(id: number)
		local character = server.player(id).Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	function server.humanoid(id: number)
		local character = server.player(id).Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	-- Polls until predicate() is truthy. Errors after `timeout` seconds.
	function server.waitFor(what: string, predicate: () -> any, timeout: number?): any
		local deadline = os.clock() + (timeout or 5)
		while os.clock() < deadline do
			local value = predicate()
			if value then
				return value
			end
			task.wait(0.005)
		end
		error("timed out waiting for " .. what, 2)
	end

	-- Walls between attacker and target (true = every line of sight is blocked).
	function server.blockSight(blocked: boolean, distance: number?)
		sim.blockRays = blocked
		sim.wallDistance = distance
	end

	local function channel(name: string)
		return game:GetService("TextChatService").WolfVillageChannels[name]
	end

	-- "Send", "Read" or nil: this user's place in a chat channel.
	function server.chatAccess(channelName: string, userId: number): string?
		for _, source in channel(channelName):GetChildren() do
			if source.ClassName == "TextSource" and source.UserId == userId then
				return if source.CanSend then "Send" else "Read"
			end
		end
		return nil
	end

	-- Would a message typed by `speakerId` in the channel reach `targetId`?
	-- (Both must be in the channel; this asks the channel's delivery rule.)
	function server.chatDelivers(channelName: string, speakerId: number, targetId: number): boolean
		if server.chatAccess(channelName, speakerId) ~= "Send" or server.chatAccess(channelName, targetId) == nil then
			return false
		end
		local callback = sim.callbacks[channel(channelName):GetFullName()]
		return callback({ TextSource = { UserId = speakerId } }, { UserId = targetId })
	end

	-- The player's Humanoid dies by itself (reset button, physics).
	function server.killHumanoid(id: number)
		local humanoid = server.humanoid(id)
		signalFor("Died:" .. humanoid:GetFullName()):Fire()
	end

	function server.phase(): string
		local last = server.last("PhaseChanged", "all")
		return if last then last[1].Phase else "None"
	end

	function server.waitForPhase(phase: string, timeout: number?)
		server.waitFor("phase " .. phase, function()
			return server.phase() == phase
		end, timeout)
	end

	for _, entry in options.Players do
		server.addPlayer(entry.Id, entry.Name)
	end

	local main = game.ServerScriptService.Main
	luau.load(main.Source, { debugName = "ServerScriptService.Main", environment = loaded.env(main) })()

	return server
end

FakeEngine.readFile = fs.readFile

return FakeEngine
