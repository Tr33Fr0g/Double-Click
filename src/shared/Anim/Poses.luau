--!strict
-- Placeholder animations (doc: "Beta build: debug mode and animations").
-- Every move gets a simple pose for its wind-up and active phases; recovery blends back
-- to neutral. Angles are degrees (pitch, yaw, roll) in the torso's space:
--   +pitch swings a limb forward/up (and leans the torso back),
--   +yaw turns left, +roll raises a right limb outward.
-- Polished animations come later, likely from an animator.

export type Joint = "Torso" | "Head" | "RightArm" | "LeftArm" | "RightLeg" | "LeftLeg"
export type Pose = { [string]: Vector3 } -- keyed by Joint
export type AttackPose = { windup: Pose, active: Pose }

local v = Vector3.new

local Poses = {}

Poses.Joints = { "Torso", "Head", "RightArm", "LeftArm", "RightLeg", "LeftLeg" } :: { Joint }

Poses.Attack = {
	JabRight = {
		windup = { Torso = v(0, -25, 0), RightArm = v(-30, 0, 15), LeftArm = v(60, 0, -10) },
		active = { Torso = v(-5, 25, 0), RightArm = v(90, 0, 0), LeftArm = v(40, 0, -10) },
	},
	JabLeft = {
		windup = { Torso = v(0, 25, 0), LeftArm = v(-30, 0, -15), RightArm = v(60, 0, 10) },
		active = { Torso = v(-5, -25, 0), LeftArm = v(90, 0, 0), RightArm = v(40, 0, 10) },
	},
	JabFinisher = {
		windup = { Torso = v(10, -40, 0), RightArm = v(-50, 0, 30), LeftArm = v(70, 0, -20) },
		active = { Torso = v(-15, 35, 0), RightArm = v(100, 0, 0), LeftArm = v(20, 0, -20), RightLeg = v(-20, 0, 0) },
	},
	SlideKick = {
		windup = { Torso = v(15, 0, 0), RightLeg = v(40, 0, 0) },
		active = {
			Torso = v(35, 0, 0),
			RightLeg = v(80, 0, 0),
			LeftLeg = v(10, 0, 0),
			RightArm = v(-30, 0, 25),
			LeftArm = v(-30, 0, -25),
		},
	},
	DiveKick = {
		windup = { Torso = v(10, 0, 0), RightLeg = v(70, 0, 0), LeftLeg = v(-20, 0, 0) },
		active = {
			Torso = v(20, 0, 0),
			RightLeg = v(25, 0, 0),
			LeftLeg = v(-45, 0, 0),
			RightArm = v(140, 0, 20),
			LeftArm = v(140, 0, -20),
		},
	},
	Zap = {
		windup = { RightArm = v(60, 0, 0), Torso = v(0, -10, 0) },
		active = { RightArm = v(95, 0, -5), Torso = v(-5, 15, 0), LeftArm = v(20, 0, -15) },
	},
	Heavy = {
		windup = { Torso = v(15, -50, 0), RightArm = v(-60, 0, 60), LeftArm = v(-40, 0, -60) },
		active = { Torso = v(-20, 50, 0), RightArm = v(100, -30, 0), LeftArm = v(80, 30, 0) },
	},
	Shoot = {
		windup = { Torso = v(0, 40, 0), LeftArm = v(90, -20, 0), RightArm = v(90, 30, 0) },
		active = { Torso = v(0, 40, 0), LeftArm = v(90, -20, 0), RightArm = v(60, 40, 0) },
	},
	Slam = {
		windup = { Torso = v(15, 0, 0), RightArm = v(170, 0, 10), LeftArm = v(170, 0, -10) },
		active = { Torso = v(-30, 0, 0), RightArm = v(60, 0, 0), LeftArm = v(60, 0, 0) },
	},
	Grab = {
		windup = { Torso = v(-10, 0, 0), RightArm = v(80, 0, 30), LeftArm = v(80, 0, -30) },
		active = { Torso = v(-20, 0, 0), RightArm = v(95, 0, -10), LeftArm = v(95, 0, 10) },
	},
} :: { [string]: AttackPose }

Poses.State = {
	Block = { Torso = v(-5, 0, 0), RightArm = v(110, 35, 0), LeftArm = v(110, -35, 0) },
	Blockstun = { Torso = v(10, 0, 0), RightArm = v(105, 35, 0), LeftArm = v(105, -35, 0), Head = v(10, 0, 0) },
	Parry = { Torso = v(0, 20, 0), RightArm = v(85, 20, -10), LeftArm = v(30, 0, -10) },
	Counter = { Torso = v(-10, 0, 0), RightArm = v(60, 40, 40), LeftArm = v(60, -40, -40) },
	CounterGrab = { Torso = v(-25, 0, 0), RightArm = v(120, 0, -20), LeftArm = v(120, 0, 20) },
	Hitstun = { Torso = v(25, 0, 0), Head = v(20, 0, 0), RightArm = v(-20, 0, 25), LeftArm = v(-20, 0, -25) },
	Stunned = { Torso = v(-25, 0, 10), Head = v(-30, 0, 15), RightArm = v(0, 0, 5), LeftArm = v(0, 0, -5) },
	Recovery = { Torso = v(15, 0, 0), RightArm = v(20, 0, 35), LeftArm = v(20, 0, -35) },
	Rush = { Torso = v(-60, 0, 0), Head = v(40, 0, 0), RightArm = v(-40, 0, 15), LeftArm = v(-40, 0, -15) },
	Dodge = { Torso = v(-25, 0, 0), RightArm = v(-30, 0, 25), LeftArm = v(-30, 0, -25) },
	Downed = { Torso = v(-60, 0, 0), Head = v(-20, 0, 0), RightLeg = v(70, 0, 0), LeftLeg = v(70, 0, 0) },
} :: { [string]: Pose }

return Poses
