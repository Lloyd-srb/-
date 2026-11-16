--!strict
--[[
	Server bootstrap for the Match place: the only Script on the server.
	Every service exposes Init() (set up own state, no cross-service calls)
	and Start() (connect to other services, begin work).
]]

local Services = script.Parent.Services

type Service = { Init: () -> (), Start: () -> () }

local ordered: { Service } = {
	require(Services.Net),
	require(Services.MatchService),
	require(Services.RoundService),
	require(Services.HouseService),
	require(Services.VoteService),
	require(Services.LightingService),
}

if not workspace:FindFirstChild("Map") then
	warn("[Main] Workspace.Map is missing: run build/BuildVillage.luau in Studio")
end

for _, service in ordered do
	service.Init()
end
for _, service in ordered do
	service.Start()
end
