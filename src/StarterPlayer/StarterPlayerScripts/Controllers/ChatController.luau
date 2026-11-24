--!strict
--[[
	ChatController — how chat messages look (GDD §6.2, §12).
	  - General: names in white ("Qerty : hello").
	  - The ghost / wolf chat: a red [Wolf] tag on the wolf side's words.
	  - Anything written by a ghost: gray, with a [Ghost] tag.
	  - Bubbles over heads (owner, 24 Nov 2026): Roblox's own bubbles are off;
	    this script draws them, only for what Logic.ChatBubbles allows (never
	    the ghost / wolf chat, never a ghost, a monster or someone invisible).
	  - The chat bar points at General, or at the ghost / wolf chat for a
	    ghost and for a monster in beast form; tabs can still switch.
	Who receives what is decided on the server (ChatService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local ChatBubbles = require(ReplicatedStorage.Shared.Logic.ChatBubbles)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local WHITE = "#FFFFFF"
local GRAY = "#969696"
local RED = "#FF6464"

local BUBBLE_SECONDS = 7 -- [ASSUMED] how long a bubble stays
local BUBBLE_DISTANCE = 80 -- [ASSUMED] studs: farther away, no bubble
local BUBBLE_MAX_WIDTH = 220 -- pixels
local BUBBLE_TEXT_SIZE = 17
local BUBBLE_PADDING = 8
local BUBBLE_FONT = Font.fromEnum(Enum.Font.GothamMedium)
local BUBBLE_BACKGROUND = Color3.fromRGB(250, 250, 250)
local BUBBLE_TEXT = Color3.fromRGB(45, 40, 50)

local ChatController = {}

local dead: { [number]: boolean } = {}

type Bubble = { Gui: BillboardGui, Channel: string, Until: number }
local bubbles: { [number]: Bubble } = {} -- speaker UserId -> their bubble

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
	elseif channel.Name == "Ghost" then -- a living wolf in the ghost / wolf chat
		properties.PrefixText = colored(RED, Loc.format("Chat.WolfTag")) .. " " .. colored(WHITE, name)
	else
		properties.PrefixText = colored(WHITE, name)
	end
	return properties
end

--------------------------------------------------------------------------------
-- Bubbles over heads
--------------------------------------------------------------------------------

local function speakerOf(userId: number): (Model?, ChatBubbles.Speaker)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local form = if character then character:GetAttribute("Form") else nil
	return character,
		{
			Alive = not dead[userId],
			Form = if type(form) == "string" then form else nil,
			Vanished = character ~= nil and character:GetAttribute("Vanished") == true,
		}
end

local function removeBubble(userId: number)
	local bubble = bubbles[userId]
	if bubble then
		bubbles[userId] = nil
		bubble.Gui:Destroy()
	end
end

local function makeBubble(adornee: BasePart, text: string): BillboardGui
	local bounds = TextService:GetTextSize(
		text,
		BUBBLE_TEXT_SIZE,
		Enum.Font.GothamMedium,
		Vector2.new(BUBBLE_MAX_WIDTH, 1000)
	)
	local width = math.min(BUBBLE_MAX_WIDTH, bounds.X) + BUBBLE_PADDING * 2
	local height = bounds.Y + BUBBLE_PADDING * 2

	local gui = Instance.new("BillboardGui")
	gui.Name = "ChatBubble"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(BUBBLE_MAX_WIDTH + BUBBLE_PADDING * 2, height + 10)
	gui.SizeOffset = Vector2.new(0, 0.5) -- the bottom edge (the tail) sits on the point below
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = BUBBLE_DISTANCE
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Name = "Bubble"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -8)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = BUBBLE_BACKGROUND
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 1, -8)
	tail.Size = UDim2.fromOffset(12, 12)
	tail.Rotation = 45
	tail.BackgroundColor3 = BUBBLE_BACKGROUND
	tail.BackgroundTransparency = 0.05
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(BUBBLE_PADDING, BUBBLE_PADDING)
	label.Size = UDim2.new(1, -BUBBLE_PADDING * 2, 1, -BUBBLE_PADDING * 2)
	label.FontFace = BUBBLE_FONT
	label.TextSize = BUBBLE_TEXT_SIZE
	label.TextColor3 = BUBBLE_TEXT
	label.TextWrapped = true
	label.RichText = true -- the chat already escapes what players type
	label.Text = text
	label.Parent = frame
	return gui
end

-- A message arrived (already filtered by Roblox for this player): a bubble
-- over the speaker's head, if the rules allow it.
local function onMessage(message: TextChatMessage)
	local source = message.TextSource
	local channel = message.TextChannel
	if not source or not channel or message.Text == "" then
		return
	end
	local userId = source.UserId
	local character, speaker = speakerOf(userId)
	if not character or not ChatBubbles.shows(channel.Name, speaker) then
		return
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head or not head:IsA("BasePart") then
		return
	end
	removeBubble(userId) -- a new line replaces the old one
	local gui = makeBubble(head, message.Text)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	bubbles[userId] = { Gui = gui, Channel = channel.Name, Until = os.clock() + BUBBLE_SECONDS }
end

-- Bubbles go when their time is up, or as soon as the speaker may no longer
-- have one (died, turned into a monster, vanished, body gone).
local function sweepBubbles()
	local now = os.clock()
	for userId, bubble in bubbles do
		local character, speaker = speakerOf(userId)
		local adornee = bubble.Gui.Adornee
		if
			now >= bubble.Until
			or not character
			or not adornee
			or not adornee:IsDescendantOf(character)
			or not ChatBubbles.shows(bubble.Channel, speaker)
		then
			removeBubble(userId)
		end
	end
end

function ChatController.Start()
	TextChatService.OnIncomingMessage = onIncoming

	-- Roblox's own bubbles would show every chat, the ghost / wolf one too.
	local builtIn = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if builtIn then
		builtIn.Enabled = false
	end
	TextChatService.MessageReceived:Connect(onMessage)
	task.spawn(function()
		while true do
			task.wait(0.2)
			sweepBubbles()
		end
	end)

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

	-- No default channels: people type into General; ghosts, and monsters in
	-- beast form, into the ghost / wolf chat. Tabs can still switch.
	local folder = TextChatService:WaitForChild("WolfVillageChannels", 30)
	local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	local function pointInputBar()
		local name = ChatBubbles.defaultChannel(ClientState.Alive, ClientState.Form)
		local channel = folder and folder:FindFirstChild(name)
		if channel and channel:IsA("TextChannel") and inputBar then
			inputBar.TargetTextChannel = channel
		end
	end
	if folder then
		folder:WaitForChild("General", 30)
	end
	ClientState.Changed:Connect(function(key: string)
		if key == "Alive" or key == "Form" then
			pointInputBar()
		end
	end)
	pointInputBar()
end

return ChatController
