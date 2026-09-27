--!strict
-- Speerrow's kit on the server: Parry (E), Zap (R), Rush (Q), Full Counter (G), Stacks
-- and Uncapped Speed. Rush movement is flown by the client (it owns the character's
-- physics); the server validates every Rush hit and handles blocks and stuns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Clock = require(Shared.Util.Clock)
local Damage = require(Shared.Combat.Damage)
local GameConfig = require(Shared.Config.GameConfig)
local SpeerrowKit = require(Shared.Characters.SpeerrowKit)
local Stacks = require(Shared.Combat.Stacks)
local Teams = require(Shared.Util.Teams)
local Timing = require(Shared.Combat.Timing)
local Types = require(Shared.Types)

local Actions = require(script.Parent.Parent.Actions)
local DebugService = require(script.Parent.Parent.DebugService)
local Fighter = require(script.Parent.Parent.Fighter)
local HitResolver = require(script.Parent.Parent.HitResolver)
local ServerNet = require(script.Parent.Parent.ServerNet)

type Fighter = Fighter.Fighter

local K = SpeerrowKit
local Combat = GameConfig.Combat
local def = Characters.get("Speerrow")

local RED = Color3.fromRGB(255, 60, 60)
local RUSH_HIT_RANGE = 16 -- server-side sanity check on client-reported Rush hits

local Speerrow = {}

local function reject(fighter: Fighter, slot: string)
	ServerNet.toPlayer(fighter.player, "AbilityRejected", { slot = slot })
end

local function stacksText(amount: number): string
	return if amount >= K.Stacks.Max then "max stacks" else `+{amount} stacks`
end

-- Passives -----------------------------------------------------------------------------

-- Stacks (+20% per whole stack) and Uncapped Speed (up to +50% at full sprint) add up.
function Speerrow.damageBonus(fighter: Fighter, _move: Types.MoveDef): number
	local stackBonus = Stacks.damageMultiplier(fighter.stacks, K.Stacks) - 1
	local speed = Fighter.planarSpeed(fighter, Clock.scale())
	if fighter.state == "Rushing" then
		speed = math.max(speed, K.Rush.Speed)
	end
	local speedBonus = Damage.speedBonus(speed, fighter.stats.sprintSpeed, K.UncappedSpeed.MaxBonus)
	return stackBonus + speedBonus
end

-- He loses 1 stack per hit that lands on him (blocked hits don't cost stacks, for now).
function Speerrow.onDamaged(fighter: Fighter)
	Stacks.loseOnHit(fighter.stacks, K.Stacks)
end

-- Rush -------------------------------------------------------------------------------

local function endRush(fighter: Fighter, now: number)
	local rush = fighter.kitState.rush
	if rush == nil then
		return
	end
	fighter.kitState.rush = nil
	fighter.intangible = false
	fighter.pose = nil
	if fighter.state == "Rushing" then
		Fighter.release(fighter, now)
	end
	-- Longer cooldown than his other abilities; it starts when the Rush ends.
	Fighter.setCooldown(fighter, "Q", now + def.abilities.Q.cooldown)
end

local function rushHit(fighter: Fighter, payload: { [string]: any }, now: number)
	local rush = fighter.kitState.rush
	if rush == nil or fighter.state ~= "Rushing" then
		return
	end
	local target = Fighter.get(payload.target)
	if target == nil or target == fighter or not Teams.areEnemies(fighter.model, target.model) then
		return
	end
	local offset = target.root.Position - fighter.root.Position
	if offset.Magnitude > RUSH_HIT_RANGE then
		return
	end
	local last = rush.lastHit[target.model]
	if last and now - last < K.Rush.SameTargetDelay then
		return
	end
	rush.lastHit[target.model] = now

	local result = HitResolver.resolve(fighter, target, K.Rush.Move, { direction = offset })
	if result == "Hit" then
		-- Each enemy hit gives 0.5 stacks.
		Stacks.gain(fighter.stacks, K.Stacks.RushGain, now, K.Stacks)
	elseif result == "Block" then
		-- Blocked: he bounces back, takes a 0.6s stun, and Rush ends.
		endRush(fighter, now)
		local away = Vector3.new(-offset.X, 0, -offset.Z)
		ServerNet.toPlayer(fighter.player, "RushBlocked", {
			away = if away.Magnitude > 1e-3 then away.Unit else -Fighter.facing(fighter),
		})
		HitResolver.stun(fighter, K.Rush.BlockedStun, now, "Rush blocked", target)
	end
end

-- Abilities --------------------------------------------------------------------------

local function parry(fighter: Fighter, payload: { [string]: any }, now: number)
	if not Fighter.canAct(fighter) or not Fighter.cooldownReady(fighter, "E", now) then
		reject(fighter, "E")
		return
	end
	local start = Fighter.pressTime(payload.t, now)
	fighter.parryStart = start
	fighter.blockStart = nil
	Fighter.setState(fighter, "Parrying", K.Parry.Stance - (now - start), now, "Parry")
	Fighter.setCooldown(fighter, "E", now + def.abilities.E.cooldown)
end

local function zap(fighter: Fighter, aim: Vector3, now: number)
	if not Fighter.canAct(fighter) or not Fighter.cooldownReady(fighter, "R", now) then
		reject(fighter, "R")
		return
	end
	-- Cooldown starts on use, so an interrupted Zap still goes on cooldown.
	Fighter.setCooldown(fighter, "R", now + def.abilities.R.cooldown)
	Actions.start(fighter, K.Zap, aim, now, "R")
end

local function rush(fighter: Fighter, now: number)
	if not Fighter.canAct(fighter) or not Fighter.cooldownReady(fighter, "Q", now) then
		reject(fighter, "Q")
		return
	end
	fighter.blockStart = nil
	Fighter.setState(fighter, "Rushing", K.Rush.ServerTimeout, now, "Rush")
	fighter.kitState.rush = { startedAt = now, lastHit = {} :: { [Model]: number } }
end

local function fullCounter(fighter: Fighter, payload: { [string]: any }, now: number)
	if fighter.ult < Combat.UltMax or not Fighter.canAct(fighter) then
		reject(fighter, "G")
		return
	end
	-- If nobody hits him in the window, he loses the whole ult.
	fighter.ult = 0
	local start = Fighter.pressTime(payload.t, now)
	fighter.counterStart = start
	fighter.blockStart = nil
	Fighter.setState(fighter, "Countering", math.max(0, K.FullCounter.Window - (now - start)), now, "Counter")
end

function Speerrow.ability(fighter: Fighter, slot: string, payload: { [string]: any }, now: number)
	local aim = if typeof(payload.aim) == "Vector3" then payload.aim :: Vector3 else Fighter.facing(fighter)
	if slot == "E" then
		parry(fighter, payload, now)
	elseif slot == "R" then
		zap(fighter, aim, now)
	elseif slot == "Q" then
		rush(fighter, now)
	elseif slot == "G" then
		fullCounter(fighter, payload, now)
	end
end

function Speerrow.message(fighter: Fighter, name: string, payload: { [string]: any }, now: number)
	if name == "RushLand" then
		-- He can't be hit during landings.
		if fighter.kitState.rush and fighter.state == "Rushing" then
			fighter.intangible = true
		end
	elseif name == "RushLaunch" then
		fighter.intangible = false
	elseif name == "RushHit" then
		rushHit(fighter, payload, now)
	elseif name == "RushEnd" then
		endRush(fighter, now)
	end
end

-- Parry and Full Counter resolution ------------------------------------------------------

function Speerrow.onParry(
	fighter: Fighter,
	attacker: Fighter,
	move: Types.MoveDef,
	timing: number,
	ctx: Fighter.HitContext
)
	local now = Clock.now()
	local tier = Timing.parryTier(timing, K.Parry.Tiers)
	if tier == nil then
		return
	end
	fighter.parryStart = nil
	Fighter.release(fighter, now)

	if tier.stacks >= K.Stacks.Max then
		Stacks.setMax(fighter.stacks, now, K.Stacks)
	else
		Stacks.gain(fighter.stacks, tier.stacks, now, K.Stacks)
	end

	if tier.cooldown == "refresh" then
		Fighter.setCooldown(fighter, "E", now)
	elseif tier.cooldown == "refreshAll" then
		for slot in fighter.cooldowns do
			fighter.cooldowns[slot] = now
		end
		fighter.m1LockUntil = -math.huge
	end

	-- A parry is a landed ability; a Perfect within 0.08s also gives +50% ult charge.
	Fighter.addUlt(fighter, Combat.UltPerAbilityHit * def.ultChargeRate)
	local extra = ""
	if tier.name == "Perfect" and timing <= K.Parry.PerfectUltWindow + 1e-9 then
		Fighter.addUlt(fighter, K.Parry.PerfectUltBonus)
		extra = " +50% ult charge."
	end

	-- The rest of the incoming damage is cancelled in every tier.
	local raw = HitResolver.rawDamage(attacker, move)
	local text = Timing.describe("Parry", tier.name, timing)
	if ctx.projectile then
		-- Ranged: damage cancelled and stacks gained, but nothing reflects and no stun.
		text ..= string.format(" Cancelled %.1f damage (ranged: no reflect), %s.", raw, stacksText(tier.stacks))
	else
		local stackBonus = Stacks.damageMultiplier(fighter.stacks, K.Stacks) - 1
		local reflected = Damage.compute(raw * tier.reflect, 1, stackBonus, attacker.stats.defenseMult)
		HitResolver.dealDamage(fighter, attacker, reflected, false)
		HitResolver.stun(attacker, K.Parry.MeleeStun, now, "Parry", fighter)
		text ..= string.format(
			" Reflected %.1f damage (%d%%), %s.",
			reflected,
			math.floor(tier.reflect * 100 + 0.5),
			stacksText(tier.stacks)
		)
	end

	HitResolver.flash({ fighter, attacker }, "PARRY: " .. string.upper(tier.name), tier.color)
	HitResolver.effect("Parry", fighter.root.Position, tier.color)
	DebugService.log({ fighter, attacker }, text .. extra, tier.color)
end

function Speerrow.onFullCounter(
	fighter: Fighter,
	attacker: Fighter,
	move: Types.MoveDef,
	timing: number,
	_ctx: Fighter.HitContext
)
	local now = Clock.now()
	fighter.counterStart = nil

	-- Reflects 5x the damage back to the attacker, and the attack is countered.
	local raw = HitResolver.rawDamage(attacker, move)
	local reflected = Damage.compute(raw * K.FullCounter.ReflectMult, 1, 0, attacker.stats.defenseMult)
	Fighter.cancelAction(attacker)
	HitResolver.dealDamage(fighter, attacker, reflected, true)

	-- Countering a grab-style ult plays a special counter animation.
	local isGrab = move.kind == "grab"
	fighter.intangible = true
	fighter.kitState.counterAnimUntil = now + (if isGrab then 0.6 else 0.25)
	Fighter.setState(
		fighter,
		"Recovery",
		if isGrab then 0.6 else 0.25,
		now,
		if isGrab then "CounterGrab" else "Counter"
	)

	local text = Timing.describe("Full Counter", "Success", timing)
		.. string.format(" Reflected %.1f damage (%dx).", reflected, K.FullCounter.ReflectMult)
	if move.isUltimate then
		-- Countering an ultimate stuns every enemy on the map for 3s.
		for _, other in Fighter.all do
			if other ~= fighter and Teams.areEnemies(fighter.model, other.model) and other.state ~= "Downed" then
				HitResolver.stun(other, K.FullCounter.UltStun, now, "Full Counter", fighter)
			end
		end
		text ..= " Countered an ultimate: every enemy is stunned!"
	end

	HitResolver.flash({ fighter, attacker }, "FULL COUNTER", RED)
	HitResolver.effect("FullCounter", fighter.root.Position, RED)
	DebugService.log({ fighter, attacker }, text, RED)
end

-- Upkeep -----------------------------------------------------------------------------------

function Speerrow.update(fighter: Fighter, now: number, _dt: number)
	Stacks.update(fighter.stacks, now, K.Stacks)

	local counterAnimUntil = fighter.kitState.counterAnimUntil
	if counterAnimUntil and now >= counterAnimUntil then
		fighter.kitState.counterAnimUntil = nil
		fighter.intangible = false
	end

	if fighter.state == "Parrying" and now >= fighter.stateUntil then
		fighter.parryStart = nil
		Fighter.setState(fighter, "Recovery", K.Parry.WhiffRecovery, now, "Recovery")
		DebugService.log({ fighter }, `Parry: missed (nothing hit within {K.Parry.Stance}s).`)
	elseif fighter.state == "Countering" and now >= fighter.stateUntil then
		fighter.counterStart = nil
		Fighter.setState(fighter, "Recovery", K.FullCounter.WhiffRecovery, now, "Recovery")
		DebugService.log({ fighter }, "Full Counter: missed. The ult is lost.", RED)
	end

	-- Knocked out of the Rush (hit, stunned, parried...) or timed out.
	if fighter.kitState.rush and (fighter.state ~= "Rushing" or now >= fighter.stateUntil) then
		endRush(fighter, now)
		ServerNet.toPlayer(fighter.player, "RushEnd", {})
	end
end

function Speerrow.reset(fighter: Fighter)
	fighter.kitState.rush = nil
	fighter.kitState.counterAnimUntil = nil
	fighter.intangible = false
end

function Speerrow.attach(fighter: Fighter)
	fighter.stackDuration = K.Stacks.Duration
	for slot in def.abilities do
		fighter.cooldowns[slot] = 0
	end
	fighter.kit = Speerrow.kit
end

Speerrow.kit = {
	damageBonus = Speerrow.damageBonus,
	onDamaged = Speerrow.onDamaged,
	onParry = Speerrow.onParry,
	onFullCounter = Speerrow.onFullCounter,
	ability = Speerrow.ability,
	message = Speerrow.message,
	update = Speerrow.update,
	reset = Speerrow.reset,
} :: Fighter.Kit

return Speerrow
