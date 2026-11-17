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
	- Players in the forest are outlined in red for the wolf side only.

	Outlines are never created here: the server tells the allowed viewers which
	ids to highlight, and their clients draw them locally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Roster = require(script.Parent.Parent.Logic.Roster)

local CombatService = require(script.Parent.CombatService)
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
	Form: string, -- "Wolf" | "Pup"
	Shell: Model?,
	LastAttack: number,
	SprintUntil: number,
	MaulUntil: number,
	ReadyAt: { [string]: number }, -- ability -> os.clock() when usable again
}

local WolfService = {}

local wolves: { [number]: WolfState } = {}
local forestIds: { number } = {}
local forestLoopToken = 0

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
		-- No name tag over a werewolf.
		humanoid.DisplayDistanceType = if hidden
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
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
	local form = if member.IsPup then "Pup" else "Wolf"
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
	if shell then
		paintShell(shell, MatchService.PlayerOf(member.Id))
	end
	setBodyHidden(character, shell, true)
	character:SetAttribute("Form", form)
	wolves[member.Id] = {
		Form = form,
		Shell = shell,
		LastAttack = 0,
		SprintUntil = 0,
		MaulUntil = 0,
		ReadyAt = {},
	}
	MoveService.SetBase(member.Id, if member.IsPup then Config.Pup.WalkSpeed else Config.Wolf.WalkSpeed)
	local player = MatchService.PlayerOf(member.Id)
	if player then
		Net.fire(player, "FormChanged", form)
	end
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
	MoveService.SetBase(id, Config.Human.WalkSpeed)
	local player = MatchService.PlayerOf(id)
	if player then
		Net.fire(player, "FormChanged", "Human")
	end
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
end

local function startForestLoop()
	forestLoopToken += 1
	local token = forestLoopToken
	forestIds = {}
	task.spawn(function()
		while token == forestLoopToken and RoundService.IsNight() and not MatchService.Winner do
			scanForest()
			task.wait(Config.Wolf.ForestScanInterval)
		end
	end)
end

local function stopForestLoop()
	forestLoopToken += 1
	forestIds = {}
	sendHighlight(wolfSidePlayers(), "Forest", {}, nil)
end

--------------------------------------------------------------------------------
-- Attack
--------------------------------------------------------------------------------

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
	local isPup = wolf.Form == "Pup"
	local stats = if isPup then Config.Pup else Config.Wolf
	local now = os.clock()
	if now < wolf.MaulUntil or now - wolf.LastAttack < stats.AttackCooldown or CombatService.IsStunned(member.Id) then
		return
	end
	local root = MatchService.RootOf(member.Id)
	if not root or HouseService.IsTrespassing(member.Id) then
		return
	end
	wolf.LastAttack = now
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
	HouseService.HitDoorNear(root.CFrame.Position, root.CFrame.LookVector, Config.Door.HitRange, stats.DoorDamage)
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

local function onAbility(player: Player, ability: any)
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
	end
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
		end
	end)
end

return WolfService
