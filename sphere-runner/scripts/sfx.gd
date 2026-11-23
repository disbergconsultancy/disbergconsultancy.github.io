class_name Sfx
extends Node
## Small synthesized sound effects (no audio files): each effect is a short tone sweep
## (or a sequence of notes) rendered once to a PCM buffer at startup.

const RATE := 22050
const VOICES := 6

# name: list of notes [from_hz, to_hz, seconds, wave, volume, start_delay]
const EFFECTS := {
	"jump": [[300, 700, 0.12, "square", 0.25, 0.0]],
	"slide": [[400, 150, 0.12, "triangle", 0.3, 0.0]],
	"swish": [[500, 350, 0.06, "triangle", 0.18, 0.0]],
	"dash": [[700, 1400, 0.08, "saw", 0.12, 0.0]],
	"coin": [[988, 1319, 0.08, "square", 0.15, 0.0]],
	"close": [[1200, 1800, 0.07, "triangle", 0.2, 0.0]],
	"combo": [[660, 660, 0.06, "square", 0.2, 0.0], [990, 990, 0.1, "square", 0.2, 0.06]],
	"lap": [[523, 523, 0.1, "square", 0.25, 0.0], [784, 784, 0.18, "square", 0.25, 0.11]],
	"power": [[440, 880, 0.12, "square", 0.25, 0.0], [660, 1320, 0.15, "square", 0.25, 0.09]],
	"shield": [[900, 200, 0.25, "triangle", 0.3, 0.0]],
	"ready": [[523, 523, 0.08, "square", 0.22, 0.0], [659, 659, 0.08, "square", 0.22, 0.08], [784, 784, 0.14, "square", 0.22, 0.16]],
	"ability": [[150, 900, 0.35, "saw", 0.25, 0.0]],
	"smash": [[160, 50, 0.18, "square", 0.35, 0.0]],
	"crash": [[200, 40, 0.4, "saw", 0.35, 0.0]],
}

var enabled := true
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for name in EFFECTS:
		_streams[name] = _render(EFFECTS[name])
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String) -> void:
	if not enabled or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[name]
	p.play()


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
		var start := int(n[5] * RATE)
		var length := int(dur * RATE)
		var phase := 0.0
		for i in length:
			var t := float(i) / length
			var f := f0 * pow(f1 / f0, t)        # exponential sweep
			phase = fmod(phase + f / RATE, 1.0)
			var v := 0.0
			match wave:
				"square": v = 1.0 if phase < 0.5 else -1.0
				"triangle": v = 1.0 - 4.0 * absf(phase - 0.5)
				"saw": v = 2.0 * phase - 1.0
				_: v = sin(phase * TAU)
			var env := pow(1.0 - t, 2.0)          # quick decay
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
