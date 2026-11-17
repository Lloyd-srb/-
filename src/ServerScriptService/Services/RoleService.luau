--!strict
--[[
	RoleService — the special roles' abilities (GDD §9).

	  Villager   flashlight (toggle)
	  Sheriff    stun gun: 1 shot per day and 1 per night; kills the Killer
	  Doctor     revive a body that died at night: 1 per game (+ First aid)
	  Seer       once per night: every survivor outlined in white for 5 s
	  Chief      double vote + tie-break (handled by VoteService)
	  Bodyguard  dash forward, stuns a wolf it runs into; 30 s cooldown
	  Monk       each morning: bless one player (self allowed); the blessing
	             blocks one wolf / knife attack until the next morning
	  Engineer   reinforce a door: 1 per day + 1 per night
	  Killer     knife: one-hit kill, 1 per day + 1 per night
	  Fool       no ability (wins by being voted out)

	The client only sends "use ability X (with this aim / target)". Every rule
	is checked here: role, alive, not a pup, not hidden, not stunned, phase,
	uses left, distance. Results that are secret go to the user only.

	A "day" for limits covers the Day and MeetingCountdown phases; nothing can
	be used during the meeting itself or the full-moon warning.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local AbilityUses = require(Logic.AbilityUses)
local DoorState = require(Logic.DoorState)
local Roster = require(Logic.Roster)

local CombatService = require(script.Parent.CombatService)
local Flashlight = require(script.Parent.Flashlight)
local HidingService = require(script.Parent.HidingService)
local HouseService = require(script.Parent.HouseService)
local AudioService = require(script.Parent.AudioService)
local MatchService = require(script.Parent.MatchService)
local Melee = require(script.Parent.Melee)
local MovementGuard = require(script.Parent.MovementGuard)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)
local Sight = require(script.Parent.Sight)
local WolfService = require(script.Parent.WolfService)

local Abilities = Config.Abilities
local REACH_SLACK = 4 -- extra studs allowed over a prompt's activation distance (lag)
local REVIVE_RISE = 2.5 -- a revived body stands up this far above the corpse's centre
local WOLF_DAMAGE_CAUSES = { Wolf = true, Pup = true, Killer = true }

local RoleService = {}

--[[
	Milestone 5 hook: lets the Doctor spend a First aid for an extra revive.
	Returns true when one was consumed.
]]
RoleService.ConsumeExtraRevive = function(_doctorId: number): boolean
	return false
end

local uses = AbilityUses.new()
local blessed: { [number]: boolean } = {}
local dashReadyAt: { [number]: number } = {}
local lightToggledAt: { [number]: number } = {}
local reinforcePrompts: { [number]: ProximityPrompt } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- The current limit scope: ("Day:3", "Day") / ("Night:2", "Night") / nil.
local function scope(): (string?, string?)
	local state = RoundService.State
	if state.Phase == "Night" then
		return "Night:" .. state.Night, "Night"
	elseif state.Phase == "Day" or state.Phase == "MeetingCountdown" then
		return "Day:" .. state.Day, "Day"
	end
	return nil, nil
end

-- The member behind `player` if they may act as `roleId` right now.
local function actor(player: Player, roleId: Config.RoleId): Roster.Member?
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or MatchService.Winner or not MatchService.Started then
		return nil
	end
	if member.Role ~= roleId or member.IsPup then
		return nil
	end
	if HidingService.IsHidden(member.Id) or CombatService.IsStunned(member.Id) then
		return nil
	end
	if not MatchService.RootOf(member.Id) or HouseService.IsTrespassing(member.Id) then
		return nil
	end
	return member
end

local function within(id: number, position: Vector3, distance: number): boolean
	local root = MatchService.RootOf(id)
	return root ~= nil and (root.CFrame.Position - position).Magnitude <= distance
end

local function limitFor(roleId: Config.RoleId, kind: string?): (string?, number)
	if roleId == "Sheriff" then
		return "Shoot", Abilities.Sheriff.ShotsPerPhase
	elseif roleId == "Seer" then
		return "See", if kind == "Night" then Abilities.Seer.UsesPerNight else 0
	elseif roleId == "Monk" then
		return "Bless", if kind == "Day" then Abilities.Monk.BlessingsPerMorning else 0
	elseif roleId == "Killer" then
		return "Stab", if kind == "Night" then Abilities.Killer.KillsPerNight else Abilities.Killer.KillsPerDay
	elseif roleId == "Engineer" then
		return "Reinforce", if kind == "Night" then Abilities.Engineer.UsesPerNight else Abilities.Engineer.UsesPerDay
	elseif roleId == "Doctor" then
		return "Revive", Abilities.Doctor.RevivesPerGame
	end
	return nil, 0
end

-- Tells a player how many uses of their ability are left right now (or when
-- the Bodyguard's dash is ready). Private to that player.
local function sendState(member: Roster.Member)
	local player = MatchService.PlayerOf(member.Id)
	if not player then
		return
	end
	if member.Role == "Bodyguard" then
		local readyAt = dashReadyAt[member.Id] or 0
		Net.fire(player, "AbilityState", {
			Name = "Dash",
			ReadyAt = workspace:GetServerTimeNow() + math.max(0, readyAt - os.clock()),
		})
		return
	end
	local scopeKey, kind = scope()
	local ability, limit = limitFor(member.Role, kind)
	if not ability then
		return
	end
	if ability == "Revive" then
		scopeKey = "Game"
	end
	local left = if scopeKey then AbilityUses.left(uses, member.Id, ability, scopeKey, limit) else 0
	Net.fire(player, "AbilityState", { Name = ability, UsesLeft = left })
end

local function sendAllStates()
	for _, member in Roster.alive(MatchService.Roster) do
		if not member.IsPup then
			sendState(member)
		end
	end
end

--------------------------------------------------------------------------------
-- Sheriff (and, from milestone 5, the gun item)
--------------------------------------------------------------------------------

-- The colour of a member's gun / knife skin (or the default look).
function RoleService.SkinColor(memberId: number, slot: string): Color3
	local skinId = ProfileService.Skin(MatchService.PlayerOf(memberId), slot)
	local skin = if skinId then Config.Skins[skinId] else nil
	return (if skin then skin.Color else nil) or (Config.DefaultLook :: any)[slot]
end

-- What a stun-gun hit does: the Killer dies at once, anyone else is stunned.
function RoleService.ApplyGunHit(targetId: number, shooterId: number)
	local target = MatchService.Roster.Members[targetId]
	if not target or not target.Alive then
		return
	end
	if target.Role == "Killer" and not target.IsPup then
		CombatService.Damage(targetId, math.huge, "Sheriff", shooterId)
	else
		CombatService.Stun(targetId, Abilities.Sheriff.StunDuration)
	end
end

-- Fires one stun shot from `shooterId` along `direction`. Shared with the gun item.
function RoleService.FireGun(shooterId: number, direction: Vector3)
	local root = MatchService.RootOf(shooterId)
	if not root then
		return
	end
	local cfg = Abilities.Sheriff
	local origin = root.CFrame.Position + Vector3.new(0, cfg.MuzzleHeight, 0)
	local ray = direction.Unit * cfg.Range
	local hitId = Sight.firstBody(origin, ray, MatchService.CharacterOf(shooterId))
	local hitRoot = if hitId then MatchService.RootOf(hitId) else nil
	-- Everyone nearby would see and hear a shot, so the tracer is public.
	Net.fireAll("Effect", {
		Kind = "Shot",
		From = origin,
		To = if hitRoot then hitRoot.CFrame.Position else origin + ray,
		Color = RoleService.SkinColor(shooterId, "Gun"),
	})
	if hitId then
		RoleService.ApplyGunHit(hitId, shooterId)
	end
end

local function isDirection(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X -- not NaN
		and value.Y == value.Y
		and value.Z == value.Z
		and value.Magnitude > 1e-3
		and value.Magnitude < 1e6
end

local function shoot(player: Player, direction: any)
	local member = actor(player, "Sheriff")
	local scopeKey = scope()
	if not member or not scopeKey or not isDirection(direction) then
		return
	end
	if not AbilityUses.tryUse(uses, member.Id, "Shoot", scopeKey, Abilities.Sheriff.ShotsPerPhase) then
		return
	end
	RoleService.FireGun(member.Id, direction)
	sendState(member)
end

--------------------------------------------------------------------------------
-- Seer
--------------------------------------------------------------------------------

local function see(player: Player)
	local member = actor(player, "Seer")
	local scopeKey, kind = scope()
	if not member or kind ~= "Night" or not scopeKey then
		return
	end
	if not AbilityUses.tryUse(uses, member.Id, "See", scopeKey, Abilities.Seer.UsesPerNight) then
		return
	end
	-- Every survivor, white, bodies only: no names, no roles.
	local ids: { number } = {}
	for _, other in Roster.alive(MatchService.Roster) do
		if other.Id ~= member.Id and not HidingService.IsHidden(other.Id) and MatchService.RootOf(other.Id) then
			table.insert(ids, other.Id)
		end
	end
	Net.fire(player, "Highlight", { Kind = "Seer", Ids = ids, Duration = Abilities.Seer.Duration })
	sendState(member)
end

--------------------------------------------------------------------------------
-- Bodyguard
--------------------------------------------------------------------------------

-- Distance from `point` to the segment a-b (horizontal plane).
local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local flatPoint = Vector3.new(point.X, 0, point.Z)
	local flatA = Vector3.new(a.X, 0, a.Z)
	local flatB = Vector3.new(b.X, 0, b.Z)
	local segment = flatB - flatA
	local length = segment.Magnitude
	if length < 1e-6 then
		return (flatPoint - flatA).Magnitude
	end
	local t = math.clamp((flatPoint - flatA):Dot(segment) / (length * length), 0, 1)
	return (flatPoint - (flatA + segment * t)).Magnitude
end

local function dash(player: Player)
	local member = actor(player, "Bodyguard")
	if not member or not scope() then
		return
	end
	local cfg = Abilities.Bodyguard
	local now = os.clock()
	if now < (dashReadyAt[member.Id] or 0) then
		return
	end
	local root = MatchService.RootOf(member.Id)
	local character = MatchService.CharacterOf(member.Id)
	if not root or not character then
		return
	end
	dashReadyAt[member.Id] = now + cfg.Cooldown

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local start = root.CFrame.Position
	local distance = math.max(0, Sight.clearDistance(start, flat * cfg.DashDistance) - 1)
	local finish = start + flat * distance

	-- Only a wolf in wolf form is stopped; people (the Killer too) are passed through.
	for _, other in Roster.alive(MatchService.Roster) do
		if other.Id ~= member.Id and Roster.isWolfSide(other) and WolfService.IsTransformed(other.Id) then
			local otherRoot = MatchService.RootOf(other.Id)
			if otherRoot and distanceToSegment(otherRoot.CFrame.Position, start, finish) <= cfg.HitRadius then
				CombatService.Stun(other.Id, cfg.StunDuration)
			end
		end
	end

	-- Passing through other characters for the length of the dash.
	local duration = distance / cfg.DashSpeed
	MatchService.SetCollisionGroup(character, MatchService.DashGroup)
	task.delay(duration + 0.2, function()
		if character.Parent then
			MatchService.SetCollisionGroup(character, MatchService.CharacterGroup)
		end
	end)
	-- The player's own client moves its character (it owns its physics).
	MovementGuard.Allow(member.Id, duration + 1)
	Net.fire(player, "DashStart", { Direction = flat, Speed = cfg.DashSpeed, Duration = duration })
	AudioService.At("BodyguardDash", start)
	sendState(member)
end

--------------------------------------------------------------------------------
-- Monk
--------------------------------------------------------------------------------

local function bless(player: Player, targetId: any)
	local member = actor(player, "Monk")
	local scopeKey, kind = scope()
	if not member or kind ~= "Day" or not scopeKey or type(targetId) ~= "number" then
		return
	end
	local target = MatchService.Roster.Members[targetId]
	if not target or not target.Alive then
		return
	end
	if not AbilityUses.tryUse(uses, member.Id, "Bless", scopeKey, Abilities.Monk.BlessingsPerMorning) then
		return
	end
	blessed[targetId] = true
	-- Only the Monk is told; the blessed player finds out when it saves them.
	Net.fire(player, "Effect", { Kind = "Blessed", Name = target.Name })
	sendState(member)
end

function RoleService.IsBlessed(id: number): boolean
	return blessed[id] == true
end

--------------------------------------------------------------------------------
-- Killer
--------------------------------------------------------------------------------

local function stab(player: Player)
	local member = actor(player, "Killer")
	local scopeKey, kind = scope()
	if not member or not scopeKey then
		return
	end
	local cfg = Abilities.Killer
	local limit = if kind == "Night" then cfg.KillsPerNight else cfg.KillsPerDay
	if AbilityUses.left(uses, member.Id, "Stab", scopeKey, limit) <= 0 then
		return
	end
	local target = Melee.findTarget(member.Id, cfg.KnifeRange, cfg.MinDot, function()
		return true -- the Killer may kill anyone, wolves included
	end)
	if not target then
		return -- a miss does not use up the kill
	end
	AbilityUses.tryUse(uses, member.Id, "Stab", scopeKey, limit)
	local targetRoot = MatchService.RootOf(target.Id)
	CombatService.Damage(target.Id, cfg.KnifeDamage, "Killer", member.Id)
	sendState(member)
	-- Only players close by see the slash (in the Killer's knife colour).
	if targetRoot then
		local at = targetRoot.CFrame.Position
		for _, viewer in Players:GetPlayers() do
			local viewerRoot = viewer.Character and viewer.Character:FindFirstChild("HumanoidRootPart")
			if viewerRoot and viewerRoot:IsA("BasePart") and (viewerRoot.CFrame.Position - at).Magnitude <= Config.SlashViewRadius then
				Net.fire(viewer, "Effect", { Kind = "Slash", At = at, Color = RoleService.SkinColor(member.Id, "Knife") })
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Villager
--------------------------------------------------------------------------------

local function flashlight(player: Player)
	local member = actor(player, "Villager")
	local character = if member then MatchService.CharacterOf(member.Id) else nil
	if not member or not character then
		return
	end
	local now = os.clock()
	if now - (lightToggledAt[member.Id] or 0) < Abilities.Villager.ToggleCooldown then
		return
	end
	lightToggledAt[member.Id] = now

	Flashlight.toggle(character)
end

--------------------------------------------------------------------------------
-- Doctor
--------------------------------------------------------------------------------

local function onRevivePrompt(player: Player, corpseId: number, prompt: ProximityPrompt)
	local member = actor(player, "Doctor")
	local corpse = MatchService.Roster.Members[corpseId]
	local body = MatchService.BodyOf(corpseId)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not member or not corpse or corpse.Alive or not corpse.DiedAtNight or corpse.Left then
		return
	end
	if not (root and root:IsA("BasePart")) then
		return
	end
	if not within(member.Id, root.CFrame.Position, prompt.MaxActivationDistance + REACH_SLACK) then
		return
	end
	local limit = Abilities.Doctor.RevivesPerGame
	local free = AbilityUses.left(uses, member.Id, "Revive", "Game", limit) > 0
	if free then
		AbilityUses.tryUse(uses, member.Id, "Revive", "Game", limit)
	elseif not RoleService.ConsumeExtraRevive(member.Id) then
		return
	end
	local where = CFrame.new(root.CFrame.Position + Vector3.new(0, REVIVE_RISE, 0))
	MatchService.Revive(corpseId, where)
	AudioService.At("Revive", where.Position)
	sendState(member)
end

local function addRevivePrompt(member: Roster.Member, body: Model)
	if not member.DiedAtNight then
		return -- only bodies of people who died at night can be revived (GDD §6.4)
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local prompt = Prompts.create(root, "RevivePrompt", "Prompt.Revive", Abilities.Doctor.ReviveHold)
	prompt:SetAttribute("Audience", "Role:Doctor")
	prompt:SetAttribute("Active", true)
	prompt.Enabled = true
	prompt.Triggered:Connect(function(player: Player)
		onRevivePrompt(player, member.Id, prompt)
	end)
end

--------------------------------------------------------------------------------
-- Engineer
--------------------------------------------------------------------------------

local function onReinforcePrompt(player: Player, houseId: number, prompt: ProximityPrompt)
	local member = actor(player, "Engineer")
	local scopeKey, kind = scope()
	local door = HouseService.DoorOf(houseId)
	local anchor = prompt.Parent
	if not member or not scopeKey or not door or door.State == "Broken" then
		return
	end
	local position = if anchor and anchor:IsA("Attachment")
		then Zones.worldCFrame(anchor).Position
		elseif anchor and anchor:IsA("BasePart") then anchor.CFrame.Position
		else nil
	if not position or not within(member.Id, position, prompt.MaxActivationDistance + REACH_SLACK) then
		return
	end
	local _, limit = limitFor("Engineer", kind)
	if not AbilityUses.tryUse(uses, member.Id, "Reinforce", scopeKey, limit) then
		return
	end
	HouseService.ReinforceDoor(houseId)
	sendState(member)
end

local function refreshReinforcePrompts()
	local usable = scope() ~= nil
	for houseId, prompt in reinforcePrompts do
		local door = HouseService.DoorOf(houseId)
		local active = usable and door ~= nil and door.State ~= "Broken"
		prompt:SetAttribute("Active", active)
		prompt.Enabled = active
	end
end

local function addReinforcePrompts()
	for _, door in CollectionService:GetTagged("Door") do
		local houseId = door:GetAttribute("HouseId")
		local anchor = door:FindFirstChild("PromptAnchor") or door
		if type(houseId) == "number" then
			local prompt = Prompts.create(anchor, "ReinforcePrompt", "Prompt.Reinforce", Abilities.Engineer.ReinforceHold)
			prompt:SetAttribute("Audience", "Role:Engineer")
			-- Its own keys, so it never fights the "open door" prompt on the same door.
			prompt.KeyboardKeyCode = Enum.KeyCode.R
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
			prompt.UIOffset = Vector2.new(0, -80)
			prompt.Triggered:Connect(function(player: Player)
				onReinforcePrompt(player, houseId, prompt)
			end)
			reinforcePrompts[houseId] = prompt
		end
	end
end

--------------------------------------------------------------------------------

local HANDLERS: { [string]: (Player, any) -> () } = {
	Shoot = shoot,
	See = see,
	Dash = dash,
	Bless = bless,
	Stab = stab,
	Flashlight = flashlight,
}

local function onAbility(player: Player, ability: any, argument: any)
	local handler = if type(ability) == "string" then HANDLERS[ability] else nil
	if handler then
		handler(player, argument)
	end
end

function RoleService.Init()
	addReinforcePrompts()
end

function RoleService.Start()
	Net.on("AbilityUse", onAbility, 12, 5)

	-- The blessing blocks one wolf / pup / knife attack (GDD §9 Monk).
	CombatService.AddShield(function(victimId: number, cause: Roster.DeathCause): boolean
		if blessed[victimId] and WOLF_DAMAGE_CAUSES[cause] then
			blessed[victimId] = nil
			return true
		end
		return false
	end)

	CombatService.CorpseCreated:Connect(addRevivePrompt)

	HouseService.DoorChanged:Connect(function(houseId: number, door: DoorState.Door)
		local prompt = reinforcePrompts[houseId]
		if prompt then
			local active = scope() ~= nil and door.State ~= "Broken"
			prompt:SetAttribute("Active", active)
			prompt.Enabled = active
		end
	end)

	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Day" then
			table.clear(blessed) -- blessings wear off each morning
		end
		refreshReinforcePrompts()
		sendAllStates()
	end)

	MatchService.MatchStarted:Connect(sendAllStates)
	MatchService.MemberDied:Connect(function(member: Roster.Member)
		blessed[member.Id] = nil
	end)
	MatchService.SyncRequested:Connect(function(player: Player)
		local member = MatchService.MemberOf(player)
		if member and member.Alive and not member.IsPup then
			sendState(member)
		end
	end)
end

return RoleService
