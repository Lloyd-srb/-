--!strict
--[[
	Purchases — Robux Developer Products (GDD §13), for both places.

	MarketplaceService.ProcessReceipt is idempotent:
	  - every purchase id given is stored in the player's profile
	    (Config.Data.ReceiptHistory most recent ones);
	  - a purchase id already in the profile is never given again;
	  - "granted" is only answered once the profile with that purchase id is
	    saved. Otherwise Roblox asks again later (on this or another server),
	    and the saved data decides.
	A purchase for a player whose profile is not loaded, or is temporary
	(DataStore down), waits: Roblox keeps asking until it can be saved.

	Product ids come from Config.Products.DevProducts (0 = not created yet).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local ProfileLogic = require(script.Parent.Logic.ProfileLogic)
local Profiles = require(script.Parent.Profiles)

local Purchases = {}

Purchases.Granted = Signal.new() -- (player, productKey, rewards)

local RECEIPT_WAIT = 15 -- seconds to wait for a joining player's profile

local function productKeyOf(productId: number): string?
	for productKey, id in Config.Products.DevProducts do
		if id ~= 0 and id == productId then
			return productKey
		end
	end
	return nil
end

function Purchases.ProcessReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local productKey = productKeyOf(info.ProductId)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not productKey then
		warn(`[Purchases] unknown product id {tostring(info.ProductId)}: add it to Config.Products.DevProducts`)
		return notYet
	end
	if not player then
		return notYet
	end
	local data = Profiles.WaitFor(player, RECEIPT_WAIT)
	if not data or Profiles.IsTemporary(player) then
		return notYet
	end

	local purchaseId = tostring(info.PurchaseId)
	if ProfileLogic.hasReceipt(data, purchaseId) then
		-- Already given; maybe the earlier "granted" never arrived, or the
		-- save failed. Confirm only once it is on disk.
		return if Profiles.SaveNow(player) then Enum.ProductPurchaseDecision.PurchaseGranted else notYet
	end

	local rewards: { ProfileLogic.Reward }? = nil
	Profiles.Update(player, function(profile: ProfileLogic.Data)
		rewards = ProfileLogic.grantProduct(profile, productKey)
		ProfileLogic.addReceipt(profile, purchaseId)
	end)
	if not Profiles.SaveNow(player) then
		return notYet -- the receipt id is kept in memory: the retry confirms after a save
	end
	Purchases.Granted:Fire(player, productKey, rewards or {})
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Opens Roblox's purchase window. False if the product is not set up yet.
function Purchases.Prompt(player: Player, productKey: string): boolean
	local productId = Config.Products.DevProducts[productKey]
	if not productId or productId == 0 then
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	return ok
end

function Purchases.Init() end

function Purchases.Start()
	MarketplaceService.ProcessReceipt = Purchases.ProcessReceipt
end

return Purchases
