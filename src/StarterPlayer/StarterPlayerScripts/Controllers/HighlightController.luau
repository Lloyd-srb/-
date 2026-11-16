--!strict
--[[
	HighlightController — draws outlines for this viewer only.

	The server never creates Highlights. It tells the players who are allowed
	to see them (wolf side for the forest glow / howl, the sniffing wolf, later
	the Seer) which member ids to outline, and this script creates the
	Highlight instances locally, so no other client ever has them.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FILL_TRANSPARENCY = 0.6

-- Highlight kind -> key in Config.Highlights
local COLOR_KEYS: { [string]: string } = {
	Forest = "ForestTarget",
	Sniff = "Sniff",
	Howl = "Howl",
	Seer = "Seer",
}

local HighlightController = {}

local active: { [string]: { Highlight } } = {}
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

local function show(kind: string, ids: { any }, duration: number?)
	local colorKey = COLOR_KEYS[kind]
	if not colorKey then
		return
	end
	clear(kind)
	tokens[kind] = (tokens[kind] or 0) + 1
	local token = tokens[kind]

	local color = (Config.Highlights :: any)[colorKey] :: Color3
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
		show(data.Kind, data.Ids, if type(data.Duration) == "number" then data.Duration else nil)
	end)
	-- Back to human in the morning: nothing stays outlined.
	Remotes.get("FormChanged").OnClientEvent:Connect(function(form: any)
		if form == "Human" then
			for kind in active do
				clear(kind)
			end
		end
	end)
end

return HighlightController
