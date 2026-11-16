--!strict
--[[
	Loc — turns a text key (+ parameters) into the player's language.

	Uses the LocalizationTable built by build/BuildLocalization.luau. If that
	table is missing (not built yet) it falls back to Shared.Strings directly,
	so the game never shows raw keys. Locale is detected automatically.
]]

local LocalizationService = game:GetService("LocalizationService")

local Strings = require(script.Parent.Strings)

local TABLE_NAME = "WolfVillageStrings"

local Loc = {}

local translator: Translator? = nil
local triedTranslator = false

local function localeId(): string
	local ok, id = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	return if ok then id else "en-us"
end

local function getTranslator(): Translator?
	if not triedTranslator then
		triedTranslator = true
		local localizationTable = LocalizationService:FindFirstChild(TABLE_NAME)
		if localizationTable and localizationTable:IsA("LocalizationTable") then
			local ok, result = pcall(function()
				return localizationTable:GetTranslator(localeId())
			end)
			if ok then
				translator = result
			end
		end
	end
	return translator
end

-- "{name}" and "{count:int}" placeholders.
local function substitute(template: string, args: { [string]: any }?): string
	if not args then
		return template
	end
	local replaced = template:gsub("{(%w+):?%w*}", function(name: string): string
		local value = args[name]
		return if value == nil then "{" .. name .. "}" else tostring(value)
	end)
	return replaced
end

function Loc.has(key: string): boolean
	return Strings[key] ~= nil
end

function Loc.format(key: string, args: { [string]: any }?): string
	local active = getTranslator()
	if active then
		local ok, text = pcall(function()
			return active:FormatByKey(key, args)
		end)
		if ok and text ~= "" then
			return text
		end
	end
	local entry = Strings[key]
	if not entry then
		return key
	end
	local useThai = localeId():sub(1, 2) == "th"
	return substitute(if useThai then entry.th else entry.en, args)
end

return Loc
