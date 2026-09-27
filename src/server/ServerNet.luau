--!strict
-- Server -> client helpers around the Event remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local ServerNet = {}

function ServerNet.toPlayer(player: Player?, name: string, payload: { [string]: any })
	if player and player.Parent == Players then
		Net.Event:FireClient(player, name, payload)
	end
end

function ServerNet.toAll(name: string, payload: { [string]: any })
	Net.Event:FireAllClients(name, payload)
end

-- Sends to the player controlling each model (dummies are skipped), once per player.
function ServerNet.toModels(models: { Model }, name: string, payload: { [string]: any })
	local sent: { [Player]: boolean } = {}
	for _, model in models do
		local player = Players:GetPlayerFromCharacter(model)
		if player and not sent[player] then
			sent[player] = true
			Net.Event:FireClient(player, name, payload)
		end
	end
end

return ServerNet
