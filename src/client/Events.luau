--!strict
-- Routes server -> client events (the Event remote) to handlers by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

type Handler = (payload: { [string]: any }) -> ()

local Events = {}

local handlers: { [string]: { Handler } } = {}

function Events.on(name: string, handler: Handler)
	local list = handlers[name]
	if list == nil then
		list = {}
		handlers[name] = list
	end
	table.insert(list, handler)
end

function Events.send(name: string, payload: { [string]: any }?)
	Net.Action:FireServer(name, payload or {})
end

function Events.init()
	Net.Event.OnClientEvent:Connect(function(name: any, payload: any)
		if type(name) ~= "string" then
			return
		end
		local list = handlers[name]
		if list == nil then
			return
		end
		local data = if type(payload) == "table" then payload else {}
		for _, handler in list do
			task.spawn(handler, data)
		end
	end)
end

return Events
