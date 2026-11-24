class_name Missions
extends RefCounted
## Missions: three at a time, in sets. Each mission gives coins and XP; finishing all three
## gives a set bonus and the next set (a little harder). No score multiplier: the score
## stays about the run itself.
##
## A mission counts a stat, either over all runs ("total") or within one run ("run").
## Stats come from main.gd's run counts: coins, close, smash, jump, slide, power, dist,
## boss, hops (planets reached), clean_boss (a boss beaten without a stumble),
## close_<hero> (close calls with that hero).

# id: [text (with %d or %s), stat, mode, base target, extra per set, icon]
const KINDS := {
	"coins":     ["Collect %d coins", "coins", "total", 150, 75, "coin"],
	"close":     ["Make %d close calls", "close", "total", 10, 5, "eye"],
	"smash":     ["Smash %d obstacles", "smash", "total", 6, 3, "bolt"],
	"jump":      ["Jump %d times", "jump", "total", 40, 20, "up"],
	"slide":     ["Slide %d times", "slide", "total", 25, 12, "down"],
	"power":     ["Grab %d power-ups", "power", "total", 4, 2, "magnet"],
	"dist_run":  ["Run %d m in one run", "dist", "run", 600, 250, "boot"],
	"coins_run": ["Collect %d coins in one run", "coins", "run", 50, 20, "coin"],
	"boss":      ["Beat %d bosses", "boss", "total", 1, 1, "crown"],
	"world":     ["Reach %s in one run", "hops", "run", 1, 0, "wing"],
	"clean":     ["Beat a boss without a stumble", "clean_boss", "run", 1, 0, "heart"],
	"hero":      ["Make %d close calls with the %s", "close_", "total", 8, 4, "hero"],
}
const WORLDS := ["", "Dunes", "Glacier", "Ember", "the new bosses"]
const HEROES := ["runner", "smasher", "jumper"]


## The three missions of set s (0 = the first set: easy ones for a new player).
static func make_set(s: int) -> Array:
	var ids: Array
	if s == 0:
		ids = ["coins", "jump", "dist_run"]
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * s + 13
		var pool := KINDS.keys()
		if s < 3:                                  # bosses and feats come a bit later
			pool.erase("clean")
		ids = []
		while ids.size() < 3:
			var id: String = pool[rng.randi() % pool.size()]
			if id in ids or (id.begins_with("coins") and ids.any(func(x): return x.begins_with("coins"))):
				continue
			ids.append(id)
	var out := []
	for id in ids:
		var k: Array = KINDS[id]
		var m := {"id": id, "prog": 0, "done": false, "target": int(k[3] + k[4] * mini(s, 12))}
		if id == "world":
			m["target"] = clampi(1 + s / 2, 1, 4)
		elif id == "boss":
			m["target"] = mini(1 + s / 3, 5)
		elif id == "hero":
			m["hero"] = HEROES[s % 3]
		out.append(m)
	return out


static func stat(m: Dictionary) -> String:
	var k: Array = KINDS[m["id"]]
	return k[1] + m.get("hero", "")


static func text(m: Dictionary) -> String:
	var k: Array = KINDS[m["id"]]
	match m["id"]:
		"world": return k[0] % WORLDS[m["target"]]
		"clean": return k[0]
		"hero": return k[0] % [m["target"], Config.CHARS[m["hero"]]["name"]]
	return k[0] % m["target"]


static func icon(m: Dictionary) -> String:
	return KINDS[m["id"]][5]


## Progress including the run in progress (run: this run's counts, or {}).
static func value(m: Dictionary, run: Dictionary) -> int:
	if m["done"]:
		return m["target"]
	var v: int = int(run.get(stat(m), 0))
	return mini(m["target"], m["prog"] + v if KINDS[m["id"]][2] == "total" else maxi(m["prog"], v))


static func reward_coins(s: int) -> int:
	return mini(40 + 20 * s, 300)


static func reward_xp(s: int) -> int:
	return mini(80 + 40 * s, 800)


static func set_bonus(s: int) -> int:
	return mini(150 + 75 * s, 1000)
