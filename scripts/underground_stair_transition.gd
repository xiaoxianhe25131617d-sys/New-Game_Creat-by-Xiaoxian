extends CanvasLayer

signal completed

const DEFAULT_DURATION: float = 9.64
const AUDIO_FINISH_GRACE: float = 0.25
const STEP_COUNT: int = 13

var transition_duration: float = DEFAULT_DURATION
var progress: float = 0.0

var _elapsed: float = 0.0
var _is_playing: bool = false
var _did_complete: bool = false
var _visuals: StairVisual
var _audio: AudioStreamPlayer

class StairVisual extends Control:
	var animation_progress: float = 0.0

	func set_animation_progress(value: float) -> void:
		animation_progress = clampf(value, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var viewport_size := size
		if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
			return

		var reveal := smoothstep(0.0, 0.08, animation_progress)
		var footstep_strength := smoothstep(0.04, 0.18, animation_progress) * (1.0 - smoothstep(0.82, 1.0, animation_progress))
		var bob := sin(animation_progress * TAU * 7.0) * 7.0 * footstep_strength
		var sway := sin(animation_progress * TAU * 3.5) * 5.0 * footstep_strength
		var width := viewport_size.x
		var height := viewport_size.y
		var horizon := height * 0.28 + bob

		draw_rect(Rect2(Vector2.ZERO, viewport_size), _fade(Color("#07080b"), reveal))
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(width * 0.43 + sway, horizon), Vector2(width * 0.36, height), Vector2(0, height)]),
			PackedColorArray([_fade(Color("#17191d"), reveal)])
		)
		draw_polygon(
			PackedVector2Array([Vector2(width, 0), Vector2(width * 0.57 + sway, horizon), Vector2(width * 0.64, height), Vector2(width, height)]),
			PackedColorArray([_fade(Color("#14161a"), reveal)])
		)
		draw_polygon(
			PackedVector2Array([Vector2(0, height), Vector2(width * 0.43 + sway, horizon), Vector2(width * 0.57 + sway, horizon), Vector2(width, height)]),
			PackedColorArray([_fade(Color("#0d0f12"), reveal)])
		)

		_draw_far_door(width, height, horizon, sway, reveal)
		_draw_wall_lights(width, height, horizon, sway, reveal)
		_draw_steps(width, height, horizon, sway, reveal)
		_draw_vignette(width, height, reveal)

		var final_black := smoothstep(0.84, 1.0, animation_progress)
		if final_black > 0.0:
			draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, final_black))

	func _draw_far_door(width: float, height: float, horizon: float, sway: float, opacity: float) -> void:
		var door_width := width * 0.12
		var door_height := height * 0.18
		var door_rect := Rect2(Vector2(width * 0.5 - door_width * 0.5 + sway, horizon - door_height), Vector2(door_width, door_height))
		draw_rect(door_rect, _fade(Color("#030506"), opacity))
		draw_line(door_rect.position, door_rect.position + Vector2(0, door_height), _fade(Color("#3b3429"), opacity), 3.0)
		draw_line(door_rect.position + Vector2(door_width, 0), door_rect.end, _fade(Color("#3b3429"), opacity), 3.0)

	func _draw_wall_lights(width: float, height: float, horizon: float, sway: float, opacity: float) -> void:
		for i in range(4):
			var depth := fposmod(float(i) / 4.0 + animation_progress * 0.72, 1.0)
			var y := horizon + pow(depth, 1.55) * (height - horizon)
			var spread := lerpf(width * 0.075, width * 0.43, depth)
			var radius := lerpf(3.0, 15.0, depth)
			var glow := _fade(Color("#b87938"), opacity * (1.0 - depth * 0.45))
			var flame := _fade(Color("#ffd58a"), opacity)
			for side in [-1.0, 1.0]:
				var light_position := Vector2(width * 0.5 + sway + spread * side, y - radius * 2.0)
				draw_circle(light_position, radius * 2.6, Color(glow, glow.a * 0.16))
				draw_circle(light_position, radius, flame)

	func _draw_steps(width: float, height: float, horizon: float, sway: float, opacity: float) -> void:
		var phase := fposmod(animation_progress * 7.0, 1.0) / float(STEP_COUNT)
		var depths: Array[float] = []
		for i in range(STEP_COUNT):
			depths.append(fposmod(float(i) / float(STEP_COUNT) + phase, 1.0))
		depths.sort()

		for depth in depths:
			var next_depth := minf(depth + 1.0 / float(STEP_COUNT), 1.0)
			var y_far := horizon + pow(depth, 1.58) * (height - horizon + 36.0)
			var y_near := horizon + pow(next_depth, 1.58) * (height - horizon + 36.0)
			var half_far := lerpf(width * 0.055, width * 0.48, depth)
			var half_near := lerpf(width * 0.055, width * 0.48, next_depth)
			var center_x := width * 0.5 + sway * (1.0 - depth)
			var tread := PackedVector2Array([
				Vector2(center_x - half_far, y_far),
				Vector2(center_x + half_far, y_far),
				Vector2(center_x + half_near, y_near),
				Vector2(center_x - half_near, y_near),
			])
			var shade := lerpf(0.72, 1.12, depth)
			draw_polygon(tread, PackedColorArray([_fade(Color("#25262a") * shade, opacity)]))
			var edge_width := lerpf(1.0, 5.0, depth)
			draw_line(Vector2(center_x - half_near, y_near), Vector2(center_x + half_near, y_near), _fade(Color("#57534d"), opacity), edge_width)

	func _draw_vignette(width: float, height: float, opacity: float) -> void:
		var edge := minf(width, height) * 0.14
		draw_rect(Rect2(0, 0, width, edge), Color(0, 0, 0, opacity * 0.34))
		draw_rect(Rect2(0, height - edge, width, edge), Color(0, 0, 0, opacity * 0.5))
		draw_rect(Rect2(0, 0, edge, height), Color(0, 0, 0, opacity * 0.42))
		draw_rect(Rect2(width - edge, 0, edge, height), Color(0, 0, 0, opacity * 0.42))

	func _fade(color: Color, opacity: float) -> Color:
		return Color(color, color.a * clampf(opacity, 0.0, 1.0))

func _ready() -> void:
	layer = 2000
	process_mode = Node.PROCESS_MODE_ALWAYS

	_visuals = StairVisual.new()
	_visuals.name = "FirstPersonStairs"
	_visuals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visuals.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_visuals)

	_audio = AudioStreamPlayer.new()
	_audio.name = "UndergroundEntryAudio"
	_audio.volume_db = -2.0
	_audio.finished.connect(_on_audio_finished)
	add_child(_audio)
	set_process(false)

func configure(stream: AudioStream) -> void:
	_audio.stream = stream
	if stream != null and stream.get_length() > 0.0:
		transition_duration = stream.get_length()
	else:
		transition_duration = DEFAULT_DURATION

func play() -> void:
	_elapsed = 0.0
	progress = 0.0
	_did_complete = false
	_is_playing = true
	_visuals.set_animation_progress(progress)
	if _audio.stream != null:
		_audio.play()
	set_process(true)

func _process(delta: float) -> void:
	_advance(delta)

func _advance(delta: float) -> void:
	if not _is_playing or _did_complete:
		return
	_elapsed += maxf(delta, 0.0)
	progress = clampf(_elapsed / transition_duration, 0.0, 1.0)
	_visuals.set_animation_progress(progress)
	if _audio.stream == null and _elapsed >= transition_duration:
		_finish()
	elif _elapsed >= transition_duration + AUDIO_FINISH_GRACE:
		_finish()

func _on_audio_finished() -> void:
	_finish()

func _finish() -> void:
	if _did_complete:
		return
	_did_complete = true
	_is_playing = false
	progress = 1.0
	_visuals.set_animation_progress(progress)
	_audio.stop()
	set_process(false)
	completed.emit()
