--!strict
--[[
	Server bootstrap for the Lobby place: the only Script on the server.
	Every service exposes Init() and Start() (see the Match place's Main).
]]

local ServerStorage = game:GetService("ServerStorage")

local Services = script.Parent.Services

type Service = { Init: () -> (), Start: () -> () }

local ordered: { Service } = {
	require(ServerStorage:WaitForChild("ServerShared"):WaitForChild("Net")),
	require(Services.QueueService),
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
