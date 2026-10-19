class_name Sfx
extends Node
## Sound effects for the battle screen, synthesised in code (no audio files): footsteps for moves, a whoosh for
## missed blows and shots, a thud for wounding hits, a clank for armour saves, a clash for parries, a bow twang for
## shots, and a death cry followed by a heavy fall for a take-down. Sounds are picked from the battle log (events_for), so the rules engine
## knows nothing about them, and are queued a little apart so a burst of log lines plays as a sequence.

const RATE := 22050
const VARIANTS := 3
const POOL := 8

static var _streams := {}           # name -> [AudioStreamWAV variants]

var _players: Array = []
var _next := 0
var _queue: Array = []              # [{"at": seconds, "name": String, "pitch": float, "db": float}]
var _clock := 0.0
var _free_at := 0.0                 # when the queue is next free (sequencing)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	build_streams()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	_clock += delta
	while not _queue.is_empty() and _queue[0]["at"] <= _clock:
		var e: Dictionary = _queue.pop_front()
		_play_now(e["name"], e["pitch"], e["db"])


## Plays the sounds a log line calls for, after whatever is already queued.
func on_log(text: String) -> void:
	for e in events_for(text):
		queue(e["name"], e.get("gap", 0.12), e.get("pitch", 1.0), e.get("db", 0.0))


func queue(sound: String, gap := 0.12, pitch := 1.0, db := 0.0) -> void:
	if not _streams.has(sound):
		return
	var at := maxf(_clock, _free_at)
	if _queue.size() > 24:
		return   # never build up a long backlog
	_queue.append({"at": at, "name": sound, "pitch": pitch * _rng.randf_range(0.93, 1.07), "db": db})
	_free_at = at + gap


func _play_now(sound: String, pitch: float, db: float) -> void:
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	var vs: Array = _streams[sound]
	p.stream = vs[_rng.randi() % vs.size()]
	p.pitch_scale = pitch
	p.volume_db = db - 4.0
	p.play()


## What a log line sounds like: [{"name", "gap", "pitch", "db"}]. Static so tests can check it.
static func events_for(text: String) -> Array:
	var out: Array = []
	if text.begins_with("[") or text.begins_with("—"):
		return out
	if text.contains("☠"):
		out.append({"name": "death", "gap": 0.45, "db": 1.0})
		out.append({"name": "down", "gap": 0.5})
		return out
	var mv := RegEx.create_from_string("makes an? (\\w+) move: ([0-9.]+)\" used")
	var m := mv.search(text)
	if m:
		var fast := m.get_string(1) in ["run", "charge"]
		var steps := clampi(int(round(float(m.get_string(2)) / 1.4)), 1, 8)
		for i in steps:
			out.append({"name": "step", "gap": 0.17 if fast else 0.26, "db": -2.0})
		return out
	if text.contains(" fires ") or text.contains(" unleashes "):
		out.append({"name": "shot", "gap": 0.22})
		var misses := mini(text.count("✗") + (1 if text.contains("— miss") else 0), 3)
		for i in misses:
			out.append({"name": "whiz", "gap": 0.14})
		return out
	if text.contains(" rolls: "):
		# Melee attack dice: one whoosh for each blow that misses (hits sound when they land).
		for i in mini(text.count("✗"), 3):
			out.append({"name": "swing", "gap": 0.16})
		return out
	if text.contains("parry fails"):
		out.append({"name": "swing", "gap": 0.16})
		return out
	if text.contains(" parries "):
		out.append({"name": "parry", "gap": 0.3})
		return out
	if text.contains(" hits ") or text.contains("is hit"):
		var crit := text.contains("CRIT")
		if text.contains("SAVED") and not text.contains("Bludgeon"):
			out.append({"name": "clank", "gap": 0.28})
		else:
			out.append({"name": "hit", "gap": 0.25, "pitch": 0.85 if crit else 1.0, "db": 2.0 if crit else 0.0})
		return out
	return out


# =============================================================================================
# Synthesis

static func build_streams() -> void:
	if not _streams.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1347
	for sound in ["step", "swing", "whiz", "hit", "clank", "parry", "shot", "down", "death"]:
		var vs: Array = []
		for v in VARIANTS:
			vs.append(_wav(_make(sound, rng)))
		_streams[sound] = vs


static func has_sound(sound: String) -> bool:
	return _streams.has(sound)


static func _make(sound: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound:
		"step":
			# Boot on cobbles: a dull thump and a short gritty scrape.
			var s := _buf(0.12)
			var lp := 0.0
			for i in s.size():
				var t := float(i) / RATE
				lp += 0.18 * (rng.randf_range(-1, 1) - lp)
				s[i] = lp * 1.6 * exp(-t / 0.02) + 0.6 * sin(TAU * 75.0 * t) * exp(-t / 0.03)
			return _norm(s, 0.7)
		"swing":
			# A blade cutting air: noise whose brightness rises and falls.
			var s2 := _buf(0.28)
			var lp2 := 0.0
			for i in s2.size():
				var u := float(i) / s2.size()
				var a := 0.03 + 0.3 * sin(PI * u)
				lp2 += a * (rng.randf_range(-1, 1) - lp2)
				s2[i] = lp2 * pow(sin(PI * u), 2.0)
			return _norm(s2, 0.6)
		"whiz":
			# An arrow or bolt flying past: short, bright, falling.
			var s3 := _buf(0.16)
			var lp3 := 0.0
			var hp := 0.0
			for i in s3.size():
				var u3 := float(i) / s3.size()
				lp3 += (0.6 - 0.45 * u3) * (rng.randf_range(-1, 1) - lp3)
				hp = lp3 - hp * 0.6
				s3[i] = hp * sin(PI * u3)
			return _norm(s3, 0.45)
		"hit":
			# Weapon into a body: a low falling thump with a slap on top.
			var s4 := _buf(0.22)
			var ph := 0.0
			var lp4 := 0.0
			for i in s4.size():
				var t4 := float(i) / RATE
				ph += TAU * (45.0 + 90.0 * exp(-t4 / 0.04)) / RATE
				lp4 += 0.35 * (rng.randf_range(-1, 1) - lp4)
				s4[i] = sin(ph) * exp(-t4 / 0.07) + lp4 * 1.4 * exp(-t4 / 0.012)
			return _norm(s4, 0.9)
		"clank":
			# Blow turned by armour: inharmonic metal ring.
			return _norm(_ring([520.0, 1235.0, 1870.0, 2650.0], [1.0, 0.6, 0.4, 0.25], 0.22, 0.35, rng, 0.02), 0.7)
		"parry":
			# Blade on blade: brighter, longer ring.
			return _norm(_ring([1480.0, 2390.0, 3710.0, 5020.0], [1.0, 0.7, 0.45, 0.3], 0.4, 0.55, rng, 0.012), 0.6)
		"shot":
			# Bowstring or crossbow release: a plucked string (Karplus-Strong) and a thwip.
			var s5 := _buf(0.3)
			var period := int(RATE / rng.randf_range(120.0, 160.0))
			var line := PackedFloat32Array()
			line.resize(period)
			for k in period:
				line[k] = rng.randf_range(-1, 1)
			for i in s5.size():
				var j := i % period
				var nxt := line[(j + 1) % period]
				var val := line[j]
				line[j] = 0.497 * (val + nxt)
				var t5 := float(i) / RATE
				s5[i] = val * exp(-t5 / 0.12) + rng.randf_range(-1, 1) * 0.5 * exp(-t5 / 0.01)
			return _norm(s5, 0.6)
		"down":
			# A fighter falling: a heavy thump, then the body hitting the ground.
			var s6 := _buf(0.6)
			var ph6 := 0.0
			var lp6 := 0.0
			for i in s6.size():
				var t6 := float(i) / RATE
				ph6 += TAU * (38.0 + 60.0 * exp(-t6 / 0.06)) / RATE
				lp6 += 0.08 * (rng.randf_range(-1, 1) - lp6)
				var second := 0.0
				if t6 > 0.16:
					second = sin(TAU * 55.0 * (t6 - 0.16)) * 0.6 * exp(-(t6 - 0.16) / 0.07)
				s6[i] = sin(ph6) * exp(-t6 / 0.12) + lp6 * 2.0 * exp(-t6 / 0.15) + second
			return _norm(s6, 0.95)
		"death":
			# A dying cry: a voiced "aah" (sawtooth through vowel formants) whose pitch sags and breaks, with breath.
			return _norm(_cry(rng), 0.85)
	return _buf(0.05)


static func _cry(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _buf(0.85)
	var f0 := rng.randf_range(150.0, 230.0)          # voice pitch varies per variant (and per play via pitch_scale)
	var formants := [[rng.randf_range(650.0, 780.0), 1.0], [rng.randf_range(1050.0, 1250.0), 0.55], [rng.randf_range(2400.0, 2700.0), 0.25]]
	var filters: Array = []
	for fm in formants:
		filters.append(_bandpass(fm[0], 6.0))
	var ph := 0.0
	var jitter := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := t / 0.85
		# Pitch: a short rise, then a long sag with a ragged wobble as the voice gives out.
		var pitch := f0 * (1.0 + 0.12 * sin(PI * minf(u * 4.0, 1.0))) * (1.0 - 0.45 * u)
		jitter += 0.02 * (rng.randf_range(-1, 1) - jitter)
		pitch *= 1.0 + 0.03 * sin(TAU * 6.0 * t) + jitter * (0.5 + u)
		ph = fmod(ph + pitch / RATE, 1.0)
		var src := (2.0 * ph - 1.0) * 0.8 + rng.randf_range(-1, 1) * (0.15 + 0.35 * u)   # breathier as it fades
		var v := 0.0
		for k in filters.size():
			v += float(formants[k][1]) * _bp_step(filters[k], src)
		var env := minf(1.0, t / 0.04) * pow(1.0 - u, 1.6)
		s[i] = v * env
	return s


## Biquad band-pass filter state for a centre frequency and Q: [b0, b2, a1, a2, x1, x2, y1, y2].
static func _bandpass(freq: float, q: float) -> Array:
	var w := TAU * freq / RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	return [alpha / a0, -alpha / a0, -2.0 * cos(w) / a0, (1.0 - alpha) / a0, 0.0, 0.0, 0.0, 0.0]


static func _bp_step(st: Array, x: float) -> float:
	var y: float = st[0] * x + st[1] * st[5] - st[2] * st[6] - st[3] * st[7]
	st[5] = st[4]
	st[4] = x
	st[7] = st[6]
	st[6] = y
	return y


static func _ring(freqs: Array, amps: Array, decay: float, length: float, rng: RandomNumberGenerator, click: float) -> PackedFloat32Array:
	var s := _buf(length)
	var detune := rng.randf_range(0.97, 1.03)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += float(amps[k]) * sin(TAU * float(freqs[k]) * detune * t) * exp(-t / (decay / (1.0 + k * 0.5)))
		v += rng.randf_range(-1, 1) * exp(-t / click)
		s[i] = v
	return s


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


static func _norm(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	var n := s.size()
	for i in n:
		var fade := minf(1.0, float(n - i) / 64.0)   # avoid a click at the end
		s[i] = s[i] / m * peak * fade
	return s


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
