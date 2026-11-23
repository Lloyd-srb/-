--!strict
--[[
	MatchService — who is in the match and what happened to them.
	Owns the roster (roles, alive / dead), character setup, deaths, exile,
	players leaving and the win check. Roles are only ever sent to their owner.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Logic = script.Parent.Parent.Logic
local RoleAssignment = require(Logic.RoleAssignment)
local Roster = require(Logic.Roster)
local WinConditions = require(Logic.WinConditions)
local WolfPack = require(Logic.WolfPack)

local BotBody = require(script.Parent.BotBody)
local Net = require(script.Parent.Net)
local Travel = require(script.Parent.Travel)
local Prompts = require(script.Parent.Prompts)
local ProfileService = require(script.Parent.ProfileService)

local BOT_ID_BASE = -1000 -- Studio test clients already use small negative UserIds

local MatchService = {}

MatchService.Roster = Roster.new()
MatchService.Started = false
MatchService.Winner = nil :: string?
MatchService.LateJoiners = {} :: { [number]: boolean } -- arrived after the start (sent back)
MatchService.DeathsThisNight = 0

MatchService.MatchStarted = Signal.new() -- ()
MatchService.MemberDied = Signal.new() -- (member, cause)
MatchService.MemberConverted = Signal.new() -- (member) a villager became the wolf pup
MatchService.MemberRevived = Signal.new() -- (member)
MatchService.BodyReplaced = Signal.new() -- (member) a living member got a new body (not a revive: no healing)
MatchService.GameOver = Signal.new() -- (winner)
MatchService.SyncRequested = Signal.new() -- (player) a client asks for the current state

local rng = Rng.wrap(Random.new())
local nightsStarted = 0
local isNight = false
local botBodies: { [number]: Model } = {} -- debug bots have no Player
local corpses: { [number]: Model } = {} -- bodies of the dead (a dead player's character is their ghost)
local picks: { [number]: { Config.RoleId } } = {} -- confirmed on the role screen
local activeTonight: { [number]: boolean } = {} -- did something this night (AFK rule)

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

-- Seats in this match: the players present, plus debug bots in Studio.
function MatchService.Seats(): number
	if Config.Debug.Enabled and Config.Debug.FillWithBots then
		return math.max(#Players:GetPlayers(), Config.Debug.FillTo or Config.Match.MaxPlayers)
	end
	return #Players:GetPlayers()
end

function MatchService.PlayerCount(): number
	return #Players:GetPlayers()
end

function MatchService.RequiredPlayers(): number
	if Config.Debug.Enabled then
		return Config.Debug.MinPlayers
	end
	return Config.Match.MinPlayers
end

function MatchService.MemberOf(player: Player): Roster.Member?
	return MatchService.Roster.Members[player.UserId]
end

function MatchService.PlayerOf(id: number): Player?
	return Players:GetPlayerByUserId(id)
end

function MatchService.IsAlive(player: Player): boolean
	local member = MatchService.MemberOf(player)
	return member ~= nil and member.Alive
end

function MatchService.IsNight(): boolean
	return isNight
end

-- The member did something (walked, pressed a prompt or button, chatted).
function MatchService.MarkActive(id: number)
	activeTonight[id] = true
end

function MatchService.WasActiveTonight(id: number): boolean
	return activeTonight[id] == true
end

-- The member's body, alive or dead (a corpse stays in the world).
function MatchService.BodyOf(id: number): Model?
	local body: Model? = corpses[id] or botBodies[id]
	if not body then
		local player = MatchService.PlayerOf(id)
		body = if player then player.Character else nil
	end
	if body and body.Parent ~= nil then
		return body
	end
	return nil
end

-- The body a death left behind (set by CombatService before the ragdoll).
function MatchService.MarkCorpse(id: number, body: Model)
	corpses[id] = body
end

-- The member's living, controllable character (nil once removed, a corpse or a ghost).
function MatchService.CharacterOf(id: number): Model?
	local member = MatchService.Roster.Members[id]
	if member and not member.Alive then
		return nil
	end
	local body = MatchService.BodyOf(id)
	if body and not body:GetAttribute("Corpse") then
		return body
	end
	return nil
end

function MatchService.RootOf(id: number): BasePart?
	local character = MatchService.CharacterOf(id)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function MatchService.HumanoidOf(id: number): Humanoid?
	local character = MatchService.CharacterOf(id)
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

--------------------------------------------------------------------------------
-- Replication (public data only: never roles)
--------------------------------------------------------------------------------

local function publicRoster(): { any }
	local list = {}
	for _, member in Roster.list(MatchService.Roster) do
		table.insert(list, {
			Id = member.Id,
			Name = member.Name,
			Alive = member.Alive,
			IsBot = member.IsBot,
		})
	end
	return list
end

local function broadcastRoster()
	Net.fireAll("RosterChanged", publicRoster())
end

local function sendRole(player: Player)
	local member = MatchService.MemberOf(player)
	if member then
		Net.fire(player, "RoleAssigned", if member.IsPup then "Pup" else member.Role)
	end
end

-- Tells every wolf-side player who their pack is. Nobody else receives this.
function MatchService.SendPack()
	local ids: { number } = {}
	local packPlayers: { Player } = {}
	for _, member in Roster.alive(MatchService.Roster) do
		if Roster.isWolfSide(member) then
			table.insert(ids, member.Id)
			local player = MatchService.PlayerOf(member.Id)
			if player then
				table.insert(packPlayers, player)
			end
		end
	end
	for _, player in packPlayers do
		Net.fire(player, "PackChanged", ids)
	end
end

-- Lets clients find a member's body (for highlights). UserIds are not secret.
local function markBody(body: Model, id: number)
	body:SetAttribute("MemberId", id)
	body:AddTag("MemberBody")
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------

-- Characters share one collision group so a dashing Bodyguard can pass
-- through people (GDD §9).
MatchService.CharacterGroup = "Characters"
MatchService.DashGroup = "Dash"
MatchService.GhostGroup = "Ghosts"

function MatchService.SetCollisionGroup(body: Model, group: string)
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local respawnInPlace: (player: Player, character: Model) -> ()

local function setupCharacter(player: Player, character: Model)
	-- Ghost bodies are set up by GhostService.
	local member = MatchService.MemberOf(player)
	if MatchService.Started and member and not member.Alive then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Config.Human.WalkSpeed
		humanoid.MaxHealth = Config.Human.MaxHealth
		humanoid.Health = Config.Human.MaxHealth
		humanoid.BreakJointsOnDeath = false
		-- Names must not show through walls: they would give away who is in
		-- which house at night.
		humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
		-- No health bar over heads: a hurt villager would tell everyone the
		-- pup bit them last night. Each player still sees their own health.
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.Died:Connect(function()
			respawnInPlace(player, character)
		end)
	end
	-- No passive healing: a pup must always need exactly 2 hits (GDD §8.2).
	local regen = character:WaitForChild("Health", 5)
	if regen then
		regen:Destroy()
	end
	MatchService.SetCollisionGroup(character, MatchService.CharacterGroup)
end

local expected: number? = nil -- how many the lobby sent (TeleportData)

local function readJoinData(player: Player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local data = if ok and type(joinData) == "table" then joinData.TeleportData else nil
	if type(data) == "table" and type((data :: any).Expected) == "number" then
		local count = math.clamp(math.floor((data :: any).Expected), 1, Config.Match.MaxPlayers)
		expected = math.max(expected or 0, count)
	end
end

--[[
	Waits until the match can begin. Returns false when it cannot (fewer than
	Config.Match.MinPlayers arrived): the caller sends everyone back.
	  Studio: waits for Config.Debug.MinPlayers (no teleports there).
	  Live:   waits for everyone the lobby sent, or Config.Match.ArrivalTimeout
	          seconds after the first arrival, whichever comes first.
	`report(count, needed)` is called while waiting.
]]
function MatchService.WaitForPlayers(report: (count: number, needed: number) -> ()): boolean
	if Config.Debug.Enabled then
		while MatchService.PlayerCount() < MatchService.RequiredPlayers() do
			report(MatchService.PlayerCount(), MatchService.RequiredPlayers())
			task.wait(1)
		end
		return true
	end
	while MatchService.PlayerCount() == 0 do
		task.wait(0.25)
	end
	local deadline = os.clock() + Config.Match.ArrivalTimeout
	while os.clock() < deadline do
		local target = expected or Config.Match.MaxPlayers
		if MatchService.PlayerCount() >= target then
			break
		end
		report(MatchService.PlayerCount(), target)
		task.wait(0.25)
	end
	return MatchService.PlayerCount() >= Config.Match.MinPlayers
end

local function onPlayerAdded(player: Player)
	if not MatchService.Started then
		readJoinData(player)
	end
	player.CharacterAdded:Connect(function(character: Model)
		setupCharacter(player, character)
	end)
	if not MatchService.Started then
		player:LoadCharacterAsync()
		return
	end
	-- [owner] 18 Nov 2026: nobody joins a match that has started. The lobby
	-- only sends players into reserved servers before the start, so this is
	-- just a guard: whoever still arrives goes back to the lobby.
	MatchService.LateJoiners[player.UserId] = true
	if not Travel.toLobby({ player }) and not RunService:IsStudio() and Config.Places.LobbyPlaceId ~= 0 then
		player:Kick(Loc.format("Match.AlreadyStarted"))
	end
end

--------------------------------------------------------------------------------
-- Winning
--------------------------------------------------------------------------------

local function finish(winner: string)
	if MatchService.Winner then
		return
	end
	MatchService.Winner = winner
	MatchService.GameOver:Fire(winner)
	Net.fireAll("GameOver", { Winner = winner, EndingKey = "Ending." .. winner })
end

-- A win that is not about who is alive (the Fire Maniac's oil, owner 18 Nov 2026).
function MatchService.DeclareWinner(winner: string)
	if MatchService.Started then
		finish(winner)
	end
end

function MatchService.CheckWin()
	if MatchService.Winner or not MatchService.Started then
		return
	end
	local winner = WinConditions.evaluate(Roster.snapshot(MatchService.Roster))
	if winner then
		finish(winner)
	end
end

--------------------------------------------------------------------------------
-- Deaths
--------------------------------------------------------------------------------

-- Records a death. Does not decide what happens to the body (callers do).
function MatchService.Kill(id: number, cause: Roster.DeathCause, killerId: number?): boolean
	if not Roster.recordDeath(MatchService.Roster, id, cause, nightsStarted, killerId) then
		return false
	end
	if isNight then
		MatchService.DeathsThisNight += 1
	end
	MatchService.Roster.Members[id].DiedAtNight = isNight
	MatchService.MemberDied:Fire(MatchService.Roster.Members[id], cause)
	broadcastRoster()
	return true
end

-- Voted out: dies without the role being revealed (GDD §6.2).
function MatchService.Exile(id: number)
	local member = MatchService.Roster.Members[id]
	if not member or not member.Alive then
		return
	end
	local exiledRole = if member.IsPup then "Pup" else member.Role
	local character = MatchService.CharacterOf(id) -- taken before the death is recorded
	MatchService.Kill(id, "Exile")

	-- The exiled leave no body: they come back as a ghost (GhostService).
	if character then
		character:Destroy()
	end

	local winner = WinConditions.onExile(exiledRole)
	if winner then
		finish(winner)
	else
		MatchService.CheckWin()
	end
end

-- The wolf's first night victim joins the wolf side instead of dying (GDD §8.2).
function MatchService.ConvertToPup(id: number, wolfId: number?): boolean
	if not Roster.convertToPup(MatchService.Roster, id, wolfId) then
		return false
	end
	local member = MatchService.Roster.Members[id]
	local player = MatchService.PlayerOf(id)
	if player then
		sendRole(player)
	end
	MatchService.MemberConverted:Fire(member)
	MatchService.SendPack()
	MatchService.CheckWin()
	return true
end

--[[
	Deaths only happen through MatchService.Kill. If a living player's Humanoid
	dies anyway (reset button, a physics glitch), they would be stuck "alive"
	with no body, because characters never auto-respawn. Give them a fresh
	body where the old one was.
]]
function respawnInPlace(player: Player, character: Model)
	local member = MatchService.MemberOf(player)
	if not MatchService.Started or not member or not member.Alive or character:GetAttribute("Corpse") then
		return
	end
	if player.Character ~= character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local where = if root and root:IsA("BasePart") then root.CFrame else nil
	player:LoadCharacterAsync()
	local fresh = player.Character
	if fresh and where then
		fresh:PivotTo(where + Vector3.new(0, 2, 0))
		markBody(fresh, member.Id)
	end
	MatchService.BodyReplaced:Fire(member)
end

--[[
	The Doctor's revive (GDD §9): the corpse is replaced by a living body at
	`where`. Yields while a player's character loads.
]]
function MatchService.Revive(id: number, where: CFrame): boolean
	local member = MatchService.Roster.Members[id]
	if not member or MatchService.Winner or not Roster.revive(MatchService.Roster, id) then
		return false
	end
	local corpse = corpses[id] or MatchService.BodyOf(id)
	corpses[id] = nil
	if corpse and not corpse:HasTag("Ghost") then
		corpse:Destroy()
	end
	if member.IsBot then
		local body = BotBody.create(member.Name, 0, 1, where.Position)
		markBody(body, id)
		botBodies[id] = body
	else
		local player = MatchService.PlayerOf(id)
		if player then
			player:LoadCharacterAsync()
			local character = player.Character
			if character then
				character:PivotTo(where)
				markBody(character, id)
			end
		end
	end
	MatchService.MemberRevived:Fire(member)
	broadcastRoster()
	return true
end

local function onPlayerRemoving(player: Player)
	local member = MatchService.MemberOf(player)
	if not MatchService.Started or not member or not member.Alive or MatchService.Winner then
		return
	end
	local wasMainWolf = member.Faction == "Wolf" and not member.IsPup
	MatchService.Kill(member.Id, "Left")
	if wasMainWolf then
		local winner = WinConditions.onWolfLeft(Roster.pup(MatchService.Roster) ~= nil)
		if winner then
			finish(winner)
			return
		end
	end
	MatchService.CheckWin()
end

--------------------------------------------------------------------------------
-- Role picks (validated by RoleSelectService)
--------------------------------------------------------------------------------

function MatchService.SetPicks(userId: number, chosen: { Config.RoleId })
	picks[userId] = chosen
end

function MatchService.PicksOf(userId: number): { Config.RoleId }?
	return picks[userId]
end

function MatchService.AllPicked(): boolean
	for _, player in Players:GetPlayers() do
		if not picks[player.UserId] then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Round hooks (called by RoundService)
--------------------------------------------------------------------------------

-- Builds the roster from the players in the server and hands out roles.
function MatchService.BeginMatch()
	local roster = MatchService.Roster
	local seats = MatchService.Seats()
	local starterRoles = RoleAssignment.usableRoles({}, Config.PlayerLevel.StartLevel)
	local candidates: { RoleAssignment.Candidate } = {}

	-- Players who did not confirm in time get random picks from what they own.
	local function join(id: number, name: string, isBot: boolean, usable: { [Config.RoleId]: boolean })
		Roster.add(roster, id, name, isBot)
		table.insert(candidates, {
			Id = id,
			Picks = picks[id] or RoleAssignment.defaultPicks(usable, rng),
			Usable = usable,
		})
	end

	local firstPlayerId: number? = nil
	for _, player in Players:GetPlayers() do
		firstPlayerId = firstPlayerId or player.UserId
		join(player.UserId, player.DisplayName, false, ProfileService.UsableRoles(player))
		if player.Character then
			markBody(player.Character, player.UserId)
		end
	end
	if Config.Debug.Enabled and Config.Debug.FillWithBots then
		for seat = #candidates + 1, seats do
			local id = BOT_ID_BASE - seat
			join(id, "Bot " .. seat, true, starterRoles)
			if Config.Debug.BotBodies then
				local body = BotBody.create("Bot " .. seat, seat, seats)
				markBody(body, id)
				botBodies[id] = body
			end
		end
	end

	local forced: { [number]: Config.RoleId }? = nil
	if Config.Debug.Enabled then
		local map: { [number]: Config.RoleId } = {}
		if Config.Debug.ForceRoles then
			for id, roleId in Config.Debug.ForceRoles do
				map[id] = roleId
			end
		end
		local targetId = Config.Debug.ForceRoleUserId or firstPlayerId
		if Config.Debug.ForceRole and targetId then
			map[targetId] = Config.Debug.ForceRole
		end
		if next(map) ~= nil then
			forced = map
		end
	end

	-- The roles follow the number of people actually in the match (8-12).
	local composition = RoleAssignment.composition(#candidates)
	Roster.setRoles(roster, RoleAssignment.assign(candidates, composition, rng, forced))
	-- The wolf plays the monster picked in the Lobby (owner, 19 Nov 2026).
	for _, member in Roster.list(roster) do
		local player = MatchService.PlayerOf(member.Id)
		local forcedMonster = if Config.Debug.Enabled then Config.Debug.ForceMonster else nil
		member.Monster = forcedMonster or (if player then ProfileService.Monster(player) else "Werewolf")
	end
	MatchService.Started = true

	for _, player in Players:GetPlayers() do
		sendRole(player)
	end
	broadcastRoster()
	MatchService.MatchStarted:Fire()
end

-- Returns the pup that just grew into the wolf, if that happens tonight.
function MatchService.BeginNight(night: number): Roster.Member?
	nightsStarted = night
	isNight = true
	MatchService.DeathsThisNight = 0
	table.clear(activeTonight)
	if WolfPack.shouldPromote(night, MatchService.Roster.MainWolfLostAtNight) then
		local promoted = Roster.promotePup(MatchService.Roster)
		if promoted then
			local player = MatchService.PlayerOf(promoted.Id)
			if player then
				sendRole(player)
			end
			MatchService.SendPack()
		end
		return promoted
	end
	return nil
end

function MatchService.EndNight()
	isNight = false
	-- A night spent doing nothing at all is not a night survived (owner, 17 Nov 2026).
	Roster.creditNightSurvived(MatchService.Roster, if Config.Afk.Enabled
		then function(member: Roster.Member): boolean
			return member.IsBot or activeTonight[member.Id] == true
		end
		else nil)
end

--------------------------------------------------------------------------------

function MatchService.Init()
	Players.CharacterAutoLoads = false -- the match decides who has a body
	-- pcall: the groups already exist when the server script restarts in Studio.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(MatchService.CharacterGroup)
		PhysicsService:RegisterCollisionGroup(MatchService.DashGroup)
		PhysicsService:RegisterCollisionGroup(MatchService.GhostGroup)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(MatchService.DashGroup, MatchService.CharacterGroup, false)
		-- Ghosts walk on the map but never push (or block) anyone, nor each other.
		for _, group in { MatchService.CharacterGroup, MatchService.DashGroup, MatchService.GhostGroup } do
			PhysicsService:CollisionGroupSetCollidable(MatchService.GhostGroup, group, false)
		end
	end)
end

function MatchService.Start()
	Net.onActivity(function(player: Player)
		MatchService.MarkActive(player.UserId)
	end)
	Prompts.onTriggered(function(player: Player)
		MatchService.MarkActive(player.UserId)
	end)

	Net.on("RequestSync", function(player: Player)
		if MatchService.Started then
			sendRole(player)
			local member = MatchService.MemberOf(player)
			if member and member.Alive and Roster.isWolfSide(member) then
				MatchService.SendPack()
			end
			Net.fire(player, "RosterChanged", publicRoster())
			if MatchService.Winner then
				Net.fire(player, "GameOver", {
					Winner = MatchService.Winner,
					EndingKey = "Ending." .. MatchService.Winner,
				})
			end
		end
		MatchService.SyncRequested:Fire(player)
	end, 4, 10)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MatchService
