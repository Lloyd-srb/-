--!strict
--[[
	Codes — redeeming a code on the Lobby's "Codes" page (GDD §3).
	Players may type any case and spaces around it. Each code works once per
	player and not after its expiry time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ProfileLogic = require(script.Parent.ProfileLogic)

export type CodeList = { [string]: { Rewards: { any }, Expires: number? } }

local Codes = {}

-- "  wolfVillage " -> "WOLFVILLAGE"; nil for anything that cannot be a code.
function Codes.normalize(text: any): string?
	if type(text) ~= "string" or #text > Config.CodeMaxLength * 4 then
		return nil
	end
	local code = text:match("^%s*(.-)%s*$") :: string
	code = code:upper()
	if #code == 0 or #code > Config.CodeMaxLength or code:find("[^%w_%-]") then
		return nil
	end
	return code
end

--[[
	Returns (true, rewards) or (false, reason):
	  "Unknown" (no such code), "Used" (already redeemed), "Expired".
]]
function Codes.redeem(data: ProfileLogic.Data, text: any, now: number, list: CodeList): (boolean, any)
	local code = Codes.normalize(text)
	local def = if code then list[code] else nil
	if not code or not def then
		return false, "Unknown"
	end
	if data.Codes[code] then
		return false, "Used"
	end
	if def.Expires and now > def.Expires then
		return false, "Expired"
	end
	data.Codes[code] = true
	local given = {}
	for _, reward in def.Rewards do
		table.insert(given, ProfileLogic.applyReward(data, reward))
	end
	return true, given
end

return Codes
