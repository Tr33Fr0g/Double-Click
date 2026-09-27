--!strict
-- Attribute names the server writes on every fighter model. Clients read them for
-- movement limits, the HUD, placeholder animations and the debug overlay.

local Attr = {
	Tag = "DC_Fighter", -- CollectionService tag on every fighter model

	Character = "DC_Character",
	Team = "DC_Team",
	HP = "DC_HP",
	MaxHP = "DC_MaxHP",
	BlockMeter = "DC_BlockMeter",
	BlockMeterMax = "DC_BlockMeterMax",
	Ult = "DC_Ult",

	-- "Free" | "Attacking" | "Blocking" | "Blockstun" | "Hitstun" | "Stunned" | "Recovery"
	-- | "Parrying" | "Countering" | "Rushing" | "Dodging" | "Downed"
	State = "DC_State",
	StateUntil = "DC_StateUntil",
	MoveMult = "DC_MoveMult", -- 0..1, how much the fighter may move right now
	Blocking = "DC_Blocking",
	Intangible = "DC_Intangible",

	Action = "DC_Action", -- move name, "" when idle
	Pose = "DC_Pose", -- placeholder animation id
	Phase = "DC_Phase", -- "Windup" | "Active" | "Recovery" | ""
	PhaseStart = "DC_PhaseStart",
	PhaseEnd = "DC_PhaseEnd",

	Stacks = "DC_Stacks",
	StacksExpireAt = "DC_StacksExpireAt",
	StunCount = "DC_StunCount",
	StunImmuneUntil = "DC_StunImmuneUntil",
	LastStun = "DC_LastStun", -- duration of the last stun, for the overlay

	-- Cooldowns are stored as the game time they're ready at.
	CooldownPrefix = "DC_CD_",
}

function Attr.cooldown(slot: string): string
	return Attr.CooldownPrefix .. slot
end

return Attr
