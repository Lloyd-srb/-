--!strict
--[[
	HighlightController — draws outlines for this viewer only.

	The server never creates Highlights. It tells the players who are allowed
	to see them (wolf side for the forest glow / howl, the sniffing wolf, later
	the Seer) which member ids to outline, and this script creates the
	Highlight instances locally, so no other client ever has them.
	Fish baits come as spots: a red person-shaped glow is made here, locally.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local FILL_TRANSPARENCY = 0.6

-- Highlight kind -> key in Config.Highlights
local COLOR_KEYS: { [string]: string } = {
	Forest = "ForestTarget",
	Sniff = "Sniff",
	Howl = "Howl",
	Seer = "Seer",
	Bait = "ForestTarget", -- a fish on the ground, seen as someone standing there
}

-- A person-shaped decoy (local to this client) for a bait: torso, head, arms, legs.
local DECOY_PARTS: { { Size: Vector3, Offset: Vector3 } } = {
	{ Size = Vector3.new(2, 2, 1), Offset = Vector3.new(0, 3, 0) },
	{ Size = Vector3.new(1.2, 1.2, 1.2), Offset = Vector3.new(0, 4.6, 0) },
	{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(-1.5, 3, 0) },
	{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(1.5, 3, 0) },
	{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(-0.5, 1, 0) },
	{ Size = Vector3.new(1, 2, 1), Offset = Vector3.new(0.5, 1, 0) },
}
local DECOY_TRANSPARENCY = 0.9 -- the glow does the showing

local HighlightController = {}

local active: { [string]: { Instance } } = {}
local tokens: { [string]: number } = {}

local function bodyOf(id: number): Instance?
	for _, body in CollectionService:GetTagged("MemberBody") do
		if body:GetAttribute("MemberId") == id and not body:GetAttribute("Corpse") then
			return body
		end
	end
	return nil
end

local function clear(kind: string)
	local existing = active[kind]
	if existing then
		for _, highlight in existing do
			highlight:Destroy()
		end
	end
	active[kind] = {}
end

local function show(kind: string, ids: { any }, duration: number?, spots: { any }?)
	local colorKey = COLOR_KEYS[kind]
	if not colorKey then
		return
	end
	clear(kind)
	tokens[kind] = (tokens[kind] or 0) + 1
	local token = tokens[kind]

	local color = (Config.Highlights :: any)[colorKey] :: Color3
	if kind == "Bait" then
		local list: { any } = spots or {}
		for _, spot in list do
			if typeof(spot) == "Vector3" then
				local decoy = Instance.new("Model")
				decoy.Name = "BaitDecoy"
				for _, piece in DECOY_PARTS do
					local part = Instance.new("Part")
					part.Size = piece.Size
					part.CFrame = CFrame.new(spot + piece.Offset)
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
					part.Color = color
					part.Transparency = DECOY_TRANSPARENCY
					part.Parent = decoy
				end
				local highlight = Instance.new("Highlight")
				highlight.FillColor = color
				highlight.OutlineColor = color
				highlight.FillTransparency = FILL_TRANSPARENCY
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Parent = decoy
				decoy.Parent = workspace
				table.insert(active[kind], decoy)
			end
		end
		return
	end
	for _, id in ids do
		local body = if type(id) == "number" then bodyOf(id) else nil
		if body then
			local highlight = Instance.new("Highlight")
			highlight.Name = kind .. "Highlight"
			highlight.Adornee = body
			highlight.FillColor = color
			highlight.OutlineColor = color
			highlight.FillTransparency = FILL_TRANSPARENCY
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = body
			table.insert(active[kind], highlight)
		end
	end

	if duration then
		task.delay(duration, function()
			if tokens[kind] == token then
				clear(kind)
			end
		end)
	end
end

function HighlightController.Start()
	Remotes.get("Highlight").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or type(data.Kind) ~= "string" or type(data.Ids) ~= "table" then
			return
		end
		local duration = if type(data.Duration) == "number" then data.Duration else nil
		show(data.Kind, data.Ids, duration, if type(data.Spots) == "table" then data.Spots else nil)
	end)
	-- Back to human in the morning, or dead: nothing stays outlined.
	local function clearAll()
		for kind in active do
			clear(kind)
		end
	end
	Remotes.get("FormChanged").OnClientEvent:Connect(function(form: any)
		if form == "Human" then
			clearAll()
		end
	end)
	ClientState.Changed:Connect(function(key: string)
		if key == "Alive" and not ClientState.Alive then
			clearAll()
		end
	end)
end

return HighlightController
