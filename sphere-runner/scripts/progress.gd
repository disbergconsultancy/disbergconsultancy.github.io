extends Node
## Long-term progression, autoloaded as `Progress`:
## - XP and levels 1-20 per character, skill points (one per level to 8, then every second level: 13)
## - a skill tree per character (3 branches x 4 tiers, 8 points per branch, tiers open at 0/2/4/6)
## - the core shop (coins saved between runs): Luck, Power-up duration, Stumble guard
## - balance stats (last 10 runs per character and difficulty) and settings
## Everything is saved in user://save.cfg.

const SAVE_PATH := "user://save.cfg"
const MAX_LEVEL := 20
const TIER_REQ := [0, 2, 4, 6]
const BRANCH_POINTS := 8
const TREE_POINTS := 24

# Branches per character: [name, colour, node ids from tier 1 to the capstone].
# Ranks: tier 1 has 3, tiers 2 and 3 have 2, the capstone 1.
const TREES := {
	"runner": [["Flow", "ffd23d", ["rhythm", "showtime", "chain", "crescendo"]],
		["Agility", "7fd4ff", ["quickfeet", "aircontrol", "spring", "slipstream"]],
		["Focus", "8fa2ff", ["charge", "readthrow", "still", "field"]]],
	"smasher": [["Demolition", "ff8a2a", ["fuel", "wreck", "overdrive", "aftershock"]],
		["Bulk", "aab6cc", ["legs", "pound", "sprinter", "ram"]],
		["Plunder", "ffd23d", ["scrap", "salvage", "rampage", "jackpot"]]],
	"jumper": [["Skyward", "8dff7a", ["springlegs", "glider", "quickland", "djump"]],
		["Leap", "d4ff3d", ["windup", "vault", "hang", "meteor"]],
		["Aerial", "7df9ff", ["daredevil", "flyer", "windrider", "updraft"]]],
}
const NODE_NAMES := {
	"rhythm": "Rhythm", "showtime": "Showtime", "chain": "Chain Master", "crescendo": "Crescendo",
	"quickfeet": "Quick Feet", "aircontrol": "Air Control", "spring": "Spring", "slipstream": "Slipstream",
	"charge": "Charge", "readthrow": "Read the Throw", "still": "Stillness", "field": "Focus Field",
	"fuel": "Fuel", "wreck": "Wrecking Ball", "overdrive": "Overdrive", "aftershock": "Aftershock",
	"legs": "Power Legs", "pound": "Ground Pound", "sprinter": "Sprinter", "ram": "Battering Ram",
	"scrap": "Scrap Value", "salvage": "Salvage", "rampage": "Rampage", "jackpot": "Jackpot",
	"springlegs": "Spring Legs", "glider": "Glider", "quickland": "Quick Landing", "djump": "Double Jump",
	"windup": "Wind Up", "vault": "Vault", "hang": "Hang Time", "meteor": "Meteor",
	"daredevil": "Daredevil", "flyer": "Frequent Flyer", "windrider": "Wind Rider", "updraft": "Updraft",
}
const BOSS_NODES := ["readthrow", "wreck", "vault"]
const XP_NODES := ["showtime", "salvage", "flyer"]

const CORE := {
	"luck": {"name": "Luck", "max": 5, "prices": [100, 200, 400, 700, 1100], "color": "7df9ff"},
	"dur": {"name": "Power-up duration", "max": 5, "prices": [100, 200, 400, 700, 1100], "color": "ff4fa3"},
	"stumble": {"name": "Stumble guard", "max": 3, "prices": [400, 900, 1500], "color": "ffb020"},
}

var prog := {}        # character -> {"lvl", "xp", "alloc": {node: rank}}
var wallet := 0
var core := {"luck": 0, "dur": 0, "stumble": 0}
var runs := {}        # "character_difficulty" -> [{"d": metres, "s": score}] (last 10)
var best := {}        # "character_difficulty" -> score


func _ready() -> void:
	load_save()


# =====================================================================
# Save
# =====================================================================

func load_save() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(SAVE_PATH) == OK
	for c in Config.CHARS:
		prog[c] = cfg.get_value("prog", c, {"lvl": 1, "xp": 0, "alloc": {}}) if ok else {"lvl": 1, "xp": 0, "alloc": {}}
	if not ok:
		return
	wallet = cfg.get_value("core", "wallet", 0)
	core = cfg.get_value("core", "levels", core)
	runs = cfg.get_value("stats", "runs", {})
	best = cfg.get_value("stats", "best", {})
	Config.character = cfg.get_value("settings", "character", Config.character)
	Config.difficulty = cfg.get_value("settings", "difficulty", Config.difficulty)
	Config.sound = cfg.get_value("settings", "sound", Config.sound)


func save() -> void:
	var cfg := ConfigFile.new()
	for c in prog:
		cfg.set_value("prog", c, prog[c])
	cfg.set_value("core", "wallet", wallet)
	cfg.set_value("core", "levels", core)
	cfg.set_value("stats", "runs", runs)
	cfg.set_value("stats", "best", best)
	cfg.set_value("settings", "character", Config.character)
	cfg.set_value("settings", "difficulty", Config.difficulty)
	cfg.set_value("settings", "sound", Config.sound)
	cfg.save(SAVE_PATH)


# =====================================================================
# Levels and skill points
# =====================================================================

## XP needed for the next level grows with level^1.5: level 2 after the first run,
## level 10 after ~40 runs, level 20 after ~74,000 XP (~250 runs).
static func xp_for_next(lvl: int) -> int:
	return roundi(110.0 * pow(lvl, 1.5))


static func points_at_level(lvl: int) -> int:
	return mini(lvl, 8) - 1 + maxi(0, (lvl - 8) / 2)


func spent(c: String) -> int:
	var n := 0
	for v in prog[c]["alloc"].values():
		n += v
	return n


func free_points(c: String) -> int:
	return points_at_level(prog[c]["lvl"]) - spent(c)


static func max_rank(tier: int) -> int:
	return 3 if tier == 0 else 1 if tier == 3 else 2


func branch_points(c: String, b: int) -> int:
	var n := 0
	for id in TREES[c][b][2]:
		n += prog[c]["alloc"].get(id, 0)
	return n


func can_learn(c: String, b: int, tier: int) -> bool:
	var id: String = TREES[c][b][2][tier]
	return free_points(c) > 0 and prog[c]["alloc"].get(id, 0) < max_rank(tier) and branch_points(c, b) >= TIER_REQ[tier]


func learn(c: String, b: int, tier: int) -> void:
	if not can_learn(c, b, tier):
		return
	var id: String = TREES[c][b][2][tier]
	prog[c]["alloc"][id] = prog[c]["alloc"].get(id, 0) + 1
	save()


func respec(c: String) -> void:
	prog[c]["alloc"] = {}
	save()


## Adds XP for a finished run; returns {"xp", "levels", "points"}.
func award(c: String, base_xp: int) -> Dictionary:
	var xp := roundi(base_xp * stats(c)["xp_mul"])
	var p: Dictionary = prog[c]
	var before: int = p["lvl"]
	p["xp"] += xp
	while p["lvl"] < MAX_LEVEL and p["xp"] >= xp_for_next(p["lvl"]):
		p["xp"] -= xp_for_next(p["lvl"])
		p["lvl"] += 1
	if p["lvl"] >= MAX_LEVEL:
		p["xp"] = 0
	save()
	return {"xp": xp, "levels": p["lvl"] - before, "points": points_at_level(p["lvl"]) - points_at_level(before)}


# =====================================================================
# Skill effects
# =====================================================================

## What a node does at rank r (shown in the skill tree screen).
static func describe(id: String, r: int) -> String:
	match id:
		"rhythm": return "Combo window +%.1f s" % (0.4 * r)
		"showtime": return "+%d%% XP; close calls give +%d points" % [5 * r, 10 * r]
		"chain": return "Combo goes up a level every %d pickups (was 10)" % (9 - r)
		"crescendo": return "Combo can reach x6 (was x5)"
		"quickfeet": return "Lane switches %d%% faster" % (8 * r)
		"aircontrol": return "Air dash %d%% faster, float +%.2f s" % [35 * r, 0.15 * r]
		"spring": return "Jump %d%% higher" % (7 * r)
		"slipstream": return "After a close call: 1.5 s of 20% faster lane switches"
		"charge": return "Meter fills %d%% faster" % (13 * r)
		"readthrow": return "Focus +%.2f s; boss throws land %d m further ahead (more warning)" % [0.45 * r, 3 * r]
		"still": return "Focus slows the game to %d%% speed (was 45%%)" % (45 - 6 * r)
		"field": return "During Focus, nearby coins fly to you"
		"fuel": return "Meter fills %d%% faster" % (11 * r)
		"wreck": return "Each smash adds %.2f s (was 0.4); during Smash, boss throws aimed at you shatter in mid-air" % (0.4 + 0.15 * r)
		"overdrive": return "Smash can last up to %.2f s (was 5)" % (5.0 + 0.75 * r)
		"aftershock": return "When Smash ends, a blast clears every block in the next 10 m"
		"legs": return "Jump %d%% higher" % (7 * r)
		"pound": return "Slam down %d%% faster" % (22 * r)
		"sprinter": return "Lane switches %d%% faster" % (7 * r)
		"ram": return "Sliding into a crate breaks it instead of stopping you"
		"scrap": return "Smashed blocks give +%d points" % (7 * r)
		"salvage": return "+%d%% XP; coins worth %d%% more" % [5 * r, 15 * r]
		"rampage": return "Each smash adds +%d extra combo" % r
		"jackpot": return "Every smashed block also gives 3 coins"
		"springlegs": return "Jump %d%% higher" % (5 * r)
		"glider": return "Float +%.2f s" % (0.18 * r)
		"quickland": return "Slam down %d%% faster" % (22 * r)
		"djump": return "Swipe up again in mid-air to jump once more"
		"windup": return "Meter fills %d%% faster" % (11 * r)
		"vault": return "Jumping a boss throw or stomp wave fills %d%% meter, a crate %d%%" % [7 * r, 3 * r]
		"hang": return "Hover %.2f s at the top of a super jump" % (0.35 * r)
		"meteor": return "Landing from a super jump smashes the blocks just ahead"
		"daredevil": return "Close calls give +%d points" % (8 * r)
		"flyer": return "+%d%% XP; coins caught in the air worth %d%% more" % [5 * r, 30 * r]
		"windrider": return "Combo window +%.2f s" % (0.35 * r)
		"updraft": return "Close calls while in the air add 10% to the meter"
	return ""


static func _apply(s: Dictionary, id: String, r: int) -> void:
	match id:
		"rhythm": s["combo_time"] += 0.4 * r
		"showtime": s["xp_mul"] += 0.05 * r; s["close_bonus"] += 10 * r
		"chain": s["combo_step"] = 9 - r
		"crescendo": s["combo_cap"] = 6
		"quickfeet": s["lane_mul"] *= 1.0 + 0.08 * r
		"aircontrol": s["air_dash_mul"] *= 1.0 + 0.35 * r; s["float_time"] += 0.15 * r
		"spring", "legs": s["jump_v"] *= sqrt(1.0 + 0.07 * r)   # jump height scales with velocity squared
		"slipstream": s["slipstream"] = true
		"charge": s["meter_mul"] *= 1.0 + 0.13 * r
		"readthrow": s["ability_time"] += 0.45 * r; s["throw_lead"] += 3.0 * r
		"still": s["focus_slow"] = 0.45 - 0.06 * r
		"field": s["focus_magnet"] = true
		"fuel", "windup": s["meter_mul"] *= 1.0 + 0.11 * r
		"wreck": s["smash_extend"] += 0.15 * r; s["wreck"] = true
		"overdrive": s["ability_max"] += 0.75 * r
		"aftershock": s["aftershock"] = true
		"pound", "quickland": s["slam_mul"] *= 1.0 + 0.22 * r
		"sprinter": s["lane_mul"] *= 1.0 + 0.07 * r
		"ram": s["ram"] = true
		"scrap": s["smash_pts"] += 7 * r
		"salvage": s["xp_mul"] += 0.05 * r; s["coin_mul"] *= 1.0 + 0.15 * r
		"rampage": s["smash_combo"] += r
		"jackpot": s["jackpot"] = true
		"springlegs": s["jump_v"] *= sqrt(1.0 + 0.05 * r)
		"glider": s["float_time"] += 0.18 * r
		"djump": s["double_jump"] = true
		"vault": s["vault_boss"] += 0.07 * r; s["vault_crate"] += 0.03 * r
		"hang": s["hang_time"] += 0.35 * r
		"meteor": s["meteor"] = true
		"daredevil": s["close_bonus"] += 8 * r
		"flyer": s["xp_mul"] += 0.05 * r; s["air_coin_mul"] *= 1.0 + 0.3 * r
		"windrider": s["combo_time"] += 0.35 * r
		"updraft": s["updraft"] = true


## The character's base stats plus everything learned in its tree.
func stats(c: String = Config.character) -> Dictionary:
	var d: Dictionary = Config.CHARS[c]
	var s := {"lane_mul": d["lane_mul"], "jump_v": d["jump_v"], "float_time": d["float_time"], "combo_time": d["combo_time"],
		"combo_step": 10, "combo_cap": 5, "close_bonus": 0, "meter_mul": d["meter_mul"], "ability_time": d["ability_time"],
		"ability_max": d["ability_max"], "smash_extend": d["smash_extend"], "focus_slow": 0.45, "focus_magnet": false,
		"air_dash_mul": 1.0, "double_jump": false, "slam_mul": 1.0, "ram": false, "smash_pts": 0, "coin_mul": 1.0,
		"smash_combo": 0, "jackpot": false, "hang_time": 0.0, "meteor": false, "air_coin_mul": 1.0, "updraft": false,
		"xp_mul": 1.0, "slipstream": false, "throw_lead": 0.0, "wreck": false, "aftershock": false,
		"vault_boss": 0.0, "vault_crate": 0.0}
	var alloc: Dictionary = prog[c]["alloc"]
	for id in alloc:
		_apply(s, id, alloc[id])
	s["ability_max"] = maxf(s["ability_max"], s["ability_time"])
	return s


# =====================================================================
# Core shop
# =====================================================================

static func core_text(k: String, l: int) -> String:
	match k:
		"luck": return "Power-ups appear %d%% more often" % (6 * l) if l > 0 else "Power-ups appear more often"
		"dur": return "Magnet, x2 and Orbit last %d%% longer" % (10 * l) if l > 0 else "Magnet, x2 and Orbit last longer"
		"stumble":
			return ["Small hits (crate, bar, boulder, thrown log or bar, stomp wave) end the run",
				"1 stumble per run: a small hit costs your combo, your whole meter and some speed",
				"1 stumble per run, lighter: you keep half your meter",
				"2 stumbles per run (lighter penalty)"][l]
	return ""


func buy(k: String) -> bool:
	var l: int = core[k]
	if l >= CORE[k]["max"] or wallet < CORE[k]["prices"][l]:
		return false
	wallet -= CORE[k]["prices"][l]
	core[k] = l + 1
	save()
	return true


func luck_mul() -> float:
	return 1.0 + 0.06 * core["luck"]


func dur_mul() -> float:
	return 1.0 + 0.1 * core["dur"]


func stumbles_per_run() -> int:
	return 2 if core["stumble"] >= 3 else 1 if core["stumble"] >= 1 else 0


# =====================================================================
# Balance stats
# =====================================================================

func record_run(metres: int, score: int) -> bool:
	var key := Config.character + "_" + Config.difficulty
	var list: Array = runs.get(key, [])
	list.append({"d": metres, "s": score})
	runs[key] = list.slice(-10)
	var is_best: bool = score > best.get(key, 0)
	if is_best:
		best[key] = score
	save()
	return is_best


func best_score() -> int:
	return best.get(Config.character + "_" + Config.difficulty, 0)


## Average distance and score of the last 10 runs per character at this difficulty.
func stats_table() -> String:
	var lines: Array[String] = []
	for c in Config.CHARS:
		var list: Array = runs.get(c + "_" + Config.difficulty, [])
		if list.is_empty():
			lines.append("%s: no runs yet" % Config.CHARS[c]["name"])
			continue
		var d := 0.0
		var s := 0.0
		for r in list:
			d += r["d"]
			s += r["s"]
		lines.append("%s: %d runs · avg %d m · avg score %d" % [Config.CHARS[c]["name"], list.size(), int(d / list.size()), int(s / list.size())])
	return "\n".join(lines)
