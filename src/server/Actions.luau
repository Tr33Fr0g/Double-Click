--!strict
-- Move timelines: wind-up -> active -> recovery. Hitboxes are checked on the server every
-- frame of the active phase. Also owns the M1 string (standing / forward / air) and input
-- buffering.
--
-- Combos aren't scripted: a follow-up connects only if it comes out faster than the
-- enemy's hitstun (doc). The frame data in the character files decides what combos.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Teams = require(Shared.Util.Teams)
local Types = require(Shared.Types)

local DebugService = require(script.Parent.DebugService)
local Fighter = require(script.Parent.Fighter)
local HitResolver = require(script.Parent.HitResolver)
local Projectiles = require(script.Parent.Projectiles)

type Fighter = Fighter.Fighter
type ActionState = Fighter.ActionState

export type M1Variant = "standing" | "forward" | "air"

local Combat = GameConfig.Combat

local Actions = {}

local function planarAim(fighter: Fighter, aim: Vector3): Vector3
	local flat = Vector3.new(aim.X, 0, aim.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Fighter.facing(fighter)
end

local function phaseLength(action: ActionState, phase: Types.Phase): number
	local move = action.move
	local seconds = if phase == "Windup" then move.windup elseif phase == "Active" then move.active else move.recovery
	return seconds / action.speed
end

local function enterPhase(fighter: Fighter, action: ActionState, phase: Types.Phase, at: number)
	action.phase = phase
	action.phaseStart = at
	action.phaseEnd = at + phaseLength(action, phase)
	DebugService.hitbox(fighter, action.move, phase, action.aim, action.phaseEnd)
end

-- Seconds until the whole action is over.
local function remaining(action: ActionState, now: number): number
	local left = math.max(0, action.phaseEnd - now)
	if action.phase == "Windup" then
		left += phaseLength(action, "Active") + phaseLength(action, "Recovery")
	elseif action.phase == "Active" then
		left += phaseLength(action, "Recovery")
	end
	return left
end

local function hitboxCFrame(fighter: Fighter, action: ActionState, hitbox: Types.HitboxDef): CFrame
	local position = fighter.root.Position
	return CFrame.lookAt(position, position + action.aim) * hitbox.offset
end

local function runActive(fighter: Fighter, action: ActionState, now: number, firstCheck: boolean)
	local move = action.move

	if move.projectile then
		if not action.spawned then
			action.spawned = true
			local origin = fighter.root.Position + action.aim * 2 + Vector3.new(0, 0.5, 0)
			Projectiles.spawn(fighter, move, origin, action.aim3)
		end
		return
	end

	local hitbox = move.hitbox
	if not hitbox then
		return
	end

	local cframe = hitboxCFrame(fighter, action, hitbox)
	local params = Fighter.overlapParams()
	local parts = if hitbox.shape == "Ball"
		then workspace:GetPartBoundsInRadius(cframe.Position, hitbox.size.X / 2, params)
		else workspace:GetPartBoundsInBox(cframe, hitbox.size, params)

	-- The first check uses the scheduled start of the active phase as the impact time,
	-- so timing feedback doesn't depend on the server's frame rate.
	local impact = if firstCheck then action.phaseStart else now
	for _, part in parts do
		local target = Fighter.byHurtbox[part :: BasePart]
		if
			target
			and target ~= fighter
			and not action.hit[target.model]
			and Teams.areEnemies(fighter.model, target.model)
		then
			action.hit[target.model] = true
			local result = HitResolver.resolve(fighter, target, move, { origin = cframe.Position, time = impact })
			if fighter.action ~= action then
				return -- parried, countered or stunned out of the attack
			end
			if move.kind == "grab" and result ~= "Ignored" then
				-- A grab only ever takes one target.
				action.phaseEnd = math.min(action.phaseEnd, now)
				return
			end
		end
	end
end

local function finish(fighter: Fighter, action: ActionState, now: number)
	fighter.action = nil
	fighter.hyperArmor = false
	if action.slot == "M1" then
		fighter.m1LastEnd = now
		if action.isStringEnd or not action.isStringHit then
			local lag = fighter.def.m1.stringEndLag
			fighter.m1LockUntil = now + (if action.isStringHit then lag else lag * 0.5)
			fighter.m1Index = 1
		end
	end
	Fighter.release(fighter, now)

	local buffered = fighter.buffered
	fighter.buffered = nil
	if buffered and now - buffered.at <= Combat.M1BufferWindow + 0.1 then
		Actions.tryM1(fighter, buffered.variant :: M1Variant, buffered.aim, now)
	end
end

function Actions.start(
	fighter: Fighter,
	move: Types.MoveDef,
	aim: Vector3,
	now: number,
	slot: string,
	isStringHit: boolean?,
	isStringEnd: boolean?
): ActionState
	local speed = fighter.stats.attackSpeed
	local flat = planarAim(fighter, aim)
	local action: ActionState = {
		move = move,
		slot = slot,
		phase = "Windup",
		phaseStart = now,
		phaseEnd = now + move.windup / speed,
		speed = speed,
		aim = flat,
		aim3 = if aim.Magnitude > 1e-3 then aim.Unit else flat,
		hit = {},
		spawned = false,
		extraRecovery = 0,
		isStringHit = isStringHit == true,
		isStringEnd = isStringEnd == true,
		activeChecks = 0,
	}
	fighter.action = action
	fighter.buffered = nil
	fighter.blockStart = nil
	fighter.parryStart = nil
	fighter.counterStart = nil
	fighter.hyperArmor = move.hyperArmor == true
	Fighter.setState(fighter, "Attacking")
	DebugService.hitbox(fighter, move, "Windup", flat, action.phaseEnd)
	Actions.step(fighter, now)
	return action
end

function Actions.step(fighter: Fighter, now: number)
	local action = fighter.action
	if action == nil then
		return
	end
	-- Loop so phases shorter than a frame (or slow frames) are never skipped.
	for _ = 1, 4 do
		if action.phase == "Windup" then
			if now < action.phaseEnd then
				return
			end
			enterPhase(fighter, action, "Active", action.phaseEnd)
		elseif action.phase == "Active" then
			action.activeChecks += 1
			runActive(fighter, action, now, action.activeChecks == 1)
			if fighter.action ~= action or now < action.phaseEnd then
				return
			end
			enterPhase(fighter, action, "Recovery", action.phaseEnd)
		else
			if now < action.phaseEnd then
				return
			end
			finish(fighter, action, now)
			return
		end
	end
end

function Actions.cancel(fighter: Fighter)
	Fighter.cancelAction(fighter)
end

-- Starts (or buffers) an M1. Returns true if an attack started.
function Actions.tryM1(fighter: Fighter, variant: M1Variant, aim: Vector3, now: number): boolean
	local action = fighter.action
	if action then
		if action.slot == "M1" and remaining(action, now) <= Combat.M1BufferWindow then
			fighter.buffered = { variant = variant :: string, aim = aim, at = now }
		end
		return false
	end
	if fighter.state ~= "Free" or now < fighter.m1LockUntil then
		return false
	end

	local m1 = fighter.def.m1
	local move: Types.MoveDef
	local isStringHit, isStringEnd = false, false
	if variant == "air" then
		move = m1.air
	elseif variant == "forward" then
		move = m1.forward
	else
		if now - fighter.m1LastEnd > m1.stringResetTime then
			fighter.m1Index = 1
		end
		local index = math.clamp(fighter.m1Index, 1, #m1.string)
		move = m1.string[index]
		isStringHit = true
		isStringEnd = index >= #m1.string
		fighter.m1Index = if isStringEnd then 1 else index + 1
	end

	Actions.start(fighter, move, aim, now, "M1", isStringHit, isStringEnd)
	return true
end

return Actions
