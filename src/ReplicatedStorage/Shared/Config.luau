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
-- "Bodyguard", "Monk", "Engineer", "Killer", "Fool" (keys of Config.Roles).
export type RoleId = string

-- "Village" | "Wolf" | "Killer" | "Fool"
export type Faction = string

-- "Casual" | "Turbo" (keys of Config.Modes)
export type ModeId = string

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
}

export type ModeDef = {
	Players: number,
	Wolves: number,
	SpecialSlots: number, -- max players holding a "Special" role
	AllowVillager: boolean, -- plain villagers fill whatever is left
	AllowSolo: boolean, -- Killer / Fool may appear (they take a villager slot)
}

export type DebugConfig = {
	Enabled: boolean,
	MinPlayers: number,
	FillWithBots: boolean,
	BotBodies: boolean,
	DoorHitPrompt: boolean,
	ForceRole: RoleId?,
	ForceRoleUserId: number?,
	TimerScale: number,
	SkipRoleSelect: boolean,
}

local Config = {}

--------------------------------------------------------------------------------
-- §2 Game modes
--------------------------------------------------------------------------------

Config.Modes = {
	-- [GDD] 1 wolf + up to 6 special + villagers as filler (5 when all special slots
	-- are used). Killer / Fool are not "special": they replace a villager slot.
	Casual = { Players = 12, Wolves = 1, SpecialSlots = 6, AllowVillager = true, AllowSolo = true } :: ModeDef,
	-- [GDD] 1 wolf + 5 special, nobody is a plain villager.
	-- [ASSUMED] no villager slots means Killer / Fool cannot appear in Turbo.
	Turbo = { Players = 6, Wolves = 1, SpecialSlots = 5, AllowVillager = false, AllowSolo = false } :: ModeDef,
}

-- Used by the Match place when there is no TeleportData (Studio testing).
Config.DefaultMode = "Casual" :: ModeId

--------------------------------------------------------------------------------
-- §4 Role selection
--------------------------------------------------------------------------------

Config.RoleSelect = {
	PickCount = 3, -- [GDD] each player picks 3 owned roles
	Duration = 30, -- [ASSUMED] seconds on the role-selection screen
	StarterRoles = { "Villager", "Sheriff", "Doctor" } :: { RoleId }, -- [GDD] free for new players
}

--------------------------------------------------------------------------------
-- §9 / §13.1 Roles: faction, slot kind, prices, level gates
--------------------------------------------------------------------------------

Config.Roles = {
	Wolf = { Faction = "Wolf", Kind = "Wolf", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Villager = { Faction = "Village", Kind = "Filler", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Sheriff = { Faction = "Village", Kind = "Special", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Doctor = { Faction = "Village", Kind = "Special", CoinPrice = 0, RobuxPrice = 0, RequiredLevel = 1, Free = true },
	Chief = { Faction = "Village", Kind = "Special", CoinPrice = 1200, RobuxPrice = 99, RequiredLevel = 5, Free = false },
	Bodyguard = { Faction = "Village", Kind = "Special", CoinPrice = 1200, RobuxPrice = 99, RequiredLevel = 5, Free = false },
	Seer = { Faction = "Village", Kind = "Special", CoinPrice = 2500, RobuxPrice = 199, RequiredLevel = 10, Free = false },
	Monk = { Faction = "Village", Kind = "Special", CoinPrice = 2500, RobuxPrice = 199, RequiredLevel = 10, Free = false },
	Engineer = { Faction = "Village", Kind = "Special", CoinPrice = 2500, RobuxPrice = 199, RequiredLevel = 10, Free = false },
	Killer = { Faction = "Killer", Kind = "Solo", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 20, Free = false },
	Fool = { Faction = "Fool", Kind = "Solo", CoinPrice = 5000, RobuxPrice = 399, RequiredLevel = 20, Free = false },
} :: { [RoleId]: RoleDef }

-- Display / iteration order (role screen, scoreboard).
Config.RoleOrder = {
	"Villager",
	"Sheriff",
	"Doctor",
	"Chief",
	"Bodyguard",
	"Seer",
	"Monk",
	"Engineer",
	"Killer",
	"Fool",
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
}

--------------------------------------------------------------------------------
-- §6.2 Voting
--------------------------------------------------------------------------------

Config.Vote = {
	MeetingsPerDay = 1, -- [GDD]
	DefaultWeight = 1,
	ChiefWeight = 2, -- [GDD]
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
	WalkSpeed = 20, -- [GDD]
	AttackDamage = 100, -- [GDD] one hit kills
	AttackCooldown = 1, -- [GDD]
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
}

--------------------------------------------------------------------------------
-- Hiding (§6.4)
--------------------------------------------------------------------------------

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
	},
	Doctor = {
		RevivesPerGame = 1, -- [GDD] extra revives consume a First aid
		ReviveHold = 3, -- [ASSUMED]
	},
	Seer = {
		Duration = 5, -- [GDD]
		UsesPerNight = 1, -- [GDD]
	},
	Bodyguard = {
		Cooldown = 30, -- [GDD]
		StunDuration = 5, -- [GDD]
		DashDistance = 24, -- [ASSUMED]
		DashSpeed = 80, -- [ASSUMED]
	},
	Monk = {
		BlessingsPerMorning = 1, -- [GDD]
		BlocksPerBlessing = 1, -- [GDD]
	},
	Engineer = {
		UsesPerDay = 1, -- [GDD]
		UsesPerNight = 1, -- [GDD]
		ReinforceHold = 2, -- [ASSUMED]
	},
	Killer = {
		KillsPerDay = 1, -- [GDD]
		KillsPerNight = 1, -- [GDD]
		KnifeRange = 6, -- [ASSUMED]
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
	PremiumRobuxPrice = 0, -- [ASSUMED] not in the GDD: owner must set a price
}

--------------------------------------------------------------------------------
-- §13.3 Daily Spin
--------------------------------------------------------------------------------

Config.DailySpin = {
	FreeSpinsPerDay = 1, -- [GDD]
	-- [GDD] weights in percent (sum = 100)
	Prizes = {
		{ Kind = "Coins", Amount = 20, Weight = 30 },
		{ Kind = "Diamonds", Amount = 20, Weight = 15 },
		{ Kind = "Coins", Amount = 50, Weight = 22 },
		{ Kind = "Diamonds", Amount = 50, Weight = 8 },
		{ Kind = "Coins", Amount = 100, Weight = 12 },
		{ Kind = "Diamonds", Amount = 100, Weight = 4 },
		{ Kind = "Coins", Amount = 200, Weight = 6 },
		{ Kind = "Diamonds", Amount = 200, Weight = 1.5 },
		{ Kind = "Role", Id = "Killer", Weight = 1 },
		{ Kind = "Skin", Id = "WolfSpin", Weight = 0.5 },
	} :: { SpinPrize },
	DuplicateRoleCoins = 2500, -- [GDD] already own Killer
	DuplicateSkinDiamonds = 200, -- [default] already own the spin wolf skin
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
	Seed = 20261116, -- deterministic prop placement
}

--------------------------------------------------------------------------------
-- Lighting presets (§6.5): bright by day, black distance fog at night.
--------------------------------------------------------------------------------

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
	WinJingle = 0,
	LoseJingle = 0,
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
		RoleMonk = 0,
		RoleEngineer = 0,
		RoleKiller = 0,
		RoleFool = 0,
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
	DoorHitPrompt = true, -- adds a "hit door" prompt at night to test door HP without a wolf
	ForceRole = nil, -- e.g. "Wolf" to always get that role
	ForceRoleUserId = nil, -- nil = the first player in the server
	TimerScale = 1, -- e.g. 0.1 makes every timer 10x shorter
	SkipRoleSelect = false,
} :: DebugConfig

return Config
