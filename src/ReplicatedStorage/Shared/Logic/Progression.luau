--!strict
--[[
	Progression — pure level maths (GDD §13): player level, mastery and the
	Season Pass (levels, reward table, premium bonus levels).
	Shared so that both the server (granting) and the client (UI) use one source.
]]

local Config = require(script.Parent.Parent.Config)

export type Track = "Free" | "Premium"

export type PassReward = {
	Kind: "Title" | "Coins" | "Diamonds" | "Spin" | "Skin",
	Amount: number?,
	Id: string?,
}

local Progression = {}

local Pass = Config.SeasonPass

--------------------------------------------------------------------------------
-- Player level (flat EXP per level, starts at level 1)
--------------------------------------------------------------------------------

function Progression.playerLevel(exp: number): number
	return Config.PlayerLevel.StartLevel + math.floor(math.max(0, exp) / Config.PlayerLevel.ExpPerLevel)
end

-- EXP inside the current level and EXP needed for the next one (for bars).
function Progression.playerLevelProgress(exp: number): (number, number)
	local perLevel = Config.PlayerLevel.ExpPerLevel
	return math.max(0, exp) % perLevel, perLevel
end

--------------------------------------------------------------------------------
-- Mastery (per role)
--------------------------------------------------------------------------------

function Progression.masteryLevel(points: number): number
	return math.floor(math.max(0, points) / Config.Mastery.PointsPerMastery)
end

-- Diamonds earned when mastery points go from `before` to `after`.
function Progression.masteryDiamonds(before: number, after: number): number
	local gained = Progression.masteryLevel(after) - Progression.masteryLevel(before)
	return math.max(0, gained) * Config.Mastery.DiamondsPerMastery
end

--------------------------------------------------------------------------------
-- Season Pass levels. Level 0 = nothing earned yet; Lv1 needs 200 EXP.
-- Levels 1-60 cost 200 EXP each, every level after 60 costs 1,000 EXP.
--------------------------------------------------------------------------------

local MAIN_EXP = Pass.MainLevels * Pass.ExpPerLevel

function Progression.passLevel(exp: number): number
	exp = math.max(0, exp)
	if exp < MAIN_EXP then
		return math.floor(exp / Pass.ExpPerLevel)
	end
	return Pass.MainLevels + math.floor((exp - MAIN_EXP) / Pass.ExpPerLevelAfterMain)
end

-- Total EXP needed to reach `level`.
function Progression.passExpForLevel(level: number): number
	if level <= Pass.MainLevels then
		return math.max(0, level) * Pass.ExpPerLevel
	end
	return MAIN_EXP + (level - Pass.MainLevels) * Pass.ExpPerLevelAfterMain
end

function Progression.passLevelProgress(exp: number): (number, number)
	local level = Progression.passLevel(exp)
	local floorExp = Progression.passExpForLevel(level)
	return exp - floorExp, Progression.passExpForLevel(level + 1) - floorExp
end

-- New EXP total after jumping `levels` levels (premium purchase: +10).
-- Progress inside the current level is kept.
function Progression.passExpAfterBonusLevels(exp: number, levels: number): number
	local level = Progression.passLevel(exp)
	local into = exp - Progression.passExpForLevel(level)
	return Progression.passExpForLevel(level + levels) + into
end

local function contains(list: { number }, value: number): boolean
	return table.find(list, value) ~= nil
end

-- Rewards for reaching `level` on a track (GDD §13.2).
function Progression.passRewards(level: number, track: Track): { PassReward }
	if level < 1 then
		return {}
	end

	if level > Pass.MainLevels then
		if track == "Free" then
			return { { Kind = "Coins", Amount = Pass.FreeCoinAmount } }
		end
		return { { Kind = "Diamonds", Amount = Pass.PremiumDiamondAmount } }
	end

	if level == 1 then
		return { { Kind = "Title", Id = if track == "Free" then Pass.FreeTitle else Pass.PremiumTitle } }
	elseif level == Pass.MainLevels then
		if track == "Free" then
			return { { Kind = "Skin", Id = "KnifePass" }, { Kind = "Skin", Id = "GunPass" } }
		end
		return { { Kind = "Skin", Id = "WolfPass" } }
	elseif contains(Pass.DiamondLevels, level) then
		return { { Kind = "Diamonds", Amount = Pass.DiamondLevelAmount } }
	elseif contains(Pass.SpinLevels, level) then
		return { { Kind = "Spin", Amount = 1 } }
	elseif track == "Free" then
		return { { Kind = "Coins", Amount = Pass.FreeCoinAmount } }
	end
	return { { Kind = "Diamonds", Amount = Pass.PremiumDiamondAmount } }
end

return Progression
