--!strict
-- Default PC layout from the design doc. Every action goes through this table so keys
-- can be remapped later (remapping UI and the controller layout are still to be done).

export type Binding = Enum.KeyCode | Enum.UserInputType

local Keybinds: { [string]: Binding } = {
	MoveForward = Enum.KeyCode.W,
	MoveBack = Enum.KeyCode.S,
	MoveLeft = Enum.KeyCode.A,
	MoveRight = Enum.KeyCode.D,
	Jump = Enum.KeyCode.Space,
	Attack = Enum.UserInputType.MouseButton1, -- M1
	Block = Enum.KeyCode.F,
	DodgeSprint = Enum.KeyCode.LeftShift, -- tap = dodge, hold = sprint
	AbilityE = Enum.KeyCode.E,
	AbilityR = Enum.KeyCode.R,
	AbilityQ = Enum.KeyCode.Q,
	Ultimate = Enum.KeyCode.G,
	Extra = Enum.KeyCode.LeftAlt,
	LockOn = Enum.UserInputType.MouseButton3,
	Minimap = Enum.KeyCode.M,

	-- Debug mode (private and test servers only)
	DebugPanel = Enum.KeyCode.Backquote,
	DebugHitboxes = Enum.KeyCode.H,
	DebugSlower = Enum.KeyCode.LeftBracket,
	DebugFaster = Enum.KeyCode.RightBracket,
	DebugPause = Enum.KeyCode.P,
	DebugStep = Enum.KeyCode.Period,
}

return Keybinds
