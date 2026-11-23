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
	"POWER": {"h": 0.7, "y0": 0.5, "d": 0.7, "color": Color.WHITE},
	# Boss throws (same colour code) and helpers
	"FIST": {"h": 2.6, "y0": 0.0, "d": 2.0, "color": Color("d93333")},
	"BLOCK": {"h": 3.2, "y0": 0.0, "d": 1.6, "color": Color("d93333")},
	"SWEEPLOW": {"h": 0.9, "y0": 0.0, "d": 1.2, "color": Color("ff8c26")},
	"SWEEPHIGH": {"h": 1.4, "y0": 1.0, "d": 1.2, "color": Color("d940cc")},
	"SHOCK": {"h": 0.5, "y0": 0.0, "d": 0.7, "color": Color.WHITE},
	"MARK": {"h": 0.04, "y0": 0.02, "d": 2.6, "color": Color("ff2a2a")},
	# Signature moves
	"ROLLER": {"h": 2.2, "y0": 0.0, "d": 2.2, "color": Color("d93333")},
	"LAVA": {"h": 0.06, "y0": 0.0, "d": 20.0, "color": Color("ff4a1a")},
	"VINE": {"h": 1.4, "y0": 1.0, "d": 1.2, "color": Color("d940cc")},     # slide under (purple)
	"ICE": {"h": 0.05, "y0": 0.0, "d": 16.0, "color": Color("9fe8ff")},    # no lane switches while on it
	"LEG": {"h": 6.5, "y0": 0.0, "d": 3.2, "color": Color("d93333")},      # Gate slam: boss legs on the track
}
const HAZARDS := ["LOW", "HIGH", "WALL", "MOVER", "PIT", "PLATFORM", "FIST", "BLOCK", "SWEEPLOW", "SWEEPHIGH", "SHOCK", "ROLLER", "LAVA", "VINE", "LEG"]
const SMASHABLE := ["LOW", "HIGH", "WALL", "MOVER", "FIST", "BLOCK", "SWEEPLOW", "SWEEPHIGH", "SHOCK", "ROLLER", "VINE"]
const FLOOR_HAZARDS := ["PIT", "LAVA"]   # deadly when your feet touch them

# --- Boss moves -------------------------------------------------------
# Every boss is composed from: an archetype, base throws, signature moves, phases and a threat budget.
# Each move costs threat; a boss earns `rate` threat per second (more in later phases) and spends it.
# Answers always use existing moves: switch lane (red), jump (orange), slide (purple).
const BOSS_MOVES := {
	"smash": {"cost": 1.0, "label": ""},          # boulder on one lane
	"block": {"cost": 1.3, "label": ""},          # wall over two lanes
	"sweep_low": {"cost": 1.0, "label": ""},      # log across the track
	"sweep_high": {"cost": 1.0, "label": ""},     # bar across the track
	"stomp": {"cost": 1.3, "label": ""},          # wave rolling toward you
	"rolling_boulder": {"cost": 1.8, "label": "ROLLING BOULDER"},   # rolls at you, switches lane once
	"lava_trail": {"cost": 2.0, "label": "LAVA TRAIL"},             # a lane of lava for 20 m
	"vine_sweep": {"cost": 1.2, "label": "VINE SWEEP"},             # vines over two lanes at slide height
	"meteor_shower": {"cost": 2.2, "label": "METEOR SHOWER"},       # four small meteors in a row, weave
	"ice_lane": {"cost": 1.9, "label": "ICE LANE"},                 # frozen lane (no switching) with a boulder at its end
	"quake_rhythm": {"cost": 2.2, "label": "QUAKE RHYTHM"},         # three stomp waves in a beat
	"decoy": {"cost": 1.2, "label": "DECOY"},                       # the marker jumps lanes mid-flight
	"gate_slam": {"cost": 0.0, "label": "GATE SLAM"},               # at the final pass: legs close in, one moving gap
}
# Phases by chase progress: 1 = base throws, 2 = signature moves unlocked, 3 = enraged (faster, combos).
const BOSS_PHASES := [0.0, 0.3, 0.8]

# --- Power-ups --------------------------------------------------------
const POWERS := {
	"magnet": {"color": Color("00e5ff"), "time": 10.0, "label": "MAGNET"},
	"shield": {"color": Color("3dff6e"), "time": 0.0, "label": "SHIELD"},
	"orbit": {"color": Color.WHITE, "time": 6.0, "label": "ORBIT"},
	"x2": {"color": Color("ff4fa3"), "time": 12.0, "label": "x2 SCORE"},
}
const ORBIT_H := 9.0

# --- Characters -------------------------------------------------------
# One strength, one weakness, one ability each; the Runner is the baseline.
const METER_PER_COIN := 0.035
const METER_PER_CLOSE := 0.11
const SUPER_JUMP_V := 27.0
const SMASH_POINTS := 15
const CHARS := {
	"runner": {"name": "Runner", "desc": "Baseline. Strength: longer combo window. Ability: Focus, time slows down for 3 s.",
		"lane_mul": 1.0, "jump_v": 14.0, "float_time": 0.45, "combo_time": 3.5, "meter_mul": 1.0,
		"ability": "focus", "ability_time": 3.0, "ability_max": 3.0, "smash_extend": 0.0, "label": "FOCUS",
		"body": Color("3380ff"), "limb": Color("2559c4"), "accent": Color("f0f0f5"), "visor": Color("29d4ff"),
		"shape": {"torso_w": 1.0, "shoulder": 1.0, "arm_t": 1.0, "hand": 1.0, "leg_len": 1.0, "leg_t": 1.0, "head": 1.0},
		"model": "Ranger", "model_scale": 1.0},
	"smasher": {"name": "Smasher", "desc": "Heavy. Strength: meter fills 40% faster. Weakness: lower jump. Ability: Smash through blocks for 3 s; each block smashed adds 0.4 s, up to 5 s.",
		"lane_mul": 1.0, "jump_v": 12.5, "float_time": 0.3, "combo_time": 2.5, "meter_mul": 1.4,
		"ability": "smash", "ability_time": 3.0, "ability_max": 5.0, "smash_extend": 0.4, "label": "SMASH", "heavy": true,
		"body": Color("3a4658"), "limb": Color("2a3342"), "accent": Color("ffb020"), "visor": Color("ffb020"),
		"shape": {"torso_w": 1.3, "shoulder": 1.25, "arm_t": 1.45, "hand": 1.7, "leg_len": 0.88, "leg_t": 1.35, "head": 0.95},
		"model": "Barbarian", "model_scale": 1.12},
	"jumper": {"name": "Jumper", "desc": "Light. Strength: jumps higher (about 3 m) and floats longer. Weakness: more time in the air. Ability: Super jump, a huge leap over anything.",
		"lane_mul": 1.0, "jump_v": 16.5, "float_time": 0.8, "combo_time": 2.5, "meter_mul": 1.0,
		"ability": "super", "ability_time": 0.0, "ability_max": 0.0, "smash_extend": 0.0, "label": "SUPER JUMP",
		"body": Color("22b357"), "limb": Color("15803d"), "accent": Color("eafff0"), "visor": Color("b6ff3d"),
		"shape": {"torso_w": 0.85, "shoulder": 0.9, "arm_t": 0.85, "hand": 1.0, "leg_len": 1.18, "leg_t": 0.85, "head": 1.0},
		"model": "Rogue", "model_scale": 0.97},
}

# --- Planets ----------------------------------------------------------
# Each world: its own size, colours and scenery; a number of laps, then a boss chase
# (as long as `boss_loops` x BOSS_LOOP_M) and a hop to the next planet.
const HOP_TIME := 2.6
const HOP_H := 14.0
const BOSS_SIZE := 14.0
const BOSS_LIFT := 6.0          # the boss straddles the track: you run underneath it
const BOSS_LOOP_M := 138.2      # one "loop" of chase distance (2 * PI * 22 m)
const THEMES := [
	{"name": "MEADOW", "radius": 45.0, "sky_top": Color("5f9fe6"), "sky_bottom": Color("cfe8f7"),
		"ground": [Color("6cbf5a"), Color("5aa84d"), Color("8a9a58")], "water": Color("4fa3d9"), "shore": Color("e3d39a"),
		"track": Color("6e5f50"), "curb": Color("e9dfcc"), "dash": Color("fff6e0"), "glow_road": false,
		"props": {"tree": 5, "tree2": 4, "pine": 4, "rock": 3, "house": 2, "bush": 4},
		"laps_to_boss": 2, "boss_loops": 3,
		"boss": {"name": "MINOTAUR", "model": "minotaur", "model_h": 21.0, "body": Color("8a8f7a"), "eye": Color("ffe14d"), "wave": Color("a8ff6a"), "glow": 0.0,
			"throws": {"smash": 45, "block": 0, "sweep_low": 25, "sweep_high": 20, "stomp": 10}, "combo": 0.0, "rate": 0.75,
			"archetype": "gate_walker", "signature": {"vine_sweep": 25}}},
	{"name": "DUNES", "radius": 36.0, "sky_top": Color("f0a05a"), "sky_bottom": Color("fbe3b8"),
		"ground": [Color("e8c98a"), Color("dcb672"), Color("c99a5a")], "water": Color("3fb8c0"), "shore": Color("9cc47a"),
		"track": Color("6e4e3e"), "curb": Color("c9a06a"), "dash": Color("ffe9c2"), "glow_road": false,
		"props": {"cactus": 5, "pyramid": 1, "palm": 3, "mesa": 2, "dune": 5},
		"laps_to_boss": 2, "boss_loops": 4,
		"boss": {"name": "SAND WYVERN", "model": "wyvern", "model_h": 13.0, "hover": 9.0, "tint": Color("9a5a32"), "body": Color("c9a060"), "eye": Color("3fe0ff"), "wave": Color("ffd27a"), "glow": 0.0,
			"throws": {"smash": 38, "block": 10, "sweep_low": 20, "sweep_high": 20, "stomp": 12}, "combo": 0.12, "rate": 0.85,
			"archetype": "gate_walker", "signature": {"rolling_boulder": 25, "meteor_shower": 18}}},
	{"name": "GLACIER", "radius": 54.0, "sky_top": Color("6f9fd8"), "sky_bottom": Color("e6f2fb"),
		"ground": [Color("f4fbff"), Color("e2eef7"), Color("cfe0ee")], "water": Color("9cc8e8"), "shore": Color.WHITE,
		"track": Color("5d7ea8"), "curb": Color.WHITE, "dash": Color("e6f6ff"), "glow_road": false,
		"props": {"spike": 4, "snowpine": 5, "igloo": 1, "ice_rock": 3, "snowman": 1},
		"laps_to_boss": 3, "boss_loops": 4,
		"boss": {"name": "ICE TITAN", "model": "ice_golem", "model_h": 20.0, "tint": Color("5fa8dc"), "body": Color("bfe3ff"), "eye": Color("29a0ff"), "wave": Color("9fe8ff"), "glow": 0.15,
			"throws": {"smash": 32, "block": 20, "sweep_low": 16, "sweep_high": 16, "stomp": 16}, "combo": 0.25, "rate": 0.95,
			"archetype": "gate_walker", "signature": {"ice_lane": 20, "quake_rhythm": 15, "decoy": 15}}},
	{"name": "EMBER", "radius": 30.0, "sky_top": Color("1a1024"), "sky_bottom": Color("5a2a3a"),
		"ground": [Color("4a3030"), Color("3a2626"), Color("5a3a32")], "water": Color("ff5a1f"), "shore": Color("2a1a1a"),
		"track": Color("2c2a30"), "curb": Color("ff7a2a"), "dash": Color("ff9a4a"), "glow_road": true,
		"props": {"volcano": 2, "shard": 4, "deadtree": 4, "lava": 3, "ash_rock": 4},
		"laps_to_boss": 3, "boss_loops": 5,
		"boss": {"name": "MAGMA GIANT", "model": "lava_monster", "model_h": 21.0, "body": Color("3a2a2a"), "eye": Color("ffc400"), "wave": Color("ff7a2a"), "glow": 0.8,
			"throws": {"smash": 30, "block": 22, "sweep_low": 15, "sweep_high": 15, "stomp": 18}, "combo": 0.35, "rate": 1.05,
			"archetype": "gate_walker", "signature": {"lava_trail": 22, "quake_rhythm": 14, "decoy": 16, "gate_slam": 1}}},
]
var THEME: Dictionary = THEMES[0]    # the current planet

var difficulty := "medium"
var character := "runner"
var sound := true
var hero_models := true     # 3D models for heroes and bosses (true) or the block figures (false)


func diff() -> Dictionary:
	return DIFF[difficulty]


func char_def() -> Dictionary:
	return CHARS[character]


func lane_x(lane: int) -> float:
	return lane * LANE_W
