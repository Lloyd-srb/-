--!strict
--[[
	BuildSettings — place-level settings for the Match place that scripts rely
	on. Run in Studio (command bar / MCP). Idempotent.

	Not scriptable (the owner sets these in Game Settings): avatar type R6,
	voice chat, HTTP / API access.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildSettings: ReplicatedStorage.Shared is missing (import src/ first)")
local Config = (require :: any)((Shared :: any).Config:Clone())

-- The match decides who has a body (dead players must not respawn).
Players.CharacterAutoLoads = false

-- The whole map is ~1,400 parts, so instance streaming buys nothing, and it
-- would unload the house around a hiding player (whose body is parked far
-- away) and the far-away players that sniff / Seer / forest outlines show.
workspace.StreamingEnabled = false

StarterPlayer.CharacterWalkSpeed = Config.Human.WalkSpeed

print("[BuildSettings] done")
