--!strict
-- The local player's character, its definition and derived stats, and quick access to
-- the combat attributes the server replicates onto it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local Characters = require(Shared.Characters)
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Stats = require(Shared.Combat.Stats)
local Types = require(Shared.Types)

export type Body = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	align: AlignOrientation,
	attachment: Attachment,
	def: Types.CharacterDef,
	stats: Stats.Derived,
}

local Me = {}

Me.player = Players.LocalPlayer
Me.body = nil :: Body?
Me.Spawned = Signal.new() :: Signal.Signal<Body>
Me.Despawned = Signal.new() :: Signal.Signal<>

local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not (humanoid and root) then
		return
	end
	local align = root:WaitForChild("DC_Align", 10) :: AlignOrientation?
	local attachment = root:WaitForChild("DC_Attachment", 10) :: Attachment?
	if not (align and attachment) or character.Parent == nil then
		return
	end
	local id = character:GetAttribute(Attr.Character)
	local def = Characters.tryGet(if type(id) == "string" then id else nil) or Characters.get(Characters.Default)
	local body: Body = {
		character = character,
		humanoid = humanoid,
		root = root,
		align = align,
		attachment = attachment,
		def = def,
		stats = Stats.derive(def.stats, GameConfig.Stats, GameConfig.HealthByStat, def.movement.sprintSpeedOverride),
	}
	Me.body = body
	Me.Spawned:Fire(body)
end

function Me.attr(name: string): any
	local body = Me.body
	return if body then body.character:GetAttribute(name) else nil
end

function Me.number(name: string, default: number): number
	local value = Me.attr(name)
	return if type(value) == "number" then value else default
end

function Me.state(): string
	local value = Me.attr(Attr.State)
	return if type(value) == "string" then value else "Free"
end

-- Seconds left on a cooldown slot ("E", "R", "Q", "G", "Dodge").
function Me.cooldownLeft(slot: string, now: number): number
	return math.max(0, Me.number(Attr.cooldown(slot), 0) - now)
end

function Me.init()
	Me.player.CharacterAdded:Connect(function(character)
		Me.body = nil
		Me.Despawned:Fire()
		task.spawn(setup, character)
	end)
	Me.player.CharacterRemoving:Connect(function()
		Me.body = nil
		Me.Despawned:Fire()
	end)
	if Me.player.Character then
		task.spawn(setup, Me.player.Character)
	end
end

return Me
