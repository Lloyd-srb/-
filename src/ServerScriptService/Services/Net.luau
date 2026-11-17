--!strict
-- The rate-limited remotes live in ServerStorage.ServerShared so the Lobby
-- place can use the same code. This keeps the Match place's requires short.
local ServerStorage = game:GetService("ServerStorage")

return require(ServerStorage:WaitForChild("ServerShared"):WaitForChild("Net"))
