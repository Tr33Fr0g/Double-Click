--!strict
-- Debug mode (doc: "Beta build: debug mode and animations").
-- Only works in private and test servers, never in ranked:
--   * hitbox view (hurtboxes + attack hitboxes colored by phase)
--   * timing feedback for every block, close block, parry and Full Counter
--   * live overlay (read by the client from attributes)
--   * slow motion and frame step (the game clock + gravity)
--   * training dummy controls (registered by DummyService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local SpeerrowKit = require(Shared.Characters.SpeerrowKit)
local Stacks = require(Shared.Combat.Stacks)
local StunChain = require(Shared.Combat.StunChain)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Fighter)

type Fighter = Fighter.Fighter
type Handler = (player: Player, args: { [string]: any }) -> ()

local DebugService = {}

local allowed = false
local enabledFor: { [Player]: boolean } = {}
local commands: { [string]: Handler } = {}
local baseGravity = 196.2
local scaleBeforePause = 1

local function computeAllowed(): boolean
	local cfg = GameConfig.Debug
	if workspace:GetAttribute("DC_Ranked") == true then
		return false
	end
	if cfg.ForceEnable then
		return true
	end
	if cfg.AllowInStudio and RunService:IsStudio() then
		return true
	end
	if cfg.AllowInPrivateServers and game.PrivateServerId ~= "" then
		return true
	end
	return table.find(cfg.TestPlaceIds, game.PlaceId) ~= nil
end

function DebugService.isAllowed(): boolean
	return allowed
end

function DebugService.registerCommand(name: string, handler: Handler)
	commands[name] = handler
end

-- Prints a line to the Output and to the debug log of every player involved.
function DebugService.log(fighters: { Fighter? }, text: string, color: Color3?)
	if not allowed then
		return
	end
	print("[Double Click] " .. text)
	local sent: { [Player]: boolean } = {}
	for _, fighter in fighters do
		local player = fighter and fighter.player
		if player and not sent[player] then
			sent[player] = true
			Net.Event:FireClient(player, "DebugLog", { text = text, color = color })
		end
	end
end

-- Sends an attack hitbox to everyone with debug mode on, colored by phase on the client.
function DebugService.hitbox(
	attacker: Fighter,
	move: Types.MoveDef,
	phase: Types.Phase,
	aim: Vector3,
	untilTime: number
)
	if not allowed then
		return
	end
	local hitbox = move.hitbox
	if not hitbox then
		return
	end
	local payload = {
		model = attacker.model,
		shape = hitbox.shape,
		size = hitbox.size,
		offset = hitbox.offset,
		aim = aim,
		phase = phase,
		untilTime = untilTime,
	}
	for player, on in enabledFor do
		if on then
			Net.Event:FireClient(player, "Hitbox", payload)
		end
	end
end

local function setTimeScale(scale: number)
	Clock.setScale(scale)
	if scale > 0 then
		workspace.Gravity = baseGravity * scale * scale
	end
end

local function fighterFor(player: Player): Fighter?
	return Fighter.get(player.Character)
end

local function registerBuiltins()
	DebugService.registerCommand("SetEnabled", function(player, args)
		enabledFor[player] = args.on == true
	end)

	DebugService.registerCommand("TimeScale", function(_, args)
		local scale = tonumber(args.scale)
		if scale and scale > 0 and scale <= 1 then
			setTimeScale(scale)
		end
	end)

	DebugService.registerCommand("Pause", function()
		if Clock.isPaused() then
			setTimeScale(scaleBeforePause)
		else
			scaleBeforePause = Clock.scale()
			setTimeScale(0)
		end
	end)

	DebugService.registerCommand("Step", function()
		if Clock.isPaused() then
			Clock.step(GameConfig.Debug.FrameStep)
		end
	end)

	DebugService.registerCommand("FillUlt", function(player)
		local fighter = fighterFor(player)
		if fighter then
			fighter.ult = GameConfig.Combat.UltMax
		end
	end)

	DebugService.registerCommand("ResetCooldowns", function(player)
		local fighter = fighterFor(player)
		if fighter then
			for slot in fighter.cooldowns do
				fighter.cooldowns[slot] = 0
			end
			fighter.m1LockUntil = -math.huge
		end
	end)

	DebugService.registerCommand("MaxStacks", function(player)
		local fighter = fighterFor(player)
		if fighter then
			Stacks.setMax(fighter.stacks, Clock.now(), SpeerrowKit.Stacks)
		end
	end)

	DebugService.registerCommand("ResetMe", function(player)
		local fighter = fighterFor(player)
		if fighter then
			Fighter.resetCombat(fighter)
			StunChain.reset(fighter.stun)
		end
	end)
end

function DebugService.init()
	allowed = computeAllowed()
	baseGravity = workspace.Gravity
	ReplicatedStorage:SetAttribute("DC_DebugAllowed", allowed)
	registerBuiltins()

	Net.Debug.OnServerEvent:Connect(function(player: Player, command: any, args: any)
		if not allowed or type(command) ~= "string" then
			return
		end
		local handler = commands[command]
		if handler then
			handler(player, if type(args) == "table" then args else {})
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		enabledFor[player] = nil
	end)

	if allowed then
		print("[Double Click] Debug mode is available on this server. Press ` in game to open it.")
	end
end

return DebugService
