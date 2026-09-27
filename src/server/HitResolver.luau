--!strict
-- Applies what happens when an attack reaches a fighter: Full Counter, parry, block
-- (including close blocks and block breaks) or a clean hit with damage, hitstun, stuns
-- and knockback. Also owns the repeated-stun rule and wall stuns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BlockMeter = require(Shared.Combat.BlockMeter)
local Clock = require(Shared.Util.Clock)
local Damage = require(Shared.Combat.Damage)
local GameConfig = require(Shared.Config.GameConfig)
local Resolve = require(Shared.Combat.Resolve)
local SpeerrowKit = require(Shared.Characters.SpeerrowKit)
local StunChain = require(Shared.Combat.StunChain)
local Timing = require(Shared.Combat.Timing)
local Types = require(Shared.Types)

local DebugService = require(script.Parent.DebugService)
local Fighter = require(script.Parent.Fighter)
local ServerNet = require(script.Parent.ServerNet)

type Fighter = Fighter.Fighter
type HitContext = Fighter.HitContext

local Combat = GameConfig.Combat

local HitResolver = {}

local resolveConfig: Resolve.Config = {
	fullCounterWindow = SpeerrowKit.FullCounter.Window,
	parryStance = SpeerrowKit.Parry.Stance,
	blockArcDot = Resolve.arcDot(Combat.BlockArcDegrees),
}

local arenaParams = RaycastParams.new()
arenaParams.FilterType = Enum.RaycastFilterType.Include

local ORDINALS = { "1st", "2nd", "3rd", "4th" }

function HitResolver.setArena(arena: Instance)
	arenaParams.FilterDescendantsInstances = { arena }
end

local function planar(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-3 then v.Unit else fallback
end

-- Effects and feedback -----------------------------------------------------------------

function HitResolver.effect(kind: string, position: Vector3, color: Color3?)
	ServerNet.toAll("Effect", { kind = kind, position = position, color = color })
end

-- The colored flash both players see (close blocks, parries, Full Counters).
function HitResolver.flash(fighters: { Fighter }, label: string, color: Color3)
	local models = {}
	for _, fighter in fighters do
		table.insert(models, fighter.model)
	end
	ServerNet.toModels(models, "Flash", { label = label, color = color })
end

-- Damage -------------------------------------------------------------------------------

local function bonusFor(attacker: Fighter, move: Types.MoveDef): number
	local kit = attacker.kit
	if kit and kit.damageBonus then
		return kit.damageBonus(attacker, move)
	end
	return 0
end

-- Damage before the defender's Defense (used for block meter drain and reflects).
function HitResolver.rawDamage(attacker: Fighter, move: Types.MoveDef): number
	return Damage.compute(move.damage, attacker.stats.damageMult, bonusFor(attacker, move), 1)
end

local function down(target: Fighter, now: number, attacker: Fighter?)
	target.hp = 0
	Fighter.cancelAction(target)
	target.parryStart = nil
	target.counterStart = nil
	target.intangible = false
	Fighter.setState(target, "Downed", Combat.DownedTime, now)
	target.stopMotion()
	DebugService.log({ attacker, target }, `{target.model.Name} is down (0 HP).`)
	HitResolver.effect("Downed", target.root.Position)
end

-- Removes HP, charges the attacker's ult and runs on-damaged passives.
function HitResolver.dealDamage(attacker: Fighter?, target: Fighter, amount: number, isAbility: boolean)
	if amount <= 0 or target.state == "Downed" then
		return
	end
	target.hp -= amount
	target.kitState.lastDamagedAt = Clock.now()
	if attacker and attacker ~= target then
		local charge = amount * Combat.UltPerDamage + (if isAbility then Combat.UltPerAbilityHit else 0)
		Fighter.addUlt(attacker, charge * attacker.def.ultChargeRate)
	end
	local kit = target.kit
	if kit and kit.onDamaged then
		kit.onDamaged(target)
	end
	if target.hp <= 0 then
		if target.kitState.infiniteHp then
			target.hp = target.stats.maxHp
		else
			down(target, Clock.now(), attacker)
		end
	end
end

-- Stuns and knockback ------------------------------------------------------------------

-- Applies a stun through the repeated-stun rule. Returns the actual duration (0 if the
-- target was immune or has hyper armor).
function HitResolver.stun(target: Fighter, base: number, now: number, source: string, attacker: Fighter?): number
	if target.state == "Downed" then
		return 0
	end
	if target.hyperArmor then
		DebugService.log({ attacker, target }, `{source}: no stun (hyper armor).`)
		return 0
	end
	local result = StunChain.apply(target.stun, now, base, Combat.Stun)
	if result.immune then
		DebugService.log({ attacker, target }, `{source}: no stun, {target.model.Name} is immune (repeated-stun rule).`)
		return 0
	end
	Fighter.cancelAction(target)
	target.parryStart = nil
	target.counterStart = nil
	target.blockStart = nil
	local untilTime = now + result.duration
	if not (target.state == "Stunned" and target.stateUntil > untilTime) then
		Fighter.setState(target, "Stunned", result.duration, now)
	end
	target.model:SetAttribute("DC_LastStun", result.duration)
	local percent = math.floor(Combat.Stun.Multipliers[result.index] * 100 + 0.5)
	DebugService.log(
		{ attacker, target },
		string.format(
			"%s: stunned %.2fs (%s in a row, %d%%).",
			source,
			result.duration,
			ORDINALS[result.index] or tostring(result.index),
			percent
		)
	)
	HitResolver.effect("Stun", target.root.Position + Vector3.new(0, 3, 0))
	return result.duration
end

function HitResolver.knockback(target: Fighter, velocity: Vector3, now: number)
	if target.hyperArmor or target.state == "Downed" then
		return
	end
	target.knockbackUntil = now + Combat.WallStunCheckTime
	target.knockbackDir = unitOr(planar(velocity), Vector3.zero)
	target.wallStunned = false
	target.applyKnockback(velocity, Combat.KnockbackLock)
end

-- Knocked into a wall -> wall stun (0.4s, follows the repeated-stun rule).
function HitResolver.stepKnockback(fighter: Fighter, now: number)
	if fighter.wallStunned or now > fighter.knockbackUntil then
		return
	end
	local scale = Clock.scale()
	if scale <= 0 then
		return
	end
	local velocity = planar(fighter.root.AssemblyLinearVelocity) / scale
	if velocity.Magnitude < Combat.WallStunMinSpeed then
		return
	end
	local direction = velocity.Unit
	local result = workspace:Raycast(fighter.root.Position, direction * Combat.WallStunDistance, arenaParams)
	if result and math.abs(result.Normal.Y) < GameConfig.Movement.WallMaxNormalY then
		fighter.wallStunned = true
		fighter.knockbackUntil = -math.huge
		fighter.stopMotion()
		HitResolver.effect("Wall", result.Position)
		HitResolver.stun(fighter, Combat.WallStun, now, "Wall stun", fighter.lastAttacker)
	end
end

-- Close-blocked attackers stop hitting and sit in a longer recovery: the punish window.
local function punish(attacker: Fighter, extra: number, now: number)
	local action = attacker.action
	if action == nil then
		return
	end
	local remaining = if action.phase == "Recovery"
		then math.max(0, action.phaseEnd - now)
		else action.move.recovery / action.speed
	action.phase = "Recovery"
	action.phaseStart = now
	action.phaseEnd = now + remaining + extra
	action.extraRecovery = extra
	action.isStringEnd = true
	attacker.buffered = nil
	attacker.m1Index = 1
	DebugService.hitbox(attacker, action.move, "Recovery", action.aim, action.phaseEnd)
end

-- Resolution ---------------------------------------------------------------------------

local function directionFromAttacker(attacker: Fighter, target: Fighter, ctx: HitContext): Vector3
	local fallback = Fighter.facing(attacker)
	if ctx.direction then
		return unitOr(planar(ctx.direction), fallback)
	end
	local from = ctx.origin or attacker.root.Position
	return unitOr(planar(target.root.Position - from), fallback)
end

local function defenderView(attacker: Fighter, target: Fighter, ctx: HitContext): Resolve.DefenderView
	local toAttacker = -directionFromAttacker(attacker, target, ctx)
	return {
		intangible = target.intangible,
		downed = target.state == "Downed",
		counterStart = if target.state == "Countering" then target.counterStart else nil,
		parryStart = if target.state == "Parrying" then target.parryStart else nil,
		blocking = Fighter.isBlocking(target),
		blockStart = target.blockStart,
		facingDot = Fighter.facing(target):Dot(toAttacker),
	}
end

local function onBlock(
	attacker: Fighter,
	target: Fighter,
	move: Types.MoveDef,
	timing: number,
	ctx: HitContext,
	now: number
): Types.CloseBlockLevel?
	local level = Timing.closeBlockLevel(timing, Combat.CloseBlock)
	local raw = HitResolver.rawDamage(attacker, move)
	local broke = BlockMeter.drain(target.block, raw, now, Combat)
	local text = if timing > 2
		then "Block: Normal (held, no fresh press)."
		else Timing.describe(
			if level then "Close block" else "Block",
			if level then level.name else "Normal",
			timing
		)
	-- Timers run from the current time; `now` is the impact time used for timing.
	local current = Clock.now()

	if broke then
		DebugService.log({ attacker, target }, text .. " The block broke!", Color3.fromRGB(255, 90, 90))
		HitResolver.effect("GuardBreak", target.root.Position)
		HitResolver.stun(target, Combat.GuardBreakStun, current, "Block break", attacker)
		BlockMeter.refill(target.block)
		return nil
	end

	local base = move.blockstun or move.hitstun * Combat.DefaultBlockstunMult
	local blockstun = base * (if level then level.blockstunMult else 1)
	if blockstun > 0 then
		Fighter.setState(target, "Blockstun", blockstun, current)
	end

	if level then
		punish(attacker, level.attackerExtraRecovery, current)
		HitResolver.flash({ attacker, target }, string.upper(level.name), level.color)
		HitResolver.effect("CloseBlock", target.root.Position, level.color)
	else
		HitResolver.effect("Block", target.root.Position)
	end

	local knockback = move.knockback
	if knockback then
		-- Blocked knockback moves still push a little (no wall stun).
		local push = directionFromAttacker(attacker, target, ctx) * knockback.horizontal * 0.3
		target.applyKnockback(push, 0.12)
	end

	DebugService.log({ attacker, target }, text, if level then level.color else nil)
	return level
end

local function onHit(attacker: Fighter, target: Fighter, move: Types.MoveDef, ctx: HitContext, now: number)
	local amount =
		Damage.compute(move.damage, attacker.stats.damageMult, bonusFor(attacker, move), target.stats.defenseMult)
	HitResolver.dealDamage(attacker, target, amount, move.isAbility == true)
	HitResolver.effect("Hit", target.root.Position, attacker.def.color)
	DebugService.log({ attacker, target }, string.format("Hit: %s for %.1f damage.", move.name, amount))

	if target.state == "Downed" or target.hyperArmor then
		return
	end

	-- Getting hit interrupts whatever you were doing (an interrupted ability stays on
	-- cooldown, since cooldowns start when the ability is used).
	Fighter.cancelAction(target)
	target.parryStart = nil
	target.counterStart = nil
	if move.hitstun > 0 and not (target.state == "Stunned" and target.stateUntil > now + move.hitstun) then
		target.blockStart = nil
		Fighter.setState(target, "Hitstun", move.hitstun, now)
	end
	if move.stun then
		HitResolver.stun(target, move.stun, now, move.name, attacker)
	end

	local knockback = move.knockback
	if knockback then
		local mult = target.stats.knockbackMult
		local direction = directionFromAttacker(attacker, target, ctx)
		HitResolver.knockback(
			target,
			direction * knockback.horizontal * mult + Vector3.yAxis * knockback.vertical * mult,
			now
		)
	end
end

-- Resolves `move` from `attacker` reaching `target`. Returns the result and, for blocks,
-- the close-block level (nil for a normal block).
function HitResolver.resolve(
	attacker: Fighter,
	target: Fighter,
	move: Types.MoveDef,
	ctx: HitContext
): (Resolve.Result, Types.CloseBlockLevel?)
	local now = ctx.time or Clock.now()
	local outcome = Resolve.decide(move, defenderView(attacker, target, ctx), now, resolveConfig)
	local result = outcome.result
	if result == "Ignored" then
		return result, nil
	end
	target.lastAttacker = attacker

	local kit = target.kit
	if result == "FullCounter" and kit and kit.onFullCounter then
		kit.onFullCounter(target, attacker, move, outcome.timing, ctx)
		return result, nil
	elseif result == "Parry" and kit and kit.onParry then
		kit.onParry(target, attacker, move, outcome.timing, ctx)
		return result, nil
	elseif result == "Block" then
		return result, onBlock(attacker, target, move, outcome.timing, ctx, now)
	end

	onHit(attacker, target, move, ctx, Clock.now())
	return "Hit", nil
end

return HitResolver
