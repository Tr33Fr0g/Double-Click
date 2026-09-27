--!strict
-- Debug mode on the client (private and test servers only).
--   `  cycles: panel + overlay (mouse free) -> overlay only -> off
--   H  hitbox view: hurtboxes (green) + attack hitboxes by phase (yellow/red/blue)
--   [ ]  slower / faster,  P  pause,  .  step one frame while paused
-- The panel also configures the training dummy and has quick cheats for testing.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Teams = require(Shared.Util.Teams)

local CameraController = require(script.Parent.CameraController)
local Events = require(script.Parent.Events)
local Input = require(script.Parent.Input)
local Me = require(script.Parent.Me)
local UI = require(script.Parent.UI)

type HitboxView = {
	part: Part,
	model: Model,
	offset: CFrame,
	aim: Vector3,
	untilTime: number,
}

local DebugController = {}

local level = 0 -- 0 off, 1 panel + overlay, 2 overlay only
local hitboxesOn = false
local panel: GuiObject? = nil
local overlay: TextLabel? = nil
local logBox: Frame? = nil
local logLines: { { text: string, color: Color3? } } = {}
local hitboxViews: { [Model]: HitboxView } = {}
local hurtboxBoxes: { [BasePart]: SelectionBox } = {}
local dummyLabels: { [string]: TextLabel } = {}
local hitboxToggle: TextButton? = nil
local timeLabel: TextLabel? = nil

local LOG_LIMIT = 12
local COLORS = GameConfig.Debug.Colors

local function send(command: string, args: { [string]: any }?)
	Net.Debug:FireServer(command, args or {})
end

local function effectsFolder(): Instance
	return workspace:FindFirstChild("DC_ClientEffects") or workspace
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Log ------------------------------------------------------------------------------------------

local function renderLog()
	local box = logBox
	if box == nil then
		return
	end
	local label = box:FindFirstChild("Text") :: TextLabel?
	if label == nil then
		return
	end
	local lines = {}
	for _, line in logLines do
		local text = escape(line.text)
		local color = line.color
		table.insert(lines, if color then `<font color="{hex(color)}">{text}</font>` else text)
	end
	label.Text = table.concat(lines, "\n")
end

function DebugController.log(text: string, color: Color3?)
	table.insert(logLines, { text = text, color = color })
	while #logLines > LOG_LIMIT do
		table.remove(logLines, 1)
	end
	renderLog()
end

-- Hitbox view ----------------------------------------------------------------------------------

local function phaseColor(phase: string): Color3
	return if phase == "Windup" then COLORS.Windup elseif phase == "Active" then COLORS.Active else COLORS.Recovery
end

local function onHitbox(payload: { [string]: any })
	if not hitboxesOn then
		return
	end
	local model = payload.model
	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		return
	end
	local attacker = model :: Model
	local size = if typeof(payload.size) == "Vector3" then payload.size :: Vector3 else Vector3.one
	local shape = if payload.shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
	local view = hitboxViews[attacker]
	if view == nil or view.part.Shape ~= shape then
		if view then
			view.part:Destroy()
		end
		local part = Instance.new("Part")
		part.Name = "DC_HitboxView"
		part.Shape = shape
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0.55
		part.Parent = effectsFolder()
		view = {
			part = part,
			model = attacker,
			offset = CFrame.new(),
			aim = Vector3.new(0, 0, -1),
			untilTime = 0,
		}
		hitboxViews[attacker] = view
	end
	local current = view :: HitboxView
	current.part.Size = size
	current.part.Color = phaseColor(tostring(payload.phase))
	current.offset = if typeof(payload.offset) == "CFrame" then payload.offset :: CFrame else CFrame.new()
	current.aim = if typeof(payload.aim) == "Vector3" then payload.aim :: Vector3 else Vector3.new(0, 0, -1)
	current.untilTime = tonumber(payload.untilTime) or 0
end

local function updateHitboxViews(now: number)
	for model, view in hitboxViews do
		local root = model:FindFirstChild("HumanoidRootPart")
		if
			not hitboxesOn
			or model.Parent == nil
			or now > view.untilTime + 0.05
			or not (root and root:IsA("BasePart"))
		then
			view.part:Destroy()
			hitboxViews[model] = nil
			continue
		end
		local position = root.Position
		view.part.CFrame = CFrame.lookAt(position, position + view.aim) * view.offset
	end
end

local function updateHurtboxes()
	local seen: { [BasePart]: boolean } = {}
	if hitboxesOn then
		for _, instance in CollectionService:GetTagged(Attr.Tag) do
			local hurtbox = instance:FindFirstChild("DC_Hurtbox")
			if hurtbox and hurtbox:IsA("BasePart") then
				seen[hurtbox] = true
				if not hurtboxBoxes[hurtbox] then
					local box = Instance.new("SelectionBox")
					box.Name = "DC_HurtboxView"
					box.Adornee = hurtbox
					box.Color3 = COLORS.Hurtbox
					box.LineThickness = 0.04
					box.SurfaceTransparency = 0.92
					box.SurfaceColor3 = COLORS.Hurtbox
					box.Parent = effectsFolder()
					hurtboxBoxes[hurtbox] = box
				end
			end
		end
	end
	for hurtbox, box in hurtboxBoxes do
		if not seen[hurtbox] then
			box:Destroy()
			hurtboxBoxes[hurtbox] = nil
		end
	end
end

local function setHitboxes(on: boolean)
	hitboxesOn = on
	send("SetEnabled", { on = on })
	local toggle = hitboxToggle
	if toggle then
		toggle.Text = if on then "Hitboxes: ON  (H)" else "Hitboxes: OFF  (H)"
	end
end

-- Overlay -------------------------------------------------------------------------------------

local function num(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function str(model: Model, name: string): string
	local value = model:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

local function secondsText(value: number): string
	return if value > 0.005 then string.format("%.2fs", value) else "-"
end

local function describeState(model: Model, now: number): string
	local state = str(model, Attr.State)
	local left = num(model, Attr.StateUntil, 0) - now
	local text = state
	if left > 0 and num(model, Attr.StateUntil, 0) > 0 then
		text ..= string.format(" (%.2fs)", left)
	end
	local phase = str(model, Attr.Phase)
	if phase ~= "" then
		text ..= string.format(
			'  ·  %s <font color="%s">%s</font> %.2fs',
			escape(str(model, Attr.Action)),
			hex(phaseColor(phase)),
			phase,
			math.max(0, num(model, Attr.PhaseEnd, 0) - now)
		)
	end
	return text
end

local function stunText(model: Model, now: number): string
	local immune = num(model, Attr.StunImmuneUntil, 0) - now
	return string.format(
		"chain %d  ·  immune %s  ·  last %s",
		num(model, Attr.StunCount, 0),
		secondsText(immune),
		secondsText(num(model, Attr.LastStun, 0))
	)
end

local function findTarget(): Model?
	local locked = CameraController.lockTarget()
	if locked then
		return locked
	end
	local body = Me.body
	if body == nil then
		return nil
	end
	local best: Model? = nil
	local bestDistance = 60
	for _, instance in CollectionService:GetTagged(Attr.Tag) do
		if instance:IsA("Model") and instance ~= body.character and Teams.areEnemies(body.character, instance) then
			local root = instance:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local distance = (root.Position - body.root.Position).Magnitude
				if distance < bestDistance then
					best = instance
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function updateOverlay(now: number)
	local label = overlay
	if label == nil then
		return
	end
	label.Visible = level > 0
	if level == 0 then
		return
	end
	local body = Me.body
	local scale = Clock.scale()
	local lines = {
		string.format(
			"<b>TIME</b>  %s%s",
			if scale == 0 then "paused" else string.format("%.2gx", scale),
			if scale == 0 then "  (press . to step)" else ""
		),
	}
	if body then
		local model = body.character
		local velocity = body.root.AssemblyLinearVelocity
		local speed = if scale > 0 then Vector3.new(velocity.X, 0, velocity.Z).Magnitude / scale else 0
		local cooldowns = {}
		for _, slot in { "E", "R", "Q", "Dodge" } do
			local left = num(model, Attr.cooldown(slot), 0) - now
			table.insert(
				cooldowns,
				string.format("%s %s", slot, if left > 0.005 then string.format("%.1f", left) else "-")
			)
		end
		table.insert(cooldowns, string.format("G %d%%", math.floor(num(model, Attr.Ult, 0))))
		local stacks = num(model, Attr.Stacks, 0)
		local stackExpire = num(model, Attr.StacksExpireAt, 0) - now
		table.insert(lines, "")
		table.insert(lines, `<b>YOU</b>  {body.def.displayName}`)
		table.insert(lines, "State  " .. describeState(model, now))
		table.insert(
			lines,
			string.format(
				"Speed  %.1f studs/s  (walk %.1f · sprint %.1f)",
				speed,
				body.stats.walkSpeed,
				body.stats.sprintSpeed
			)
		)
		table.insert(lines, string.format("HP  %.1f / %d", num(model, Attr.HP, 0), num(model, Attr.MaxHP, 0)))
		table.insert(
			lines,
			string.format("Block meter  %.0f / %d", num(model, Attr.BlockMeter, 0), num(model, Attr.BlockMeterMax, 0))
		)
		table.insert(
			lines,
			string.format(
				"Stacks  %.1f  (x%.1f dmg)  ·  drop in %s",
				stacks,
				1 + 0.2 * math.floor(stacks),
				secondsText(stackExpire)
			)
		)
		table.insert(lines, "Stun  " .. stunText(model, now))
		table.insert(lines, "Cooldowns  " .. table.concat(cooldowns, "   "))
		table.insert(lines, "Can't be hit  " .. (if model:GetAttribute(Attr.Intangible) == true then "yes" else "no"))
	end
	local target = findTarget()
	if target then
		table.insert(lines, "")
		table.insert(lines, `<b>TARGET</b>  {escape(target.Name)}`)
		table.insert(lines, "State  " .. describeState(target, now))
		table.insert(
			lines,
			string.format(
				"HP  %.1f / %d  ·  Block %.0f / %d",
				num(target, Attr.HP, 0),
				num(target, Attr.MaxHP, 0),
				num(target, Attr.BlockMeter, 0),
				num(target, Attr.BlockMeterMax, 0)
			)
		)
		table.insert(lines, "Stun  " .. stunText(target, now))
	end
	label.Text = table.concat(lines, "\n")
end

-- Panel ---------------------------------------------------------------------------------------

local function button(text: string, width: number, onClick: () -> ()): TextButton
	local b = UI.new("TextButton", {
		Size = UDim2.fromOffset(width, 26),
		BackgroundColor3 = Color3.fromRGB(48, 52, 64),
		AutoButtonColor = true,
		Text = text,
		TextSize = 13,
		Font = UI.Font,
		TextColor3 = UI.Text,
	}, { UI.corner(5) }) :: TextButton
	b.Activated:Connect(function()
		onClick()
	end)
	return b
end

local function row(order: number, children: { Instance }): Frame
	local frame = UI.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
	}, { UI.list(4, Enum.FillDirection.Horizontal) }) :: Frame
	for i, child in children do
		if child:IsA("GuiObject") then
			child.LayoutOrder = i
		end
		child.Parent = frame
	end
	return frame
end

local function heading(order: number, text: string): TextLabel
	return UI.label(text, 13, { LayoutOrder = order, TextColor3 = UI.Accent })
end

local function valueLabel(key: string, width: number): TextLabel
	local label = UI.label("", 13, {
		Size = UDim2.fromOffset(width, 26),
		Font = UI.BodyFont,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	dummyLabels[key] = label
	return label
end

local function refreshDummyConfig()
	local raw = ReplicatedStorage:GetAttribute("DC_DummyConfig")
	if type(raw) ~= "string" then
		return
	end
	local ok, config = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(config) ~= "table" then
		return
	end
	local set = function(key: string, text: string)
		local label = dummyLabels[key]
		if label then
			label.Text = text
		end
	end
	set("behavior", "Behavior: " .. tostring(config.behavior))
	set("attack", "Attack: " .. tostring(config.attack))
	set("interval", string.format("Every %.1fs", tonumber(config.interval) or 0))
	set(
		"windup",
		string.format("Wind-up %.2fs%s", tonumber(config.windup) or 0, if config.windupOverridden then "*" else "")
	)
	set("hp", "Infinite HP: " .. (if config.infiniteHp then "on" else "off"))
	set("count", `{tonumber(config.count) or 0} dummies`)
end

local function buildPanel(parent: ScreenGui)
	local content = UI.new("ScrollingFrame", {
		Name = "DebugPanel",
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.fromOffset(310, 470),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BackgroundColor3 = UI.Background,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}, { UI.corner(8), UI.padding(10), UI.list(6) }) :: ScrollingFrame

	local order = 0
	local function add(instance: Instance)
		order += 1
		if instance:IsA("GuiObject") then
			instance.LayoutOrder = order
		end
		instance.Parent = content
	end

	add(UI.label("DEBUG MODE", 16, {}))
	add(UI.label("` cycle view · H hitboxes · [ ] speed · P pause · . step", 11, {
		TextColor3 = UI.Muted,
		Font = UI.BodyFont,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 28),
	}))

	add(heading(0, "VIEW"))
	local toggle = button("Hitboxes: OFF  (H)", 288, function()
		setHitboxes(not hitboxesOn)
	end)
	hitboxToggle = toggle
	add(row(0, { toggle }))

	add(heading(0, "TIME"))
	local scaleButtons: { Instance } = {}
	for _, scale in GameConfig.Debug.TimeScales do
		table.insert(
			scaleButtons,
			button(string.format("%gx", scale), 68, function()
				send("TimeScale", { scale = scale })
			end)
		)
	end
	add(row(0, scaleButtons))
	local time = UI.label("", 13, { Size = UDim2.fromOffset(100, 26), TextYAlignment = Enum.TextYAlignment.Center })
	timeLabel = time
	add(row(0, {
		button("Pause (P)", 90, function()
			send("Pause")
		end),
		button("Step (.)", 90, function()
			send("Step")
		end),
		time,
	}))

	add(heading(0, "YOU"))
	add(row(0, {
		button("Fill ult", 94, function()
			send("FillUlt")
		end),
		button("Reset CDs", 94, function()
			send("ResetCooldowns")
		end),
		button("Max stacks", 92, function()
			send("MaxStacks")
		end),
	}))
	add(row(0, {
		button("Reset HP / state", 288, function()
			send("ResetMe")
		end),
	}))

	add(heading(0, "TRAINING DUMMY"))
	add(row(0, {
		valueLabel("behavior", 190),
		button("Next", 94, function()
			send("DummyBehavior")
		end),
	}))
	add(row(0, {
		valueLabel("attack", 190),
		button("Next", 94, function()
			send("DummyAttack")
		end),
	}))
	add(row(0, {
		valueLabel("interval", 130),
		button("-", 50, function()
			send("DummyInterval", { delta = -0.25 })
		end),
		button("+", 50, function()
			send("DummyInterval", { delta = 0.25 })
		end),
	}))
	add(row(0, {
		valueLabel("windup", 130),
		button("-", 36, function()
			send("DummyWindup", { delta = -0.05 })
		end),
		button("+", 36, function()
			send("DummyWindup", { delta = 0.05 })
		end),
		button("Reset", 70, function()
			send("DummyWindup", { reset = true })
		end),
	}))
	add(row(0, {
		valueLabel("hp", 190),
		button("Toggle", 94, function()
			send("DummyInfiniteHP")
		end),
	}))
	add(row(0, {
		button("Spawn here", 94, function()
			send("DummySpawn")
		end),
		button("Reset all", 94, function()
			send("DummyReset")
		end),
		button("Clear all", 92, function()
			send("DummyClear")
		end),
	}))
	add(row(0, { valueLabel("count", 288) }))

	panel = content
	refreshDummyConfig()
end

local function build()
	local screen = UI.new("ScreenGui", {
		Name = "DC_Debug",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	buildPanel(screen)

	overlay = UI.new("TextLabel", {
		Name = "Overlay",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 40),
		Size = UDim2.fromOffset(400, 300),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UI.Background,
		BackgroundTransparency = 0.25,
		RichText = true,
		Text = "",
		TextSize = 13,
		Font = Enum.Font.Code,
		TextColor3 = UI.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = screen,
	}, { UI.corner(8), UI.padding(10) }) :: TextLabel

	logBox = UI.new("Frame", {
		Name = "TimingLog",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -24),
		Size = UDim2.fromOffset(520, 190),
		BackgroundColor3 = UI.Background,
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = screen,
	}, {
		UI.corner(8),
		UI.padding(8),
		UI.new("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			RichText = true,
			Text = "",
			TextSize = 13,
			Font = Enum.Font.Code,
			TextColor3 = UI.Text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
		}),
	}) :: Frame

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function setLevel(newLevel: number)
	level = newLevel % 3
	local p = panel
	if p then
		p.Visible = level == 1
	end
	local box = logBox
	if box then
		box.Visible = level > 0
	end
	CameraController.setMouseFree(level == 1)
end

local function stepScale(direction: number)
	local scales = GameConfig.Debug.TimeScales -- fastest first
	local current = Clock.scale()
	local index = 1
	for i, scale in scales do
		if math.abs(scale - current) < 1e-3 then
			index = i
		end
	end
	local nextIndex = math.clamp(index - direction, 1, #scales)
	send("TimeScale", { scale = scales[nextIndex] })
end

function DebugController.init()
	if ReplicatedStorage:GetAttribute("DC_DebugAllowed") ~= true then
		return
	end
	build()
	ReplicatedStorage:GetAttributeChangedSignal("DC_DummyConfig"):Connect(refreshDummyConfig)

	Events.on("DebugLog", function(payload)
		if type(payload.text) == "string" then
			DebugController.log(
				payload.text,
				if typeof(payload.color) == "Color3" then payload.color :: Color3 else nil
			)
		end
	end)
	Events.on("Hitbox", onHitbox)

	Input.Began:Connect(function(action)
		if action == "DebugPanel" then
			setLevel(level + 1)
		elseif action == "DebugHitboxes" then
			setHitboxes(not hitboxesOn)
		elseif action == "DebugSlower" then
			stepScale(-1)
		elseif action == "DebugFaster" then
			stepScale(1)
		elseif action == "DebugPause" then
			send("Pause")
		elseif action == "DebugStep" then
			send("Step")
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = Clock.now()
		updateHitboxViews(now)
		updateHurtboxes()
		updateOverlay(now)
		local time = timeLabel
		if time then
			local scale = Clock.scale()
			time.Text = if scale == 0 then "  paused" else string.format("  %.2gx", scale)
		end
	end)

	DebugController.log("Debug mode ready. Every block, close block, parry and Full Counter prints its timing here.")
end

return DebugController
