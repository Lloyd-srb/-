local Rng = require(game.ReplicatedStorage.Shared.Rng)
local VoteTally = require(game.ServerScriptService.Logic.VoteTally)

local function ballot(target, confirmed)
	return { Target = target, Confirmed = confirmed ~= false }
end

test("nobody voted = nobody is exiled", function()
	local result = VoteTally.tally({}, nil, Rng.seeded(1))
	expect(result.Exiled).toBeNil()
	expect(result.Resolution).toBe("NoVotes")
end)

test("most votes is exiled; unconfirmed selections count (auto-confirm)", function()
	local result = VoteTally.tally({
		[1] = ballot(5),
		[2] = ballot(5, false),
		[3] = ballot(6),
	}, nil, Rng.seeded(1))
	expect(result.Exiled).toBe(5)
	expect(result.Resolution).toBe("Majority")
	expect(result.Counts[5]).toBe(2)
end)

test("the chief's vote counts twice", function()
	local result = VoteTally.tally({
		[1] = ballot(5), -- chief
		[2] = ballot(6),
	}, 1, Rng.seeded(1))
	expect(result.Exiled).toBe(5)
	expect(result.Resolution).toBe("Majority")
	expect(result.Counts[5]).toBe(2)
end)

test("tie: the side the chief voted for is exiled (Ahem!)", function()
	for seed = 1, 50 do
		local result = VoteTally.tally({
			[1] = ballot(5), -- chief: 2 votes on 5
			[2] = ballot(6),
			[3] = ballot(6),
		}, 1, Rng.seeded(seed))
		expect(result.Exiled).toBe(5)
		expect(result.Resolution).toBe("ChiefTieBreak")
	end
end)

test("tie without a chief: random among the tied players only", function()
	local seen = {}
	for seed = 1, 200 do
		local result = VoteTally.tally({
			[1] = ballot(5),
			[2] = ballot(6),
			[3] = ballot(7),
			[4] = ballot(5),
			[8] = ballot(6),
		}, nil, Rng.seeded(seed))
		expect(result.Resolution).toBe("RandomTieBreak")
		expect(result.Tied).toEqual({ 5, 6 })
		seen[result.Exiled] = (seen[result.Exiled] or 0) + 1
	end
	expect(seen[7]).toBeNil()
	expect(seen[5]).toBeNear(100, 35)
	expect(seen[6]).toBeNear(100, 35)
end)

test("tie where the chief voted for neither side: random", function()
	local result = VoteTally.tally({
		[1] = ballot(9), -- chief: 2 votes on 9, which is not one of the tied sides
		[2] = ballot(5),
		[3] = ballot(5),
		[10] = ballot(5),
		[4] = ballot(6),
		[7] = ballot(6),
		[11] = ballot(6),
	}, 1, Rng.seeded(3))
	expect(result.Resolution).toBe("RandomTieBreak")
	expect(result.Tied).toEqual({ 5, 6 })
end)

test("publicCounts shows gray/blue numbers and never voter ids", function()
	local counts = VoteTally.publicCounts({
		[1] = ballot(5, false),
		[2] = ballot(5, true),
		[3] = ballot(6, true),
	}, nil)
	expect(counts).toEqual({
		[5] = { Pending = 1, Confirmed = 1 },
		[6] = { Pending = 0, Confirmed = 1 },
	})
end)

test("isValidVote: only living players, no self vote", function()
	local alive = { [1] = true, [2] = true }
	expect(VoteTally.isValidVote(1, 2, alive)).toBe(true)
	expect(VoteTally.isValidVote(1, 1, alive)).toBe(false)
	expect(VoteTally.isValidVote(1, 3, alive)).toBe(false)
	expect(VoteTally.isValidVote(3, 1, alive)).toBe(false)
end)
