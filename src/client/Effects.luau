--!strict
-- Placeholder visual effects: hit sparks, block rings, and the colored flash both players
-- see on a close block, parry or Full Counter.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Events = require(script.Parent.Events)
local UI = require(script.Parent.UI)

local Effects = {}

local folder: Folder? = nil
local flashFrame: Frame? = nil
local flashLabel: TextLabel? = nil
local flashScale: UIScale? = nil
local shakeHandler: ((amount: number) -> ())? = nil

local WHITE = Color3.new(1, 1, 1)
local BLUE = Color3.fromRGB(90, 160, 255)
local ORANGE = Color3.fromRGB(255, 140, 40)
local GRAY = Color3.fromRGB(170, 170, 170)
local YELLOW = Color3.fromRGB(255, 230, 60)

local function effectsFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "DC_ClientEffects"
	newFolder.Parent = workspace
	folder = newFolder
	return newFolder
end

local function localRootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function makePart(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0.2
	part.Parent = effectsFolder()
	return part
end

function Effects.burst(position: Vector3, color: Color3, size: number, duration: number)
	local part = makePart(Enum.PartType.Ball, Vector3.one * (size * 0.3), CFrame.new(position), color)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1 }
	)
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	tween:Play()
end

function Effects.ring(position: Vector3, color: Color3, size: number, duration: number)
	local part = makePart(
		Enum.PartType.Cylinder,
		Vector3.new(0.3, size * 0.3, size * 0.3),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, size, size), Transparency = 1 }
	)
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	tween:Play()
end

function Effects.puff(position: Vector3)
	Effects.burst(position, GRAY, 3, 0.25)
end

function Effects.text(position: Vector3, text: string, color: Color3)
	local anchor = makePart(Enum.PartType.Block, Vector3.one * 0.1, CFrame.new(position), color)
	anchor.Transparency = 1
	local gui = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(160, 40),
		StudsOffset = Vector3.new(0, 1, 0),
		AlwaysOnTop = true,
		Adornee = anchor,
		Parent = anchor,
	}) :: BillboardGui
	local label = UI.label(text, 26, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})
	TweenService:Create(anchor, TweenInfo.new(0.7), { CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	fade.Completed:Connect(function()
		anchor:Destroy()
	end)
	fade:Play()
end

local function shakeIfNear(position: Vector3, amount: number, radius: number)
	local handler = shakeHandler
	local me = localRootPosition()
	if handler and me and (me - position).Magnitude <= radius then
		handler(amount)
	end
end

-- The colored screen flash for close blocks, parries and Full Counters.
function Effects.flash(label: string, color: Color3)
	local frame, text, scale = flashFrame, flashLabel, flashScale
	if not (frame and text and scale) then
		return
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0.55
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	text.Text = label
	text.TextColor3 = color
	text.TextTransparency = 0
	text.TextStrokeTransparency = 0.2
	scale.Scale = 1.35
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(text, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

function Effects.play(kind: string, position: Vector3, color: Color3?)
	if kind == "Hit" then
		Effects.burst(position, color or WHITE, 3.5, 0.18)
		shakeIfNear(position, 0.25, 6)
	elseif kind == "Block" then
		Effects.ring(position, BLUE, 6, 0.2)
	elseif kind == "CloseBlock" then
		Effects.ring(position, color or BLUE, 9, 0.3)
		Effects.burst(position, color or BLUE, 5, 0.2)
		shakeIfNear(position, 0.15, 8)
	elseif kind == "Parry" then
		Effects.ring(position, color or WHITE, 10, 0.3)
		Effects.burst(position, WHITE, 5, 0.2)
		shakeIfNear(position, 0.2, 8)
	elseif kind == "FullCounter" then
		Effects.burst(position, color or Color3.fromRGB(255, 60, 60), 18, 0.4)
		Effects.ring(position, WHITE, 16, 0.4)
		shakeIfNear(position, 0.7, 30)
	elseif kind == "GuardBreak" then
		Effects.burst(position, ORANGE, 8, 0.3)
		Effects.text(position + Vector3.new(0, 3, 0), "BLOCK BREAK", ORANGE)
		shakeIfNear(position, 0.35, 8)
	elseif kind == "Wall" then
		Effects.burst(position, GRAY, 5, 0.3)
		Effects.text(position + Vector3.new(0, 2, 0), "WALL", GRAY)
		shakeIfNear(position, 0.3, 8)
	elseif kind == "Stun" then
		Effects.text(position, "STUN", YELLOW)
	elseif kind == "Downed" then
		Effects.burst(position, GRAY, 7, 0.5)
		Effects.text(position + Vector3.new(0, 3, 0), "DOWN", GRAY)
	end
end

function Effects.setShakeHandler(handler: (amount: number) -> ())
	shakeHandler = handler
end

function Effects.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UI.new("ScreenGui", {
		Name = "DC_Flash",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	flashFrame = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	}) :: Frame
	local scale = Instance.new("UIScale")
	flashScale = scale
	local label = UI.label("", 44, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(600, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = gui,
	})
	flashLabel = label
	scale.Parent = label
	gui.Parent = playerGui

	Events.on("Flash", function(payload)
		local label = if type(payload.label) == "string" then payload.label else ""
		local color = if typeof(payload.color) == "Color3" then payload.color :: Color3 else WHITE
		Effects.flash(label, color)
	end)
	Events.on("Effect", function(payload)
		if type(payload.kind) == "string" and typeof(payload.position) == "Vector3" then
			local color = if typeof(payload.color) == "Color3" then payload.color :: Color3 else nil
			Effects.play(payload.kind, payload.position, color)
		end
	end)
end

return Effects
