--!strict
-- Character kits on the server, looked up by CharacterDef.kit.

local Fighter = require(script.Parent.Fighter)
local Speerrow = require(script.Speerrow)

type Fighter = Fighter.Fighter

local Kits = {}

function Kits.attach(fighter: Fighter)
	if fighter.def.kit == "Speerrow" then
		Speerrow.attach(fighter)
	end
end

return Kits
