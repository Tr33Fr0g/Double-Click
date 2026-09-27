--!nocheck
local T = require("./lib")
local GameConfig = require("../src/shared/Config/GameConfig")
local Stats = require("../src/shared/Combat/Stats")
local Speerrow = require("../src/shared/Characters/Speerrow")
local SpeerrowKit = require("../src/shared/Characters/SpeerrowKit")
local Dummy = require("../src/shared/Characters/Dummy")
local DummyAttacks = require("../src/shared/Config/DummyAttacks")

local function derive(def)
	return Stats.derive(def.stats, GameConfig.Stats, GameConfig.HealthByStat, def.movement.sprintSpeedOverride)
end

T.describe("Stats", function()
	T.it("health values follow the doc table", function()
		T.eq(derive(Speerrow).maxHp, 100)
		T.eq(derive(Dummy).maxHp, 125)
	end)
	T.it("Speerrow sprints about double the average character", function()
		local average = derive(Dummy).sprintSpeed
		local ratio = derive(Speerrow).sprintSpeed / average
		T.truthy(ratio > 1.8 and ratio < 2.2, "ratio was " .. ratio)
	end)
	T.it("fragile characters have a weaker block meter and fly farther", function()
		local s, d = derive(Speerrow), derive(Dummy)
		T.truthy(s.blockMeterMax < d.blockMeterMax)
		T.truthy(s.knockbackMult > d.knockbackMult)
	end)
	T.it("jump height and attack speed follow Speed", function()
		local s, d = derive(Speerrow), derive(Dummy)
		T.truthy(s.jumpHeight > d.jumpHeight)
		T.near(s.attackSpeed, 1.15)
		T.near(d.attackSpeed, 1)
	end)
end)

T.describe("Frame data", function()
	local attackSpeed = derive(Speerrow).attackSpeed
	local hits = Speerrow.m1.string

	T.it("each hit of Speerrow's string combos into the next (faster than the hitstun)", function()
		for i = 1, #hits - 1 do
			local hit, nextHit = hits[i], hits[i + 1]
			-- Contact at the start of the active phase; the next hit lands at the start of
			-- its own active phase.
			local gap = (hit.active + hit.recovery + nextHit.windup) / attackSpeed
			T.truthy(
				gap < hit.hitstun,
				string.format("hit %d -> %d: %.3fs vs %.3fs hitstun", i, i + 1, gap, hit.hitstun)
			)
		end
	end)

	T.it("the 3rd hit knocks back", function()
		T.truthy(hits[#hits].knockback ~= nil)
		for i = 1, #hits - 1 do
			T.eq(hits[i].knockback, nil)
		end
	end)

	T.it("every close block leaves a window to punish with an M1", function()
		local fastest = math.huge
		for _, move in hits do
			fastest = math.min(fastest, move.windup / attackSpeed)
		end
		for _, level in GameConfig.Combat.CloseBlock do
			for i, move in hits do
				local blockstun = (move.blockstun or 0) * level.blockstunMult
				local attackerFree = (move.active + move.recovery) / attackSpeed + level.attackerExtraRecovery
				local punishLands = blockstun + fastest
				T.truthy(
					punishLands < attackerFree,
					string.format(
						"%s vs hit %d: punish at %.3fs, attacker free at %.3fs",
						level.name,
						i,
						punishLands,
						attackerFree
					)
				)
			end
		end
	end)

	T.it("a normal block gives no punish window", function()
		local fastest = hits[1].windup / attackSpeed
		local move = hits[1]
		local attackerFree = (move.active + move.recovery) / attackSpeed
		T.truthy(move.blockstun + fastest >= attackerFree)
	end)

	T.it("Zap is fast enough to fit a Perfect close block (a 'very fast' ability)", function()
		local perfect = GameConfig.Combat.CloseBlock[1]
		local move = hits[1]
		local attackerFree = (move.active + move.recovery) / attackSpeed + perfect.attackerExtraRecovery
		T.truthy(SpeerrowKit.Zap.windup / attackSpeed < attackerFree)
	end)
end)

T.describe("Training dummy attacks", function()
	T.it("every attack in the cycle exists", function()
		for _, name in DummyAttacks.Order do
			local sequence = DummyAttacks.Sequences[name] or { name }
			for _, id in sequence do
				T.truthy(DummyAttacks.Attacks[id], "missing attack " .. id)
			end
		end
	end)
	T.it("every attack has a hitbox or a projectile", function()
		for id, move in DummyAttacks.Attacks do
			T.truthy(move.hitbox or move.projectile, id .. " has no hitbox")
		end
	end)
	T.it("covers melee, ranged, area, grab and ult variants", function()
		local kinds = {}
		local ults = 0
		for _, move in DummyAttacks.Attacks do
			kinds[move.kind] = true
			if move.isUltimate then
				ults += 1
			end
		end
		T.truthy(kinds.melee and kinds.ranged and kinds.area and kinds.grab)
		T.truthy(ults >= 3)
	end)
end)
