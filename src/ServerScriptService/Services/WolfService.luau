--!strict
--[[
	WolfService — the wolf side at night (GDD §6.3, §6.4, §8).

	- Transformation: a werewolf rig is welded over the player's character and
	  the human body is hidden; reverted in the morning.
	- Attack: the client only says "I swing". The server picks the target
	  (range, facing, line of sight, cooldown) or damages the door in front.
	- Wolf: sniff (outline everyone outdoors) and four-legged sprint; a kill
	  while sprinting locks the wolf in a ~3 s maul.
	- Pup: half damage and a howl that outlines nearby players for the pack.
	- Players in the forest are outlined in red for the wolf side only, for
	  the first Config.Wolf.ForestRevealSeconds of each night (owner, 23 Nov 2026).
	- The Lurker (owner, 19 / 23 Nov 2026), the monster a player can pick
	  instead of the werewolf: its own stats, no pup, a water bolt (shares the
	  attack cooldown) and invisibility (ends when it attacks, spits or goes
	  into the water). In its matches a water channel winds round the
	  village: it swims there faster, sunk to its head and back fins and
	  silent; people wade through slowly.
	- Nobody's name shows over their head at night (owner, 19 Nov 2026).

	Outlines are never created here: the server tells the allowed viewers which
	ids to highlight, and their clients draw them locally.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Signal = require(ReplicatedStorage.Shared.Signal)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Roster = require(script.Parent.Parent.Logic.Roster)

local CombatService = require(script.Parent.CombatService)
local ForestService = require(script.Parent.ForestService)
local Sight = require(script.Parent.Sight)
local HidingService = require(script.Parent.HidingService)
local HouseService = require(script.Parent.HouseService)
local AudioService = require(script.Parent.AudioService)
local MatchService = require(script.Parent.MatchService)
local Melee = require(script.Parent.Melee)
local MoveService = require(script.Parent.MoveService)
local ProfileService = require(script.Parent.ProfileService)
local Net = require(script.Parent.Net)
local RoundService = require(script.Parent.RoundService)

type WolfState = {
	Form: string, -- "Wolf" | "Pup" | "Lurker"
	Vanished: boolean, -- The Lurker is invisible
	Submerged: boolean, -- The Lurker is swimming in the channel
	Shell: Model?,
	LastAttack: number,
	SprintUntil: number,
	MaulUntil: number,
	ReadyAt: { [string]: number }, -- ability -> os.clock() when usable again
}

local WolfService = {}

WolfService.FormChanged = Signal.new() -- (memberId, form) "Wolf" | "Pup" | "Human"

local wolves: { [number]: WolfState } = {}
local setVanished: (id: number, wolf: WolfState, vanished: boolean) -> ()
local forestIds: { number } = {}
local forestLoopToken = 0
local baitIds: { number } = {}
local baitSpots: { Vector3 } = {}

-- Set by InventoryService: fish lying on the ground (they look like people
-- to the wolf side at night; owner, 18 Nov 2026).
WolfService.Baits = function(): { { Id: number, Position: Vector3 } }
	return {}
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function WolfService.IsTransformed(id: number): boolean
	return wolves[id] ~= nil
end

-- A mauling wolf cannot be stunned (GDD §8.1).
function WolfService.IsMauling(id: number): boolean
	local wolf = wolves[id]
	return wolf ~= nil and os.clock() < wolf.MaulUntil
end

local function wolfSidePlayers(): { Player }
	local list = {}
	for _, member in Roster.alive(MatchService.Roster) do
		if Roster.isWolfSide(member) then
			local player = MatchService.PlayerOf(member.Id)
			if player then
				table.insert(list, player)
			end
		end
	end
	return list
end

-- Living non-wolf members that have a body in the world and are not hidden.
local function prey(): { Roster.Member }
	local list = {}
	for _, member in Roster.alive(MatchService.Roster) do
		if not Roster.isWolfSide(member) and not HidingService.IsHidden(member.Id) and MatchService.RootOf(member.Id) then
			table.insert(list, member)
		end
	end
	return list
end

-- Numbers for a form: the werewolf / pup from Config, The Lurker from its stat bars.
type Stats = { WalkSpeed: number, AttackDamage: number, AttackCooldown: number, AttackRange: number, DoorDamage: number }
local function statsOf(form: string): Stats
	if form == "Pup" then
		return Config.Pup :: any
	elseif form == "Lurker" then
		return {
			WalkSpeed = Config.monsterStat("Lurker", "RunSpeed"),
			AttackDamage = Config.monsterStat("Lurker", "AttackPower"),
			AttackCooldown = Config.monsterStat("Lurker", "AttackSpeed"),
			AttackRange = Config.Wolf.AttackRange,
			DoorDamage = Config.Lurker.DoorDamage,
		}
	end
	return Config.Wolf :: any
end

--------------------------------------------------------------------------------
-- Transformation
--------------------------------------------------------------------------------

local function setAnimation(wolf: WolfState, name: string)
	if wolf.Shell then
		wolf.Shell:SetAttribute("Anim", name)
		wolf.Shell:SetAttribute("AnimAt", workspace:GetServerTimeNow())
	end
end

local function setBodyHidden(character: Model, shell: Model?, hidden: boolean)
	for _, instance in character:GetDescendants() do
		if shell and instance:IsDescendantOf(shell) then
			continue
		end
		if instance:IsA("BasePart") or instance:IsA("Decal") then
			local visual = instance :: any -- both classes have Transparency
			if hidden then
				if instance:GetAttribute("HumanTransparency") == nil then
					instance:SetAttribute("HumanTransparency", visual.Transparency)
				end
				visual.Transparency = 1
			else
				local original = instance:GetAttribute("HumanTransparency")
				if type(original) == "number" then
					visual.Transparency = original
					instance:SetAttribute("HumanTransparency", nil)
				end
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- No name tag over a werewolf (and nobody's at night).
		humanoid.DisplayDistanceType = if hidden or RoundService.IsNight()
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

-- Night: no name over anyone's head (owner, 19 Nov 2026). Restored at dawn.
local function hideNightName(body: Instance)
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
		humanoid:SetAttribute("NightName", true)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function setNightNames(night: boolean)
	for _, body in CollectionService:GetTagged("MemberBody") do
		if night then
			hideNightName(body)
		else
			local humanoid = body:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid:GetAttribute("NightName") then
				humanoid:SetAttribute("NightName", nil)
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			end
		end
	end
end

local function attachShell(character: Model, form: string): Model?
	local rigs = ServerStorage:FindFirstChild("Rigs")
	local template = rigs and rigs:FindFirstChild(form)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (template and template:IsA("Model")) or not (root and root:IsA("BasePart")) then
		warn("[WolfService] werewolf rig missing: run build/BuildWolfRig.luau in Studio")
		return nil
	end
	local shell = template:Clone()
	shell.Name = "WolfShell"
	local shellRoot = shell.PrimaryPart
	if shellRoot then
		shell:PivotTo(root.CFrame)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = shellRoot
		weld.Parent = shellRoot
	end
	shell:AddTag("WolfShell")
	shell.Parent = character
	return shell
end

-- Recolours the costume with the player's equipped wolf skin (cosmetic only).
local function paintShell(shell: Model, player: Player?)
	local skinId = ProfileService.Skin(player, "Wolf")
	local skin = if skinId then Config.Skins[skinId] else nil
	local paint = if skin then skin.Paint else nil
	if not paint then
		return
	end
	for _, part in shell:GetDescendants() do
		local key = part:GetAttribute("Paint")
		if part:IsA("BasePart") and type(key) == "string" and paint[key] then
			part.Color = paint[key]
		end
	end
end

local function transform(member: Roster.Member)
	local character = MatchService.CharacterOf(member.Id)
	if wolves[member.Id] or not character then
		return
	end
	local form = if member.IsPup then "Pup" elseif member.Monster == "Lurker" then "Lurker" else "Wolf"
	-- Paws cannot hold items: put away whatever was in hand.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	-- A flashlight left on would shine out of the werewolf and give away who
	-- carried it by day.
	for _, light in character:GetDescendants() do
		if light:IsA("SpotLight") and light.Name == "Flashlight" then
			light.Enabled = false
		end
	end
	character:SetAttribute("FlashlightOn", nil)
	local shell = attachShell(character, form)
	if shell and form ~= "Lurker" then -- the wolf skins are for the werewolf
		paintShell(shell, MatchService.PlayerOf(member.Id))
	end
	setBodyHidden(character, shell, true)
	character:SetAttribute("Form", form)
	wolves[member.Id] = {
		Form = form,
		Vanished = false,
		Submerged = false,
		Shell = shell,
		LastAttack = 0,
		SprintUntil = 0,
		MaulUntil = 0,
		ReadyAt = {},
	}
	MoveService.ClearModifier(member.Id, "Boots") -- boots are for human feet
	MoveService.SetBase(member.Id, statsOf(form).WalkSpeed)
	local player = MatchService.PlayerOf(member.Id)
	if player then
		Net.fire(player, "FormChanged", form)
	end
	WolfService.FormChanged:Fire(member.Id, form)
end

local function revert(id: number)
	local wolf = wolves[id]
	if not wolf then
		return
	end
	wolves[id] = nil
	local member = MatchService.Roster.Members[id]
	local character = MatchService.BodyOf(id)
	-- A dead wolf's body stays a wolf: turning back into a person in the
	-- morning would tell everyone who the wolf was.
	if member and not member.Alive then
		character = nil
	end
	if character then
		if wolf.Shell then
			wolf.Shell:Destroy()
		end
		setBodyHidden(character, nil, false)
		character:SetAttribute("Form", "Human")
	end
	MoveService.ClearModifier(id, "Sprint")
	MoveService.ClearModifier(id, "Maul")
	MoveService.ClearModifier(id, "Swim")
	if character then
		character:SetAttribute("Vanished", nil)
	end
	MoveService.SetBase(id, Config.Human.WalkSpeed)
	if member and member.Alive and member.HasBoots then
		MoveService.SetModifier(id, "Boots", { Add = Config.Boots.SpeedBonus })
	end
	local player = MatchService.PlayerOf(id)
	if player then
		Net.fire(player, "FormChanged", "Human")
	end
	WolfService.FormChanged:Fire(id, "Human")
end

--------------------------------------------------------------------------------
-- Highlights (sent to allowed viewers only)
--------------------------------------------------------------------------------

local function sendHighlight(viewers: { Player }, kind: string, ids: { number }, duration: number?)
	for _, viewer in viewers do
		Net.fire(viewer, "Highlight", { Kind = kind, Ids = ids, Duration = duration })
	end
end

local function sameIds(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for index, id in a do
		if b[index] ~= id then
			return false
		end
	end
	return true
end

local function sendBaits(viewers: { Player })
	for _, viewer in viewers do
		Net.fire(viewer, "Highlight", { Kind = "Bait", Ids = baitIds, Spots = baitSpots })
	end
end

-- Fish baits: a red glow shaped like a person, for the wolf side only.
local function scanBaits()
	local ids: { number } = {}
	local spots: { Vector3 } = {}
	for _, bait in WolfService.Baits() do
		table.insert(ids, bait.Id)
		table.insert(spots, bait.Position)
	end
	if not sameIds(ids, baitIds) then
		baitIds, baitSpots = ids, spots
		sendBaits(wolfSidePlayers())
	end
end

-- GDD §6.4: at night, players in the forest glow red for the wolf side.
local function scanForest()
	local ids: { number } = {}
	for _, member in prey() do
		local root = MatchService.RootOf(member.Id)
		if root and Zones.isForest(root.CFrame.Position) then
			table.insert(ids, member.Id)
		end
	end
	table.sort(ids)
	if not sameIds(ids, forestIds) then
		forestIds = ids
		sendHighlight(wolfSidePlayers(), "Forest", ids, nil)
	end
	scanBaits()
end

local stopForestLoop: () -> ()

local function startForestLoop()
	forestLoopToken += 1
	local token = forestLoopToken
	forestIds = {}
	local started = os.clock()
	local window = Config.Wolf.ForestRevealSeconds * (if Config.Debug.Enabled then Config.Debug.TimerScale else 1)
	task.spawn(function()
		while token == forestLoopToken and RoundService.IsNight() and not MatchService.Winner do
			if os.clock() - started < window then
				scanForest()
			else
				-- People in the forest glow only in the first moments of the
				-- night (owner, 23 Nov 2026); fish baits glow all night (owner,
				-- 23 Nov 2026: on purpose).
				if #forestIds > 0 then
					forestIds = {}
					sendHighlight(wolfSidePlayers(), "Forest", {}, nil)
				end
				scanBaits()
			end
			task.wait(Config.Wolf.ForestScanInterval)
		end
	end)
end

function stopForestLoop()
	forestLoopToken += 1
	forestIds = {}
	sendHighlight(wolfSidePlayers(), "Forest", {}, nil)
	baitIds, baitSpots = {}, {}
	sendBaits(wolfSidePlayers())
end

--------------------------------------------------------------------------------
-- Attack
--------------------------------------------------------------------------------

-- The Lurker's invisibility: the costume (and its shadow) disappears.
function setVanished(id: number, wolf: WolfState, vanished: boolean)
	if wolf.Vanished == vanished then
		return
	end
	wolf.Vanished = vanished
	local shell = wolf.Shell
	if shell then
		for _, part in shell:GetDescendants() do
			if part:IsA("BasePart") then
				if vanished then
					part:SetAttribute("ShellTransparency", part.Transparency)
					part:SetAttribute("ShellShadow", part.CastShadow)
					part.Transparency = 1
					part.CastShadow = false
				else
					local transparency = part:GetAttribute("ShellTransparency")
					local shadow = part:GetAttribute("ShellShadow")
					part.Transparency = if type(transparency) == "number" then transparency else 0
					part.CastShadow = shadow ~= false
					part:SetAttribute("ShellTransparency", nil)
					part:SetAttribute("ShellShadow", nil)
				end
			end
		end
	end
	local character = MatchService.CharacterOf(id) or MatchService.BodyOf(id)
	if character then
		character:SetAttribute("Vanished", if vanished then true else nil)
	end
end

local function startMaul(id: number, wolf: WolfState)
	local duration = Config.Wolf.Sprint.MaulDuration
	wolf.MaulUntil = os.clock() + duration
	wolf.SprintUntil = 0
	MoveService.ClearModifier(id, "Sprint")
	MoveService.SetModifier(id, "Maul", { Override = 0, NoJump = true })
	setAnimation(wolf, "Maul")
	local root = MatchService.RootOf(id)
	if root then
		AudioService.At("WolfMaul", root.CFrame.Position)
	end
	task.delay(duration, function()
		if wolves[id] == wolf then
			MoveService.ClearModifier(id, "Maul")
		end
	end)
end

local function onAttack(player: Player)
	local member = MatchService.MemberOf(player)
	local wolf = if member then wolves[member.Id] else nil
	if not member or not wolf or not member.Alive or not RoundService.IsNight() or MatchService.Winner then
		return
	end
	local stats = statsOf(wolf.Form)
	local now = os.clock()
	if now < wolf.MaulUntil or now - wolf.LastAttack < stats.AttackCooldown or CombatService.IsStunned(member.Id) then
		return
	end
	local root = MatchService.RootOf(member.Id)
	if not root or HouseService.IsTrespassing(member.Id) then
		return
	end
	wolf.LastAttack = now
	setVanished(member.Id, wolf, false) -- attacking shows The Lurker
	setAnimation(wolf, "Attack")
	AudioService.At("WolfAttack", root.CFrame.Position)

	local target = Melee.findTarget(member.Id, stats.AttackRange, Config.Wolf.AttackMinDot, function(other: Roster.Member)
		return not Roster.isWolfSide(other)
	end)
	if target then
		local outcome = CombatService.Damage(target.Id, stats.AttackDamage, wolf.Form, member.Id)
		if outcome == "Killed" and now < wolf.SprintUntil then
			startMaul(member.Id, wolf)
		end
		return
	end
	-- Nobody in reach: the swing lands on the door in front, if there is one.
	HouseService.HitDoorNear(root.CFrame.Position, root.CFrame.LookVector, Config.Door.HitRange, stats.DoorDamage, member.Id)
end

--------------------------------------------------------------------------------
-- Abilities
--------------------------------------------------------------------------------

local function useCooldown(player: Player, wolf: WolfState, ability: string, cooldown: number): boolean
	local now = os.clock()
	if now < (wolf.ReadyAt[ability] or 0) or now < wolf.MaulUntil then
		return false
	end
	wolf.ReadyAt[ability] = now + cooldown
	Net.fire(player, "AbilityState", { Name = ability, ReadyAt = workspace:GetServerTimeNow() + cooldown })
	return true
end

local function sniff(player: Player, wolf: WolfState)
	if not useCooldown(player, wolf, "Sniff", Config.Wolf.Sniff.Cooldown) then
		return
	end
	-- Everyone on the map who is not inside a house.
	local ids: { number } = {}
	for _, member in prey() do
		local root = MatchService.RootOf(member.Id)
		if root and HouseService.HouseAt(root.CFrame.Position) == nil then
			table.insert(ids, member.Id)
		end
	end
	sendHighlight({ player }, "Sniff", ids, Config.Wolf.Sniff.Duration)
end

local function sprint(player: Player, id: number, wolf: WolfState)
	local cfg = Config.Wolf.Sprint
	if not useCooldown(player, wolf, "Sprint", cfg.Cooldown) then
		return
	end
	local untilTime = os.clock() + cfg.Duration
	wolf.SprintUntil = untilTime
	MoveService.SetModifier(id, "Sprint", { Multiplier = cfg.Speed / Config.Wolf.WalkSpeed })
	task.delay(cfg.Duration, function()
		if wolves[id] == wolf and wolf.SprintUntil == untilTime then
			MoveService.ClearModifier(id, "Sprint")
		end
	end)
end

local function howl(player: Player, id: number, wolf: WolfState)
	local cfg = Config.Pup.Howl
	if not useCooldown(player, wolf, "Howl", cfg.Cooldown) then
		return
	end
	setAnimation(wolf, "Howl")
	local root = MatchService.RootOf(id)
	if not root then
		return
	end
	AudioService.At("WolfHowl", root.CFrame.Position)
	local ids: { number } = {}
	for _, member in prey() do
		local other = MatchService.RootOf(member.Id)
		if other and (other.CFrame.Position - root.CFrame.Position).Magnitude <= cfg.Radius then
			table.insert(ids, member.Id)
		end
	end
	-- The whole wolf side sees the red aura.
	sendHighlight(wolfSidePlayers(), "Howl", ids, cfg.Duration)
end

local function isDirection(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X -- not NaN
		and value.Y == value.Y
		and value.Z == value.Z
		and value.Magnitude > 1e-3
		and value.Magnitude < 1e6
end

-- The Lurker's water bolt: the first body on the line takes its Attack Power.
-- Doors and walls stop it (and take nothing). Shares the attack cooldown.
local function waterBolt(player: Player, id: number, wolf: WolfState, aim: any)
	if not isDirection(aim) then
		return
	end
	local stats = statsOf("Lurker")
	local now = os.clock()
	if now - wolf.LastAttack < stats.AttackCooldown then
		return
	end
	local root = MatchService.RootOf(id)
	if not root or HouseService.IsTrespassing(id) then
		return
	end
	wolf.LastAttack = now
	setVanished(id, wolf, false)
	setAnimation(wolf, "Attack")
	local cfg = Config.Lurker.Bullet
	local origin = root.CFrame.Position + Vector3.new(0, 1.5, 0)
	local ray = (aim :: Vector3).Unit * cfg.Range
	local hitId = Sight.firstBody(origin, ray, MatchService.CharacterOf(id))
	local target = if hitId then MatchService.Roster.Members[hitId] else nil
	if target and (not target.Alive or Roster.isWolfSide(target)) then
		target = nil
	end
	local hitRoot = if target then MatchService.RootOf(target.Id) else nil
	local to = if hitRoot then hitRoot.CFrame.Position else origin + ray * (Sight.clearDistance(origin, ray) / cfg.Range)
	Net.fireAll("Effect", { Kind = "WaterBolt", From = origin, To = to, Speed = cfg.Speed })
	AudioService.At("WaterBolt", origin)
	Net.fire(player, "AbilityState", { Name = "WaterBolt", ReadyAt = workspace:GetServerTimeNow() + stats.AttackCooldown })
	if target then
		CombatService.Damage(target.Id, stats.AttackDamage, "Lurker", id)
	end
end

local function vanish(player: Player, id: number, wolf: WolfState)
	if wolf.Vanished or wolf.Submerged then
		return -- already invisible; in the water it cannot hide this way
	end
	local cfg = Config.Lurker.Vanish
	if not useCooldown(player, wolf, "Vanish", cfg.Cooldown) then
		return
	end
	setVanished(id, wolf, true)
	if cfg.MaxDuration > 0 then
		task.delay(cfg.MaxDuration, function()
			if wolves[id] == wolf then
				setVanished(id, wolf, false)
			end
		end)
	end
end

local function onAbility(player: Player, ability: any, aim: any)
	local member = MatchService.MemberOf(player)
	local wolf = if member then wolves[member.Id] else nil
	if not member or not wolf or not member.Alive or not RoundService.IsNight() or type(ability) ~= "string" then
		return
	end
	if CombatService.IsStunned(member.Id) then
		return
	end
	if wolf.Form == "Wolf" and ability == "Sniff" then
		sniff(player, wolf)
	elseif wolf.Form == "Wolf" and ability == "Sprint" then
		sprint(player, member.Id, wolf)
	elseif wolf.Form == "Pup" and ability == "Howl" then
		howl(player, member.Id, wolf)
	elseif wolf.Form == "Lurker" and ability == "WaterBolt" then
		waterBolt(player, member.Id, wolf, aim)
	elseif wolf.Form == "Lurker" and ability == "Vanish" then
		vanish(player, member.Id, wolf)
	end
end

--------------------------------------------------------------------------------
-- Skills on the hotbar (owner, 23 Nov 2026): while transformed, the monster's
-- skills are Tools in the Roblox hotbar; pressing the number uses the skill at
-- once (the tool never stays in hand). Items are put away meanwhile and come
-- back in the morning. The water bolt flies where the monster faces (its
-- camera is in shift lock, so that is where the camera looks).
--------------------------------------------------------------------------------

local SKILLS: { [string]: { string } } = {
	Wolf = { "Sniff", "Sprint" },
	Pup = { "Howl" },
	Lurker = { "WaterBolt", "Vanish" },
}
local stashes: { [number]: Folder } = {}

local function holders(player: Player): { Instance }
	local list: { Instance } = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(list, backpack)
	end
	if player.Character then
		table.insert(list, player.Character)
	end
	return list
end

function WolfService.UseSkill(player: Player, skill: string)
	local member = MatchService.MemberOf(player)
	local root = if member then MatchService.RootOf(member.Id) else nil
	onAbility(player, skill, if root then root.CFrame.LookVector else nil)
end

local function giveSkills(player: Player, form: string)
	-- Items away (kept safe, not dropped).
	local stash: Folder = stashes[player.UserId]
	if not stash then
		local folder = Instance.new("Folder")
		folder.Name = "ItemStash" .. player.UserId
		folder.Parent = ServerStorage
		stashes[player.UserId] = folder
		stash = folder
	end
	for _, holder in holders(player) do
		for _, tool in holder:GetChildren() do
			if tool:IsA("Tool") then
				if tool:GetAttribute("MonsterSkill") then
					tool:Destroy() -- an old set (a new body tonight)
				else
					tool.Parent = stash
				end
			end
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local skills: { string } = SKILLS[form] or {}
	for _, skill in skills do
		local tool = Instance.new("Tool")
		local name = Strings["Ability." .. skill]
		tool.Name = if name then name.en else skill
		tool.RequiresHandle = false
		tool.CanBeDropped = false
		tool:SetAttribute("MonsterSkill", skill)
		tool.Parent = backpack
		-- pcall: the offline test engine's tools have no events.
		pcall(function()
			tool.Equipped:Connect(function()
				WolfService.UseSkill(player, skill)
				task.defer(function()
					local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid:UnequipTools()
					end
				end)
			end)
		end)
	end
end

local function takeSkills(player: Player)
	for _, holder in holders(player) do
		for _, tool in holder:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("MonsterSkill") then
				tool:Destroy()
			end
		end
	end
	local stash = stashes[player.UserId]
	stashes[player.UserId] = nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	if stash then
		for _, tool in stash:GetChildren() do
			if backpack then
				tool.Parent = backpack
			end
		end
		stash:Destroy()
	end
end

--------------------------------------------------------------------------------
-- The water channel (The Lurker's matches, owner 19 Nov 2026)
--------------------------------------------------------------------------------

-- Sinks The Lurker's costume so only its head and back fins show above the water.
local function setSubmerged(wolf: WolfState, submerged: boolean)
	if wolf.Submerged == submerged then
		return
	end
	wolf.Submerged = submerged
	local shell = wolf.Shell
	local root = shell and shell.Parent and shell.Parent:FindFirstChild("HumanoidRootPart")
	local shellRoot = shell and shell.PrimaryPart
	if not shell or not shellRoot or not (root and root:IsA("BasePart")) then
		return
	end
	shell:SetAttribute("Submerged", if submerged then true else nil)
	local weld = shellRoot:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld.Enabled = false
	end
	local depth = if submerged then Config.Lurker.SubmergeDepth else 0
	shell:PivotTo(root.CFrame * CFrame.new(0, -depth, 0))
	if weld then
		weld.Enabled = true
	end
end

local waterToken = 0

-- Who is in the channel: people wade (slow), The Lurker swims (+5, sunk, silent).
local function scanWater()
	local wade = Config.Map.Moat.WadeSpeed
	for _, member in Roster.list(MatchService.Roster) do
		local root = if member.Alive then MatchService.RootOf(member.Id) else nil
		local inWater = root ~= nil and not HidingService.IsHidden(member.Id) and ForestService.InMoat(root.CFrame.Position)
		local wolf = wolves[member.Id]
		local character = MatchService.CharacterOf(member.Id)
		if wolf and wolf.Form == "Lurker" then
			MoveService.ClearModifier(member.Id, "Wade")
			if inWater then
				MoveService.SetModifier(member.Id, "Swim", { Add = Config.Lurker.WaterSpeedBonus })
				setVanished(member.Id, wolf, false) -- going into the water shows it
			else
				MoveService.ClearModifier(member.Id, "Swim")
			end
			setSubmerged(wolf, inWater)
		elseif inWater then
			MoveService.SetModifier(member.Id, "Wade", { Override = wade })
		else
			MoveService.ClearModifier(member.Id, "Wade")
		end
		if character then
			character:SetAttribute("InWater", if inWater then true else nil)
		end
	end
end

local function startWaterLoop()
	waterToken += 1
	local token = waterToken
	task.spawn(function()
		while token == waterToken and MatchService.Started and not MatchService.Winner do
			scanWater()
			task.wait(0.2)
		end
	end)
end

--------------------------------------------------------------------------------

function WolfService.Init() end

function WolfService.Start()
	CombatService.AddStunImmunity(WolfService.IsMauling)
	Net.on("WolfAttack", onAttack, 20, 5)
	Net.on("WolfAbility", onAbility, 10, 5)

	RoundService.PhaseStarted:Connect(function(phase: PhaseMachine.PhaseState)
		if phase.Phase == "Night" then
			for _, member in Roster.alive(MatchService.Roster) do
				if Roster.isWolfSide(member) then
					transform(member)
				end
			end
			MatchService.SendPack()
			startForestLoop()
			setNightNames(true)
		elseif phase.Phase == "Day" then
			setNightNames(false)
		end
	end)

	WolfService.FormChanged:Connect(function(memberId: number, form: string)
		local player = MatchService.PlayerOf(memberId)
		if player then
			if form == "Human" then
				takeSkills(player)
			else
				giveSkills(player, form)
			end
		end
	end)

	-- The Lurker's passive: its matches have the water channel (owner, 19 Nov 2026).
	MatchService.MatchStarted:Connect(function()
		for _, member in Roster.list(MatchService.Roster) do
			if member.Faction == "Wolf" and member.Monster == "Lurker" then
				ForestService.ShowMoat()
				startWaterLoop()
				break
			end
		end
	end)

	RoundService.PhaseEnded:Connect(function(phase: PhaseMachine.PhaseState)
		if phase.Phase == "Night" then
			stopForestLoop()
			for id in table.clone(wolves) do
				revert(id)
			end
		end
	end)

	-- Bitten tonight: the new pup changes shape on the spot (no corpse).
	MatchService.MemberConverted:Connect(function(member: Roster.Member)
		if RoundService.IsNight() then
			transform(member)
		end
	end)

	MatchService.MemberDied:Connect(function(member: Roster.Member)
		-- A dead wolf keeps its shape until morning; it just stops acting.
		local wolf = wolves[member.Id]
		if wolf then
			wolf.MaulUntil = 0
			wolf.SprintUntil = 0
		end
	end)

	-- Revived, or a fresh body after a reset: the old body (and costume) is gone.
	local function onNewBody(member: Roster.Member)
		wolves[member.Id] = nil
		if RoundService.IsNight() then
			local body = MatchService.CharacterOf(member.Id)
			if body then
				hideNightName(body)
			end
		end
		if Roster.isWolfSide(member) and RoundService.IsNight() then
			transform(member)
		end
	end
	MatchService.MemberRevived:Connect(onNewBody)
	MatchService.BodyReplaced:Connect(onNewBody)

	MatchService.SyncRequested:Connect(function(player: Player)
		local wolf = wolves[player.UserId]
		if wolf then
			Net.fire(player, "FormChanged", wolf.Form)
			Net.fire(player, "Highlight", { Kind = "Forest", Ids = forestIds })
			sendBaits({ player })
		end
	end)
end

return WolfService
