--!nocheck
local T = require("./lib")
local GameConfig = require("../src/shared/Config/GameConfig")
local SpeerrowKit = require("../src/shared/Characters/SpeerrowKit")
local Timing = require("../src/shared/Combat/Timing")
local StunChain = require("../src/shared/Combat/StunChain")
local Stacks = require("../src/shared/Combat/Stacks")
local BlockMeter = require("../src/shared/Combat/BlockMeter")
local Resolve = require("../src/shared/Combat/Resolve")
local Damage = require("../src/shared/Combat/Damage")

local combat = GameConfig.Combat

T.describe("Close blocks", function()
	local function level(t)
		local l = Timing.closeBlockLevel(t, combat.CloseBlock)
		return l and l.name or "Normal"
	end
	T.it("Perfect at 0.1s or less", function()
		T.eq(level(0), "Perfect")
		T.eq(level(0.05), "Perfect")
		T.eq(level(0.1), "Perfect")
	end)
	T.it("Great at 0.2s or less", function()
		T.eq(level(0.11), "Great")
		T.eq(level(0.17), "Great")
		T.eq(level(0.2), "Great")
	end)
	T.it("Good at 0.3s or less", function()
		T.eq(level(0.25), "Good")
		T.eq(level(0.3), "Good")
	end)
	T.it("Normal block when slower than 0.3s", function()
		T.eq(level(0.31), "Normal")
		T.eq(level(2), "Normal")
	end)
	T.it("prints the doc's feedback format", function()
		T.eq(Timing.describe("Close block", "Great", 0.17), "Close block: Great, 0.17s (10 frames) before impact.")
		T.eq(Timing.describe("Parry", "Perfect", 1 / 60), "Parry: Perfect, 0.02s (1 frame) before impact.")
	end)
end)

T.describe("Parry tiers", function()
	local tiers = SpeerrowKit.Parry.Tiers
	local function tier(t)
		local found = Timing.parryTier(t, tiers)
		return found and found.name or "None"
	end
	T.it("matches the doc's table", function()
		T.eq(tier(0.1), "Perfect")
		T.eq(tier(0.25), "Perfect")
		T.eq(tier(0.3), "Good")
		T.eq(tier(0.42), "Good")
		T.eq(tier(0.5), "Basic")
		T.eq(tier(0.58), "Basic")
		T.eq(tier(0.65), "Weak")
		T.eq(tier(0.73), "Weak")
		T.eq(tier(0.8), "None")
	end)
	T.it("folds the doc's small gaps into the slower tier", function()
		T.eq(tier(0.26), "Good")
		T.eq(tier(0.425), "Basic")
		T.eq(tier(0.59), "Weak")
	end)
	T.it("reflects and grants stacks per tier", function()
		local byName = {}
		for _, t in tiers do
			byName[t.name] = t
		end
		T.eq(byName.Weak.reflect, 0.15)
		T.eq(byName.Basic.reflect, 0.2)
		T.eq(byName.Good.reflect, 0.35)
		T.eq(byName.Perfect.reflect, 0.75)
		T.eq(byName.Weak.stacks, 1)
		T.eq(byName.Basic.stacks, 2)
		T.eq(byName.Good.stacks, 3)
		T.eq(byName.Perfect.stacks, 5)
		T.eq(byName.Good.cooldown, "refresh")
		T.eq(byName.Perfect.cooldown, "refreshAll")
	end)
end)

T.describe("Repeated-stun rule", function()
	local cfg = combat.Stun
	T.it("shrinks each stun in a row: 100/75/50/25%", function()
		local s = StunChain.new()
		T.near(StunChain.apply(s, 0, 1, cfg).duration, 1)
		T.near(StunChain.apply(s, 1.5, 1, cfg).duration, 0.75)
		T.near(StunChain.apply(s, 3, 1, cfg).duration, 0.5)
		T.near(StunChain.apply(s, 4.5, 1, cfg).duration, 0.25)
	end)
	T.it("is immune for 2s after the 4th stun, then resets", function()
		local s = StunChain.new()
		StunChain.apply(s, 0, 1, cfg)
		StunChain.apply(s, 1, 1, cfg)
		StunChain.apply(s, 2, 1, cfg)
		StunChain.apply(s, 3, 1, cfg) -- 0.25s, ends at 3.25; immune until 5.25
		T.truthy(StunChain.apply(s, 4, 1, cfg).immune, "immune during the window")
		T.truthy(StunChain.isImmune(s, 5.2), "still immune at 5.2")
		local fresh = StunChain.apply(s, 5.3, 1, cfg)
		T.eq(fresh.immune, false)
		T.near(fresh.duration, 1, 1e-6, "chain reset after immunity")
	end)
	T.it("resets after 3s with no stuns", function()
		local s = StunChain.new()
		StunChain.apply(s, 0, 1, cfg)
		T.near(StunChain.apply(s, 3.01, 1, cfg).duration, 1)
	end)
	T.it("peek reports the chain for the overlay", function()
		local s = StunChain.new()
		StunChain.apply(s, 0, 0.5, cfg)
		StunChain.apply(s, 0.5, 0.5, cfg)
		local count, immuneLeft = StunChain.peek(s, 1, cfg)
		T.eq(count, 2)
		T.eq(immuneLeft, 0)
	end)
end)

T.describe("Speerrow stacks", function()
	local cfg = SpeerrowKit.Stacks
	T.it("caps at 5 and gives +20% damage per whole stack", function()
		local s = Stacks.new()
		Stacks.gain(s, 3, 0, cfg)
		Stacks.gain(s, 0.5, 0, cfg)
		T.near(s.value, 3.5)
		T.near(Stacks.damageMultiplier(s, cfg), 1.6, 1e-6, "half stacks don't count for damage")
		Stacks.gain(s, 5, 0, cfg)
		T.near(s.value, 5)
		T.near(Stacks.damageMultiplier(s, cfg), 2, 1e-6, "double damage at 5 stacks")
	end)
	T.it("Rush speed counts half stacks, up to +50%", function()
		local s = Stacks.new()
		Stacks.gain(s, 0.5, 0, cfg)
		T.near(Stacks.rushSpeedMultiplier(s, cfg), 1.05)
		Stacks.setMax(s, 0, cfg)
		T.near(Stacks.rushSpeedMultiplier(s, cfg), 1.5)
	end)
	T.it("loses 1 per hit without resetting the timer", function()
		local s = Stacks.new()
		Stacks.gain(s, 2.5, 0, cfg)
		Stacks.loseOnHit(s, cfg)
		T.near(s.value, 1.5)
		T.eq(s.lastGainAt, 0, "loss doesn't touch the timer")
	end)
	T.it("all stacks drop 10s after the last gain", function()
		local s = Stacks.new()
		Stacks.gain(s, 2, 0, cfg)
		Stacks.gain(s, 1, 4, cfg)
		T.eq(Stacks.update(s, 13.9, cfg), false)
		T.near(Stacks.expiresIn(s, 13, cfg), 1)
		T.eq(Stacks.update(s, 14, cfg), true)
		T.eq(s.value, 0)
	end)
end)

T.describe("Block meter", function()
	T.it("drains per blocked damage and breaks at 0", function()
		local m = BlockMeter.new(30)
		T.eq(BlockMeter.drain(m, 10, 0, combat), false)
		T.near(m.value, 15)
		T.eq(BlockMeter.drain(m, 10, 0.5, combat), true)
		T.eq(m.value, 0)
	end)
	T.it("regenerates only after the delay and while not blocking", function()
		local m = BlockMeter.new(100)
		BlockMeter.drain(m, 20, 0, combat)
		BlockMeter.update(m, 1, 1, false, combat)
		T.near(m.value, 70, 1e-6, "no regen during the delay")
		BlockMeter.update(m, 1, 2, true, combat)
		T.near(m.value, 70, 1e-6, "no regen while blocking")
		BlockMeter.update(m, 1, 2, false, combat)
		T.near(m.value, 70 + combat.BlockMeterRegenRate)
	end)
end)

T.describe("Hit resolution", function()
	local cfg = {
		fullCounterWindow = SpeerrowKit.FullCounter.Window,
		parryStance = SpeerrowKit.Parry.Stance,
		blockArcDot = Resolve.arcDot(combat.BlockArcDegrees),
	}
	local function defender(overrides)
		local d = {
			intangible = false,
			downed = false,
			counterStart = nil,
			parryStart = nil,
			blocking = false,
			blockStart = nil,
			facingDot = 1,
		}
		for k, v in overrides or {} do
			d[k] = v
		end
		return d
	end
	local melee = { kind = "melee" }
	local ranged = { kind = "ranged" }
	local area = { kind = "area" }
	local grab = { kind = "grab" }
	local areaUlt = { kind = "area", isUltimate = true }
	local grabUlt = { kind = "grab", isUltimate = true }

	T.it("plain hit", function()
		T.eq(Resolve.decide(melee, defender(), 1, cfg).result, "Hit")
	end)
	T.it("intangible (Rush landing) ignores hits", function()
		T.eq(Resolve.decide(melee, defender({ intangible = true }), 1, cfg).result, "Ignored")
	end)
	T.it("blocks from the front and measures timing", function()
		local out = Resolve.decide(melee, defender({ blocking = true, blockStart = 0.83 }), 1, cfg)
		T.eq(out.result, "Block")
		T.near(out.timing, 0.17)
	end)
	T.it("a block pressed after the impact doesn't count", function()
		T.eq(Resolve.decide(melee, defender({ blocking = true, blockStart = 1.01 }), 1, cfg).result, "Hit")
	end)
	T.it("doesn't block from behind", function()
		T.eq(
			Resolve.decide(melee, defender({ blocking = true, blockStart = 0, facingDot = -0.5 }), 1, cfg).result,
			"Hit"
		)
	end)
	T.it("grabs can't be blocked or parried", function()
		T.eq(Resolve.decide(grab, defender({ blocking = true, blockStart = 0 }), 1, cfg).result, "Hit")
		T.eq(Resolve.decide(grab, defender({ parryStart = 0.9 }), 1, cfg).result, "Hit")
	end)
	T.it("melee and ranged can be parried, area can't", function()
		T.eq(Resolve.decide(melee, defender({ parryStart = 0.8 }), 1, cfg).result, "Parry")
		T.eq(Resolve.decide(ranged, defender({ parryStart = 0.8 }), 1, cfg).result, "Parry")
		T.eq(Resolve.decide(area, defender({ parryStart = 0.8 }), 1, cfg).result, "Hit")
	end)
	T.it("area attacks can still be blocked", function()
		T.eq(Resolve.decide(area, defender({ blocking = true, blockStart = 0 }), 1, cfg).result, "Block")
	end)
	T.it("parry that was pressed too early doesn't count", function()
		T.eq(Resolve.decide(melee, defender({ parryStart = 0 }), 1, cfg).result, "Hit")
	end)
	T.it("Full Counter only in the perfect window", function()
		T.eq(Resolve.decide(melee, defender({ counterStart = 0.8 }), 1, cfg).result, "FullCounter")
		T.eq(Resolve.decide(melee, defender({ counterStart = 0.7 }), 1, cfg).result, "Hit")
	end)
	T.it("Full Counter catches area and grab ults, but not regular area/grab", function()
		T.eq(Resolve.decide(areaUlt, defender({ counterStart = 0.9 }), 1, cfg).result, "FullCounter")
		T.eq(Resolve.decide(grabUlt, defender({ counterStart = 0.9 }), 1, cfg).result, "FullCounter")
		T.eq(Resolve.decide(area, defender({ counterStart = 0.9 }), 1, cfg).result, "Hit")
		T.eq(Resolve.decide(grab, defender({ counterStart = 0.9 }), 1, cfg).result, "Hit")
	end)
	T.it("Full Counter beats parry beats block", function()
		local d = defender({ counterStart = 0.9, parryStart = 0.9, blocking = true, blockStart = 0.9 })
		T.eq(Resolve.decide(melee, d, 1, cfg).result, "FullCounter")
		d.counterStart = nil
		T.eq(Resolve.decide(melee, d, 1, cfg).result, "Parry")
	end)
end)

T.describe("Damage", function()
	T.it("speed bonus is 0 standing and +50% at full sprint", function()
		T.near(Damage.speedBonus(0, 52, 0.5), 0)
		T.near(Damage.speedBonus(26, 52, 0.5), 0.25)
		T.near(Damage.speedBonus(110, 52, 0.5), 0.5)
	end)
	T.it("adds bonuses, then applies stat multipliers", function()
		-- 3 base, Damage 1 (x0.8), 5 stacks (+100%) and full sprint (+50%), Defense 3 target.
		T.near(Damage.compute(3, 0.8, 1.5, 1), 6)
	end)
end)
