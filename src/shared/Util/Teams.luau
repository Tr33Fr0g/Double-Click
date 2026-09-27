--!strict
-- Friendly fire is off in every mode (doc). Two fighters are allies when they share a
-- team id; the beta puts every player on their own team and dummies on team "Dummy",
-- so everyone can hit everyone.

local Attr = require(script.Parent.Attr)

local Teams = {}

function Teams.of(model: Instance): string
	local team = model:GetAttribute(Attr.Team)
	return if type(team) == "string" then team else model.Name
end

function Teams.areEnemies(a: Instance, b: Instance): boolean
	if a == b then
		return false
	end
	return Teams.of(a) ~= Teams.of(b)
end

return Teams
