--!strict
--[[
	Shop — what can be bought, for how much, and whether a player may buy it
	right now (GDD §13, §13.1). Shared: the lobby menus grey out what the
	server would refuse, and the server checks everything again.

	Currencies:
	  "Coins"     roles only (GDD §13.1)
	  "Diamonds"  everything Robux buys, at the same number (GDD §13)
	  "Robux"     a Developer Product (Config.Products.DevProducts)
]]

local Config = require(script.Parent.Parent.Config)

export type Kind = string -- "Role" | "Skin" | "Premium" | "Coins"
export type Currency = string -- "Coins" | "Diamonds" | "Robux"

export type Offer = {
	Kind: Kind,
	Id: string,
	Coins: number?, -- price in coins (roles only)
	Gems: number?, -- price in Robux, and the same number of Diamonds
	Gives: number?, -- coin packs: coins received
	ProductKey: string, -- key in Config.Products.DevProducts
	OneTime: boolean, -- can only be owned once (role, skin, premium)
}

-- The part of a profile the rules look at (the client gets the same fields).
export type Wallet = {
	Coins: number,
	Diamonds: number,
	Level: number,
	Roles: { [string]: boolean },
	Skins: { [string]: boolean },
	Premium: boolean,
}

local Shop = {}

local function coinPack(id: string): { Coins: number, Robux: number }?
	local amount = tonumber(id)
	for _, pack in Config.CoinPacks do
		if pack.Coins == amount then
			return pack
		end
	end
	return nil
end

-- The offer for one thing, or nil when it is not for sale.
function Shop.offer(kind: Kind, id: string): Offer?
	if kind == "Role" then
		local def = Config.Roles[id]
		if not def or def.Free or def.Kind == "Wolf" then
			return nil
		end
		local offer: Offer = { Kind = "Role", Id = id, Coins = def.CoinPrice, Gems = def.RobuxPrice, ProductKey = "Role" .. id, OneTime = true }
		return offer
	elseif kind == "Skin" then
		local def = Config.Skins[id]
		if not def or def.Source ~= "Shop" or type(def.Price) ~= "number" then
			return nil
		end
		local offer: Offer = { Kind = "Skin", Id = id, Gems = def.Price, ProductKey = "Skin" .. id, OneTime = true }
		return offer
	elseif kind == "Premium" then
		local price = Config.SeasonPass.PremiumRobuxPrice
		if price <= 0 then
			return nil
		end
		local offer: Offer = { Kind = "Premium", Id = "Premium", Gems = price, ProductKey = "SeasonPassPremium", OneTime = true }
		return offer
	elseif kind == "Coins" then
		local pack = coinPack(id)
		if not pack then
			return nil
		end
		local offer: Offer = {
			Kind = "Coins",
			Id = tostring(pack.Coins),
			Gems = pack.Robux,
			Gives = pack.Coins,
			ProductKey = "Coins" .. pack.Coins,
			OneTime = false,
		}
		return offer
	end
	return nil
end

-- The offer behind a Developer Product key (for receipts).
function Shop.offerForProduct(productKey: string): Offer?
	if productKey == "SeasonPassPremium" then
		return Shop.offer("Premium", "Premium")
	end
	for _, prefix in { "Role", "Skin", "Coins" } do
		if productKey:sub(1, #prefix) == prefix then
			return Shop.offer(prefix, productKey:sub(#prefix + 1))
		end
	end
	return nil
end

function Shop.owns(wallet: Wallet, kind: Kind, id: string): boolean
	if kind == "Role" then
		local def = Config.Roles[id]
		return (def ~= nil and def.Free) or wallet.Roles[id] == true
	elseif kind == "Skin" then
		return wallet.Skins[id] == true
	elseif kind == "Premium" then
		return wallet.Premium
	end
	return false
end

-- May this player buy it with this currency now? Returns a reason when not:
-- "NotForSale" | "Owned" | "Level" | "Funds" | "WrongCurrency" | "NoProduct"
function Shop.check(wallet: Wallet, kind: Kind, id: string, currency: Currency): (boolean, string?)
	local offer = Shop.offer(kind, id)
	if not offer then
		return false, "NotForSale"
	end
	if offer.OneTime and Shop.owns(wallet, kind, offer.Id) then
		return false, "Owned"
	end
	if kind == "Role" and Config.Shop.LevelGateForBuying and wallet.Level < Config.Roles[id].RequiredLevel then
		return false, "Level"
	end
	if currency == "Coins" then
		if not offer.Coins then
			return false, "WrongCurrency"
		end
		if wallet.Coins < offer.Coins then
			return false, "Funds"
		end
	elseif currency == "Diamonds" then
		if not offer.Gems then
			return false, "WrongCurrency"
		end
		if wallet.Diamonds < offer.Gems then
			return false, "Funds"
		end
	elseif currency == "Robux" then
		if (Config.Products.DevProducts[offer.ProductKey] or 0) == 0 then
			return false, "NoProduct" -- the owner has not created this product yet
		end
	else
		return false, "WrongCurrency"
	end
	return true, nil
end

return Shop
