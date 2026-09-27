--!strict
-- Maps raw input to named actions through Config/Keybinds, so everything can be
-- remapped later. Ignores input the game UI already handled (typing in chat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage.Shared.Config.Keybinds)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Input = {}

Input.Began = Signal.new() :: Signal.Signal<string>
Input.Ended = Signal.new() :: Signal.Signal<string>

local byKey: { [Enum.KeyCode]: string } = {}
local byType: { [Enum.UserInputType]: string } = {}
local down: { [string]: boolean } = {}

for action, binding in Keybinds do
	if typeof(binding) == "EnumItem" then
		if binding.EnumType == Enum.KeyCode then
			byKey[binding :: Enum.KeyCode] = action
		else
			byType[binding :: Enum.UserInputType] = action
		end
	end
end

local function actionFor(input: InputObject): string?
	return byKey[input.KeyCode] or byType[input.UserInputType]
end

function Input.isDown(action: string): boolean
	return down[action] == true
end

-- Movement input: X is right, Y is forward. Length is 0 or 1.
function Input.moveVector(): Vector2
	local x = (if down.MoveRight then 1 else 0) - (if down.MoveLeft then 1 else 0)
	local y = (if down.MoveForward then 1 else 0) - (if down.MoveBack then 1 else 0)
	local v = Vector2.new(x, y)
	return if v.Magnitude > 0 then v.Unit else Vector2.zero
end

local function releaseAll()
	for action in down do
		down[action] = nil
		Input.Ended:Fire(action)
	end
end

function Input.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local action = actionFor(input)
		if action and not down[action] then
			down[action] = true
			Input.Began:Fire(action)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local action = actionFor(input)
		if action and down[action] then
			down[action] = nil
			Input.Ended:Fire(action)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(releaseAll)
	UserInputService.TextBoxFocused:Connect(releaseAll)
end

return Input
