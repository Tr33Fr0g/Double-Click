--!strict
-- Combat input: M1 (standing / forward / air), F block, E R Q G abilities, Shift
-- dodge/sprint, Space jump and middle-mouse lock-on. Requests go to the server, which is
-- authoritative; movement bits (lunges, slides, dives, Rush) are predicted locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)

local CameraController = require(script.Parent.CameraController)
local Events = require(script.Parent.Events)
local Input = require(script.Parent.Input)
local Kits = require(script.Parent.Kits)
local Me = require(script.Parent.Me)
local MovementController = require(script.Parent.MovementController)

local M = GameConfig.Movement

local CombatController = {}

local ABILITY_SLOTS = {
	AbilityE = "E",
	AbilityR = "R",
	AbilityQ = "Q",
	Ultimate = "G",
}

-- Forward M1 when moving forward (toward where you aim) at a decent speed.
local function m1Variant(body: Me.Body): string
	if not MovementController.isGrounded() then
		return "air"
	end
	local input = MovementController.inputDirection()
	local velocity = MovementController.velocity()
	local aim = CameraController.flatAim()
	if input:Dot(aim) >= M.ForwardInputDot and velocity.Magnitude >= body.stats.walkSpeed * M.ForwardSpeedFraction then
		return "forward"
	end
	return "standing"
end

local function onAttack()
	local body = Me.body
	if body == nil or Kits.busy() then
		return
	end
	local variant = m1Variant(body)
	local aim = CameraController.aim()
	Events.send("M1", { variant = variant, aim = aim, t = Clock.now() })

	-- Predict the movement part if the server will most likely accept it.
	if Me.state() ~= "Free" then
		return
	end
	local m1 = body.def.m1
	MovementController.faceAction(aim)
	if variant == "air" then
		MovementController.setVerticalSpeed(-(m1.air.airDive or 0))
	elseif variant == "forward" then
		local move = m1.forward
		if move.keepMomentum then
			MovementController.keepMomentum((move.windup + move.active) / body.stats.attackSpeed)
		end
	else
		MovementController.lunge(CameraController.flatAim(), m1.string[1].lunge or 0)
	end
end

local function onAbility(slot: string)
	local body = Me.body
	if body == nil or body.def.abilities[slot] == nil then
		return
	end
	local aim = CameraController.aim()
	if not Kits.onAbility(body.def, slot, aim) then
		return
	end
	Events.send("Ability", { slot = slot, aim = aim, t = Clock.now() })
end

function CombatController.init()
	Input.Began:Connect(function(action)
		if action == "Attack" then
			onAttack()
		elseif action == "Block" then
			Events.send("BlockStart", { t = Clock.now() })
		elseif action == "DodgeSprint" then
			MovementController.onShift(true)
		elseif action == "Jump" then
			MovementController.onJump()
		elseif action == "LockOn" then
			CameraController.toggleLock()
		else
			local slot = ABILITY_SLOTS[action]
			if slot then
				onAbility(slot)
			end
		end
	end)
	Input.Ended:Connect(function(action)
		if action == "Block" then
			Events.send("BlockEnd", {})
		elseif action == "DodgeSprint" then
			MovementController.onShift(false)
		end
	end)
end

return CombatController
