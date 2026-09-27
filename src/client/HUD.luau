--!strict
-- Placeholder HUD: HP, block meter, ult charge, Speerrow's stacks, ability cooldowns
-- and a crosshair for the over-the-shoulder free aim.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)

local Me = require(script.Parent.Me)
local UI = require(script.Parent.UI)

local HUD = {}

type Slot = { frame: Frame, cover: Frame, timer: TextLabel, key: string }

local gui: ScreenGui? = nil
local hpFill: Frame? = nil
local hpText: TextLabel? = nil
local blockFill: Frame? = nil
local ultFill: Frame? = nil
local ultText: TextLabel? = nil
local stateText: TextLabel? = nil
local crosshair: Frame? = nil
local stackPips: { Frame } = {}
local stackTimer: TextLabel? = nil
local slots: { Slot } = {}
local slotRow: Frame? = nil

local SLOT_ORDER = { "E", "R", "Q", "G" }
local HP_COLOR = Color3.fromRGB(90, 220, 120)
local BLOCK_COLOR = Color3.fromRGB(90, 170, 255)
local ULT_COLOR = Color3.fromRGB(255, 200, 40)

local function buildSlots(row: Frame)
	for _, slot in slots do
		slot.frame:Destroy()
	end
	slots = {}
	local body = Me.body
	if body == nil then
		return
	end
	local keys = table.clone(SLOT_ORDER)
	table.insert(keys, "Dodge")
	for index, key in keys do
		local info = body.def.abilities[key]
		local name = if info then info.name elseif key == "Dodge" then "Dodge" else nil
		if name == nil then
			continue
		end
		local cover = UI.new("Frame", {
			Name = "Cover",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, { UI.corner(8) }) :: Frame
		local timer = UI.label("", 20, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		})
		local frame = UI.new("Frame", {
			Name = key,
			LayoutOrder = index,
			Size = UDim2.fromOffset(72, 72),
			BackgroundColor3 = UI.Panel,
			BackgroundTransparency = 0.1,
			Parent = row,
		}, {
			UI.corner(8),
			UI.stroke(Color3.fromRGB(70, 75, 90), 1.5),
			UI.label(if key == "Dodge" then "Shift" else key, 14, {
				Position = UDim2.fromOffset(6, 3),
				Size = UDim2.new(1, -12, 0, 16),
				TextColor3 = UI.Accent,
			}),
			UI.label(name, 12, {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 4, 1, -4),
				Size = UDim2.new(1, -8, 0, 28),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Font = UI.BodyFont,
			}),
			cover,
			timer,
		}) :: Frame
		table.insert(slots, { frame = frame, cover = cover, timer = timer, key = key })
	end
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = UI.new("ScreenGui", {
		Name = "DC_HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	-- Bottom center: stacks, HP, block meter, ult.
	local hpBar, hpBarFill = UI.bar(HP_COLOR, 18)
	local blockBar, blockBarFill = UI.bar(BLOCK_COLOR, 6)
	local ultBar, ultBarFill = UI.bar(ULT_COLOR, 8)
	hpFill, blockFill, ultFill = hpBarFill, blockBarFill, ultBarFill
	hpText = UI.label("", 14, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = hpBar,
	})
	local ultLabel = UI.label("", 12, {
		Size = UDim2.new(1, 0, 0, 14),
		TextColor3 = ULT_COLOR,
		LayoutOrder = 5,
	})
	ultText = ultLabel

	local pipRow = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
	}, { UI.list(6, Enum.FillDirection.Horizontal) }) :: Frame
	stackPips = {}
	for i = 1, 5 do
		local fill = UI.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = UI.Accent,
			BorderSizePixel = 0,
		}, { UI.corner(3) }) :: Frame
		UI.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(28, 12),
			BackgroundColor3 = Color3.fromRGB(12, 13, 17),
			BackgroundTransparency = 0.2,
			ClipsDescendants = true,
			Parent = pipRow,
		}, { UI.corner(3), fill })
		table.insert(stackPips, fill)
	end
	stackTimer = UI.label("", 12, {
		LayoutOrder = 6,
		Size = UDim2.fromOffset(80, 12),
		TextColor3 = UI.Muted,
		Font = UI.BodyFont,
		Parent = pipRow,
	})

	hpBar.LayoutOrder = 1
	blockBar.LayoutOrder = 2
	ultBar.LayoutOrder = 4
	UI.new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(380, 90),
		BackgroundTransparency = 1,
		Parent = screen,
	}, { UI.list(5), pipRow, hpBar, blockBar, ultBar, ultLabel })

	-- Bottom right: ability slots.
	local row = UI.new("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(5 * 78, 72),
		BackgroundTransparency = 1,
		Parent = screen,
	}, { UI.list(6, Enum.FillDirection.Horizontal) }) :: Frame
	slotRow = row

	-- State readout above the vitals.
	stateText = UI.label("", 16, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -122),
		Size = UDim2.fromOffset(380, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		TextStrokeTransparency = 0.5,
		Parent = screen,
	})

	crosshair = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		Parent = screen,
	}, { UI.corner(3), UI.stroke(Color3.new(0, 0, 0), 1, 0.4) }) :: Frame

	local debugHint = if ReplicatedStorage:GetAttribute("DC_DebugAllowed") == true
		then "   ·   press ` for debug mode"
		else ""
	UI.label(`DOUBLE CLICK  {GameConfig.Version}{debugHint}`, 13, {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(500, 16),
		TextColor3 = UI.Muted,
		Parent = screen,
	})

	screen.Parent = playerGui
	gui = screen
end

local STATE_LABELS: { [string]: string } = {
	Stunned = "STUNNED",
	Hitstun = "HIT",
	Blockstun = "BLOCKSTUN",
	Recovery = "RECOVERING",
	Downed = "DOWN",
}

local function update()
	local body = Me.body
	local screen = gui
	if screen == nil then
		return
	end
	screen.Enabled = body ~= nil
	if body == nil then
		return
	end
	local now = Clock.now()

	local hp, maxHp = Me.number(Attr.HP, 0), Me.number(Attr.MaxHP, 1)
	local block, blockMax = Me.number(Attr.BlockMeter, 0), Me.number(Attr.BlockMeterMax, 1)
	local ult = Me.number(Attr.Ult, 0)
	if hpFill then
		hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
	end
	if hpText then
		hpText.Text = string.format("%d / %d", math.ceil(hp), maxHp)
	end
	if blockFill then
		blockFill.Size = UDim2.fromScale(math.clamp(block / blockMax, 0, 1), 1)
	end
	if ultFill then
		ultFill.Size = UDim2.fromScale(math.clamp(ult / GameConfig.Combat.UltMax, 0, 1), 1)
	end
	if ultText then
		local ultName = body.def.abilities.G and body.def.abilities.G.name or "Ultimate"
		ultText.Text = if ult >= GameConfig.Combat.UltMax
			then `{string.upper(ultName)} READY  [G]`
			else string.format("%s  %d%%", ultName, math.floor(ult))
	end

	local stacks = Me.number(Attr.Stacks, 0)
	for i, fill in stackPips do
		fill.Size = UDim2.fromScale(math.clamp(stacks - (i - 1), 0, 1), 1)
	end
	if stackTimer then
		local expireAt = Me.number(Attr.StacksExpireAt, 0)
		stackTimer.Text = if stacks > 0 then string.format("%.1f  (%.0fs)", stacks, math.max(0, expireAt - now)) else ""
	end

	if stateText then
		local state = Me.state()
		local label = STATE_LABELS[state]
		if label then
			local left = math.max(0, Me.number(Attr.StateUntil, 0) - now)
			stateText.Text = if left > 0 then string.format("%s  %.2fs", label, left) else label
		else
			stateText.Text = ""
		end
	end

	if crosshair then
		crosshair.Visible = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	end

	for _, slot in slots do
		local left, total
		if slot.key == "G" then
			left = if ult >= GameConfig.Combat.UltMax then 0 else 1
			total = 1
			slot.cover.Size = UDim2.fromScale(1, 1 - math.clamp(ult / GameConfig.Combat.UltMax, 0, 1))
			slot.timer.Text = if left > 0 then string.format("%d%%", math.floor(ult)) else ""
		else
			left = Me.cooldownLeft(slot.key, now)
			local info = body.def.abilities[slot.key]
			local dodge = body.def.movement.dodge or GameConfig.Movement.Dodge
			total = if info then info.cooldown elseif slot.key == "Dodge" then dodge.Cooldown else 1
			slot.cover.Size = UDim2.fromScale(1, if total > 0 then math.clamp(left / total, 0, 1) else 0)
			slot.timer.Text = if left > 0 then string.format("%.1f", left) else ""
		end
	end
end

function HUD.init()
	build()
	Me.Spawned:Connect(function()
		local row = slotRow
		if row then
			buildSlots(row)
		end
	end)
	if Me.body and slotRow then
		buildSlots(slotRow)
	end
	RunService.RenderStepped:Connect(update)
end

return HUD
