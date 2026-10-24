extends Node
## Tiny synth: every sound is generated in code at startup, so the game ships no audio files.

const RATE := 22050
## Bigger thoughts sound lower (C major pentatonic, high to low).
const MERGE_NOTES := [1046.5, 880.0, 784.0, 659.3, 587.3, 523.3, 440.0, 392.0, 329.6, 293.7, 261.6]

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _bank := {}
var _ambient: AudioStreamPlayer
var _unlocked := false


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for t in MERGE_NOTES.size():
		_bank["merge%d" % t] = _tone(MERGE_NOTES[t], MERGE_NOTES[t], 0.55, 6.0, 0.3, true)
	_bank["drop"] = _tone(520.0, 170.0, 0.14, 16.0, 0.45)
	_bank["letgo"] = _tone(1200.0, 1800.0, 0.4, 5.0, 0.16)
	_bank["tick"] = _tone(330.0, 330.0, 0.07, 30.0, 0.22)
	_bank["over"] = _tone(392.0, 98.0, 1.2, 2.2, 0.45)
	_bank["big"] = _tone(196.0, 784.0, 1.0, 2.5, 0.4, true)
	_bank["alarm"] = _alarm()
	_ambient = AudioStreamPlayer.new()
	_ambient.stream = _night_loop()
	_ambient.volume_db = -14.0
	add_child(_ambient)


## Audio on the web may only start after a user gesture, so the first tap calls this.
func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	_ambient.play()


func play_merge(tier: int) -> void:
	_play("merge%d" % clampi(tier, 0, MERGE_NOTES.size() - 1))


func play_drop() -> void:
	_play("drop", -4.0)


func play_let_go() -> void:
	_play("letgo")


func play_tick() -> void:
	_play("tick")


func play_over() -> void:
	_play("over")


func play_big() -> void:
	_play("big")


func play_alarm() -> void:
	_play("alarm", 0.0, 1.0, false)


func _play(key: String, vol_db := 0.0, pitch := 1.0, jitter := true) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _bank[key]
	p.volume_db = vol_db
	p.pitch_scale = pitch * (randf_range(0.97, 1.03) if jitter else 1.0)
	p.play()


func _tone(f0: float, f1: float, dur: float, decay: float, vol: float, fifth := false) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var x := float(i) / n
		var f := lerpf(f0, f1, 1.0 - pow(1.0 - x, 3.0))
		phase += TAU * f / RATE
		var t := float(i) / RATE
		var env := minf(t * 150.0, 1.0) * exp(-t * decay)
		var v := sin(phase) + 0.2 * sin(phase * 2.0)
		if fifth:
			v += 0.35 * sin(phase * 1.5)
		samples[i] = v * env * vol
	return _wav(samples)


func _alarm() -> AudioStreamWAV:
	var n := int(RATE * 1.2)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / RATE
		var on := fmod(t, 0.3) < 0.18
		samples[i] = (0.3 * signf(sin(TAU * 1320.0 * t)) if on else 0.0) * 0.5
	return _wav(samples)


## Soft brown noise, like distant wind, with a crossfaded loop seam.
func _night_loop() -> AudioStreamWAV:
	var n := RATE * 4
	var fade := RATE / 2
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var b := 0.0
	for i in raw.size():
		b = (b + 0.02 * randf_range(-1.0, 1.0)) / 1.02
		var swell := 0.75 + 0.25 * sin(TAU * float(i) / (n + fade))
		raw[i] = b * 3.0 * swell
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
	for i in fade:
		var k := float(i) / fade
		out[i] = raw[n + i] * (1.0 - k) + raw[i] * k
	var w := _wav(out)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
