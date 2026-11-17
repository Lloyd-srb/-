--!strict
--[[
	EconomyService — the Lobby's shop, wardrobe, Season Pass, Daily Spin and
	codes (GDD §3, §13). The menus only ask; every rule is checked here
	(Shared.Logic.Shop, ServerShared.Logic.ProfileLogic / Codes).

	  ShopBuy(kind, id, currency)   "Role" / "Skin" / "Premium" / "Coins";
	                                Coins / Diamonds are paid here, Robux opens
	                                Roblox's purchase window (Purchases).
	  Equip(slot, id)               "Gun" / "Knife" / "Wolf" / "Title"; "" = none
	  SpinRequest()                 one Daily Spin (free one first)
	  CodeRedeem(text)              a code from the "Codes" page

	Each player is sent their own ProfileView whenever their profile changes.
	The equipped title is public: it is put on the character as an attribute
	and every client draws it over the head (TitleController).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Shop = require(ReplicatedStorage.Shared.Logic.Shop)

local ServerShared = ServerStorage:WaitForChild("ServerShared")
local CodeList = require(ServerShared.CodeList)
local Codes = require(ServerShared.Logic.Codes)
local Net = require(ServerShared.Net)
local ProfileLogic = require(ServerShared.Logic.ProfileLogic)
local Profiles = require(ServerShared.Profiles)
local Purchases = require(ServerShared.Purchases)

local EconomyService = {}

local rng = Rng.wrap(Random.new())
local viewQueued: { [Player]: boolean } = {}
local wrongCodes: { [number]: { Count: number, LockedUntil: number } } = {} -- by UserId

local function sendView(player: Player)
	local data = Profiles.Get(player)
	if not data or not player.Parent then
		return
	end
	local view = ProfileLogic.view(data, os.time())
	view.Temporary = Profiles.IsTemporary(player)
	Net.fire(player, "ProfileView", view)
end

-- At most one view per player per frame, however many changes happen.
local function queueView(player: Player)
	if viewQueued[player] then
		return
	end
	viewQueued[player] = true
	task.defer(function()
		viewQueued[player] = nil
		sendView(player)
	end)
end

local function showTitle(player: Player)
	local data = Profiles.Get(player)
	local character = player.Character
	if not character then
		return
	end
	local title = if data then data.Equipped.Title else nil
	character:SetAttribute("Title", if title and data and data.Titles[title] then title else nil)
end

local function result(player: Player, payload: { [string]: any })
	Net.fire(player, "ShopResult", payload)
end

--------------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------------

local function onBuy(player: Player, kind: any, id: any, currency: any)
	if type(kind) ~= "string" or type(id) ~= "string" or type(currency) ~= "string" or #id > 40 then
		return
	end
	local data = Profiles.Get(player)
	if not data then
		return
	end
	if currency == "Robux" then
		local ok, reason = Shop.check(ProfileLogic.wallet(data), kind, id, "Robux")
		local offer = Shop.offer(kind, id)
		if ok and offer and Profiles.IsTemporary(player) then
			ok, reason = false, "Unsaved" -- a purchase could not be saved right now
		end
		if not ok or not offer or not Purchases.Prompt(player, offer.ProductKey) then
			result(player, { Ok = false, Reason = reason or "NoProduct", Kind = kind, Id = id })
		end
		return -- the rest happens in ProcessReceipt
	end
	local ok, reason, rewards = false, nil :: string?, {}
	Profiles.Update(player, function(profile: ProfileLogic.Data)
		ok, reason, rewards = ProfileLogic.buy(profile, kind, id, currency)
	end)
	result(player, { Ok = ok, Reason = reason, Kind = kind, Id = id, Rewards = rewards })
end

local function onEquip(player: Player, slot: any, id: any)
	if type(slot) ~= "string" or (id ~= nil and type(id) ~= "string") then
		return
	end
	local wanted: string? = if id == "" then nil else id
	local ok = false
	Profiles.Update(player, function(profile: ProfileLogic.Data)
		ok = ProfileLogic.equip(profile, slot, wanted)
	end)
	if ok and slot == "Title" then
		showTitle(player)
	end
	if not ok then
		result(player, { Ok = false, Reason = "NotOwned", Kind = "Equip", Id = id })
	end
end

local function onSpin(player: Player)
	local prize: ProfileLogic.Reward? = nil
	Profiles.Update(player, function(profile: ProfileLogic.Data)
		prize = ProfileLogic.spin(profile, os.time(), rng)
	end)
	Net.fire(player, "SpinResult", { Ok = prize ~= nil, Prize = prize })
end

local function onCode(player: Player, text: any)
	if not Profiles.Get(player) then
		return
	end
	local tries: { Count: number, LockedUntil: number } = wrongCodes[player.UserId] or { Count = 0, LockedUntil = 0 }
	wrongCodes[player.UserId] = tries
	if os.clock() < tries.LockedUntil then
		Net.fire(player, "CodeResult", { Ok = false, Reason = "TooMany" })
		return
	end
	local ok, outcome = false, nil :: any
	Profiles.Update(player, function(profile: ProfileLogic.Data)
		ok, outcome = Codes.redeem(profile, text, os.time(), CodeList)
	end)
	if ok then
		tries.Count = 0
	elseif outcome == "Unknown" then
		tries.Count += 1
		if tries.Count >= Config.CodeMaxWrong then
			tries.Count = 0
			tries.LockedUntil = os.clock() + Config.CodeLockSeconds
		end
	end
	Net.fire(player, "CodeResult", {
		Ok = ok,
		Reason = if ok then nil else outcome,
		Rewards = if ok then outcome else nil,
	})
end

--------------------------------------------------------------------------------

function EconomyService.Init() end

function EconomyService.Start()
	Net.on("ShopBuy", onBuy, 6, 5)
	Net.on("Equip", onEquip, 10, 5)
	Net.on("SpinRequest", onSpin, 3, 5)
	Net.on("CodeRedeem", onCode, 5, 10)

	Profiles.Loaded:Connect(function(player: Player)
		sendView(player)
		showTitle(player)
	end)
	Profiles.Changed:Connect(queueView)
	Purchases.Granted:Connect(function(player: Player, productKey: string, rewards: { any })
		local offer = Shop.offerForProduct(productKey)
		result(player, {
			Ok = true,
			Kind = if offer then offer.Kind else nil,
			Id = if offer then offer.Id else nil,
			Rewards = rewards,
			Robux = true,
		})
	end)

	local function watchCharacters(player: Player)
		player.CharacterAdded:Connect(function()
			showTitle(player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacters)
	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		viewQueued[player] = nil
		wrongCodes[player.UserId] = nil
	end)
end

return EconomyService
