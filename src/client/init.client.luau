--!strict
-- Double Click beta: client entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)

local Animator = require(script.Animator)
local CameraController = require(script.CameraController)
local CombatController = require(script.CombatController)
local DebugController = require(script.DebugController)
local Effects = require(script.Effects)
local Events = require(script.Events)
local HUD = require(script.HUD)
local Input = require(script.Input)
local Kits = require(script.Kits)
local Me = require(script.Me)
local MovementController = require(script.MovementController)
local Overhead = require(script.Overhead)

Clock.init()
Events.init()
Input.init()
Me.init()
Effects.init()
Effects.setShakeHandler(CameraController.shake)
CameraController.init()
MovementController.init()
Kits.init()
CombatController.init()
Animator.init()
HUD.init()
Overhead.init()
DebugController.init()
