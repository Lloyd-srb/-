--!strict
--[[
	ChatController — how chat messages look (GDD §6.2, §12).
	  - General: names in white ("Qerty : hello").
	  - Wolf channel: a red [Wolf] tag.
	  - Anything written by a ghost: gray, with a [Ghost] tag.
	Who receives what is decided on the server (ChatService); this script only
	styles messages and points the chat bar at the General channel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local WHITE = "#FFFFFF"
local GRAY = "#969696"
local RED = "#FF6464"

local ChatController = {}

local dead: { [number]: boolean } = {}

local function colored(color: string, text: string): string
	return string.format('<font color="%s">%s</font>', color, text)
end

local function onIncoming(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	local channel = message.TextChannel
	if not source or not channel then
		return nil
	end
	local properties = Instance.new("TextChatMessageProperties")
	local name = message.PrefixText
	if dead[source.UserId] then
		properties.PrefixText = colored(GRAY, Loc.format("Chat.GhostTag") .. " " .. name)
		properties.Text = colored(GRAY, message.Text)
	elseif channel.Name == "Wolf" then
		properties.PrefixText = colored(RED, Loc.format("Chat.WolfTag")) .. " " .. colored(WHITE, name)
	else
		properties.PrefixText = colored(WHITE, name)
	end
	return properties
end

function ChatController.Start()
	TextChatService.OnIncomingMessage = onIncoming

	Remotes.get("RosterChanged").OnClientEvent:Connect(function(list: any)
		if type(list) ~= "table" then
			return
		end
		table.clear(dead)
		for _, entry in list do
			if type(entry) == "table" and type(entry.Id) == "number" and entry.Alive == false then
				dead[entry.Id] = true
			end
		end
	end)

	-- No default channels: the living type into General, ghosts into the
	-- Ghost channel (they may only read General). Tabs can still switch.
	local folder = TextChatService:WaitForChild("WolfVillageChannels", 30)
	local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	local function pointInputBar()
		local name = if ClientState.Alive then "General" else "Ghost"
		local channel = folder and folder:FindFirstChild(name)
		if channel and channel:IsA("TextChannel") and inputBar then
			inputBar.TargetTextChannel = channel
		end
	end
	if folder then
		folder:WaitForChild("General", 30)
	end
	ClientState.Changed:Connect(function(key: string)
		if key == "Alive" then
			pointInputBar()
		end
	end)
	pointInputBar()
end

return ChatController
