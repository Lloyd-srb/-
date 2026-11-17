--!strict
--[[
	VoteTally — pure voting rules (GDD §6.2).

	- Most votes is exiled. Nobody voted = nobody is exiled.
	- [owner] At least Config.Vote.MinVotesToExile votes are needed to exile
	  anyone ("TooFewVotes" otherwise).
	- A selection that was not confirmed is auto-confirmed when time runs out,
	  so the final tally counts every ballot.
	- The Chief's vote weighs 2. On a tie, the side the Chief voted for wins
	  ("Ahem!"). Otherwise one of the tied players is exiled at random.
	- Clients only ever receive `publicCounts` (silhouette numbers), never
	  who voted for whom. The Chief's vote shows as one silhouette like any
	  other ([owner]); only after the lock is it marked with a crown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

export type Ballot = {
	Target: number, -- UserId voted for
	Confirmed: boolean,
}

export type Resolution = "NoVotes" | "TooFewVotes" | "Majority" | "ChiefTieBreak" | "RandomTieBreak"

export type Result = {
	Exiled: number?,
	Resolution: Resolution,
	Counts: { [number]: number }, -- target -> weighted votes
	Tied: { number }, -- targets sharing the top count (sorted), 1 entry when no tie
}

export type PublicCount = {
	Pending: number, -- gray silhouettes
	Confirmed: number, -- blue silhouettes
}

local VoteTally = {}

local function weightOf(voterId: number, chiefId: number?): number
	if chiefId ~= nil and voterId == chiefId then
		return Config.Vote.ChiefWeight
	end
	return Config.Vote.DefaultWeight
end

-- May `voterId` select `targetId`? Both must be alive participants.
function VoteTally.isValidVote(voterId: number, targetId: number, alive: { [number]: boolean }): boolean
	if not alive[voterId] or not alive[targetId] then
		return false
	end
	if voterId == targetId and not Config.Vote.AllowSelfVote then
		return false
	end
	return true
end

-- What every client may see: one silhouette per voter (the Chief's too).
function VoteTally.publicCounts(ballots: { [number]: Ballot }, _chiefId: number?): { [number]: PublicCount }
	local counts: { [number]: PublicCount } = {}
	for _, ballot in ballots do
		local entry = counts[ballot.Target]
		if entry == nil then
			entry = { Pending = 0, Confirmed = 0 }
			counts[ballot.Target] = entry
		end
		if ballot.Confirmed then
			entry.Confirmed += 1
		else
			entry.Pending += 1
		end
	end
	return counts
end

-- Final result when the meeting timer ends. `chiefId` is the living Chief, if any.
function VoteTally.tally(ballots: { [number]: Ballot }, chiefId: number?, rng: Rng.Rng): Result
	local counts: { [number]: number } = {}
	local top = 0
	for voterId, ballot in ballots do
		local total = (counts[ballot.Target] or 0) + weightOf(voterId, chiefId)
		counts[ballot.Target] = total
		if total > top then
			top = total
		end
	end

	if top == 0 then
		return { Exiled = nil, Resolution = "NoVotes", Counts = counts, Tied = {} }
	end
	if top < Config.Vote.MinVotesToExile then
		return { Exiled = nil, Resolution = "TooFewVotes", Counts = counts, Tied = {} }
	end

	local tied: { number } = {}
	for target, total in counts do
		if total == top then
			table.insert(tied, target)
		end
	end
	table.sort(tied)

	if #tied == 1 then
		return { Exiled = tied[1], Resolution = "Majority", Counts = counts, Tied = tied }
	end

	if chiefId ~= nil then
		local chiefBallot = ballots[chiefId]
		if chiefBallot ~= nil and table.find(tied, chiefBallot.Target) ~= nil then
			return { Exiled = chiefBallot.Target, Resolution = "ChiefTieBreak", Counts = counts, Tied = tied }
		end
	end

	return { Exiled = Rng.pick(tied, rng), Resolution = "RandomTieBreak", Counts = counts, Tied = tied }
end

return VoteTally
