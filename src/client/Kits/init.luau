--!strict
-- Character kits on the client, looked up by CharacterDef.kit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local Speerrow = require(script.Speerrow)

local Kits = {}

-- Runs the kit's local part of an ability. Returns false if the request shouldn't be sent.
function Kits.onAbility(def: Types.CharacterDef, slot: string, aim: Vector3): boolean
	if def.kit == "Speerrow" then
		return Speerrow.onAbility(slot, aim)
	end
	return true
end

-- True while a kit is flying the character (M1s are ignored during Rush).
function Kits.busy(): boolean
	return Speerrow.isRushing()
end

function Kits.init()
	Speerrow.init()
end

return Kits
