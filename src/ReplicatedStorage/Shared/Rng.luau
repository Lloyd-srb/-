--!strict
--[[
	Rng — a tiny random-number interface so game-rule modules stay pure and
	testable. Services pass `Rng.wrap(Random.new())`; tests and builder scripts
	pass `Rng.seeded(n)` for deterministic results.
]]

export type Rng = {
	NextInteger: (self: Rng, min: number, max: number) -> number,
	NextNumber: (self: Rng) -> number,
}

local Rng = {}

local MODULUS = 2147483647 -- 2^31 - 1 (Park-Miller)
local MULTIPLIER = 48271

function Rng.wrap(random: Random): Rng
	local wrapped = {}
	function wrapped.NextInteger(_self: Rng, min: number, max: number): number
		return random:NextInteger(min, max)
	end
	function wrapped.NextNumber(_self: Rng): number
		return random:NextNumber()
	end
	return wrapped
end

function Rng.seeded(seed: number): Rng
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end

	local function step(): number
		state = (state * MULTIPLIER) % MODULUS
		return state
	end

	local seeded = {}
	function seeded.NextNumber(_self: Rng): number
		return (step() - 1) / (MODULUS - 1)
	end
	function seeded.NextInteger(_self: Rng, min: number, max: number): number
		return min + (step() % (max - min + 1))
	end
	return seeded
end

-- Returns a shuffled copy (Fisher-Yates).
function Rng.shuffle<T>(list: { T }, rng: Rng): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

function Rng.pick<T>(list: { T }, rng: Rng): T
	assert(#list > 0, "Rng.pick: empty list")
	return list[rng:NextInteger(1, #list)]
end

-- Picks one entry using its `Weight` field. Weights need not sum to 100.
function Rng.weighted<T>(entries: { T }, rng: Rng): T
	assert(#entries > 0, "Rng.weighted: empty list")
	local total = 0
	for _, entry in entries do
		total += (entry :: any).Weight
	end
	local roll = rng:NextNumber() * total
	local running = 0
	for _, entry in entries do
		running += (entry :: any).Weight
		if roll < running then
			return entry
		end
	end
	return entries[#entries]
end

return Rng
