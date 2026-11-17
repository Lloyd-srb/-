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

-- Chat (GDD §6.2, §12): only the game's own channels (General / Wolf / Ghost,
-- made by ChatService). Roblox's default channels would let ghosts talk to
-- the living, so they are switched off. Channel tabs show General / Wolf /
-- Ghost to the players who may read them.
local TextChatService = game:GetService("TextChatService")
TextChatService.ChatVersion = Enum.ChatVersion.TextChatService
TextChatService.CreateDefaultTextChannels = false
-- These configuration objects come with every place and cannot be created by script.
local tabs = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
if tabs then
	tabs.Enabled = true
else
	warn("[BuildSettings] TextChatService.ChannelTabsConfiguration is missing: enable channel tabs by hand")
end

StarterPlayer.CharacterWalkSpeed = Config.Human.WalkSpeed

print("[BuildSettings] done")
