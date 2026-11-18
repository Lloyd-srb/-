--!strict
--[[
	Rewards — pure end-of-match reward maths (GDD §13).

	Per night survived: 20 coins / 50 EXP. Win = full, lose = half.
	Killer / Fool / Fire Maniac win: +50%. Each finished task: +20 coins (win or lose).
	MVP (most likes): +20% on the whole reward.
	Season Pass EXP: 150 win / 50 lose. Mastery points: 2 win / 1 lose.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Input = {
	NightsSurvived: number,
	Won: boolean,
	Faction: Config.Faction,
	TasksCompleted: number,
	IsMvp: boolean,
}

export type Output = {
	Coins: number,
	Exp: number,
	PassExp: number,
	MasteryPoints: number,
}

local Rewards = {}

function Rewards.compute(input: Input): Output
	local cfg = Config.Rewards
	local multiplier = if input.Won then 1 else cfg.LoseMultiplier
	if input.Won and (input.Faction == "Killer" or input.Faction == "Fool" or input.Faction == "FireManiac") then
		multiplier *= cfg.SoloWinMultiplier
	end

	local coins = input.NightsSurvived * cfg.CoinsPerNight * multiplier
	local exp = input.NightsSurvived * cfg.ExpPerNight * multiplier
	coins += input.TasksCompleted * Config.Tasks.CoinReward

	if input.IsMvp then
		coins *= cfg.MvpMultiplier
		exp *= cfg.MvpMultiplier
	end

	-- + 1e-6 guards against float error such as 20 * 1.2 = 23.999999
	return {
		Coins = math.floor(coins + 1e-6),
		Exp = math.floor(exp + 1e-6),
		PassExp = if input.Won then Config.SeasonPass.WinExp else Config.SeasonPass.LoseExp,
		MasteryPoints = if input.Won then Config.Mastery.WinPoints else Config.Mastery.LosePoints,
	}
end

-- MVP = most likes. Ties are broken at random; nobody liked = no MVP.
function Rewards.pickMvp(likes: { [number]: number }, pickRandom: (tied: { number }) -> number): number?
	local top = 0
	for _, count in likes do
		if count > top then
			top = count
		end
	end
	if top == 0 then
		return nil
	end
	local tied: { number } = {}
	for userId, count in likes do
		if count == top then
			table.insert(tied, userId)
		end
	end
	table.sort(tied)
	if #tied == 1 then
		return tied[1]
	end
	return pickRandom(tied)
end

return Rewards
