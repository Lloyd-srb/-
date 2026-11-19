--!strict
--[[
	Config — the single source of every tunable number in Wolf Village.

	Section numbers (§) refer to GDD.md. Tags used in comments:
	  [GDD]      value stated in the GDD
	  [default]  value the GDD marks as a tunable default ([ค่าเริ่มต้น])
	  [ASSUMED]  value NOT in the GDD; a placeholder picked so the game can run.
	             Every [ASSUMED] value is listed for the owner to confirm.

	No other script may contain gameplay numbers. Asset IDs (animations, sounds,
	Robux products) are placeholders (0) until the owner supplies them.
]]

local RunService = game:GetService("RunService")

-- Role ids: "Wolf", "Villager", "Sheriff", "Doctor", "Seer", "Chief",
-- "Bodyguard", "Priest", "Engineer", "PlagueDoctor", "Thief", "Police",
-- "Detective", "Lover", "Killer", "Fool", "FireManiac"
-- (keys of Config.Roles).
export type RoleId = string

-- "Village" | "Wolf" | "Killer" | "Fool" | "FireManiac"
export type Faction = string


export type SpinPrize = {
	Kind: string, -- "Coins" | "Diamonds" | "Role" | "Skin"
	Amount: number?,
	Id: string?,
	Weight: number,
}

export type RoleDef = {
	Faction: Faction,
	-- "Special" roles fill the special slots, "Filler" is the plain villager,
	-- "Solo" roles (Killer, Fool) take a villager slot (§2).
	Kind: "Wolf" | "Special" | "Filler" | "Solo",
	CoinPrice: number,
	RobuxPrice: number, -- also the Diamond price (§13: same number)
	RequiredLevel: number,
	Free: boolean,
	Copies: number?, -- how many players can have it in one match (default 1; Lover 2)
}

-- How many of each kind of role a match of N players has (see Config.Match).
export type ModeDef = {
	Players: number,
	Wolves: number,
	SpecialSlots: number, -- max players holding a "Special" role
	MaxSolo: number, -- max Killer / Fool (they take a villager slot)
}

export type DebugConfig = {
	Enabled: boolean,
	MinPlayers: number,
	FillWithBots: boolean,
	BotBodies: boolean,
	ForceTask: string?,
	UnlockAllRoles: boolean,
	FillTo: number?,
	DoorHitPrompt: boolean,
	ForceRole: RoleId?,
	ForceRoleUserId: number?,
	ForceRoles: { [number]: RoleId }?,
	TimerScale: number,
	SkipRoleSelect: boolean,
}

local Config = {}

--------------------------------------------------------------------------------
-- §2 Players and roles per match (owner's decision, 17 Nov 2026: Turbo removed,
-- one 12-seat mode that can start from 8 players; roles scale with the count)
--------------------------------------------------------------------------------

Config.Match = {
	MinPlayers = 8, -- [owner] a match can start with 8 or more
	MaxPlayers = 12, -- [owner]
	Wolves = 1, -- [GDD]
	-- [default] special roles by player count (about half); villagers fill the rest.
	-- Killer / Fool are not "special": they replace a villager.
	SpecialSlots = { [8] = 4, [9] = 4, [10] = 5, [11] = 5, [12] = 6 },
	BothSoloFrom = 11, -- [owner] Killer and Fool in the same match only with 11-12 players
	ArrivalTimeout = 20, -- [default] seconds the match server waits for teleported players
	HomeAttempts = 3, -- [default] tries to send everyone back to the lobby at the end
	HomeRetryDelay = 10, -- [default] seconds between those tries
}

--------------------------------------------------------------------------------
-- §4 Role selection
--------------------------------------------------------------------------------

Config.RoleSelect = {
	-- [owner] 18 Nov 2026: the 3 roles are chosen in the Lobby (Role page) and
	-- saved; there is no role screen in the match.
	PickCount = 3, -- [GDD] each player picks 3 owned roles
	Duration = 10, -- [ASSUMED] most seconds to wait for saved profiles before day 1
	StarterRoles = { "Villager", "Sheriff", "Doctor" } :: { RoleId }, -- [GDD] free for new players
}

--------------------------------------------------------------------------------
-- §9 / §13.1 Roles: faction, slot kind, prices, level gates
--------------------------------------------------------------------------------

Config.Roles = {
	-- [owner] 18 Nov 2026: every role you buy costs the same as the most
	-- expensive one (5,000 coins / 399 R$ or Diamonds), and no role needs a
	-- level any more (RequiredLevel 1 everywhere).
	Wolf = { Faction = "Wolf", Kind = "Wolf", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Villager = { Faction = "Village", Kind = "Filler", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Sheriff = { Faction = "Village", Kind = "Special", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Doctor = { Faction = "Village", Kind = "Special", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Chief = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Bodyguard = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Seer = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Priest = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Engineer = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	-- [owner] 18 Nov 2026 new roles.
	PlagueDoctor = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Thief = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Police = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Detective = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	-- Two players share this role (Copies = 2); a lone Lover gets a partner
	-- from the players who would have been Villagers.
	Lover = { Faction = "Village", Kind = "Special", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false, Copies = 2 },
	FireManiac = { Faction = "FireManiac", Kind = "Solo", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Killer = { Faction = "Killer", Kind = "Solo", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
	Fool = { Faction = "Fool", Kind = "Solo", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 1, Free = false },
} :: { [RoleId]: RoleDef }

-- Display / iteration order (role screen, scoreboard).
Config.RoleOrder = {
	"Villager",
	"Sheriff",
	"Doctor",
	"Chief",
	"Bodyguard",
	"Seer",
	"Priest",
	"Engineer",
	"PlagueDoctor",
	"Thief",
	"Police",
	"Detective",
	"Lover",
	"Killer",
	"Fool",
	"FireManiac",
} :: { RoleId }

--------------------------------------------------------------------------------
-- §6 Round timers (seconds)
--------------------------------------------------------------------------------

Config.Timers = {
	FirstDay = 180, -- [GDD] day 1, no meeting
	FullMoonWarning = 10, -- [GDD] "Full moon in 10 seconds" (also the 10 s after a meeting)
	Night = 180, -- [GDD]
	Day = 300, -- [GDD] day 2+
	MeetingUnlockAfter = 180, -- [GDD] meeting can be called after 3 min (last 2 min)
	MeetingCountdown = 60, -- [GDD] after someone calls the meeting
	Meeting = 120, -- [GDD] discussion + vote
	-- [ASSUMED] When nobody calls a meeting and the day timer hits 0, the forced
	-- meeting starts immediately (true) or still runs the 1-minute countdown (false).
	ForcedMeetingSkipsCountdown = true,
	GameOverScoreboard = 30, -- [ASSUMED] seconds on the end scoreboard before teleporting to the lobby
	LikeWindow = 20, -- [ASSUMED] the first part of the scoreboard, when likes can be given; then rewards show
}

--------------------------------------------------------------------------------
-- §6.2 Voting
--------------------------------------------------------------------------------

Config.Vote = {
	MeetingsPerDay = 1, -- [GDD]
	DefaultWeight = 1,
	ChiefWeight = 2, -- [GDD] counted twice, but shown as one silhouette ([owner] 17 Nov 2026)
	-- [owner] 17 Nov 2026: nobody is exiled with fewer votes than this (the Chief's
	-- vote counts 2), so one lone vote cannot exile someone.
	MinVotesToExile = 2,
	-- [owner] 17 Nov 2026: in the last seconds every vote is locked (selections are
	-- confirmed) and the Chief's silhouette shows a crown.
	LockBeforeEnd = 5,
	AllowSelfVote = false, -- [ASSUMED]
	ConfirmIsFinal = true, -- [ASSUMED] a confirmed vote cannot be changed
	CallHold = 1, -- [ASSUMED] seconds holding E on the meeting bell
	PendingColor = Color3.fromRGB(150, 150, 150), -- [GDD] gray silhouette
	ConfirmedColor = Color3.fromRGB(80, 160, 255), -- [GDD] blue silhouette
}

--------------------------------------------------------------------------------
-- Humans
--------------------------------------------------------------------------------

Config.Human = {
	WalkSpeed = 16, -- [GDD §8.1]
	MaxHealth = 100, -- wolf = 1 hit, pup = 2 hits
	HideHold = 1, -- [ASSUMED] seconds holding E to hide under a bed / in a wardrobe
	InteractDistance = 10, -- [ASSUMED] studs, ProximityPrompt MaxActivationDistance
	JumpPower = 50, -- Roblox defaults, restored after a freeze
	JumpHeight = 7.2,
}

--------------------------------------------------------------------------------
-- §8.1 Werewolf
--------------------------------------------------------------------------------

Config.Wolf = {
	-- These four come from the monster's stat bars (Config.Monsters, set at
	-- the end of this file): RunSpeed -> WalkSpeed, AttackPower -> AttackDamage,
	-- AttackSpeed -> AttackCooldown, Vision -> NightVision.
	WalkSpeed = 20, -- [GDD]
	AttackDamage = 100, -- [GDD] one hit kills
	AttackCooldown = 2, -- [owner] 18 Nov 2026 (Attack Speed 3); was 1 s in the GDD
	NightVision = 150, -- studs the werewolf sees at night (night fog end)
	AttackRange = 7, -- [ASSUMED] studs
	AttackMinDot = 0, -- [ASSUMED] target must be in the front half (dot of look and direction)
	ForestScanInterval = 0.5, -- seconds between "who is in the forest" updates (§6.4)
	SearchHold = 1, -- [GDD §6.4] hold E on a bed / wardrobe to search it
	Sniff = {
		Duration = 3, -- [GDD]
		Cooldown = 30, -- [GDD]
	},
	Sprint = {
		Speed = 30, -- [GDD]
		Duration = 5, -- [GDD]
		Cooldown = 30, -- [ASSUMED] the GDD gives no cooldown
		MaulDuration = 3, -- [GDD] wolf cannot be stunned while mauling
	},
	DoorDamage = 20, -- [GDD §6.4] 5 hits break a 100 HP door
	KillsPerNight = math.huge, -- [GDD] unlimited
}

--------------------------------------------------------------------------------
-- §8.2 Wolf pup
--------------------------------------------------------------------------------

Config.Pup = {
	MaxPerGame = 1, -- [GDD]
	Scale = 0.6, -- [ASSUMED] size relative to the adult wolf
	WalkSpeed = 20, -- [GDD]
	AttackDamage = 50, -- [GDD] half damage, 2 hits to kill
	AttackCooldown = 1,
	AttackRange = 6, -- [ASSUMED]
	DoorDamage = 10, -- [default] 10 hits per door
	Howl = {
		Radius = 40, -- [default]
		Duration = 10, -- [GDD]
		Cooldown = 30, -- [default]
	},
	PromotionNights = 2, -- [GDD] becomes a full wolf on the 2nd night after the wolf is gone
}

--------------------------------------------------------------------------------
-- Werewolf look (art defaults). The rig is built by build/BuildWolfRig.luau.
--------------------------------------------------------------------------------

Config.WolfRig = {
	Fur = Color3.fromRGB(112, 114, 122),
	FurDark = Color3.fromRGB(76, 78, 88),
	Belly = Color3.fromRGB(150, 152, 160),
	Claw = Color3.fromRGB(235, 232, 220),
	Eye = Color3.fromRGB(255, 221, 51), -- glowing yellow (Neon)
	Nose = Color3.fromRGB(30, 30, 34),
	RunSpeedThreshold = 24, -- faster than this = four-legged run animation
	Height = 9, -- studs from the ground to the ears (block rig and imported mesh)

	--[[
		Optional imported wolf model (owner's "Moonfang Stalker" mesh from Meshy,
		Mixamo-style skeleton). When it has been imported into Studio,
		build/BuildWolfMesh.luau turns it into the rigs used at night; otherwise
		the block rig from build/BuildWolfRig.luau is used.

		Joints / Followers come from analysing the model's skin weights: besides
		the Mixamo bones, the auto-rigger left extra "Bone_0xx" bones that carry
		the claws, mane, snout and tail. Each follows the body part it belongs to.
	]]
	Mesh = {
		ImportName = "WolfMesh", -- ServerStorage.Imports.WolfMesh (the imported model)
		Joints = {
			Torso = "Hips",
			Chest = "Spine1",
			Head = "Head",
			LeftUpperArm = "LeftArm",
			LeftLowerArm = "LeftForeArm",
			RightUpperArm = "RightArm",
			RightLowerArm = "RightForeArm",
			LeftUpperLeg = "LeftUpLeg",
			LeftLowerLeg = "LeftLeg",
			RightUpperLeg = "RightUpLeg",
			RightLowerLeg = "RightLeg",
		},
		-- The model stands in a T-pose: these arms are turned to hang down first.
		ArmJoints = {
			LeftUpperArm = "LeftLowerArm",
			RightUpperArm = "RightLowerArm",
		},
		Followers = {
			-- mane / upper back and chest fur
			Bone_013 = "Spine2",
			Bone_003 = "Spine2",
			Bone_002 = "Spine2",
			Bone_005 = "Spine2",
			Bone_004 = "Spine2",
			Bone_007 = "Spine2",
			Bone_006 = "Spine2",
			Bone_009 = "Spine2",
			Bone_008 = "Spine2",
			-- back of the head, snout and jaw
			Bone_012 = "Head",
			Bone_028 = "Head",
			Bone_027 = "Head",
			Bone_026 = "Head",
			-- right arm, hand and claws
			Bone_031 = "RightArm",
			Bone_030 = "RightForeArm",
			Bone_029 = "RightForeArm",
			Bone_036 = "RightHand",
			Bone_035 = "RightHand",
			Bone_038 = "RightHand",
			Bone_037 = "RightHand",
			-- left arm, hand and claws
			Bone_034 = "LeftArm",
			Bone_033 = "LeftForeArm",
			Bone_032 = "LeftForeArm",
			Bone_040 = "LeftHand",
			Bone_039 = "LeftHand",
			Bone_042 = "LeftHand",
			Bone_041 = "LeftHand",
			-- tail (the rigger hung it under the head)
			Bone_022 = "Hips",
			-- toe claws (the rigger hung them under the hands)
			Bone_043 = "LeftToeBase",
			Bone_044 = "RightToeBase",
		},
		-- Feet stay flat while the legs swing.
		Level = { "LeftFoot", "RightFoot" },
		-- Used to find which way the imported model faces: { foot, toe } pairs.
		Feet = { { "LeftFoot", "LeftToeBase" }, { "RightFoot", "RightToeBase" } },
	},
}

--------------------------------------------------------------------------------
-- Hiding (§6.4)
--------------------------------------------------------------------------------

-- [owner] 18 Nov 2026: boots from the watering task, worn for the rest of the
-- match: +3 walking speed. [ASSUMED] in human form only (the werewolf keeps
-- its own speed), and a second pair does not add more.
Config.Boots = {
	SpeedBonus = 3,
}

Config.Hiding = {
	-- Hidden players' bodies are parked here, far from the map, so nobody
	-- (including exploiters) can tell which spot they are hiding in.
	HoldingHeight = 2000,
	HoldingSpacing = 30,
}

--------------------------------------------------------------------------------
-- §6.4 Doors
--------------------------------------------------------------------------------

Config.Door = {
	MaxHP = 100,
	ReinforceMultiplier = 2, -- [GDD §9 Engineer]
	HitCooldown = 1, -- same swing cooldown as the wolf attack
	HitRange = 8, -- [ASSUMED]
	OpenHold = 0.5, -- [ASSUMED] owner / killer hold-E to open
	OpenTweenTime = 0.4,
	UsableByDay = false, -- [ASSUMED] houses stay shut during the day
}

--------------------------------------------------------------------------------
-- §9 Role abilities
--------------------------------------------------------------------------------

Config.Abilities = {
	Sheriff = {
		StunDuration = 5, -- [GDD]
		ShotsPerPhase = 1, -- [GDD] once per day and once per night
		Range = 120, -- [ASSUMED]
		MuzzleHeight = 1.5, -- [ASSUMED] shot origin above the character's centre
	},
	Doctor = {
		RevivesPerGame = 1, -- [GDD] extra revives consume a First aid
		ReviveHold = 3, -- [ASSUMED]
	},
	Seer = {
		Duration = 5, -- [GDD]
		UsesPerNight = 1, -- [GDD]
	},
	Villager = {
		-- The villager's flashlight (GDD §9) uses Config.Items.Flashlight.
		ToggleCooldown = 0.3,
	},
	Bodyguard = {
		Cooldown = 30, -- [GDD]
		StunDuration = 5, -- [GDD]
		DashDistance = 24, -- [ASSUMED]
		DashSpeed = 80, -- [ASSUMED]
		HitRadius = 4, -- [ASSUMED] how close to the dash path a wolf must be
	},
	Priest = {
		BlessingsPerMorning = 1, -- [GDD]
		BlocksPerBlessing = 1, -- [GDD]
	},
	Engineer = {
		UsesPerDay = 1, -- [GDD]
		UsesPerNight = 1, -- [GDD]
		ReinforceHold = 2, -- [ASSUMED]
	},
	-- [owner] 18 Nov 2026: starts with a red potion (3 uses), once by day and
	-- once by night. On a living player: they die the next night. On a body: it
	-- gets up at once. The potion's victims can never get up again.
	PlagueDoctor = {
		PotionUses = 3, -- [owner]
		UsesPerPhase = 1, -- [owner] 1 by day + 1 by night
		Reach = 7, -- [ASSUMED] studs to the person / body
		MinDot = 0, -- [ASSUMED] the person must be in front
	},
	-- [owner] 18 Nov 2026: by day, hold E on anyone to steal one random item
	-- (never an item that came with a role).
	Thief = {
		StealsPerDay = 1, -- [ASSUMED] the owner gave no limit
		StealHold = 1.5, -- [ASSUMED]
	},
	-- [owner] 18 Nov 2026: handcuffs. By day, use them on someone: that person
	-- cannot leave their house the coming night (cannot open their own door).
	-- No effect on the main wolf; works on the pup.
	Police = {
		UsesPerDay = 1, -- [ASSUMED] the owner gave no limit
		Reach = 7, -- [ASSUMED]
		MinDot = 0, -- [ASSUMED] the person must be in front
	},
	-- [owner] 18 Nov 2026: magnifying glass. Each morning, use it on someone:
	-- white aura = stayed home last night, yellow = was out. Only the
	-- Detective sees it; it fades after 10 s. The same person again is fine.
	Detective = {
		UsesPerDay = 1, -- [owner] "every morning"
		AuraSeconds = 10, -- [owner]
		Reach = 7, -- [ASSUMED]
		MinDot = 0, -- [ASSUMED]
		ScanInterval = 1, -- [ASSUMED] how often the night is checked (who is out of their house)
	},
	-- [owner] 18 Nov 2026: oil every house (all different) and win the next
	-- morning. Hold E right next to a house wall; 1 by day + 1 by night.
	FireManiac = {
		UsesPerPhase = 1, -- [owner]
		Hold = 2, -- [ASSUMED] seconds holding E
		WallReach = 4, -- [ASSUMED] studs from the wall for the prompt to show
		PromptSpacing = 7, -- [ASSUMED] studs between prompts along a wall
	},
	Killer = {
		KillsPerDay = 1, -- [GDD]
		KillsPerNight = 1, -- [GDD]
		KnifeRange = 6, -- [ASSUMED]
		MinDot = 0, -- [ASSUMED] target must be in the front half
		KnifeDamage = 100, -- [GDD] one hit kills
	},
}

--------------------------------------------------------------------------------
-- §10 Tasks
--------------------------------------------------------------------------------

Config.Tasks = {
	CoinReward = 20, -- [GDD] per finished task, win or lose
	RepairDoor = { Hold = 10 }, -- [GDD] only offered if a door was broken last night [default]
	PlantCarrot = { Hold = 10, Reward = "Shovel" }, -- [GDD]
	PickApples = { Trees = 3, HoldPerTree = 2, Reward = "Apple", RewardCount = 1 }, -- [GDD]
	ChopTrees = { Trees = 2, HoldPerTree = 4, Reward = "Axe" }, -- [GDD]
	-- [owner] 18 Nov 2026: fetch water at the stream, then water a carrot plot -> boots.
	WaterCarrots = { FetchHold = 3, WaterHold = 5, Perk = "Boots" }, -- holds [ASSUMED]
	-- [owner] 18 Nov 2026: cast a line into the stream, wait 10 s -> a fish.
	Fishing = { Hold = 10, Reward = "Fish" },
	Kinds = { "RepairDoor", "PlantCarrot", "PickApples", "ChopTrees", "WaterCarrots", "Fishing" },
}

--------------------------------------------------------------------------------
-- §11 Items and crate
--------------------------------------------------------------------------------

Config.Items = {
	Shovel = { StunDuration = 3, Uses = 1, Range = 6 }, -- range [ASSUMED]
	Apple = { SpeedBonus = 0.30, Duration = 5, Uses = 1 },
	Axe = { StunDuration = 5, Uses = 2, ThrowSpeed = 90, ThrowRange = 80 }, -- speed/range [ASSUMED]
	Gun = { StunDuration = 5, ShotsPerPhase = 1, MaxPerPlayer = 1, Range = 120 }, -- same as the sheriff gun
	FirstAid = { Uses = 1 }, -- heal to full; the Doctor can spend it on an extra revive
	Cross = { Blocks = 1 },
	Flashlight = { Range = 45, Angle = 60, Brightness = 2 }, -- [ASSUMED]
	-- [owner] 18 Nov 2026: the Plague Doctor's red potion (a role item: never dropped or stolen).
	Potion = { Uses = 3, RoleItem = true },
	-- [owner] 18 Nov 2026: role items of the Police, the Detective and the Fire Maniac.
	Handcuffs = { RoleItem = true },
	Magnifier = { RoleItem = true },
	OilCan = { RoleItem = true },
	-- [owner] 18 Nov 2026: from fishing. Put it on the ground: at night the monster
	-- side sees a red aura there, as if a person were standing on that spot.
	Fish = { Uses = 1 },
	PickupHold = 0.5, -- [ASSUMED] hold E on an item on the ground
	DropSpread = 2.5, -- studs between items dropped in one place
	MinDot = 0, -- shovel: target must be in the front half
}

-- How items look: in the hand (Tool handle) and on the ground. Art defaults.
Config.ItemLook = {
	Shovel = { Color = Color3.fromRGB(150, 150, 160), Size = Vector3.new(0.4, 3.2, 0.4) },
	Apple = { Color = Color3.fromRGB(220, 40, 40), Size = Vector3.new(0.8, 0.8, 0.8) },
	Axe = { Color = Color3.fromRGB(150, 105, 60), Size = Vector3.new(0.4, 2.4, 0.4) },
	Gun = { Color = Color3.fromRGB(50, 50, 58), Size = Vector3.new(0.4, 0.6, 1.4) },
	FirstAid = { Color = Color3.fromRGB(240, 240, 240), Size = Vector3.new(1, 0.7, 0.7) },
	Cross = { Color = Color3.fromRGB(240, 200, 70), Size = Vector3.new(0.3, 1.4, 0.3) },
	Flashlight = { Color = Color3.fromRGB(240, 210, 60), Size = Vector3.new(0.4, 0.4, 1.2) },
	Potion = { Color = Color3.fromRGB(210, 30, 40), Size = Vector3.new(0.6, 1, 0.6) }, -- red bottle
	Handcuffs = { Color = Color3.fromRGB(190, 195, 205), Size = Vector3.new(0.9, 0.2, 0.5) },
	Magnifier = { Color = Color3.fromRGB(150, 110, 60), Size = Vector3.new(0.3, 1.2, 0.3) },
	OilCan = { Color = Color3.fromRGB(200, 60, 40), Size = Vector3.new(0.9, 1.1, 0.6) },
	Fish = { Color = Color3.fromRGB(120, 170, 210), Size = Vector3.new(0.5, 0.4, 1.4) },
}

-- Crates sit under a forest tree until someone opens them (GDD §6.1).
Config.CrateLook = {
	Color = Color3.fromRGB(150, 100, 55),
	Size = Vector3.new(2.6, 2.2, 2.6),
}

Config.Crate = {
	MorningSpawnChance = 0.30, -- [GDD §6.1]
	OpenHold = 1, -- [ASSUMED]
	-- [GDD] weights in percent (sum = 100)
	Loot = {
		{ Item = "Gun", Weight = 5 },
		{ Item = "FirstAid", Weight = 19 },
		{ Item = "Cross", Weight = 19 },
		{ Item = "Axe", Weight = 19 },
		{ Item = "Shovel", Weight = 19 },
		{ Item = "Flashlight", Weight = 19 },
	},
}

-- Roles that may never hold a gun (§9, §11).
Config.GunForbiddenRoles = { Killer = true } :: { [string]: boolean }

--------------------------------------------------------------------------------
-- §13 Economy
--------------------------------------------------------------------------------

Config.Rewards = {
	CoinsPerNight = 20, -- [GDD]
	ExpPerNight = 50, -- [GDD]
	LoseMultiplier = 0.5, -- [GDD]
	SoloWinMultiplier = 1.5, -- [GDD] Killer / Fool win
	MvpMultiplier = 1.2, -- [GDD]
}

Config.PlayerLevel = {
	ExpPerLevel = 300, -- [default]
	StartLevel = 1,
}

Config.Mastery = {
	PointsPerMastery = 20, -- [GDD]
	WinPoints = 2, -- [GDD]
	LosePoints = 1, -- [GDD]
	DiamondsPerMastery = 20, -- [GDD]
}

Config.CoinPacks = {
	{ Coins = 500, Robux = 49 },
	{ Coins = 1200, Robux = 99 },
	{ Coins = 2600, Robux = 199 },
	{ Coins = 7000, Robux = 499 },
}

--------------------------------------------------------------------------------
-- §13.2 Season Pass
--------------------------------------------------------------------------------

Config.SeasonPass = {
	WinExp = 150, -- [GDD]
	LoseExp = 50, -- [GDD]
	MainLevels = 60, -- [GDD]
	ExpPerLevel = 200, -- [GDD] levels 1-60
	ExpPerLevelAfterMain = 1000, -- [GDD] levels 61+
	PremiumBonusLevels = 10, -- [GDD]
	DiamondLevels = { 5, 15, 25, 35, 45, 55 }, -- [GDD]
	DiamondLevelAmount = 20, -- [GDD]
	SpinLevels = { 10, 20, 30, 40, 50 }, -- [GDD]
	FreeCoinAmount = 50, -- [GDD] every other free level, and every free level after 60
	PremiumDiamondAmount = 10, -- [GDD] after 60; [ASSUMED] also used for the pre-60 slots
	-- [ASSUMED] not in the GDD (OWNER_TODO 15): a suggestion until the owner
	-- sets the price. Also the Diamond price (§13: same number).
	PremiumRobuxPrice = 499, -- [owner] 18 Nov 2026
	-- Titles on level 1 of each track (GDD §13.2: "Title พิเศษ").
	FreeTitle = "PassFree",
	PremiumTitle = "PassPremium",
}

--------------------------------------------------------------------------------
-- §13.3 Daily Spin
--------------------------------------------------------------------------------

Config.DailySpin = {
	FreeSpinsPerDay = 1, -- [GDD]
	-- [GDD] weights in percent (sum = 100)
	Prizes = {
		-- [owner] 17 Nov 2026: Diamond prizes halved (10 / 25 / 50 / 100, was 20 / 50 / 100 / 200)
		-- so the free spin gives about 7 diamonds a day instead of 14. Odds unchanged.
		{ Kind = "Coins", Amount = 20, Weight = 30 },
		{ Kind = "Diamonds", Amount = 10, Weight = 15 },
		{ Kind = "Coins", Amount = 50, Weight = 22 },
		{ Kind = "Diamonds", Amount = 25, Weight = 8 },
		{ Kind = "Coins", Amount = 100, Weight = 12 },
		{ Kind = "Diamonds", Amount = 50, Weight = 4 },
		{ Kind = "Coins", Amount = 200, Weight = 6 },
		{ Kind = "Diamonds", Amount = 100, Weight = 1.5 },
		{ Kind = "Role", Id = "Killer", Weight = 1 },
		{ Kind = "Skin", Id = "WolfSpin", Weight = 0.5 },
	} :: { SpinPrize },
	DuplicateRoleCoins = 2500, -- [GDD] already own Killer
	DuplicateSkinDiamonds = 100, -- [owner] halved with the other Diamond prizes (was 200 [default])
	ResetHourUtc = 0, -- [ASSUMED] OWNER_TODO 20: the free spin comes back at 00:00 UTC (07:00 Thai time)
}

--------------------------------------------------------------------------------
-- §13 Skins and titles (cosmetic only, never change gameplay)
--   Slot "Gun"   colour of the stun-gun shot and the gun item
--   Slot "Knife" colour of the Killer's slash
--   Slot "Wolf"  colours of the werewolf body (keys of Config.WolfRig)
--   Source "Shop" = sold for Price Robux or the same number of Diamonds;
--   "Pass" / "Spin" = only from the Season Pass / Daily Spin.
--------------------------------------------------------------------------------

export type SkinDef = {
	Slot: "Gun" | "Knife" | "Wolf",
	Source: "Shop" | "Pass" | "Spin",
	Rarity: ("Rare" | "Epic" | "Legendary")?, -- Source "Shop": sets the price (Config.SkinRarityPrice)
	Price: number?, -- Robux / Diamonds (Source "Shop" only; filled from Rarity)
	Color: Color3?, -- Gun / Knife
	Paint: { [string]: Color3 }?, -- Wolf: overrides Config.WolfRig colours
}

Config.Skins = {
	-- [GDD] §13.2 / §13.3 (the looks are [ASSUMED] art choices)
	GunPass = { Slot = "Gun", Source = "Pass", Color = Color3.fromRGB(120, 230, 255) },
	KnifePass = { Slot = "Knife", Source = "Pass", Color = Color3.fromRGB(120, 230, 255) },
	WolfPass = {
		Slot = "Wolf",
		Source = "Pass",
		Paint = { Fur = Color3.fromRGB(236, 236, 242), FurDark = Color3.fromRGB(190, 196, 210), Eye = Color3.fromRGB(90, 200, 255) },
	},
	WolfSpin = {
		Slot = "Wolf",
		Source = "Spin",
		Paint = { Fur = Color3.fromRGB(150, 60, 40), FurDark = Color3.fromRGB(100, 36, 28), Eye = Color3.fromRGB(255, 90, 40) },
	},
	-- [ASSUMED] OWNER_TODO 19: example shop skins until the owner sends the real list and prices.
	GunGold = { Slot = "Gun", Source = "Shop", Rarity = "Rare", Color = Color3.fromRGB(255, 200, 60) },
	KnifeGold = { Slot = "Knife", Source = "Shop", Rarity = "Rare", Color = Color3.fromRGB(255, 200, 60) },
	WolfShadow = {
		Slot = "Wolf",
		Source = "Shop",
		Rarity = "Epic",
		Paint = { Fur = Color3.fromRGB(40, 40, 48), FurDark = Color3.fromRGB(24, 24, 30), Belly = Color3.fromRGB(60, 60, 70), Eye = Color3.fromRGB(190, 80, 255) },
	},
} :: { [string]: SkinDef }

-- [owner] 18 Nov 2026: shop skins are priced by rarity (Robux = Diamonds).
Config.SkinRarityPrice = { Rare = 99, Epic = 199, Legendary = 399 }
for _, def in Config.Skins do
	if def.Source == "Shop" and def.Rarity then
		def.Price = Config.SkinRarityPrice[def.Rarity]
	end
end

-- Shop / menu order.
Config.SkinOrder = { "GunGold", "KnifeGold", "WolfShadow", "GunPass", "KnifePass", "WolfPass", "WolfSpin" }

-- Players this close see the Killer's slash (its colour is the knife skin).
Config.SlashViewRadius = 60 -- [ASSUMED] studs

-- Without a skin.
Config.DefaultLook = {
	Gun = Color3.fromRGB(255, 240, 120), -- [ASSUMED] art
	Knife = Color3.fromRGB(230, 230, 235), -- [ASSUMED] art
}

-- Titles a player can show over their head in the lobby.
Config.Titles = { "PassFree", "PassPremium" }

--------------------------------------------------------------------------------
-- §3 / §13 Codes: the list itself is secret (clients can read this module),
-- so it lives in ServerStorage.ServerShared.CodeList.
--------------------------------------------------------------------------------

Config.CodeMaxLength = 32
-- [ASSUMED] after this many wrong codes in a row, a player must wait before trying again
-- (so nobody can guess codes by trying thousands of words).
Config.CodeMaxWrong = 8
Config.CodeLockSeconds = 300

--------------------------------------------------------------------------------
-- §13 Shop rules
--------------------------------------------------------------------------------

Config.Shop = {
	-- [ASSUMED] OWNER_TODO 66: a role can only be bought once its level is reached
	-- (nobody pays for a role they cannot use yet). The Daily Spin can still
	-- give the Killer early; it becomes usable at its level.
	LevelGateForBuying = true,
	-- [ASSUMED] a Robux purchase of something already owned (two quick
	-- clicks) gives its price back as Diamonds instead.
	RefundDuplicatesAsDiamonds = true,
}

--------------------------------------------------------------------------------
-- Fair play (owner, 17 Nov 2026)
--------------------------------------------------------------------------------

-- Speed / teleport check (MovementGuard). [ASSUMED] tuning values.
Config.AntiCheat = {
	Enabled = true,
	InStudio = false, -- Studio testers teleport on purpose
	Interval = 0.5, -- seconds between checks
	Tolerance = 1.4, -- allowed speed x this (lag, slopes)
	Slack = 6, -- studs always allowed on top
	WarpGrace = 1.5, -- seconds after a move made by the game
}

-- AFK: a night where a player did nothing at all (did not walk, press a
-- "hold" prompt, use any button or type in chat) does not count as a night
-- survived. Hiding under a bed is a plan, not AFK: pressing "hide" counts.
Config.Afk = {
	Enabled = true,
	MoveStuds = 1, -- walking at least this far in one check counts as doing something
}

--------------------------------------------------------------------------------
-- Saving (DataStore profiles with session locking)
--------------------------------------------------------------------------------

Config.Data = {
	StoreName = "Profiles_v1",
	StudioStoreName = "Profiles_Studio", -- Studio never touches the live data
	KeyPrefix = "Player_",
	AutoSaveInterval = 60, -- seconds; each save also renews this server's lock
	-- A lock not renewed for this long belongs to a server that crashed.
	LockStaleAfter = 300,
	-- Another server still holds the lock (the player just came from there):
	-- try again every few seconds; after LoadTimeout take the lock over.
	LoadRetryDelay = 2,
	LoadTimeout = 30,
	MaxAttempts = 5, -- tries per DataStore call (waits 1, 2, 4, 8 s in between)
	ReceiptHistory = 100, -- purchase ids remembered per player (no double grants)
}

--------------------------------------------------------------------------------
-- Map dimensions (studs). Read by build/BuildVillage.luau and by zone checks.
-- Layout from GDD §5; every number here is an art default, not a game rule.
--------------------------------------------------------------------------------

Config.Map = {
	HouseCount = 12, -- [GDD]
	PlazaRadius = 30,
	MeetingSpotRadius = 13, -- where players stand around the table
	HouseRingRadius = 64, -- house centre distance from the plaza centre
	GardenRingRadius = 82,
	FenceRadius = 96, -- inside = "village", outside = "forest" (§5)
	FenceGateCount = 4,
	ForestOuterRadius = 200, -- invisible wall
	OuterForestRadius = 250, -- dense dark forest beyond the wall
	TaskTreeCount = 44,
	-- [owner] 19 Nov 2026 (from the owner's drawing): a wide river fills the
	-- top-right (north-east) of the map, past the edge of the forest, with a
	-- wooden pier to walk out on (fetch water, fishing). The shore is a gentle
	-- curve: part of a huge circle whose centre lies far outside the map.
	River = {
		Angle = math.rad(45), -- direction of the river from the plaza (0 = north / -Z, clockwise)
		ShoreDistance = 128, -- [owner drawing] studs from the plaza to the nearest shore (the pier)
		Curve = 333, -- radius of the shore's curve (bigger = straighter shore)
		BeachWidth = 4, -- sand strip along the water
		PierLength = 30, -- [ASSUMED] studs the pier reaches out over the water
		PierWidth = 6, -- [ASSUMED]
	},
	Seed = 20261116, -- deterministic prop placement
}

--------------------------------------------------------------------------------
-- Lighting presets (§6.5): bright by day, black distance fog at night.
--------------------------------------------------------------------------------

-- [owner] 18 Nov 2026: at nightfall and in the morning every living player
-- except the wolf side sees a black screen ("eyes closed") while being moved.
Config.EyesClosed = {
	Seconds = 3, -- [owner] about 3 s in all
	FadeIn = 0.15, -- [ASSUMED] art
	FadeOut = 0.6, -- [ASSUMED] art
}

Config.Lighting = {
	TransitionTime = 4, -- seconds to tween between presets
	Day = {
		ClockTime = 13.5,
		Brightness = 3,
		Ambient = Color3.fromRGB(140, 140, 140),
		OutdoorAmbient = Color3.fromRGB(150, 150, 150),
		FogColor = Color3.fromRGB(190, 225, 255),
		FogStart = 250,
		FogEnd = 1200,
		ExposureCompensation = 0.1,
		Saturation = 0.15,
		Contrast = 0.05,
		TintColor = Color3.fromRGB(255, 252, 240),
	},
	Night = {
		ClockTime = 0,
		Brightness = 0.6,
		Ambient = Color3.fromRGB(28, 30, 48),
		OutdoorAmbient = Color3.fromRGB(34, 38, 60),
		FogColor = Color3.fromRGB(0, 0, 0),
		FogStart = 25,
		FogEnd = 150,
		ExposureCompensation = -0.35,
		Saturation = -0.25,
		Contrast = 0.15,
		TintColor = Color3.fromRGB(190, 200, 255),
	},
}

--------------------------------------------------------------------------------
-- Highlights (always created client-side, only for allowed viewers)
--------------------------------------------------------------------------------

Config.Highlights = {
	ForestTarget = Color3.fromRGB(255, 40, 40), -- §6.4 players in the forest, wolf side only
	Sniff = Color3.fromRGB(255, 120, 40), -- §8.1
	Howl = Color3.fromRGB(255, 40, 40), -- §8.2
	Seer = Color3.fromRGB(255, 255, 255), -- §9
	StayedHome = Color3.fromRGB(255, 255, 255), -- [owner] Detective: was home last night
	WasOut = Color3.fromRGB(255, 220, 40), -- [owner] Detective: was out last night
	Lover = Color3.fromRGB(255, 255, 255), -- [owner] each Lover sees the other
}

--------------------------------------------------------------------------------
-- Chat channels (§6.2, §12)
--------------------------------------------------------------------------------

Config.Chat = {
	General = "General",
	Wolf = "Wolf",
	Ghost = "Ghost",
	GhostColor = Color3.fromRGB(150, 150, 150), -- ghosts type in gray
	AnnouncementColor = Color3.fromRGB(255, 60, 60), -- red morning announcement
}

--------------------------------------------------------------------------------
-- Networking: default remote rate limit (per player, per remote)
--------------------------------------------------------------------------------

Config.Net = {
	DefaultRate = 10, -- calls allowed...
	DefaultWindow = 5, -- ...per this many seconds
}

--------------------------------------------------------------------------------
-- Asset placeholders — 0 means "not supplied yet" (silent / tween fallback)
--------------------------------------------------------------------------------

Config.Animations = {
	WolfWalk = 0,
	WolfRun = 0,
	WolfAttack = 0,
	WolfMaul = 0,
	WolfHowl = 0,
}

Config.Sounds = {
	WolfHowl = 0,
	FullMoonSting = 0,
	DoorHit = 0,
	DoorBreak = 0,
	DoorOpen = 0,
	DeathScream = 0,
	WolfAttack = 0,
	WolfMaul = 0,
	WolfGrowl = 0,
	Crickets = 0,
	Owl = 0,
	NightMusic = 0,
	DayAmbience = 0,
	MorningRooster = 0,
	MeetingBell = 0,
	VoteSelect = 0,
	VoteConfirm = 0,
	Exile = 0,
	Gunshot = 0,
	StunHit = 0,
	AxeThrow = 0,
	KnifeStab = 0,
	BodyguardDash = 0,
	Revive = 0,
	Blessing = 0,
	BlessingBreak = 0,
	Reinforce = 0,
	AppleEat = 0,
	TreeChop = 0,
	Digging = 0,
	ItemPickup = 0,
	CrateOpen = 0,
	TaskComplete = 0,
	UIClick = 0,
	UIOpen = 0,
	Purchase = 0,
	SpinTick = 0,
	SpinWin = 0,
	PotionUse = 0, -- the Plague Doctor's potion
	Cuff = 0, -- the Police locks someone in
	Inspect = 0, -- the Detective's magnifying glass
	OilPour = 0, -- the Fire Maniac pours oil on a house
	Steal = 0, -- the Thief takes something
	WaterFetch = 0, -- filling the bucket at the stream
	FishCatch = 0, -- a fish bites
	RoleRollTick = 0, -- each icon passing the middle of the role reveal
	RoleReveal = 0, -- the reveal stops on your role
	WinJingle = 0,
	LoseJingle = 0,
}

-- How sounds are played (IDs above). A sound that happens somewhere in the
-- world is only sent to players this close, so nobody learns from a far-away
-- door hit or scream where the wolf is (GDD §6.5). [ASSUMED] art values.
Config.Audio = {
	DefaultVolume = 0.6,
	DefaultRadius = 80, -- studs
	Volume = {
		NightMusic = 0.25,
		Crickets = 0.3,
		DayAmbience = 0.3,
		Owl = 0.45,
		UIClick = 0.35,
		SpinTick = 0.3,
	} :: { [string]: number },
	Radius = {
		DoorHit = 70,
		DoorBreak = 90,
		DoorOpen = 40,
		DeathScream = 150,
		WolfAttack = 50,
		WolfMaul = 60,
		WolfHowl = 300,
		Gunshot = 160,
		StunHit = 60,
		AxeThrow = 60,
		KnifeStab = 60,
		BodyguardDash = 50,
		Revive = 50,
		Reinforce = 50,
		TreeChop = 50,
		Digging = 40,
		CrateOpen = 40,
	} :: { [string]: number },
	Loops = { NightMusic = true, Crickets = true, DayAmbience = true } :: { [string]: boolean },
	OwlEvery = { 20, 45 }, -- seconds between owl hoots at night (random in this range)
}

Config.Products = {
	-- Developer Products, granted through MarketplaceService.ProcessReceipt.
	-- One-time items (roles, premium pass) are stored in the player's profile, so
	-- they can also be bought with Diamonds at the same number (GDD §13).
	DevProducts = {
		SeasonPassPremium = 0,
		Coins500 = 0,
		Coins1200 = 0,
		Coins2600 = 0,
		Coins7000 = 0,
		RoleChief = 0,
		RoleBodyguard = 0,
		RoleSeer = 0,
		RolePriest = 0,
		RoleEngineer = 0,
		RolePlagueDoctor = 0,
		RoleThief = 0,
		RolePolice = 0,
		RoleDetective = 0,
		RoleLover = 0,
		RoleFireManiac = 0,
		RoleKiller = 0,
		RoleFool = 0,
		SkinGunGold = 0,
		SkinKnifeGold = 0,
		SkinWolfShadow = 0,
	} :: { [string]: number },
}

--------------------------------------------------------------------------------
-- Places (one experience, two places). 0 = not set up yet (milestone 8).
--------------------------------------------------------------------------------

-- The Lobby's Monster page (owner's design, 18 Nov 2026). Only the werewolf
-- exists; the other slots show "?" until new monsters come. Stats are 1-5
-- bars shown on the page (display only); Image = an uploaded picture
-- (0 = the drawn portrait).
-- [owner] 18 Nov 2026: the stat bars on the Monster page are real. Each bar
-- is a level 1-5 and each level is a number in the game (MonsterStatValues).
-- Level 3 = the GDD's werewolf; Attack Power 5 = 100 damage (one hit kills).
Config.MonsterStatValues = {
	RunSpeed = { 16, 18, 20, 22, 24 }, -- [ASSUMED] walk speed (people: 16); level 3 = 20 [GDD]
	AttackPower = { 20, 40, 60, 80, 100 }, -- [ASSUMED] damage per hit (people: 100 HP); level 5 = 100 [owner]
	AttackSpeed = { 3, 2.5, 2, 1.5, 1 }, -- [owner] 18 Nov 2026: seconds between attacks
	Vision = { 90, 120, 150, 180, 210 }, -- [ASSUMED] studs seen at night; level 3 = 150 (same as people)
} :: { [string]: { number } }

Config.Monsters = {
	{
		Id = "Werewolf",
		Stats = { RunSpeed = 3, AttackPower = 5, AttackSpeed = 3, Vision = 3 }, -- [owner] 18 Nov 2026
		Image = 0,
	},
}
Config.MonsterLockedSlots = 2

Config.Places = {
	LobbyPlaceId = 0,
	MatchPlaceId = 0,
}

--------------------------------------------------------------------------------
-- §3 Lobby: queue pads (owner's decision, 17 Nov 2026)
--------------------------------------------------------------------------------

Config.Lobby = {
	PadCount = 4, -- [owner] four pads, 12 seats each (Config.Match.MaxPlayers)
	FullCountdown = 10, -- [owner] seconds once the pad is full; nobody can step off
	ReadyCountdown = 20, -- [owner] 18 Nov 2026: with 8-11 players the match starts by itself after this; restarts on join / leave
	ScanInterval = 0.25, -- seconds between "who stands on which pad" checks
	LaunchAttempts = 2, -- teleport tries before giving up
	ReturnCheck = 15, -- seconds after a teleport: anyone still here means it failed
	PadSize = Vector3.new(14, 1, 14), -- art
	PadColors = {
		Color3.fromRGB(110, 200, 255),
		Color3.fromRGB(255, 170, 90),
		Color3.fromRGB(150, 230, 120),
		Color3.fromRGB(230, 130, 230),
	},
}

--------------------------------------------------------------------------------
-- Debug (Studio only). Lets one developer start and test a match alone.
--------------------------------------------------------------------------------

Config.Debug = {
	Enabled = RunService:IsStudio(),
	MinPlayers = 1, -- start a match with fewer players than the mode needs
	FillWithBots = true, -- fill the empty seats with idle bots so votes / win checks work
	BotBodies = true, -- bots get a simple dummy body the wolf can chase and attack
	ForceTask = nil, -- e.g. "PickApples": everyone gets this task (if it is available that day)
	UnlockAllRoles = true, -- every role is owned and level gates are ignored
	FillTo = nil, -- bots fill the match up to this many seats (nil = Config.Match.MaxPlayers)
	DoorHitPrompt = true, -- adds a "hit door" prompt at night to test door HP without a wolf
	ForceRole = nil, -- e.g. "Wolf" to always get that role
	ForceRoleUserId = nil, -- nil = the first player in the server
	ForceRoles = nil, -- several at once: { [UserId] = "Sheriff", ... } (bots: -1004 .. -1012)
	TimerScale = 1, -- e.g. 0.1 makes every timer 10x shorter
	SkipRoleSelect = false,
} :: DebugConfig

-- The werewolf's numbers come from its stat bars (owner, 18 Nov 2026).
function Config.monsterStat(monsterId: string, key: string): number
	for _, monster in Config.Monsters do
		if monster.Id == monsterId then
			local level = math.clamp((monster.Stats :: any)[key] or 3, 1, 5)
			return Config.MonsterStatValues[key][level]
		end
	end
	return Config.MonsterStatValues[key][3]
end
Config.Wolf.WalkSpeed = Config.monsterStat("Werewolf", "RunSpeed")
Config.Wolf.AttackDamage = Config.monsterStat("Werewolf", "AttackPower")
Config.Wolf.AttackCooldown = Config.monsterStat("Werewolf", "AttackSpeed")
Config.Wolf.NightVision = Config.monsterStat("Werewolf", "Vision")

return Config
