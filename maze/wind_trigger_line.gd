@tool
extends Path2D

const SILENT_VOLUME_DB := -60.0

@export_range(4.0, 96.0, 1.0) var trigger_width := 36.0:
	set(value):
		trigger_width = value
		_queue_geometry_rebuild()
@export_range(0.05, 2.0, 0.05) var fade_duration := 0.35
@export_range(-24.0, 12.0, 0.5) var playback_volume_db := 4.0

@onready var trigger_area: Area2D = $TriggerArea
@onready var editor_preview: Line2D = $EditorPreview
@onready var wind_audio: AudioStreamPlayer = $WindAudio

var _player_touching := false
var _touching_player: Node
var _audio_enabled_for_view := false
var _audio_tween: Tween
var _loop_end_fading := false
var _geometry_rebuild_queued := false

func _ready() -> void:
	_connect_curve_changed()
	_rebuild_geometry()
	editor_preview.visible = Engine.is_editor_hint()
	if Engine.is_editor_hint():
		set_process(false)
		return
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)
	wind_audio.finished.connect(_on_audio_finished)
	wind_audio.volume_db = SILENT_VOLUME_DB
	set_process(true)

func _exit_tree() -> void:
	_kill_audio_tween()
	if is_instance_valid(wind_audio):
		wind_audio.stop()

func _process(_delta: float) -> void:
	_sync_audio_with_player_view()
	if not _audio_enabled_for_view or not wind_audio.playing or _loop_end_fading:
		return
	var stream_length := wind_audio.stream.get_length() if wind_audio.stream != null else 0.0
	if stream_length <= 0.0:
		return
	var remaining := stream_length - wind_audio.get_playback_position()
	if remaining <= fade_duration:
		_loop_end_fading = true
		_fade_audio_to(SILENT_VOLUME_DB, maxf(remaining, 0.01))

func is_player_touching() -> bool:
	return _player_touching

func _on_body_entered(body: Node) -> void:
	if not _is_player(body) or _player_touching:
		return
	_player_touching = true
	_touching_player = body
	_sync_audio_with_player_view()

func _on_body_exited(body: Node) -> void:
	if not _is_player(body) or body != _touching_player:
		return
	_player_touching = false
	_touching_player = null
	_sync_audio_with_player_view()

func _is_player(body: Node) -> bool:
	return body is MindscapePlayer

func _sync_audio_with_player_view() -> void:
	var should_enable := (
		_player_touching
		and is_instance_valid(_touching_player)
		and str(_touching_player.get("current_view")) == "blind"
	)
	if should_enable == _audio_enabled_for_view:
		return
	_audio_enabled_for_view = should_enable
	if _audio_enabled_for_view:
		if wind_audio.playing:
			_loop_end_fading = false
			_fade_audio_to(playback_volume_db, fade_duration)
		else:
			_start_audio_loop()
		return
	_fade_out_and_stop()

func _start_audio_loop() -> void:
	if wind_audio.stream == null:
		return
	_kill_audio_tween()
	_loop_end_fading = false
	wind_audio.volume_db = SILENT_VOLUME_DB
	wind_audio.play()
	_fade_audio_to(playback_volume_db, fade_duration)

func _on_audio_finished() -> void:
	if _audio_enabled_for_view:
		_start_audio_loop()

func _fade_out_and_stop() -> void:
	_loop_end_fading = false
	_kill_audio_tween()
	if not wind_audio.playing:
		wind_audio.volume_db = SILENT_VOLUME_DB
		return
	_audio_tween = create_tween()
	_audio_tween.tween_property(wind_audio, "volume_db", SILENT_VOLUME_DB, fade_duration)
	_audio_tween.tween_callback(_stop_audio_if_not_allowed)

func _stop_audio_if_not_allowed() -> void:
	if not _audio_enabled_for_view:
		wind_audio.stop()

func _fade_audio_to(target_db: float, duration: float) -> void:
	_kill_audio_tween()
	_audio_tween = create_tween()
	_audio_tween.tween_property(wind_audio, "volume_db", target_db, duration)

func _kill_audio_tween() -> void:
	if _audio_tween != null and _audio_tween.is_valid():
		_audio_tween.kill()
	_audio_tween = null

func _connect_curve_changed() -> void:
	if curve != null and not curve.changed.is_connected(_queue_geometry_rebuild):
		curve.changed.connect(_queue_geometry_rebuild)

func _queue_geometry_rebuild() -> void:
	if not is_inside_tree() or _geometry_rebuild_queued:
		return
	_geometry_rebuild_queued = true
	call_deferred("_rebuild_geometry")

func _rebuild_geometry() -> void:
	_geometry_rebuild_queued = false
	if not is_instance_valid(trigger_area) or not is_instance_valid(editor_preview):
		return
	for child in trigger_area.get_children():
		if child is CollisionShape2D:
			child.free()
	var points := PackedVector2Array()
	if curve != null and curve.point_count >= 2:
		points = curve.tessellate()
	editor_preview.points = points
	for index in range(points.size() - 1):
		_add_collision_segment(points[index], points[index + 1], index)

func _add_collision_segment(start: Vector2, finish: Vector2, index: int) -> void:
	var segment := finish - start
	if segment.length_squared() <= 0.01:
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(segment.length() + trigger_width, trigger_width)
	var collision := CollisionShape2D.new()
	collision.name = "Segment%03d" % index
	collision.shape = rectangle
	collision.position = (start + finish) * 0.5
	collision.rotation = segment.angle()
	trigger_area.add_child(collision)
