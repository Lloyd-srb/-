--!strict
--[[
	ForestLayout — pure layout of the walkable forest for one match
	(owner, 19 Nov 2026): every server start places the task trees, bushes,
	rocks and the course of the water channel (moat) somewhere new.

	  - The moat winds round the village through the forest, starting and
	    ending in the big river (north-east).
	  - Nothing grows in the river, in the moat (plus a margin), or on the way
	    from the fence to the pier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

export type Layout = {
	Moat: { Vector3 }, -- centre line, from the river round to the river
	Trees: { Vector3 },
	Bushes: { Vector3 },
	Rocks: { Vector3 },
}

local ForestLayout = {}

local MapCfg = Config.Map
local TAU = math.pi * 2

-- Ring position: angle 0 = north (-Z), clockwise seen from above.
local function onRing(radius: number, angle: number): Vector3
	return Vector3.new(math.sin(angle) * radius, 0, -math.cos(angle) * radius)
end

function ForestLayout.riverCentre(): Vector3
	local river = MapCfg.River
	return onRing(river.ShoreDistance + river.Curve, river.Angle)
end

-- In the big river (or within `margin` studs of its shore)?
function ForestLayout.inRiver(point: Vector3, margin: number?): boolean
	local flat = Vector3.new(point.X, 0, point.Z)
	return (flat - ForestLayout.riverCentre()).Magnitude < MapCfg.River.Curve + (margin or 0)
end

-- Shortest flat distance from a point to a path (a line through its points).
function ForestLayout.distanceToPath(point: Vector3, path: { Vector3 }): number
	local p = Vector3.new(point.X, 0, point.Z)
	local best = math.huge
	for index = 1, #path - 1 do
		local a, b = path[index], path[index + 1]
		local ab = b - a
		local length2 = ab:Dot(ab)
		local t = if length2 > 0 then math.clamp((p - a):Dot(ab) / length2, 0, 1) else 0
		local distance = (p - (a + ab * t)).Magnitude
		if distance < best then
			best = distance
		end
	end
	return best
end

function ForestLayout.inMoat(point: Vector3, path: { Vector3 }): boolean
	return #path >= 2 and ForestLayout.distanceToPath(point, path) <= MapCfg.Moat.Width / 2
end

-- The moat's course: a wavy ring that bends out into the river at both ends.
function ForestLayout.moat(rng: Rng.Rng): { Vector3 }
	local cfg = MapCfg.Moat
	local riverAngle = MapCfg.River.Angle
	local phaseA = rng:NextNumber() * TAU
	local phaseB = rng:NextNumber() * TAU
	local function radiusAt(angle: number): number
		local r = cfg.Radius + cfg.Wiggle[1] * math.sin(3 * angle + phaseA) + cfg.Wiggle[2] * math.sin(7 * angle + phaseB)
		-- Near the river's direction, steer out so both ends reach the water.
		local off = math.abs(((angle - riverAngle + math.pi) % TAU) - math.pi)
		local blend = math.clamp(1 - off / math.rad(55), 0, 1)
		r = r * (1 - blend) + cfg.MaxRadius * blend
		return math.clamp(r, cfg.MinRadius, cfg.MaxRadius)
	end
	-- Walk once round, starting in the river (anticlockwise, as drawn).
	local samples: { Vector3 } = {}
	local count = math.floor(TAU / cfg.Step)
	for k = 0, count do
		local angle = riverAngle - k * cfg.Step
		table.insert(samples, onRing(radiusAt(angle), angle))
	end
	-- Keep the stretch on land, plus one point in the water at each end.
	local first, last = nil :: number?, nil :: number?
	for index, point in samples do
		if not ForestLayout.inRiver(point) then
			first = first or index
			last = index
		end
	end
	if not first or not last then
		return {}
	end
	local path: { Vector3 } = {}
	for index = math.max(1, first - 1), math.min(#samples, last + 1) do
		table.insert(path, samples[index])
	end
	return path
end

-- Random points in a ring, spaced apart, away from the river, the moat and `taken`.
local function scatter(
	rng: Rng.Rng,
	count: number,
	inner: number,
	outer: number,
	spacing: number,
	taken: { Vector3 },
	moat: { Vector3 },
	moatMargin: number
): { Vector3 }
	local points: { Vector3 } = {}
	local attempts = 0
	while #points < count and attempts < count * 300 do
		attempts += 1
		local radius = math.sqrt(inner * inner + rng:NextNumber() * (outer * outer - inner * inner))
		local point = onRing(radius, rng:NextNumber() * TAU)
		local ok = not ForestLayout.inRiver(point, 6)
			and (#moat < 2 or ForestLayout.distanceToPath(point, moat) > MapCfg.Moat.Width / 2 + moatMargin)
		if ok then
			for _, other in taken do
				if (other - point).Magnitude < spacing then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(points, point)
			table.insert(taken, point)
		end
	end
	return points
end

function ForestLayout.generate(rng: Rng.Rng): Layout
	local moat = ForestLayout.moat(rng)
	-- The way from the fence to the pier stays clear.
	local taken: { Vector3 } = {}
	for radius = MapCfg.FenceRadius, MapCfg.River.ShoreDistance, 6 do
		table.insert(taken, onRing(radius, MapCfg.River.Angle))
	end
	local inner = MapCfg.FenceRadius + 10
	local outer = MapCfg.ForestOuterRadius - 12
	local margin = MapCfg.Moat.TreeMargin
	return {
		Moat = moat,
		Trees = scatter(rng, MapCfg.TaskTreeCount, inner, outer, 15, taken, moat, margin),
		Bushes = scatter(rng, MapCfg.BushCount, inner - 4, outer + 6, 7, taken, moat, 3),
		Rocks = scatter(rng, MapCfg.RockCount, inner - 4, outer + 6, 7, taken, moat, 3),
	}
end

return ForestLayout
