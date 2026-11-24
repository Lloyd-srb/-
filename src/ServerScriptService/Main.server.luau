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
	require(Services.AudioService),
	require(Services.ForestService), -- before anything that looks for task trees
	require(Services.ProfileService),
	require(Services.MatchService),
	require(Services.RoundService),
	require(Services.RoleSelectService),
	require(Services.MoveService),
	require(Services.MovementGuard),
	require(Services.CombatService),
	require(Services.HouseService),
	require(Services.HidingService),
	require(Services.GearService), -- the Ninja's smoke bomb, the Hunter's traps
	require(Services.VoteService),
	require(Services.WolfService),
	require(Services.RoleService),
	require(Services.InventoryService),
	require(Services.ArsonService),
	require(Services.TaskService),
	require(Services.GhostService),
	require(Services.ChatService),
	require(Services.VoiceService),
	require(Services.EndService),
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
