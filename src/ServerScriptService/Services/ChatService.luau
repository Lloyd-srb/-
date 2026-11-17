--!strict
--[[
	ChatService — text chat channels (GDD §6.2, §12) on TextChatService.

	Three TextChannels (General, Wolf, Ghost). Who is in which channel, who may
	type, and which messages reach whom follow Logic.ChatRules. Everything
	typed goes through Roblox's own text filtering (TextChatService does that
	for every TextChannel message).

	The default channels must be off (build/BuildSettings.luau sets
	TextChatService.CreateDefaultTextChannels = false), otherwise everyone
	could talk to everyone in RBXGeneral.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatRules = require(script.Parent.Parent.Logic.ChatRules)
local Roster = require(script.Parent.Parent.Logic.Roster)

local MatchService = require(script.Parent.MatchService)

local FOLDER_NAME = "WolfVillageChannels"

local ChatService = {}

local channels: { [string]: TextChannel } = {}
local sources: { [string]: { [number]: TextSource } } = {}
local busy: { [number]: boolean } = {}
local again: { [number]: boolean } = {}

function ChatService.Viewer(userId: number): ChatRules.Viewer
	local phase: ChatRules.Phase = if not MatchService.Started
		then "Lobby"
		elseif MatchService.Winner then "Over"
		else "Match"
	local member = MatchService.Roster.Members[userId]
	if not member then
		-- Joined after the start: a spectator, treated like a ghost.
		return { Phase = phase, Alive = phase ~= "Match", WolfSide = false }
	end
	return { Phase = phase, Alive = member.Alive, WolfSide = Roster.isWolfSide(member) }
end

function ChatService.Channel(name: string): TextChannel?
	return channels[name]
end

-- Puts one player in the right channels with the right rights.
local function apply(player: Player)
	local userId = player.UserId
	local wanted = ChatRules.membership(ChatService.Viewer(userId))
	for _, name in ChatRules.Channels do
		local access = wanted[name]
		local current: TextSource? = sources[name][userId]
		if access and not current and player.Parent then
			local source, ok = channels[name]:AddUserAsync(userId)
			if ok and source and not player.Parent then
				-- Left while being added: a stale entry would keep them out
				-- of this channel if they came back to this server.
				source:Destroy()
			elseif ok and source then
				sources[name][userId] = source
				current = source
			end
		elseif not access and current then
			sources[name][userId] = nil
			current:Destroy()
			current = nil
		end
		if current then
			current.CanSend = access == "Send"
		end
	end
end

-- AddUserAsync yields: one refresh per player at a time, repeated if asked again meanwhile.
function ChatService.Refresh(player: Player)
	local userId = player.UserId
	if busy[userId] then
		again[userId] = true
		return
	end
	busy[userId] = true
	task.spawn(function()
		repeat
			again[userId] = false
			apply(player)
		until not again[userId]
		busy[userId] = nil
	end)
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		ChatService.Refresh(player)
	end
end

local function refreshMember(member: Roster.Member)
	local player = MatchService.PlayerOf(member.Id)
	if player then
		ChatService.Refresh(player)
	end
end

function ChatService.Init()
	local old = TextChatService:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = TextChatService
	for _, name in ChatRules.Channels do
		local channel = Instance.new("TextChannel")
		channel.Name = name
		channel.Parent = folder
		channel.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource): boolean
			local speaker = message.TextSource
			if not speaker then
				return true -- system messages
			end
			return ChatRules.canDeliver(name, ChatService.Viewer(speaker.UserId), ChatService.Viewer(target.UserId))
		end
		channels[name] = channel
		sources[name] = {}
	end
end

function ChatService.Start()
	Players.PlayerAdded:Connect(ChatService.Refresh)
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, name in ChatRules.Channels do
			sources[name][player.UserId] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		ChatService.Refresh(player)
	end
	MatchService.MatchStarted:Connect(refreshAll)
	MatchService.GameOver:Connect(refreshAll)
	MatchService.MemberDied:Connect(refreshMember)
	MatchService.MemberRevived:Connect(refreshMember)
	MatchService.MemberConverted:Connect(refreshMember)
end

return ChatService
