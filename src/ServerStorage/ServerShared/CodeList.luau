--!strict
--[[
	CodeList — the redeemable codes (Lobby "Codes" page, GDD §3).

	Kept in ServerStorage: anything in ReplicatedStorage (like Config) can be
	read by every client, and a code list there would be public.

	Key = the code in CAPITALS (players may type any case).
	Rewards use the same kinds as the Season Pass: Coins, Diamonds, Spin,
	Skin (Id), Title (Id), Role (Id).
	Expires = os.time() seconds (UTC), or nil for never.
]]

export type CodeDef = {
	Rewards: { { Kind: string, Amount: number?, Id: string? } },
	Expires: number?,
}

local CodeList: { [string]: CodeDef } = {
	-- [ASSUMED] example code until the owner sends real ones (OWNER_TODO 67).
	WOLFVILLAGE = { Rewards = { { Kind = "Coins", Amount = 200 } }, Expires = nil },
}

return CodeList
