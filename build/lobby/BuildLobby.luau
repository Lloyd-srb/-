--!strict
--[[
	BuildLobby — (re)builds the Lobby place's world under Workspace.Lobby.
	Run it in the Lobby place in Studio (command bar or MCP). Idempotent.

	A small sunny village square: grass, a round plaza, the spawn in the
	middle, and four glowing 12-seat queue pads in a row with a sign each
	(GDD §3, owner's rules 17 Nov 2026).

	Contract with the scripts:
	  Tag "QueuePad"   part, attribute PadId (1-4): standing on it = in that queue
	  PadSign<N>       part with a SurfaceGui "Sign" holding TextLabels
	                   Title / Count / Status (filled in by the client)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildLobby: ReplicatedStorage.Shared is missing (import the shared code first)")
local Config = (require :: any)((Shared :: any).Config:Clone())

local rgb = Color3.fromRGB

local PAD_SPACING = 20 -- between pad centres
local PAD_ROW_Z = -34 -- the row of pads, in front of the spawn
local SIGN_HEIGHT = 9

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Anchored = true
	instance.Size = size
	instance.CFrame = cframe
	instance.Color = color
	instance.Material = Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Parent = parent
	return instance
end

local function cylinder(name: string, diameter: number, height: number, position: Vector3, color: Color3, parent: Instance): Part
	local instance = part(name, Vector3.new(height, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, parent)
	instance.Shape = Enum.PartType.Cylinder
	return instance
end

local function signLabel(name: string, parent: Instance, y: number, height: number, bold: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(0.94, height)
	label.Position = UDim2.fromScale(0.5, y)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(if bold then Enum.Font.FredokaOne else Enum.Font.GothamMedium)
	label.TextColor3 = rgb(255, 255, 255)
	label.TextScaled = true
	label.Text = ""
	label.Parent = parent
	return label
end

-- Reset.
local old = workspace:FindFirstChild("Lobby")
if old then
	old:Destroy()
end
for _, name in { "Baseplate", "SpawnLocation" } do
	local leftover = workspace:FindFirstChild(name)
	if leftover then
		leftover:Destroy()
	end
end

local Lobby = Instance.new("Folder")
Lobby.Name = "Lobby"
Lobby.Parent = workspace

-- Ground and plaza.
part("Ground", Vector3.new(260, 4, 260), CFrame.new(0, -2, 0), rgb(126, 196, 96), Lobby)
cylinder("Plaza", 110, 1, Vector3.new(0, -0.4, -10), rgb(226, 202, 158), Lobby)

local spawn = Instance.new("SpawnLocation")
spawn.Name = "LobbySpawn"
spawn.Anchored = true
spawn.Size = Vector3.new(10, 1, 10)
spawn.CFrame = CFrame.new(0, 0, 12)
spawn.Color = rgb(240, 236, 220)
spawn.Material = Enum.Material.SmoothPlastic
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.Neutral = true
spawn.Parent = Lobby

-- The four queue pads.
local pads = Instance.new("Folder")
pads.Name = "Pads"
pads.Parent = Lobby
local count = Config.Lobby.PadCount
for id = 1, count do
	local x = (id - (count + 1) / 2) * PAD_SPACING
	local color = Config.Lobby.PadColors[(id - 1) % #Config.Lobby.PadColors + 1]

	local base = part("PadBase" .. id, Config.Lobby.PadSize + Vector3.new(2, 0, 2), CFrame.new(x, 0.3, PAD_ROW_Z), rgb(90, 90, 100), pads)
	base.CanQuery = false
	local pad = part("Pad" .. id, Config.Lobby.PadSize, CFrame.new(x, 0.6, PAD_ROW_Z), color, pads)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.25
	pad:AddTag("QueuePad")
	pad:SetAttribute("PadId", id)
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 14
	glow.Brightness = 1.2
	glow.Parent = pad

	-- Sign behind the pad, facing the spawn.
	local signZ = PAD_ROW_Z - Config.Lobby.PadSize.Z / 2 - 2
	part("SignPost" .. id, Vector3.new(0.8, SIGN_HEIGHT, 0.8), CFrame.new(x, SIGN_HEIGHT / 2, signZ), rgb(112, 76, 50), pads)
	local board = part("PadSign" .. id, Vector3.new(12, 6, 0.6), CFrame.new(x, SIGN_HEIGHT + 2, signZ), rgb(44, 48, 68), pads)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Back -- the side that faces +Z (the spawn)
	gui.CanvasSize = Vector2.new(400, 200)
	gui.LightInfluence = 0
	gui.Parent = board
	signLabel("Title", gui, 0.04, 0.3, true).Text = "Match " .. id
	signLabel("Count", gui, 0.36, 0.34, true).Text = "0/" .. Config.Match.MaxPlayers
	signLabel("Status", gui, 0.72, 0.22, false)
end

-- A few trees around the square.
local trees = Instance.new("Folder")
trees.Name = "Trees"
trees.Parent = Lobby
for index = 1, 16 do
	local angle = index / 16 * math.pi * 2
	local position = Vector3.new(math.sin(angle) * 80, 0, -10 - math.cos(angle) * 80)
	part("Trunk", Vector3.new(2, 8, 2), CFrame.new(position + Vector3.new(0, 4, 0)), rgb(128, 88, 58), trees)
	local leaves = part("Leaves", Vector3.new(8, 6, 8), CFrame.new(position + Vector3.new(0, 10, 0)) * CFrame.Angles(0, angle, 0), rgb(92, 176, 88), trees)
	leaves.CastShadow = true
end

print(string.format("[BuildLobby] done: %d queue pads", count))
