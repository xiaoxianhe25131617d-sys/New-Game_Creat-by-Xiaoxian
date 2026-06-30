extends Node
## AudioManager - Handles BGM, SFX and environment sounds
## Uses AudioStreamGenerators for procedural music since we can't bundle audio files

var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var current_region: String = "plaza"
var target_volume: float = 1.0
var current_view: String = "normal"

# Procedural audio generation using Godot's AudioStreamGenerator
var generator_playback: AudioStreamGeneratorPlayback
var generator_sample_rate: float = 44100.0
var generator_phase: float = 0.0
var generator_buffer: PackedVector2Array

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bgm()
	_setup_sfx_pool()

func _setup_bgm() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM"
	bgm_player.bus = "Master"
	add_child(bgm_player)
	
	# Create a procedural audio generator
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = generator_sample_rate
	generator.buffer_length = 0.5
	bgm_player.stream = generator
	bgm_player.play()
	
	generator_playback = bgm_player.get_stream_playback()
	generator_buffer = PackedVector2Array()
	generator_buffer.resize(int(generator_sample_rate * 0.1))

func _setup_sfx_pool() -> void:
	for i in range(4):
		var sfx := AudioStreamPlayer.new()
		sfx.name = "SFX_%d" % i
		sfx.bus = "Master"
		add_child(sfx)
		sfx_players.append(sfx)

func _process(_delta: float) -> void:
	if generator_playback == null:
		return
	_fill_generator_buffer()

func _fill_generator_buffer() -> void:
	var to_fill := generator_playback.get_frames_available()
	while to_fill > 0:
		generator_playback.push_frame(_generate_sample())
		to_fill -= 1

func _generate_sample() -> Vector2:
	generator_phase += 1.0 / generator_sample_rate
	
	var sample: float = 0.0
	var view_mod: float = 1.0
	
	# Adjust music based on current view
	match current_view:
		"blind":
			view_mod = 0.3  # quieter, more ambient
		"autism":
			view_mod = 0.7  # 安静专注
		"adhd":
			view_mod = 1.3  # more energetic
		"depression":
			view_mod = 0.6  # slower, softer
	
	# Region-based melody patterns
	match current_region:
		"plaza":
			sample = _plaza_melody()
		"forest":
			sample = _forest_melody()
		"lighthouse":
			sample = _lighthouse_melody()
		"station":
			sample = _station_melody()
		"park":
			sample = _park_melody()
		"dam":
			sample = _dam_melody()
		"observatory":
			sample = _observatory_melody()
		"underground":
			sample = _underground_melody()
		_:
			sample = _plaza_melody()
	
	sample *= view_mod * 0.15  # master volume
	return Vector2(sample, sample)

# ─── REGION MELODIES ────────────────────────────────
# Each generates a gentle ambient melody using sine waves

func _plaza_melody() -> float:
	var t := generator_phase
	# Warm piano-like tones
	var s: float = sin(t * 261.63 * TAU) * 0.5  # C4
	s += sin(t * 329.63 * TAU) * 0.3  # E4
	s += sin(t * 392.0 * TAU) * 0.25  # G4
	s += sin(t * 130.81 * TAU) * 0.2  # C3 (bass)
	# Gentle pad
	s += sin(t * 261.63 * 0.5 * TAU) * 0.15
	s += sin(t * 196.0 * 0.25 * TAU) * 0.1
	return s

func _forest_melody() -> float:
	var t := generator_phase
	# Woodwind-like, peaceful
	var s: float = sin(t * 293.66 * TAU) * 0.4  # D4
	s += sin(t * 369.99 * TAU) * 0.3  # F#4
	s += sin(t * 440.0 * TAU) * 0.2  # A4
	s += sin(t * 146.83 * TAU) * 0.2  # D3
	# Bird-like high notes
	s += sin(t * 880.0 * TAU + sin(t * 0.3) * 2.0) * 0.08
	s += sin(t * 1108.73 * TAU) * 0.05
	return s

func _lighthouse_melody() -> float:
	var t := generator_phase
	# Echo-like, resonant
	var s: float = sin(t * 220.0 * TAU) * 0.4  # A3
	s += sin(t * 277.18 * TAU) * 0.3  # C#4
	s += sin(t * 329.63 * TAU) * 0.25  # E4
	# Echo/reverb effect
	s += sin(t * 220.0 * TAU + 0.5) * 0.2 * abs(sin(t * 0.7))
	s += sin(t * 440.0 * TAU) * 0.15 * abs(sin(t * 1.3))
	return s

func _station_melody() -> float:
	var t := generator_phase
	# Rhythmic, mechanical feel
	var rhythm: bool = abs(sin(t * 2.0)) > 0.5
	var s: float = sin(t * 196.0 * TAU) * 0.35  # G3
	s += sin(t * 246.94 * TAU) * 0.3  # B3
	s += sin(t * 293.66 * TAU) * 0.25  # D4
	if rhythm:
		s += sin(t * 392.0 * TAU) * 0.2  # G4 accent
	s += sin(t * 98.0 * TAU) * 0.2  # G2 bass
	return s

func _park_melody() -> float:
	var t := generator_phase
	# Upbeat, playful
	var s: float = sin(t * 349.23 * TAU) * 0.4  # F4
	s += sin(t * 440.0 * TAU) * 0.3  # A4
	s += sin(t * 523.25 * TAU) * 0.25  # C5
	s += sin(t * 174.61 * TAU) * 0.2  # F3
	# Playful arpeggios
	var arp := sin(t * 4.0) * 0.5 + 0.5
	s += sin(t * (349.23 + arp * 200.0) * TAU) * 0.12
	return s

func _dam_melody() -> float:
	var t := generator_phase
	# Flowing water feel
	var s: float = sin(t * 233.08 * TAU) * 0.35  # Bb3
	s += sin(t * 293.66 * TAU) * 0.3  # D4
	s += sin(t * 349.23 * TAU) * 0.25  # F4
	# Water flow effect
	s += sin(t * 233.08 * TAU + sin(t * 0.5) * 3.0) * 0.15
	s += sin(t * 116.54 * TAU) * 0.2  # Bb2
	return s

func _observatory_melody() -> float:
	var t := generator_phase
	# Mysterious, cosmic
	var s: float = sin(t * 207.65 * TAU) * 0.35  # Ab3
	s += sin(t * 261.63 * TAU) * 0.3  # C4
	s += sin(t * 311.13 * TAU) * 0.25  # Eb4
	# Star twinkle
	s += sin(t * 1244.51 * TAU + sin(t * 0.2) * 2.0) * 0.06
	s += sin(t * 1661.22 * TAU) * 0.04
	s += sin(t * 103.83 * TAU) * 0.2  # Ab2
	return s

func _underground_melody() -> float:
	var t := generator_phase
	# Deep, resonant, mysterious
	var s: float = sin(t * 164.81 * TAU) * 0.35  # E3
	s += sin(t * 196.0 * TAU) * 0.3  # G3
	s += sin(t * 246.94 * TAU) * 0.2  # B3
	# Drip/cave echo
	s += sin(t * 987.77 * TAU + sin(t * 1.7) * 1.5) * 0.06 * abs(sin(t * 0.4))
	s += sin(t * 82.41 * TAU) * 0.25  # E2 deep bass
	return s

# ─── SFX METHODS ───────────────────────────────────
func play_sfx(sfx_type: String) -> void:
	for sfx in sfx_players:
		if not sfx.playing:
			_play_sfx_on(sfx, sfx_type)
			return

func _play_sfx_on(player: AudioStreamPlayer, sfx_type: String) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.3
	player.stream = generator
	player.play()
	
	# Simple procedural SFX
	var playback := player.get_stream_playback()
	var frames := int(44100.0 * 0.2)
	var t: float = 0.0
	
	match sfx_type:
		"jump":
			for i in range(frames):
				t = float(i) / 44100.0
				var s: float = sin(t * 400.0 * TAU * (1.0 + t * 3.0)) * (1.0 - t / 0.2)
				playback.push_frame(Vector2(s, s) * 0.3)
		"collect":
			for i in range(frames):
				t = float(i) / 44100.0
				var s: float = sin(t * 880.0 * TAU) * (1.0 - t / 0.2) + sin(t * 1320.0 * TAU) * (1.0 - t / 0.15) * 0.5
				playback.push_frame(Vector2(s, s) * 0.25)
		"echo":
			for i in range(int(44100.0 * 0.4)):
				t = float(i) / 44100.0
				var s: float = sin(t * 220.0 * TAU * (1.0 + t * 0.5)) * exp(-t * 6.0)
				playback.push_frame(Vector2(s, s) * 0.3)
		"dash":
			for i in range(int(44100.0 * 0.15)):
				t = float(i) / 44100.0
				var s: float = (randf() * 2.0 - 1.0) * (1.0 - t / 0.15) * 0.4
				playback.push_frame(Vector2(s, s) * 0.25)
		"save":
			for i in range(int(44100.0 * 0.5)):
				t = float(i) / 44100.0
				var s: float = sin(t * 523.25 * TAU) * (1.0 - t / 0.5) * 0.3
				s += sin(t * 659.25 * TAU) * (1.0 - t / 0.4) * 0.2
				playback.push_frame(Vector2(s, s) * 0.2)
		_:
			for i in range(frames):
				playback.push_frame(Vector2.ZERO)

func set_region(region: String) -> void:
	current_region = region

func set_view(view: String) -> void:
	current_view = view

# ─── TONE GENERATOR (for puzzle audio feedback) ──
# Plays a short sine wave tone at the given frequency and duration
func play_tone(freq: float, duration: float = 0.3) -> void:
	for sfx in sfx_players:
		if not sfx.playing:
			_play_tone_on(sfx, freq, duration)
			return

func _play_tone_on(player: AudioStreamPlayer, freq: float, duration: float) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = maxf(duration + 0.05, 0.1)
	player.stream = generator
	player.play()
	
	var playback := player.get_stream_playback()
	var frames := int(44100.0 * duration)
	var t: float = 0.0
	
	for i in range(frames):
		t = float(i) / 44100.0
		var envelope: float = sin(t * PI / duration)  # smooth fade in/out
		var s: float = sin(t * freq * TAU) * envelope * 0.25
		playback.push_frame(Vector2(s, s))
