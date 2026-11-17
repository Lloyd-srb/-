--!strict
--[[
	Server bootstrap for the Lobby place: the only Script on the server.
	Every service exposes Init() and Start() (see the Match place's Main).
]]

local ServerStorage = game:GetService("ServerStorage")

local Services = script.Parent.Services

type Service = { Init: () -> (), Start: () -> () }

local ServerShared = ServerStorage:WaitForChild("ServerShared")

local ordered: { Service } = {
	require(ServerShared:WaitForChild("Net")),
	require(ServerShared:WaitForChild("Profiles")),
	require(ServerShared:WaitForChild("Purchases")),
	require(Services.QueueService),
	require(Services.EconomyService),
}

if not workspace:FindFirstChild("Lobby") then
	warn("[Main] Workspace.Lobby is missing: run build/lobby/BuildLobby.luau in Studio")
end

for _, service in ordered do
	service.Init()
end
for _, service in ordered do
	service.Start()
end
