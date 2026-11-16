--!strict
--[[
	BuildLocalization — builds LocalizationService.WolfVillageStrings (en + th)
	from ReplicatedStorage.Shared.Strings. Run in Studio whenever Strings changes.
	Idempotent. (Studio only: uses LocalizationTable:SetEntries.)
]]

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
assert(Shared, "BuildLocalization: ReplicatedStorage.Shared is missing (import src/ first)")
local Strings = (require :: any)((Shared :: any).Strings:Clone())

local TABLE_NAME = "WolfVillageStrings"

local old = LocalizationService:FindFirstChild(TABLE_NAME)
if old then
	old:Destroy()
end

local entries = {}
for key, text in Strings do
	table.insert(entries, {
		Key = key,
		Source = text.en,
		Context = "",
		Example = "",
		Values = { en = text.en, th = text.th },
	})
end
table.sort(entries, function(a, b)
	return a.Key < b.Key
end)

local localizationTable = Instance.new("LocalizationTable")
localizationTable.Name = TABLE_NAME
localizationTable.SourceLocaleId = "en"
localizationTable:SetEntries(entries)
localizationTable.Parent = LocalizationService

print(string.format("[BuildLocalization] done: %d keys", #entries))
