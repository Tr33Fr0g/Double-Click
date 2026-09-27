--!strict
-- RemoteEvents (declared in default.project.json so they exist before any script runs).
--   Action: client -> server gameplay requests  (name, payload)
--   Event:  server -> client notifications      (name, payload)
--   Debug:  client -> server debug commands     (command, args)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

return {
	Action = folder:WaitForChild("Action") :: RemoteEvent,
	Event = folder:WaitForChild("Event") :: RemoteEvent,
	Debug = folder:WaitForChild("Debug") :: RemoteEvent,
}
