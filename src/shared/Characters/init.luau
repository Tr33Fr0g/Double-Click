--!strict
-- Character registry. The first beta ships Speerrow (playable) and the training dummy.

local Types = require(script.Parent.Types)

local speerrow: Types.CharacterDef = require(script.Speerrow)
local dummy: Types.CharacterDef = require(script.Dummy)

local defs: { [string]: Types.CharacterDef } = {
	[speerrow.id] = speerrow,
	[dummy.id] = dummy,
}

local Characters = {}

Characters.Default = speerrow.id
Characters.Playable = { speerrow.id }

function Characters.get(id: string): Types.CharacterDef
	local def = defs[id]
	assert(def, `Unknown character "{id}"`)
	return def
end

function Characters.tryGet(id: string?): Types.CharacterDef?
	if id == nil then
		return nil
	end
	return defs[id]
end

return Characters
