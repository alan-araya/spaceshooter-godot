extends Node
## Áudio: efeitos sintetizados na inicialização (estilo chiptune/sfxr), sem arquivos externos.
## Para trocar um som, coloque res://assets/audio/<nome>.wav ou .ogg com o mesmo nome.

const RATE := 22050
const POOL := 20

var muted := false
var _streams := {}
var _players: Array = []
var _last := {}
var _next := 0

## nome -> receita do sintetizador
const RECIPES := {
	shot = { wave = "noise", dur = 0.07, f0 = 1800.0, f1 = 400.0, vol = 0.32, lp = 0.5 },
	shot_far = { wave = "noise", dur = 0.06, f0 = 900.0, f1 = 300.0, vol = 0.12, lp = 0.3 },
	flame = { wave = "noise", dur = 0.09, f0 = 600.0, f1 = 500.0, vol = 0.12, lp = 0.2 },
	plasma = { wave = "square", dur = 0.18, f0 = 1400.0, f1 = 300.0, vol = 0.22 },
	cannon = { wave = "noise", dur = 0.16, f0 = 500.0, f1 = 120.0, vol = 0.35, lp = 0.25 },
	throw = { wave = "square", dur = 0.08, f0 = 500.0, f1 = 900.0, vol = 0.12 },
	boom = { wave = "noise", dur = 0.45, f0 = 300.0, f1 = 60.0, vol = 0.55, lp = 0.12 },
	bigboom = { wave = "noise", dur = 0.9, f0 = 220.0, f1 = 40.0, vol = 0.7, lp = 0.08 },
	squish = { wave = "noise", dur = 0.1, f0 = 700.0, f1 = 200.0, vol = 0.2, lp = 0.15 },
	splat = { wave = "noise", dur = 0.12, f0 = 500.0, f1 = 150.0, vol = 0.25, lp = 0.12 },
	burst = { wave = "noise", dur = 0.4, f0 = 400.0, f1 = 80.0, vol = 0.45, lp = 0.1 },
	bite = { wave = "saw", dur = 0.07, f0 = 260.0, f1 = 140.0, vol = 0.18 },
	spit = { wave = "noise", dur = 0.12, f0 = 2400.0, f1 = 900.0, vol = 0.14, lp = 0.6 },
	birth = { wave = "saw", dur = 0.2, f0 = 120.0, f1 = 200.0, vol = 0.16 },
	hurt = { wave = "square", dur = 0.15, f0 = 420.0, f1 = 160.0, vol = 0.3 },
	death = { wave = "square", dur = 0.5, f0 = 500.0, f1 = 60.0, vol = 0.35 },
	scream = { wave = "saw", dur = 0.22, f0 = 700.0, f1 = 300.0, vol = 0.14 },
	pickup = { wave = "arp", dur = 0.3, f0 = 660.0, f1 = 1320.0, vol = 0.3 },
	order = { wave = "square", dur = 0.08, f0 = 880.0, f1 = 880.0, vol = 0.16 },
	respawn = { wave = "arp", dur = 0.45, f0 = 330.0, f1 = 990.0, vol = 0.3 },
	trample = { wave = "noise", dur = 0.08, f0 = 1200.0, f1 = 600.0, vol = 0.14, lp = 0.4 },
	alarm = { wave = "square", dur = 0.6, f0 = 600.0, f1 = 900.0, vol = 0.22, wobble = 8.0 },
	switch = { wave = "arp", dur = 0.35, f0 = 440.0, f1 = 880.0, vol = 0.28 },
	wallbreak = { wave = "noise", dur = 0.5, f0 = 400.0, f1 = 80.0, vol = 0.45, lp = 0.15 },
	scratch = { wave = "noise", dur = 0.05, f0 = 3000.0, f1 = 2000.0, vol = 0.08, lp = 0.7 },
	burrow = { wave = "noise", dur = 0.5, f0 = 200.0, f1 = 80.0, vol = 0.35, lp = 0.08 },
	brake = { wave = "noise", dur = 0.25, f0 = 1600.0, f1 = 800.0, vol = 0.18, lp = 0.5 },
	engine = { wave = "saw", dur = 0.8, f0 = 70.0, f1 = 110.0, vol = 0.25, wobble = 14.0 },
	jet = { wave = "noise", dur = 1.2, f0 = 900.0, f1 = 300.0, vol = 0.3, lp = 0.35 },
	zap = { wave = "square", dur = 0.12, f0 = 1800.0, f1 = 600.0, vol = 0.16 },
	victory = { wave = "arp", dur = 1.0, f0 = 392.0, f1 = 1568.0, vol = 0.35 },
	defeat = { wave = "square", dur = 1.0, f0 = 330.0, f1 = 80.0, vol = 0.35 },
	ui_move = { wave = "square", dur = 0.04, f0 = 1000.0, f1 = 1000.0, vol = 0.1 },
	ui_ok = { wave = "arp", dur = 0.15, f0 = 660.0, f1 = 990.0, vol = 0.2 },
}

const COOLDOWN := { shot = 0.05, shot_far = 0.07, flame = 0.08, squish = 0.03, bite = 0.05, scratch = 0.1, spit = 0.05 }


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 99
	for key in RECIPES:
		var stream: AudioStream = null
		for ext in ["wav", "ogg"]:
			var path := "res://assets/audio/%s.%s" % [key, ext]
			if ResourceLoader.exists(path):
				stream = load(path)
				break
		if stream == null:
			stream = _synth(RECIPES[key], rnd)
		_streams[key] = stream


func play(key: String, _x: float = 0.0) -> void:
	if muted or not _streams.has(key):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var cd: float = COOLDOWN.get(key, 0.03)
	if now - float(_last.get(key, -1.0)) < cd:
		return
	_last[key] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[key]
	p.pitch_scale = randf_range(0.93, 1.07)
	p.play()


func _synth(r: Dictionary, rnd: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(r.dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var lp := 0.0
	var hold := 0.0
	var hold_t := 0.0
	var wave: String = r.wave
	var lpk: float = r.get("lp", 1.0)
	var wob: float = r.get("wobble", 0.0)
	for i in n:
		var t := float(i) / n
		var f: float = lerpf(r.f0, r.f1, t)
		if wob > 0.0:
			f *= 1.0 + 0.15 * sin(TAU * wob * t * r.dur)
		var s := 0.0
		match wave:
			"noise":
				# ruído "sample & hold" na frequência f, filtrado
				hold_t += f / RATE
				if hold_t >= 1.0:
					hold_t = fmod(hold_t, 1.0)
					hold = rnd.randf_range(-1.0, 1.0)
				lp += (hold - lp) * lpk
				s = lp
			"square":
				phase = fmod(phase + f / RATE, 1.0)
				s = 0.6 if phase < 0.5 else -0.6
			"saw":
				phase = fmod(phase + f / RATE, 1.0)
				s = (phase * 2.0 - 1.0) * 0.7
			"arp":
				var step := floori(t * 4.0)
				var ff: float = r.f0 * pow(float(r.f1) / r.f0, step / 3.0)
				phase = fmod(phase + ff / RATE, 1.0)
				s = 0.5 if phase < 0.5 else -0.5
		var env := minf(1.0, t * 40.0) * pow(1.0 - t, 1.6)
		var v := clampi(int(s * env * r.vol * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
