extends Node
## Shared tuning for the whole game (ported from the web prototype).
## Autoloaded as `Config`.

# --- Track and player -------------------------------------------------
const LANE_W := 2.2
const TRACK_HALF := LANE_W * 1.5 + 0.2
const PLAYER_SIZE := Vector3(0.9, 1.4, 0.9)
const SLIDE_H := 0.6
const SLIDE_TIME := 0.7
const GRAVITY := 45.0
const JUMP_V := 14.0
const SLAM_V := -26.0
const LANE_SPEED := 17.0            # m/s sideways
const HIT_SHRINK := 0.12            # collision forgiveness
const JUMP_BUFFER := 0.15           # a jump swiped just before landing still counts
const FLOAT_TIME := 0.45            # hold after a jump to float
const FLOAT_GRAVITY := 0.35
const STEP_UP := 0.4                # you can step onto a surface this much higher than your feet
const NEAR_MISS := 0.35             # metres of clearance that count as a close call
const COMBO_TIME := 3.5
const HIT_PAUSE := 0.25

# --- World and pacing -------------------------------------------------
const GLOBE_R := 45.0
const LAP_BONUS := 1.5
const SPAWN_AHEAD_M := 38.0
const DESPAWN_BEHIND_M := 8.0
const CALM_M := 70.0
const WAVE_M := {"easy": 220.0, "medium": 260.0, "hard": 300.0}

# Difficulty: start/max speed (m/s), accel, row gap (s at current speed), min gap (m),
# chance a lane is free (and how much it drops as speed rises), jump/slide chances, obstacles per row.
const DIFF := {
	"easy": {"start": 9.0, "max": 20.0, "accel": 0.15, "gap": 1.4, "min_gap": 14.0,
		"empty": 0.62, "empty_ramp": 0.10, "low": 0.18, "high": 0.12, "max_blocked": 1},
	"medium": {"start": 10.5, "max": 25.0, "accel": 0.20, "gap": 1.1, "min_gap": 11.0,
		"empty": 0.52, "empty_ramp": 0.15, "low": 0.20, "high": 0.15, "max_blocked": 2},
	"hard": {"start": 12.0, "max": 30.0, "accel": 0.28, "gap": 0.85, "min_gap": 9.0,
		"empty": 0.45, "empty_ramp": 0.20, "low": 0.20, "high": 0.18, "max_blocked": 3},
}

# Obstacle kinds: height, bottom, depth (along the track), colour.
# Colour code: orange = jump, purple = slide, red = switch lanes.
const KIND := {
	"LOW": {"h": 1.0, "y0": 0.0, "d": 0.8, "color": Color("ff8c26")},
	"HIGH": {"h": 2.2, "y0": 1.0, "d": 0.8, "color": Color("d940cc")},
	"WALL": {"h": 3.5, "y0": 0.0, "d": 1.5, "color": Color("d93333")},
	"MOVER": {"h": 1.6, "y0": 0.0, "d": 1.2, "color": Color("ff3d6e")},
	"PIT": {"h": 0.06, "y0": 0.0, "d": 2.6, "color": Color("ff4a1a")},
	"PLATFORM": {"h": 1.6, "y0": 0.0, "d": 0.0, "color": Color("5a6b8c")},
	"RAMP": {"h": 1.6, "y0": 0.0, "d": 5.0, "color": Color("8899bb")},
	"COIN": {"h": 0.45, "y0": 0.0, "d": 0.45, "color": Color("ffd91a")},
}
const HAZARDS := ["LOW", "HIGH", "WALL", "MOVER", "PIT", "PLATFORM"]

# Meadow planet colours (more planets come in a later phase).
const THEME := {
	"sky_top": Color("5f9fe6"), "sky_bottom": Color("cfe8f7"),
	"ground": [Color("6cbf5a"), Color("5aa84d"), Color("8a9a58")],
	"track": Color("6e5f50"), "curb": Color("e9dfcc"), "dash": Color("fff6e0"),
}

var difficulty := "medium"


func diff() -> Dictionary:
	return DIFF[difficulty]


func lane_x(lane: int) -> float:
	return lane * LANE_W
