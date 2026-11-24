class_name Sfx
extends Node
## Sound: effects from Kenney's CC0 packs (assets/audio/sfx, picked by tools/pick_sfx.py),
## 8-bit effects synthesized at startup for the rest (and as a fallback), and chiptune music
## loops (assets/audio/music, made by tools/gen_music.py) with a short cross-fade.
## Landing uses footsteps that match the ground of the world (grass, sand, snow, rock).
## Effects: a list of notes [from_hz, to_hz, seconds, wave, volume, start_delay, duty].
## Waves: square (duty), triangle, saw, sine, noise (pitch = how fast it changes).

const RATE := 22050
const VOICES := 8

const EFFECTS := {
	"jump": [[330, 660, 0.10, "square", 0.22, 0.0, 0.25], [660, 880, 0.06, "square", 0.12, 0.07, 0.25]],
	"land": [[900, 300, 0.07, "noise", 0.28, 0.0], [140, 70, 0.08, "sine", 0.35, 0.0]],
	"slide": [[3000, 800, 0.22, "noise", 0.18, 0.0], [300, 160, 0.12, "triangle", 0.18, 0.0]],
	"swish": [[5000, 2200, 0.08, "noise", 0.12, 0.0]],
	"dash": [[500, 1500, 0.09, "triangle", 0.18, 0.0], [5000, 3000, 0.06, "noise", 0.08, 0.0]],
	"coin": [[988, 988, 0.05, "square", 0.13, 0.0, 0.125], [1319, 1319, 0.12, "square", 0.13, 0.05, 0.125]],
	"close": [[1568, 2093, 0.06, "square", 0.12, 0.0, 0.125], [2093, 2637, 0.08, "square", 0.10, 0.05, 0.125]],
	"combo": [[659, 659, 0.05, "square", 0.16, 0.0, 0.25], [880, 880, 0.05, "square", 0.16, 0.05, 0.25], [1319, 1319, 0.1, "square", 0.16, 0.1, 0.25]],
	"lap": [[523, 523, 0.09, "square", 0.2, 0.0, 0.5], [784, 784, 0.16, "square", 0.2, 0.1, 0.5]],
	"power": [[440, 880, 0.12, "square", 0.2, 0.0, 0.25], [660, 1320, 0.14, "square", 0.2, 0.09, 0.25], [1320, 1760, 0.12, "triangle", 0.14, 0.18]],
	"shield": [[1200, 300, 0.25, "triangle", 0.28, 0.0], [4000, 1500, 0.2, "noise", 0.1, 0.0]],
	"ready": [[523, 523, 0.07, "square", 0.18, 0.0, 0.25], [659, 659, 0.07, "square", 0.18, 0.07, 0.25], [784, 784, 0.12, "square", 0.18, 0.14, 0.25]],
	"ability": [[150, 900, 0.32, "saw", 0.2, 0.0], [600, 2400, 0.3, "noise", 0.1, 0.0]],
	"smash": [[2500, 300, 0.2, "noise", 0.35, 0.0], [160, 50, 0.18, "square", 0.25, 0.0, 0.5]],
	"crash": [[3000, 200, 0.45, "noise", 0.4, 0.0], [220, 40, 0.45, "saw", 0.25, 0.0]],
	"stumble": [[500, 200, 0.18, "square", 0.2, 0.0, 0.5], [1500, 400, 0.15, "noise", 0.18, 0.0]],
	"throw": [[800, 3500, 0.28, "noise", 0.14, 0.0], [880, 880, 0.06, "square", 0.1, 0.0, 0.5], [660, 660, 0.06, "square", 0.1, 0.08, 0.5]],
	"stomp": [[90, 35, 0.5, "sine", 0.55, 0.0], [1200, 150, 0.4, "noise", 0.35, 0.0]],
	"hop": [[392, 392, 0.07, "square", 0.18, 0.0, 0.25], [523, 523, 0.07, "square", 0.18, 0.07, 0.25], [659, 659, 0.07, "square", 0.18, 0.14, 0.25],
		[784, 784, 0.07, "square", 0.18, 0.21, 0.25], [1047, 1047, 0.25, "square", 0.18, 0.28, 0.25], [200, 2000, 0.6, "noise", 0.08, 0.0]],
	"defeat": [[523, 523, 0.1, "square", 0.2, 0.0, 0.5], [659, 659, 0.1, "square", 0.2, 0.1, 0.5], [784, 784, 0.1, "square", 0.2, 0.2, 0.5],
		[1047, 1047, 0.4, "square", 0.2, 0.3, 0.5], [262, 262, 0.7, "triangle", 0.25, 0.0]],
	"gameover": [[523, 523, 0.14, "square", 0.18, 0.0, 0.5], [415, 415, 0.14, "square", 0.18, 0.15, 0.5], [349, 349, 0.14, "square", 0.18, 0.3, 0.5],
		[262, 262, 0.5, "square", 0.18, 0.45, 0.5], [131, 131, 0.9, "triangle", 0.25, 0.0]],
	"click": [[1800, 1200, 0.03, "square", 0.1, 0.0, 0.5]],
	"tip": [[784, 784, 0.08, "triangle", 0.2, 0.0], [1175, 1175, 0.16, "triangle", 0.2, 0.08]],
}

var enabled := true            # sound effects
var music_on := true
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: Array[AudioStreamPlayer] = []   # two players for cross-fades
var _track := ""
var _fade := 0.0
var _rng := RandomNumberGenerator.new()
var surface := "grass"         # which footstep "land" plays
const SURFACES := {"meadow": "grass", "dunes": "carpet", "glacier": "snow", "ember": "concrete"}


func _ready() -> void:
	_rng.seed = 7
	for name in EFFECTS:
		_streams[name] = _render(EFFECTS[name])
	for f in ResourceLoader.list_directory("res://assets/audio/sfx"):
		if f.ends_with(".ogg"):
			_streams[f.get_basename()] = load("res://assets/audio/sfx/" + f)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)


## pitch: playback speed (1 = as made); used for the coin chime climbing with the combo.
func play(name: String, pitch := 1.0) -> void:
	if name == "land" and _streams.has("land_" + surface):
		name = "land_" + surface
	if not enabled or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()


## Switches the music loop ("" = fade out). Same track: nothing happens.
func music(name: String) -> void:
	if name == _track:
		return
	_track = name
	surface = SURFACES.get(name, surface)
	var old := _music[0]
	var new := _music[1]
	_music = [new, old]
	if name != "" and music_on:
		var path := "res://assets/audio/music/%s.ogg" % name
		if ResourceLoader.exists(path):
			var s: AudioStreamOggVorbis = load(path)
			s.loop = true
			new.stream = s
			new.volume_db = -40.0
			new.play()
	_fade = 1.0


func set_music_on(on: bool) -> void:
	music_on = on
	var t := _track
	_track = "-"
	if on:
		music(t)
	else:
		for m in _music:
			m.stop()
		_track = t


## Stop and let go of every stream before the players are freed (quitting mid-song crashed).
func _exit_tree() -> void:
	for p in _players + _music:
		p.stop()
		p.stream = null


func _process(delta: float) -> void:
	if _fade <= 0.0:
		return
	_fade = maxf(0.0, _fade - delta / 0.6)
	var u := 1.0 - _fade
	_music[0].volume_db = linear_to_db(maxf(0.0001, u * 0.55)) if _music[0].playing else -80.0
	_music[1].volume_db = linear_to_db(maxf(0.0001, (1.0 - u) * 0.55))
	if _fade <= 0.0:
		_music[1].stop()


func _render(notes: Array) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total = maxf(total, n[5] + n[2])
	var count := int(total * RATE) + 1
	var buf := PackedFloat32Array()
	buf.resize(count)
	for n in notes:
		var f0: float = n[0]
		var f1: float = n[1]
		var dur: float = n[2]
		var wave: String = n[3]
		var vol: float = n[4]
		var duty: float = n[6] if n.size() > 6 else 0.5
		var start := int(n[5] * RATE)
		var length := int(dur * RATE)
		var phase := 0.0
		var nv := 0.0
		var hold := 0.0
		for i in length:
			var t := float(i) / length
			var f := f0 * pow(f1 / f0, t)        # exponential sweep
			phase = fmod(phase + f / RATE, 1.0)
			var v := 0.0
			match wave:
				"square": v = 1.0 if phase < duty else -1.0
				"triangle": v = 1.0 - 4.0 * absf(phase - 0.5)
				"saw": v = 2.0 * phase - 1.0
				"noise":
					hold -= 1.0
					if hold <= 0.0:              # a new random level every 1/f seconds (pitched noise)
						nv = _rng.randf_range(-1.0, 1.0)
						hold = RATE / maxf(f, 1.0)
					v = nv
				_: v = sin(phase * TAU)
			var attack := minf(1.0, i / (0.004 * RATE))
			var env := attack * pow(1.0 - t, 1.6)  # quick attack, smooth decay
			if start + i < count:
				buf[start + i] += v * vol * env
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s
