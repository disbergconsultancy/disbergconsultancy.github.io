class_name Spawner
extends RefCounted
## Places obstacles and coins ahead of the runner: hand-made patterns ("chunks") mixed
## with random rows, in waves of rising intensity followed by a calm coin stretch.

const CHUNK_WEIGHTS := {
	"easy": {"row": 50, "platform_run": 14, "zigzag": 10, "pit": 12, "jump_slide": 8, "corridor": 0, "mover": 6},
	"medium": {"row": 38, "platform_run": 14, "zigzag": 12, "pit": 10, "jump_slide": 8, "corridor": 8, "mover": 10},
	"hard": {"row": 30, "platform_run": 14, "zigzag": 14, "pit": 10, "jump_slide": 10, "corridor": 10, "mover": 12},
}

var planet: Planet
var next_spawn := 0.0      # globe-local angle of the next pattern
var spawned := 0
var wave_left := 0.0
var calm_next := false
var speed := 10.0          # current run speed, set by the game each frame
var allow_powers := false  # power-ups only during a run (not behind the menu)
var power_in := 90.0       # metres until the next power-up
var stop_angle := INF      # no patterns past this point (the boss chase starts there)
var rng := RandomNumberGenerator.new()


func _init(p: Planet) -> void:
	planet = p
	rng.randomize()


func reset(start_angle: float) -> void:
	next_spawn = start_angle + 25.0 / planet.radius
	spawned = 0
	wave_left = Config.WAVE_M[Config.difficulty]
	calm_next = false
	power_in = 90.0


func update(angle: float) -> void:
	var r := planet.radius
	var d: Dictionary = Config.diff()
	while next_spawn < angle + Config.SPAWN_AHEAD_M / r and next_spawn < stop_angle:
		var chunk := "calm" if calm_next else _pick_chunk()
		if calm_next:
			calm_next = false
			wave_left = Config.WAVE_M[Config.difficulty]
		var length: float = call("_chunk_" + chunk, next_spawn)
		spawned += 1
		var intensity: float = 1.0 - wave_left / Config.WAVE_M[Config.difficulty]
		var gap := 8.0 if chunk == "calm" else maxf(d["min_gap"], speed * d["gap"] * (1.0 - 0.2 * intensity))
		if chunk != "calm":
			wave_left -= length + gap
			if wave_left <= 0.0:
				calm_next = true
		# Power-ups float in the empty gap between patterns.
		power_in -= length + gap
		if power_in <= 0.0 and allow_powers:
			power_in = (160.0 + rng.randf() * 140.0) / Progress.luck_mul()
			_add_power(next_spawn + (length + gap / 2.0) / r, _lane())
		next_spawn += (length + gap) / r
	# Remove what is well behind the runner.
	var keep: Array[Item] = []
	for it in planet.items:
		if (it.phi - angle) * r < -(Config.DESPAWN_BEHIND_M + it.hd):
			planet.remove_item(it)
		else:
			keep.append(it)
	planet.items = keep


func _pick_chunk() -> String:
	if spawned < 3:
		return "row"   # every run starts with a few simple rows
	var w: Dictionary = CHUNK_WEIGHTS[Config.difficulty].duplicate()
	var intensity: float = 1.0 - wave_left / Config.WAVE_M[Config.difficulty]
	w["row"] = w["row"] * (1.0 - 0.5 * intensity)   # later in a wave: fewer plain rows
	var total := 0.0
	for v in w.values():
		total += v
	var roll := rng.randf() * total
	for k in w:
		roll -= w[k]
		if roll < 0.0:
			return k
	return "row"


func _add_power(phi: float, lane: int) -> void:
	planet.add_item("POWER", phi, Config.lane_x(lane), {"power": Config.POWERS.keys().pick_random()})


func _lane() -> int:
	return [-1, 0, 1][rng.randi() % 3]


func _at(phi: float, m: float) -> float:
	return phi + m / planet.radius


func _coin_line(phi: float, lane: int, from_m: float, to_m: float, y := 0.4, step := 1.6) -> void:
	var m := from_m
	while m <= to_m + 0.01:
		planet.add_item("COIN", _at(phi, m), Config.lane_x(lane), {"y0": y})
		m += step


func _coin_arc(phi: float, lane: int, centre_m: float, base := 1.2) -> void:
	for k in 5:
		var dm := (k - 2) * 1.6
		planet.add_item("COIN", _at(phi, centre_m + dm), Config.lane_x(lane), {"y0": base + 1.2 * (1.0 - pow(dm / 4.0, 2))})


# --- Chunks: each places its content from phi and returns its length in metres -------

func _chunk_row(phi: float) -> float:
	var d: Dictionary = Config.diff()
	var difficulty := clampf((speed - d["start"]) / (d["max"] - d["start"]), 0.0, 1.0)
	var row: Array[String] = []
	for i in 3:
		var r := rng.randf()
		var e: float = d["empty"] - d["empty_ramp"] * difficulty
		if r < e:
			row.append("EMPTY")
		elif r < e + d["low"]:
			row.append("LOW")
		elif r < e + d["low"] + d["high"]:
			row.append("HIGH")
		else:
			row.append("WALL")
	var blocked: Array[int] = []
	for i in 3:
		if row[i] != "EMPTY":
			blocked.append(i)
	while blocked.size() > int(d["max_blocked"]):
		row[blocked.pop_at(rng.randi() % blocked.size())] = "EMPTY"
	if not ("EMPTY" in row or "LOW" in row or "HIGH" in row):
		row[rng.randi() % 3] = "EMPTY"
	if row.count("EMPTY") == 3:
		row[rng.randi() % 3] = "LOW" if rng.randf() < 0.5 else "HIGH"
	for i in 3:
		if row[i] != "EMPTY":
			planet.add_item(row[i], phi, Config.lane_x(i - 1))
	var lanes: Array[int] = []
	for i in 3:
		if row[i] != "WALL":
			lanes.append(i)
	if lanes.size() > 0 and rng.randf() < 0.65:
		var ci: int = lanes[rng.randi() % lanes.size()]
		if row[ci] == "LOW":
			_coin_arc(phi, ci - 1, 0.0)
		else:
			_coin_line(phi, ci - 1, -3.2, 3.2, 0.1 if row[ci] == "HIGH" else 0.4)
	return 1.0


## Ramp up onto a long block; hazards in the other lanes make the roof the safe route.
func _chunk_platform_run(phi: float) -> float:
	var lane := _lane()
	var length := 14.0 + rng.randf() * 10.0
	var top: float = Config.KIND["PLATFORM"]["h"]
	planet.add_item("RAMP", _at(phi, 2.5), Config.lane_x(lane))
	planet.add_item("PLATFORM", _at(phi, 5.0 + length / 2.0), Config.lane_x(lane), {"depth": length})
	_coin_line(phi, lane, 6.0, 4.0 + length, top + 0.4, 2.0)
	var others := [-1, 0, 1].filter(func(l): return l != lane)
	var m := 8.0
	while m < length:
		var kinds := ["LOW", "HIGH"] if Config.difficulty == "easy" else ["LOW", "HIGH", "WALL"]
		planet.add_item(kinds.pick_random(), _at(phi, m), Config.lane_x(others.pick_random()))
		m += 9.0
	return 5.0 + length


## Two blocks on the outer lanes; the middle lane is a jump-slide-jump gauntlet.
func _chunk_corridor(phi: float) -> float:
	var length := 22.0
	for l in [-1, 1]:
		planet.add_item("PLATFORM", _at(phi, length / 2.0), Config.lane_x(l), {"depth": length})
	planet.add_item("LOW", _at(phi, 5.0), 0.0)
	planet.add_item("HIGH", _at(phi, 12.0), 0.0)
	planet.add_item("LOW", _at(phi, 19.0), 0.0)
	_coin_arc(phi, 0, 5.0)
	_coin_line(phi, 0, 11.0, 13.0, 0.1, 1.0)
	_coin_arc(phi, 0, 19.0)
	return length


## Walls force a lane change every few metres.
func _chunk_zigzag(phi: float) -> float:
	var n := 4 if Config.difficulty == "hard" else 3
	var gap := 11.0 if Config.difficulty == "easy" else 8.0
	var free := _lane()
	for i in n:
		var choices := [-1, 0, 1].filter(func(l): return l != free and absi(l - free) == 1)
		free = choices.pick_random()
		for l in [-1, 0, 1]:
			if l != free and (Config.difficulty != "easy" or absi(l - free) == 1):
				planet.add_item("WALL", _at(phi, i * gap), Config.lane_x(l))
		planet.add_item("COIN", _at(phi, i * gap), Config.lane_x(free), {"y0": 0.4})
	return (n - 1) * gap


## Glowing floor: jump across.
func _chunk_pit(phi: float) -> float:
	var lanes := [-1, 0, 1]
	if Config.difficulty == "easy":
		lanes.shuffle()
		lanes = lanes.slice(0, 2)
	for l in lanes:
		planet.add_item("PIT", phi, Config.lane_x(l))
	_coin_arc(phi, lanes.pick_random(), 0.0)
	return 3.0


## Jump, then slide.
func _chunk_jump_slide(phi: float) -> float:
	var gap := 7.0 if Config.difficulty == "hard" else 9.0
	for l in [-1, 0, 1]:
		planet.add_item("LOW", phi, Config.lane_x(l))
		planet.add_item("HIGH", _at(phi, gap), Config.lane_x(l))
	var c := _lane()
	_coin_arc(phi, c, 0.0)
	_coin_line(phi, c, gap - 1.5, gap + 1.5, 0.1, 1.5)
	return gap


## A block that slides between lanes.
func _chunk_mover(phi: float) -> float:
	for i in (2 if rng.randf() < 0.5 else 1):
		var it := planet.add_item("MOVER", _at(phi, i * 10.0), 0.0)
		it.move_amp = Config.LANE_W
		it.move_speed = 1.6 + rng.randf()
		it.move_phase = rng.randf() * TAU
	return 10.0


## Calm stretch: a snake of coins, no hazards.
func _chunk_calm(phi: float) -> float:
	var lane := _lane()
	var m := 0.0
	while m < Config.CALM_M - 10.0:
		if rng.randf() < 0.12:
			lane = clampi(lane + [-1, 1].pick_random(), -1, 1)
		var y := 1.2 + sin(m * 0.5) * 0.6 if int(m / 18.0) % 2 == 1 else 0.4
		planet.add_item("COIN", _at(phi, m), Config.lane_x(lane), {"y0": y})
		m += 1.8
	if allow_powers and rng.randf() < minf(1.0, 0.6 * Progress.luck_mul()):   # usually a power-up at the end of a calm stretch
		_add_power(_at(phi, Config.CALM_M - 5.0), _lane())
		power_in = (160.0 + rng.randf() * 100.0) / Progress.luck_mul()
	return Config.CALM_M
