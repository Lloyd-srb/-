--!strict
--[[
	GearService — the Ninja's smoke bomb and the Hunter's bear traps
	(owner, 24 Nov 2026). Both are role items: InventoryService gives them at
	the start and calls in here when they are used.

	Ninja (smoke bomb)
	  - Press: invisible for 6 s. Usable by day and by night. 20 s cooldown,
	    counted from the press.
	  - Pressed while someone has the Ninja outlined (Seer, Detective, the
	    monster's forest glow / sniff / howl, a Hunter's trap): every outline
	    on the Ninja is taken off at once, for every viewer.
	  - Any action except knocking on a door ends it early, like the
	    monster's invisibility: using an item or an ability, finishing a
	    "hold E" prompt.
	  - [owner] 24 Nov 2026: works like the monster's invisibility: an
	    outline put on afterwards (e.g. the Seer) still shows the Ninja.

	Hunter (bear traps)
	  - Press: a trap is put on the ground at the Hunter's feet. At most 3 on
	    the map at once. 50 s cooldown, counted from putting one down.
	  - A trap stays until someone steps on it: a person or a monster (not
	    the Hunter who set it, [ASSUMED]). That one is stunned for 2 s and the
	    Hunter sees them outlined in red. The trap is used up.
	  - [owner] 24 Nov 2026: everyone can see the traps on the ground.

	Invisibility here hides a person's body; the monster's own invisibility
	is WolfService's. Both put "Vanished" on the character, which is what the
	outline senders look at.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Logic = script.Parent.Parent.Logic
local Roster = require(Logic.Roster)

local AudioService = require(script.Parent.AudioService)
local CombatService = require(script.Parent.CombatService)
local HidingService = require(script.Parent.HidingService)
local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)

local GearService = {}

-- Fired with (memberId) when a Ninja appears again (time up or an action).
GearService.Revealed = Signal.new()
-- Fired with (memberId) when a Ninja vanishes.
GearService.Smoked = Signal.new()

type Smoke = { Token: number, Character: Model, Added: RBXScriptConnection? }

local smokes: { [number]: Smoke } = {} -- ninja id -> current invisibility
local smokeReadyAt: { [number]: number } = {} -- os.clock()
local trapReadyAt: { [number]: number } = {}
local nextToken = 0
local trapFolder: Folder

local KNOCK_PROMPT = "KnockPrompt"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function tell(memberId: number, payload: { [string]: any })
	local player = MatchService.PlayerOf(memberId)
	if player then
		Net.fire(player, "Effect", payload)
	end
end

local function serverTime(readyAtClock: number): number
	return workspace:GetServerTimeNow() + math.max(0, readyAtClock - os.clock())
end

-- By day and by night ([owner]); not during the meeting or the full-moon warning,
-- like the other abilities.
local USABLE_PHASES = { Day = true, MeetingCountdown = true, Night = true }
local function playing(): boolean
	return MatchService.Started and not MatchService.Winner and USABLE_PHASES[RoundService.State.Phase] == true
end

-- When each gear can be used again (server time, for the hotbar countdown).
function GearService.ReadyAt(id: number, kind: string): number
	local readyAt = if kind == "SmokeBomb" then smokeReadyAt[id] else trapReadyAt[id]
	return serverTime(readyAt or 0)
end

--------------------------------------------------------------------------------
-- Ninja: smoke bomb
--------------------------------------------------------------------------------

local function hidePart(instance: Instance)
	if instance:IsA("BasePart") then
		if instance:GetAttribute("SmokeTransparency") == nil then
			instance:SetAttribute("SmokeTransparency", instance.Transparency)
			instance:SetAttribute("SmokeShadow", instance.CastShadow)
		end
		instance.Transparency = 1
		instance.CastShadow = false
	elseif instance:IsA("Decal") then
		if instance:GetAttribute("SmokeTransparency") == nil then
			instance:SetAttribute("SmokeTransparency", instance.Transparency)
		end
		instance.Transparency = 1
	elseif instance:IsA("Light") or instance:IsA("BillboardGui") then
		if instance:GetAttribute("SmokeEnabled") == nil then
			instance:SetAttribute("SmokeEnabled", (instance :: any).Enabled)
		end
		(instance :: any).Enabled = false
	end
end

local function showPart(instance: Instance)
	local transparency = instance:GetAttribute("SmokeTransparency")
	if type(transparency) == "number" then
		if instance:IsA("BasePart") then
			instance.Transparency = transparency
			instance.CastShadow = instance:GetAttribute("SmokeShadow") ~= false
		elseif instance:IsA("Decal") then
			instance.Transparency = transparency
		end
	end
	local enabled = instance:GetAttribute("SmokeEnabled")
	if type(enabled) == "boolean" and (instance:IsA("Light") or instance:IsA("BillboardGui")) then
		(instance :: any).Enabled = enabled
	end
	instance:SetAttribute("SmokeTransparency", nil)
	instance:SetAttribute("SmokeShadow", nil)
	instance:SetAttribute("SmokeEnabled", nil)
end

local function setBodyHidden(character: Model, hidden: boolean)
	for _, instance in character:GetDescendants() do
		if hidden then
			hidePart(instance)
		else
			showPart(instance)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if hidden then
			if humanoid:GetAttribute("SmokeName") == nil then
				humanoid:SetAttribute("SmokeName", humanoid.DisplayDistanceType.Name)
			end
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		else
			local name = humanoid:GetAttribute("SmokeName")
			humanoid:SetAttribute("SmokeName", nil)
			-- Nobody has a name at night (WolfService gives it back in the
			-- morning); by day it comes back now.
			if RoundService.State.Phase == "Night" then
				humanoid:SetAttribute("NightName", true)
			elseif type(name) == "string" and not humanoid:GetAttribute("NightName") then
				humanoid.DisplayDistanceType = (Enum.HumanoidDisplayDistanceType :: any)[name]
			end
		end
	end
	character:SetAttribute("Vanished", if hidden then true else nil)
end

-- Ends a Ninja's invisibility (time up, an action, death, a new body).
function GearService.Reveal(id: number)
	local smoke = smokes[id]
	if not smoke then
		return
	end
	smokes[id] = nil
	if smoke.Added then
		smoke.Added:Disconnect()
	end
	if smoke.Character.Parent then
		setBodyHidden(smoke.Character, false)
	end
	GearService.Revealed:Fire(id)
end

function GearService.IsSmoked(id: number): boolean
	return smokes[id] ~= nil
end

-- Returns whether the smoke bomb went off.
function GearService.UseSmokeBomb(id: number): boolean
	local member = MatchService.Roster.Members[id]
	local cfg = Config.Abilities.Ninja
	if not member or not member.Alive or member.Role ~= "Ninja" or not playing() then
		return false
	end
	local now = os.clock()
	if now < (smokeReadyAt[id] or 0) then
		tell(id, { Kind = "Cooldown" })
		return false
	end
	local character = MatchService.CharacterOf(id)
	if not character then
		return false
	end
	smokeReadyAt[id] = now + cfg.Cooldown
	GearService.Reveal(id) -- (not normally possible: the cooldown is longer)
	nextToken += 1
	local token = nextToken
	local smoke: Smoke = { Token = token, Character = character }
	smokes[id] = smoke
	setBodyHidden(character, true)
	-- Something put into the hands while invisible stays invisible too.
	smoke.Added = character.DescendantAdded:Connect(hidePart)

	-- Every outline on the Ninja goes, for every viewer.
	Net.fireAll("Unhighlight", { Id = id })
	local root = MatchService.RootOf(id)
	if root then
		AudioService.At("SmokeBomb", root.CFrame.Position)
		Net.fireAll("Effect", { Kind = "Smoke", At = root.CFrame.Position })
	end
	GearService.Smoked:Fire(id)
	task.delay(cfg.Duration, function()
		local current = smokes[id]
		if current and current.Token == token then
			GearService.Reveal(id)
		end
	end)
	return true
end

-- Any action except knocking shows the Ninja again (called by the services
-- that handle items, abilities and prompts).
function GearService.Acted(id: number)
	if smokes[id] then
		GearService.Reveal(id)
	end
end

--------------------------------------------------------------------------------
-- Hunter: bear traps
--------------------------------------------------------------------------------

local function trapsOf(hunterId: number): { BasePart }
	local list = {}
	for _, trap in trapFolder:GetChildren() do
		if trap:IsA("BasePart") and trap:GetAttribute("OwnerId") == hunterId then
			table.insert(list, trap)
		end
	end
	return list
end

function GearService.TrapsOf(hunterId: number): { BasePart }
	return trapsOf(hunterId)
end

local function groundBelow(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { trapFolder }
	for _, body in CollectionService:GetTagged("MemberBody") do
		table.insert(exclude, body)
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return if hit then hit.Position else position - Vector3.new(0, 3, 0)
end

-- Returns whether a trap was put down.
function GearService.PlaceTrap(id: number): boolean
	local member = MatchService.Roster.Members[id]
	local cfg = Config.Abilities.Hunter
	if not member or not member.Alive or member.Role ~= "Hunter" or not playing() then
		return false
	end
	local now = os.clock()
	if now < (trapReadyAt[id] or 0) then
		tell(id, { Kind = "Cooldown" })
		return false
	end
	if #trapsOf(id) >= cfg.MaxTraps then
		tell(id, { Kind = "TrapsFull" })
		return false
	end
	local root = MatchService.RootOf(id)
	if not root then
		return false
	end
	trapReadyAt[id] = now + cfg.Cooldown
	local look = Config.TrapLook
	local at = groundBelow(root.CFrame.Position)
	local trap = Instance.new("Part")
	trap.Name = "BearTrap"
	trap.Shape = Enum.PartType.Cylinder
	trap.Size = look.Size
	trap.Color = look.Color
	trap.Material = Enum.Material.Metal
	trap.Anchored = true
	trap.CanCollide = false
	trap.CanQuery = false
	trap.CanTouch = false
	trap.CastShadow = false
	-- A cylinder lies along X: turn it flat on the ground.
	trap.CFrame = CFrame.new(at + Vector3.new(0, look.Size.X / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trap:SetAttribute("OwnerId", id)
	trap:AddTag("BearTrap")
	trap.Parent = trapFolder
	local player = MatchService.PlayerOf(id)
	if player then
		AudioService.To(player, "TrapSet")
	end
	return true
end

local function spring(trap: BasePart, victim: Roster.Member)
	local cfg = Config.Abilities.Hunter
	local hunterId = trap:GetAttribute("OwnerId")
	local position = trap.CFrame.Position
	trap:Destroy()
	CombatService.Stun(victim.Id, cfg.StunDuration)
	AudioService.At("TrapSnap", position)
	tell(victim.Id, { Kind = "Trapped" })
	local hunter = if type(hunterId) == "number" then MatchService.PlayerOf(hunterId) else nil
	local hunterMember = if type(hunterId) == "number" then MatchService.Roster.Members[hunterId] else nil
	if hunter and hunterMember and hunterMember.Alive then
		Net.fire(hunter, "Highlight", { Kind = "Trapped", Ids = { victim.Id }, Duration = cfg.HighlightSeconds })
		tell(hunterMember.Id, { Kind = "TrapSprung" })
	end
end

local function scanTraps()
	local traps = trapFolder:GetChildren()
	if #traps == 0 or not MatchService.Started or MatchService.Winner then
		return
	end
	local radius = Config.Abilities.Hunter.TriggerRadius
	for _, member in Roster.alive(MatchService.Roster) do
		if not HidingService.IsHidden(member.Id) then
			local root = MatchService.RootOf(member.Id)
			if root then
				local position = root.CFrame.Position
				for _, trap in traps do
					if trap.Parent and trap:IsA("BasePart") and trap:GetAttribute("OwnerId") ~= member.Id then
						local offset = position - trap.CFrame.Position
						if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= 6 then
							spring(trap, member)
							break
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function GearService.Init()
	trapFolder = Instance.new("Folder")
	trapFolder.Name = "Traps"
	trapFolder.Parent = workspace
end

function GearService.Start()
	-- Finishing any "hold E" prompt is an action; knocking is not.
	Prompts.onAction(function(player: Player, prompt: ProximityPrompt)
		if prompt.Name ~= KNOCK_PROMPT then
			local member = MatchService.MemberOf(player)
			if member then
				GearService.Acted(member.Id)
			end
		end
	end)
	MatchService.MemberDied:Connect(function(member: Roster.Member)
		GearService.Reveal(member.Id)
	end)
	MatchService.BodyReplaced:Connect(function(member: Roster.Member)
		GearService.Reveal(member.Id)
	end)
	MatchService.MemberConverted:Connect(function(member: Roster.Member)
		GearService.Reveal(member.Id)
		-- A Hunter who became the pup has left the role behind: their traps
		-- stay on the ground but belong to nobody (no red outline for the
		-- wolf side, and the pup can step on them like anyone else).
		for _, trap in trapsOf(member.Id) do
			trap:SetAttribute("OwnerId", 0)
		end
	end)
	-- A new phase that moves people or changes wolves (night, morning, the
	-- meeting itself): the smoke is over. Calling the meeting moves nobody.
	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase ~= "MeetingCountdown" then
			for id in table.clone(smokes) do
				GearService.Reveal(id)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Abilities.Hunter.ScanInterval)
			scanTraps()
		end
	end)
end

return GearService
