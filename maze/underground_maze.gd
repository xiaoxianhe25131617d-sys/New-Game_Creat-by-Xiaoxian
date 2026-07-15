@tool
extends Node2D
class_name UndergroundMaze

const MAP_SIZE := Vector2(3096, 1758)
const CLIMB_SPEED := 180.0
const BLIND_VISION_SHADER := preload("res://shaders/blind_vision.gdshader")
const UNDERGROUND_DARKNESS_SHADER := preload("res://shaders/underground_darkness.gdshader")
const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const PUZZLE_NOTE_POPUP_SCRIPT := preload("res://scripts/puzzle_note_popup.gd")
const MAIN_RETURN_POSITION := Vector2(9000.0, 3150.0)
const MAIN_EXIT_RETURN_POSITION := Vector2(10400.0, 3150.0)
const CHEST_TEXTURE := preload("res://assets/stone_chest.png")
const COMPASS_TEXTURE := preload("res://assets/ui/generated/maze_compass.png")
const ENDING_KEEPSAKES_TEXTURE := preload("res://assets/ui/generated/ending_keepsakes.png")
const HIDDEN_DOOR_TEXTURE := preload("res://assets/ui/generated/hidden_stone_door.png")
const MAZE_CORRECT_AUDIO := preload("res://assets/audio/黑色迷宫正确声音.MP3")
const MAZE_WRONG_AUDIO := preload("res://assets/audio/黑色迷宫错误.MP3")
const MAZE_BGM_AUDIO := preload("res://assets/audio/地下迷宫音乐.MP3")
const COMPASS_ROUTE: Array[Vector2] = [
	Vector2(1240, 795),
	Vector2(930, 795),
	Vector2(915, 660),
	Vector2(1004, 683),
	Vector2(1005, 500),
	Vector2(720, 500),
	Vector2(600, 650),
	Vector2(455, 780),
	Vector2(452, 827),
	Vector2(300, 840),
	Vector2(216, 850),
	Vector2(138, 920),
]
const COMPASS_REACH_DISTANCE := 88.0
const EXIT_GUIDANCE_ROUTE: Array[Vector2] = [
	Vector2(1504, 795), Vector2(1180, 795), Vector2(915, 795),
	Vector2(915, 660), Vector2(1005, 660), Vector2(1005, 500),
	Vector2(730, 500), Vector2(730, 320), Vector2(1050, 150),
	Vector2(2240, 150), Vector2(2280, 250), Vector2(2058, 250),
	Vector2(2058, 440), Vector2(2350, 440), Vector2(2350, 620),
	Vector2(2560, 620), Vector2(2560, 890), Vector2(2710, 890),
	Vector2(2939, 877),
]
const ROUTE_CORRECT_DISTANCE := 52.0
const ROUTE_WRONG_DISTANCE := 56.0
const ROUTE_ADVANCE_DISTANCE := 64.0
const EXIT_TRIGGER_RADIUS := 140.0
const SPAWN_RETURN_INTERACT_RADIUS := 120.0
const KEY_INTERACT_RADIUS := 112.0
const NAVIGATION_SOURCE_DISTANCE := 180.0
const DEBUG_SPAWN_OFFSETS := {
	"PlayerSpawn": Vector2.ZERO,
	"HiddenDoor": Vector2(118, -18),
	"Chest": Vector2(112, -18),
	"PortalExit": Vector2(-180, -18),
}

static func advance_compass_route(player_position: Vector2, route: Array[Vector2], current_index: int, reach_distance: float) -> int:
	var next_index := clampi(current_index, 0, route.size())
	while next_index < route.size() and player_position.distance_to(route[next_index]) <= reach_distance:
		next_index += 1
	return next_index

static func nearest_route_index(player_position: Vector2, route: Array[Vector2]) -> int:
	if route.is_empty():
		return 0
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(route.size()):
		var distance := player_position.distance_squared_to(route[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return nearest_index

static func nearest_route_segment_index(player_position: Vector2, route: Array[Vector2]) -> int:
	if route.size() < 2:
		return 0
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(route.size() - 1):
		var segment := route[index + 1] - route[index]
		if segment.length_squared() <= 0.001:
			continue
		var amount := clampf((player_position - route[index]).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var distance := player_position.distance_squared_to(route[index] + segment * amount)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return nearest_index

static func advance_ordered_route(player_position: Vector2, route: Array[Vector2], current_segment_index: int, reach_distance: float) -> int:
	if route.size() < 2:
		return 0
	var segment_index := clampi(current_segment_index, 0, route.size() - 2)
	while segment_index < route.size() - 2 and player_position.distance_to(route[segment_index + 1]) <= reach_distance:
		segment_index += 1
	return segment_index

static func sample_active_route_segment(player_position: Vector2, route: Array[Vector2], current_segment_index: int) -> Dictionary:
	if route.size() < 2:
		return {"distance": INF, "progress": 0.0, "point": Vector2.ZERO, "segment_index": 0, "amount": 0.0}
	var first_segment := clampi(current_segment_index, 0, route.size() - 2)
	var last_segment := mini(first_segment + 1, route.size() - 2)
	var total_length := 0.0
	for index in range(route.size() - 1):
		total_length += route[index].distance_to(route[index + 1])
	var walked_length := 0.0
	var best_distance := INF
	var best_progress_length := 0.0
	var best_point := route[first_segment]
	var best_segment_index := first_segment
	var best_amount := 0.0
	for index in range(route.size() - 1):
		var start := route[index]
		var finish := route[index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		if index >= first_segment and index <= last_segment:
			var amount := clampf((player_position - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
			var projected := start + segment * amount
			var distance := player_position.distance_to(projected)
			if distance < best_distance:
				best_distance = distance
				best_progress_length = walked_length + segment_length * amount
				best_point = projected
				best_segment_index = index
				best_amount = amount
		walked_length += segment_length
	return {
		"distance": best_distance,
		"progress": clampf(best_progress_length / maxf(total_length, 0.001), 0.0, 1.0),
		"point": best_point,
		"segment_index": best_segment_index,
		"amount": best_amount,
	}

static func cardinal_direction_text(offset: Vector2) -> String:
	if offset.length() <= 16.0:
		return "继续前进"
	if absf(offset.x) >= absf(offset.y):
		return "向右" if offset.x > 0.0 else "向左"
	return "向下" if offset.y > 0.0 else "向上"

static func sample_route(player_position: Vector2, route: Array[Vector2]) -> Dictionary:
	if route.size() < 2:
		return {"distance": INF, "progress": 0.0, "point": Vector2.ZERO}
	var total_length := 0.0
	for index in range(route.size() - 1):
		total_length += route[index].distance_to(route[index + 1])
	var best_distance := INF
	var best_progress_length := 0.0
	var best_point := route[0]
	var best_segment_index := 0
	var walked_length := 0.0
	for index in range(route.size() - 1):
		var start := route[index]
		var finish := route[index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		var amount := clampf((player_position - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var projected := start + segment * amount
		var distance := player_position.distance_to(projected)
		if distance < best_distance:
			best_distance = distance
			best_progress_length = walked_length + segment_length * amount
			best_point = projected
			best_segment_index = index
		walked_length += segment_length
	return {
		"distance": best_distance,
		"progress": clampf(best_progress_length / maxf(total_length, 0.001), 0.0, 1.0),
		"point": best_point,
		"segment_index": best_segment_index,
	}

static func route_volume_db(progress: float) -> float:
	return lerpf(2.0, 14.0, pow(clampf(progress, 0.0, 1.0), 0.55))

static func route_interval(progress: float) -> float:
	return lerpf(0.20, 0.075, pow(clampf(progress, 0.0, 1.0), 0.75))

@export var map_size := MAP_SIZE
@export var show_reference_in_editor := true:
	set(value):
		show_reference_in_editor = value
		_update_reference_visibility()

@onready var reference_image: Sprite2D = $ReferenceImage
@onready var walls: TileMapLayer = $Walls
@onready var one_way_stairs: TileMapLayer = $OneWayStairs
@onready var ladders: Node2D = $Ladders
@onready var player_spawn: Marker2D = $Markers/PlayerSpawn
@onready var spawn_return_prompt: Label = $SpawnReturnPrompt

var runtime_player: MindscapePlayer
var active_ladder: Area2D
var ladder_detach_cooldown := 0.0
var blind_vision_canvas: CanvasLayer
var blind_vision: ColorRect
var blind_vision_material: ShaderMaterial
var _leaving_maze: bool = false
var _maze_key_granted: bool = false
var current_view: String = "blind"
var maze_state: Dictionary = {}
var hidden_door_body: StaticBody2D
var hidden_door_overlay: Polygon2D
var hidden_door_label: Label
var hidden_chest_sprite: Sprite2D
var hidden_chest_label: Label
var maze_key_sprite: Sprite2D
var maze_key_label: Label
var underground_inventory_canvas: CanvasLayer
var compass_button: Button
var compass_hud_canvas: CanvasLayer
var compass_panel: Panel
var compass_panel_style: StyleBoxFlat
var compass_needle: Polygon2D
var compass_heading_label: Label
var compass_distance_label: Label
var compass_error_flash: ColorRect
var compass_error_tween: Tween
var compass_audio: AudioStreamPlayer
var route_audio: AudioStreamPlayer
var maze_bgm_player: AudioStreamPlayer
var compass_route_index: int = 0
var compass_ping_timer: float = 0.0
var compass_route_correct: bool = true
var compass_route_initialized: bool = false
var compass_texture: Texture2D
var ending_keepsakes_texture: Texture2D
var hidden_door_texture: Texture2D
var _ending_playing: bool = false
var _route_feedback_correct: bool = true
var _route_feedback_initialized: bool = false
var _route_feedback_timer: float = 0.0
var _route_feedback_beep_timer: float = 0.0
var _route_feedback_last_progress: float = 0.0
var _navigation_cue_remaining: float = 0.0
var _compass_cue_remaining: float = 0.0
var _route_cue_remaining: float = 0.0
var exit_route_segment_index: int = 0
var note_popup: CanvasLayer

func _ready() -> void:
	add_to_group("world")
	_update_reference_visibility()
	if Engine.is_editor_hint():
		return
	_load_runtime_assets()
	AudioManager.stop_bgm()
	maze_state = _get_saved_state()
	_spawn_runtime_player()
	_make_maze_bgm()
	_make_blind_vision()
	_make_hidden_door()
	_make_hidden_chest()
	_make_maze_key()
	_make_underground_inventory()
	_make_compass_hud()
	_make_compass_audio()
	_make_debug_toolbar()
	_update_maze_key_prompt()
	exit_route_segment_index = nearest_route_segment_index(runtime_player.global_position, EXIT_GUIDANCE_ROUTE)
	compass_route_index = clampi(int(maze_state.get("maze_compass_route_index", 0)), 0, COMPASS_ROUTE.size() - 2)
	process_priority = 1000
	if not get_tree().has_meta("mindscape_play_formal_ending") and not bool(maze_state.get("ending_pending", false)):
		call_deferred("_show_underground_note_once")
	if get_tree().has_meta("mindscape_play_formal_ending"):
		get_tree().remove_meta("mindscape_play_formal_ending")
		var ending_source := str(get_tree().get_meta("mindscape_ending_source", "time_capsule"))
		get_tree().remove_meta("mindscape_ending_source")
		GameData.begin_ending(maze_state, ending_source)
		ProfileManager.save_state(maze_state)
		call_deferred("_play_formal_ending")
	elif bool(maze_state.get("ending_pending", false)) and not bool(maze_state.get("ending_seen", false)):
		call_deferred("_play_formal_ending")

func _exit_tree() -> void:
	_stop_maze_bgm()
	if compass_audio != null:
		compass_audio.stop()
	if route_audio != null:
		route_audio.stop()

func _show_underground_note_once() -> void:
	if bool(maze_state.get("ending_pending", false)) or runtime_player == null:
		return
	var seen: Array = maze_state.get("seen_notes", []) as Array
	if seen.has("underground_maze"):
		return
	seen.append("underground_maze")
	maze_state["seen_notes"] = seen
	ProfileManager.save_state(maze_state)
	runtime_player.suspend_for_interaction()
	note_popup = PUZZLE_NOTE_POPUP_SCRIPT.new()
	note_popup.name = "UndergroundPuzzleNote"
	add_child(note_popup)
	note_popup.connect("closed", func():
		if runtime_player != null and is_instance_valid(runtime_player):
			runtime_player.resume_after_interaction()
	)
	note_popup.call("open_note", GameData.PUZZLE_NOTES["underground_maze"], str(maze_state.get("current_view", "blind")))

func _make_maze_bgm() -> void:
	maze_bgm_player = AudioStreamPlayer.new()
	maze_bgm_player.name = "MazeBGM"
	maze_bgm_player.stream = MAZE_BGM_AUDIO
	maze_bgm_player.volume_db = -27.0
	maze_bgm_player.bus = "Master"
	maze_bgm_player.finished.connect(_on_maze_bgm_finished)
	add_child(maze_bgm_player)
	maze_bgm_player.play()

func _on_maze_bgm_finished() -> void:
	if maze_bgm_player != null and not _leaving_maze and not _ending_playing:
		maze_bgm_player.play()

func _stop_maze_bgm() -> void:
	if maze_bgm_player != null:
		maze_bgm_player.stop()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or runtime_player == null or blind_vision_material == null:
		return
	_update_blind_vision()
	_update_navigation_cue(delta)
	_update_route_feedback(delta)
	_update_compass(delta)
	_update_maze_key_prompt()
	_update_spawn_return_prompt()
	if not _leaving_maze and runtime_player.global_position.distance_to($Markers/PortalExit.global_position) < EXIT_TRIGGER_RADIUS:
		_leave_to_main(MAIN_EXIT_RETURN_POSITION)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or runtime_player == null or _leaving_maze or _ending_playing:
		return
	if event.is_action_pressed("toggle_compass"):
		_toggle_compass()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if runtime_player.global_position.distance_to($Markers/Key.global_position) < KEY_INTERACT_RADIUS:
			_collect_maze_key()
			get_viewport().set_input_as_handled()
			return
		if runtime_player.global_position.distance_to($Markers/Chest.global_position) < 112.0:
			_try_open_hidden_chest()
			get_viewport().set_input_as_handled()
			return
		if runtime_player.global_position.distance_to(player_spawn.global_position) < SPAWN_RETURN_INTERACT_RADIUS:
			_leave_to_main(MAIN_RETURN_POSITION)
			get_viewport().set_input_as_handled()

func _update_spawn_return_prompt() -> void:
	if spawn_return_prompt == null or runtime_player == null:
		return
	spawn_return_prompt.visible = runtime_player.global_position.distance_to(player_spawn.global_position) < SPAWN_RETURN_INTERACT_RADIUS

func _make_hidden_door() -> void:
	var marker := $Markers/HiddenDoor
	var is_open := _hidden_door_is_open()
	var glow := Polygon2D.new()
	glow.name = "HiddenDoorGlow"
	glow.polygon = PackedVector2Array([
		Vector2(-62, 48), Vector2(-62, -4), Vector2(-48, -28), Vector2(-30, -44),
		Vector2(0, -53), Vector2(30, -44), Vector2(48, -28), Vector2(62, -4), Vector2(62, 48)
	])
	glow.position = marker.position
	glow.color = Color("#86edf2", 0.25 if is_open else 0.0)
	glow.z_index = 1
	add_child(glow)

	var door := Polygon2D.new()
	door.name = "HiddenDoorOverlay"
	door.polygon = PackedVector2Array([
		Vector2(-72, 50), Vector2(-72, -4), Vector2(-58, -30), Vector2(-40, -48),
		Vector2(0, -60), Vector2(40, -48), Vector2(58, -30), Vector2(72, -4), Vector2(72, 50)
	])
	door.position = marker.position
	door.color = Color("#111820", 0.96) if not is_open else Color("#173641", 0.18)
	door.z_index = 2
	add_child(door)
	hidden_door_overlay = door

	var frame := Line2D.new()
	frame.name = "HiddenDoorFrame"
	frame.width = 8.0
	frame.closed = true
	frame.default_color = Color("#596a75")
	frame.z_index = 3
	frame.position = marker.position
	frame.points = PackedVector2Array([
		Vector2(-76, 50), Vector2(-76, -6), Vector2(-60, -34), Vector2(-40, -52),
		Vector2(0, -64), Vector2(40, -52), Vector2(60, -34), Vector2(76, -6), Vector2(76, 50)
	])
	add_child(frame)
	if hidden_door_texture != null:
		var door_atlas := AtlasTexture.new()
		door_atlas.atlas = hidden_door_texture
		door_atlas.region = Rect2(791 if is_open else 0, 0, 790, 995)
		var door_sprite := Sprite2D.new()
		door_sprite.name = "HiddenDoorArtwork"
		door_sprite.texture = door_atlas
		door_sprite.position = marker.position + Vector2(0, -32)
		door_sprite.scale = Vector2(0.16, 0.16)
		door_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		door_sprite.z_index = 4
		add_child(door_sprite)

	var label := Label.new()
	label.position = marker.position + Vector2(-120, 66)
	label.size = Vector2(240, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	if is_open:
		frame.default_color = Color("#6fe0e7")
		label.text = "地下隐藏门已打开"
		label.add_theme_color_override("font_color", Color("#8deaf0"))
	else:
		label.text = "隐藏门暂未回应"
		label.add_theme_color_override("font_color", Color("#80919b"))
	add_child(label)
	hidden_door_label = label

	if not is_open:
		hidden_door_body = StaticBody2D.new()
		hidden_door_body.name = "HiddenDoorCollision"
		hidden_door_body.position = marker.position + Vector2(0, -5)
		hidden_door_body.collision_layer = 1
		hidden_door_body.collision_mask = 0
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(38, 118)
		collision.shape = shape
		hidden_door_body.add_child(collision)
		add_child(hidden_door_body)

func _load_runtime_assets() -> void:
	compass_texture = COMPASS_TEXTURE
	ending_keepsakes_texture = ENDING_KEEPSAKES_TEXTURE
	hidden_door_texture = HIDDEN_DOOR_TEXTURE

func _get_saved_state() -> Dictionary:
	var profile: Dictionary = ProfileManager.get_current_profile()
	var saved_state: Dictionary = (profile.get("state", GameData.default_state()) as Dictionary).duplicate(true)
	if GameData.migrate_state(saved_state):
		ProfileManager.save_state(saved_state)
	return saved_state

func _hidden_door_is_open() -> bool:
	return bool(maze_state.get("hidden_door_opened", false)) or _laser_focus_completed()

func _make_hidden_chest() -> void:
	var marker: Marker2D = $Markers/Chest
	hidden_chest_sprite = Sprite2D.new()
	hidden_chest_sprite.name = "HiddenEndingChest"
	hidden_chest_sprite.texture = CHEST_TEXTURE
	hidden_chest_sprite.position = marker.position + Vector2(0, -40)
	hidden_chest_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hidden_chest_sprite.z_index = 4
	if bool(maze_state.get("hidden_chest_opened", false)):
		hidden_chest_sprite.modulate = Color(0.65, 0.7, 0.72, 0.58)
	add_child(hidden_chest_sprite)

	hidden_chest_label = Label.new()
	hidden_chest_label.position = marker.position + Vector2(-100, 40)
	hidden_chest_label.size = Vector2(200, 44)
	hidden_chest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hidden_chest_label.add_theme_font_size_override("font_size", 16)
	hidden_chest_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hidden_chest_label.text = "旧物已经回到相册" if bool(maze_state.get("hidden_chest_opened", false)) else "按 E 打开隐藏宝箱"
	hidden_chest_label.visible = false
	hidden_chest_label.z_index = 5
	add_child(hidden_chest_label)

func _make_maze_key() -> void:
	var marker: Marker2D = $Markers/Key
	maze_key_sprite = Sprite2D.new()
	maze_key_sprite.name = "MazeKey"
	maze_key_sprite.texture = _make_key_texture()
	maze_key_sprite.position = marker.position
	maze_key_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	maze_key_sprite.z_index = 4
	add_child(maze_key_sprite)

	maze_key_label = Label.new()
	maze_key_label.position = marker.position + Vector2(-88, 28)
	maze_key_label.size = Vector2(176, 34)
	maze_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	maze_key_label.add_theme_font_size_override("font_size", 14)
	maze_key_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	maze_key_label.text = "按 E 拾取迷宫钥匙"
	maze_key_label.z_index = 5
	add_child(maze_key_label)

func _make_underground_inventory() -> void:
	underground_inventory_canvas = CanvasLayer.new()
	underground_inventory_canvas.name = "UndergroundInventoryCanvas"
	underground_inventory_canvas.layer = 620
	add_child(underground_inventory_canvas)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 12.0
	panel.offset_top = -102.0
	panel.offset_right = -12.0
	panel.offset_bottom = -8.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#091018", 0.9)
	panel_style.border_color = Color("#476575")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", panel_style)
	underground_inventory_canvas.add_child(panel)

	var collected_count := (maze_state.get("collectibles", []) as Array).size()
	var title := _make_inventory_label("地下物品栏\n拼图 %d / 27" % collected_count, Vector2(14, 18), Color("#ffe8a0"), 16)
	title.size = Vector2(112, 58)
	panel.add_child(title)
	var keys: Array = maze_state.get("collected_keys", []) as Array
	panel.add_child(_make_inventory_label("钥匙", Vector2(144, 8), Color("#ffd36b"), 14))
	var key_names: PackedStringArray = []
	for key_id in ["key_1", "key_2", "key_4", "maze_key"]:
		var key_data: Dictionary = GameData.KEYS.get(key_id, {}) as Dictionary
		key_names.append(("✓" if keys.has(key_id) else "·") + str(key_data.get("name", key_id)).trim_suffix("钥匙"))
	var key_list := _make_inventory_label("    ".join(key_names), Vector2(144, 35), Color("#c7d2dc"), 12)
	key_list.size = Vector2(430, 38)
	panel.add_child(key_list)

	var completed: Array = maze_state.get("completed_levels", []) as Array
	var debug_loadout := bool(maze_state.get("debug_laser_loadout", false))
	var has_laser_1 := debug_loadout or completed.has("find_difference") or bool(maze_state.get("laser_focus_1_installed", false))
	var has_laser_2 := debug_loadout or completed.has("nine_grid") or bool(maze_state.get("laser_focus_2_installed", false))
	panel.add_child(_make_inventory_label("激光装置", Vector2(594, 8), Color("#8bbcff"), 14))
	panel.add_child(_make_inventory_label("%s 装置 1    %s 装置 2" % [("✓" if has_laser_1 else "·"), ("✓" if has_laser_2 else "·")], Vector2(594, 35), Color("#c7d2dc"), 12))

	panel.add_child(_make_inventory_label("探索工具", Vector2(850, 8), Color("#8deaf0"), 14))
	compass_button = Button.new()
	compass_button.position = Vector2(850, 28)
	compass_button.size = Vector2(360, 54)
	compass_button.icon = compass_texture
	compass_button.expand_icon = true
	compass_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	compass_button.pressed.connect(_toggle_compass)
	panel.add_child(compass_button)
	_refresh_compass_ui()

func _make_inventory_label(text_value: String, position_value: Vector2, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = Vector2(190, 28)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_compass_hud() -> void:
	compass_hud_canvas = CanvasLayer.new()
	compass_hud_canvas.name = "MazeCompassHUD"
	compass_hud_canvas.layer = 630
	add_child(compass_hud_canvas)
	compass_error_flash = ColorRect.new()
	compass_error_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass_error_flash.color = Color(0.82, 0.04, 0.04, 0.0)
	compass_error_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_hud_canvas.add_child(compass_error_flash)
	compass_panel = Panel.new()
	compass_panel.position = Vector2(530, 18)
	compass_panel.size = Vector2(220, 92)
	compass_panel_style = StyleBoxFlat.new()
	compass_panel_style.bg_color = Color("#0b1820", 0.9)
	compass_panel_style.border_color = Color("#8deaf0")
	compass_panel_style.set_border_width_all(2)
	compass_panel_style.set_corner_radius_all(6)
	compass_panel.add_theme_stylebox_override("panel", compass_panel_style)
	compass_hud_canvas.add_child(compass_panel)

	var icon := TextureRect.new()
	icon.texture = compass_texture
	icon.position = Vector2(12, 10)
	icon.size = Vector2(68, 68)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	compass_panel.add_child(icon)

	compass_needle = Polygon2D.new()
	compass_needle.name = "CompassNeedle"
	compass_needle.position = Vector2(46, 44)
	compass_needle.polygon = PackedVector2Array([Vector2(-5, 9), Vector2(0, -22), Vector2(5, 9), Vector2(0, 4)])
	compass_needle.color = Color("#fff1a6")
	compass_panel.add_child(compass_needle)

	compass_heading_label = _make_inventory_label("隐藏宝箱方向", Vector2(88, 14), Color("#ffe8a0"), 14)
	compass_heading_label.size = Vector2(122, 26)
	compass_panel.add_child(compass_heading_label)
	compass_distance_label = _make_inventory_label("", Vector2(88, 45), Color("#8deaf0"), 12)
	compass_distance_label.size = Vector2(122, 34)
	compass_panel.add_child(compass_distance_label)
	_refresh_compass_ui()

func _make_compass_audio() -> void:
	# Navigation cues must remain clearly audible even when the player is
	# near a wall or outside the camera's 2D listener falloff.
	compass_audio = AudioStreamPlayer.new()
	compass_audio.name = "MazeNavigationAudio"
	compass_audio.volume_db = 0.0
	compass_audio.bus = "Master"
	add_child(compass_audio)
	route_audio = AudioStreamPlayer.new()
	route_audio.name = "MazeExitRouteAudio"
	route_audio.volume_db = 0.0
	route_audio.bus = "Master"
	route_audio.finished.connect(_on_route_audio_finished)
	add_child(route_audio)

func _on_route_audio_finished() -> void:
	if route_audio != null and _route_feedback_correct and not bool(maze_state.get("maze_compass_enabled", false)) and not _leaving_maze and not _ending_playing:
		route_audio.play()

func _toggle_compass() -> void:
	var enabled := GameData.toggle_maze_compass(maze_state)
	if enabled:
		compass_route_index = nearest_route_segment_index(runtime_player.global_position, COMPASS_ROUTE)
		maze_state["maze_compass_route_index"] = compass_route_index
		compass_route_initialized = false
	ProfileManager.save_state(maze_state)
	compass_ping_timer = 0.0
	if not enabled and compass_audio != null:
		compass_audio.stop()
	if enabled and route_audio != null:
		route_audio.stop()
	_refresh_compass_ui()
	if not bool(maze_state.get("maze_compass_owned", false)):
		_show_maze_toast("指南针还没有进入物品栏。完成激光聚焦后再来看看。")
	else:
		_show_maze_toast("指南针已启用" if enabled else "指南针已收起")

func _refresh_compass_ui() -> void:
	var owned := bool(maze_state.get("maze_compass_owned", false))
	var enabled := bool(maze_state.get("maze_compass_enabled", false))
	var chest_opened := bool(maze_state.get("hidden_chest_opened", false))
	if compass_button != null:
		compass_button.disabled = not owned or chest_opened
		if chest_opened:
			compass_button.text = "  指南针已完成指引"
		elif not owned:
			compass_button.text = "  未获得指南针"
		else:
			compass_button.text = "  指南针：%s\n  点击或按 C 切换" % ("开启" if enabled else "关闭")
	if compass_panel != null:
		compass_panel.visible = owned and enabled and not chest_opened

func _update_compass(delta: float) -> void:
	if hidden_chest_label != null:
		hidden_chest_label.visible = _hidden_door_is_open() and runtime_player.global_position.distance_to($Markers/Chest.global_position) < 150.0
		if bool(maze_state.get("hidden_chest_opened", false)):
			hidden_chest_label.text = "旧物已经回到相册"
		elif _get_maze_keys().has("maze_key"):
			hidden_chest_label.text = "按 E 使用迷宫钥匙打开宝箱"
		else:
			hidden_chest_label.text = "宝箱已锁，需要迷宫钥匙"
	if not bool(maze_state.get("maze_compass_owned", false)) or not bool(maze_state.get("maze_compass_enabled", false)) or bool(maze_state.get("hidden_chest_opened", false)):
		return
	compass_route_index = advance_ordered_route(runtime_player.global_position, COMPASS_ROUTE, compass_route_index, COMPASS_REACH_DISTANCE)
	var sample := sample_active_route_segment(runtime_player.global_position, COMPASS_ROUTE, compass_route_index)
	var route_distance := float(sample.get("distance", INF))
	var should_be_correct := compass_route_correct
	if route_distance <= ROUTE_CORRECT_DISTANCE:
		should_be_correct = true
	elif route_distance >= ROUTE_WRONG_DISTANCE:
		should_be_correct = false
	if not compass_route_initialized or should_be_correct != compass_route_correct:
		compass_route_correct = should_be_correct
		compass_route_initialized = true
		compass_ping_timer = 0.0
		if not compass_route_correct:
			_flash_compass_error()
	var sample_segment := int(sample.get("segment_index", compass_route_index))
	var target: Vector2 = COMPASS_ROUTE[compass_route_index]
	if compass_route_correct:
		target = COMPASS_ROUTE[mini(sample_segment + 1, COMPASS_ROUTE.size() - 1)]
	var offset: Vector2 = target - runtime_player.global_position
	var distance: float = offset.length()
	if compass_needle != null:
		compass_needle.rotation = offset.angle() + PI * 0.5
	if compass_distance_label != null:
		var direction := cardinal_direction_text(offset)
		compass_distance_label.text = ("%s\n返回路线" % direction) if not compass_route_correct else ("宝箱就在附近" if distance < 120.0 else "%s · %d 步" % [direction, maxi(1, int(round(distance / 32.0)))])
	_update_compass_warning_style(not compass_route_correct)
	if compass_audio == null:
		return
	_set_navigation_source(target)
	compass_ping_timer -= delta
	if compass_ping_timer <= 0.0:
		if compass_route_correct:
			var distance_ratio := clampf(distance / 900.0, 0.0, 1.0)
			_play_navigation_cue(compass_audio, MAZE_CORRECT_AUDIO, lerpf(-1.0, 8.0, pow(clampf(1.0 - distance_ratio, 0.0, 1.0), 0.8)), 1.02, 0.16)
			compass_ping_timer = lerpf(0.14, 0.42, distance_ratio)
		else:
			_play_navigation_cue(compass_audio, MAZE_WRONG_AUDIO, 8.0, 0.78, 0.18)
			AudioManager.play_tone(145.0, 0.10)
			_flash_compass_error()
			compass_ping_timer = 0.14

func _update_compass_warning_style(is_wrong: bool) -> void:
	if compass_panel_style != null:
		compass_panel_style.border_color = Color("#ff4d4d") if is_wrong else Color("#8deaf0")
	if compass_heading_label != null:
		compass_heading_label.text = "偏离路线" if is_wrong else "隐藏宝箱方向"
		compass_heading_label.add_theme_color_override("font_color", Color("#ff7777") if is_wrong else Color("#ffe8a0"))
	if compass_distance_label != null:
		compass_distance_label.add_theme_color_override("font_color", Color("#ff9b9b") if is_wrong else Color("#8deaf0"))

func _flash_compass_error() -> void:
	if compass_error_flash == null:
		return
	if compass_error_tween != null and compass_error_tween.is_valid():
		compass_error_tween.kill()
	compass_error_flash.color.a = 0.24
	compass_error_tween = create_tween()
	compass_error_tween.tween_property(compass_error_flash, "color:a", 0.0, 0.13)

func _show_maze_toast(message: String, duration: float = 2.4) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 900
	add_child(canvas)
	var toast := Label.new()
	toast.text = message
	toast.position = Vector2(340, 552)
	toast.size = Vector2(600, 52)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_font_size_override("font_size", 18)
	toast.add_theme_color_override("font_color", Color("#ffe8a0"))
	canvas.add_child(toast)
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(toast, "modulate:a", 0.0, 0.35)
	tween.tween_callback(canvas.queue_free)

func _update_route_feedback(delta: float) -> void:
	if current_view != "blind" or bool(maze_state.get("maze_compass_enabled", false)) or _ending_playing:
		_route_feedback_initialized = false
		if route_audio != null:
			route_audio.stop()
		return
	exit_route_segment_index = advance_ordered_route(runtime_player.global_position, EXIT_GUIDANCE_ROUTE, exit_route_segment_index, ROUTE_ADVANCE_DISTANCE)
	var sample := sample_active_route_segment(runtime_player.global_position, EXIT_GUIDANCE_ROUTE, exit_route_segment_index)
	var distance := float(sample.get("distance", INF))
	var progress := float(sample.get("progress", 0.0))
	var route_index := int(sample.get("segment_index", exit_route_segment_index))
	var route_segment := EXIT_GUIDANCE_ROUTE[mini(route_index + 1, EXIT_GUIDANCE_ROUTE.size() - 1)] - EXIT_GUIDANCE_ROUTE[route_index]
	var route_dir := route_segment.normalized() if route_segment.length_squared() > 0.001 else Vector2.RIGHT
	var velocity := Vector2.ZERO
	if runtime_player != null and "velocity" in runtime_player:
		velocity = runtime_player.get("velocity")
	var speed := velocity.length()
	var moving_forward := speed < 8.0 or velocity.normalized().dot(route_dir) > 0.2
	var should_be_correct := _route_feedback_correct
	if distance <= ROUTE_CORRECT_DISTANCE and moving_forward and progress >= _route_feedback_last_progress - 0.015:
		should_be_correct = true
	elif distance >= ROUTE_WRONG_DISTANCE or (speed > 8.0 and velocity.normalized().dot(route_dir) < -0.3):
		should_be_correct = false
	if not _route_feedback_initialized or should_be_correct != _route_feedback_correct:
		_route_feedback_correct = should_be_correct
		_route_feedback_initialized = true
		_route_feedback_timer = 0.0
		_route_feedback_beep_timer = 0.0
		if route_audio != null:
			route_audio.stop()
	if _route_feedback_correct:
		_route_feedback_last_progress = maxf(_route_feedback_last_progress, progress)
	elif progress < _route_feedback_last_progress - 0.08:
		_route_feedback_last_progress = progress
	_route_feedback_timer -= delta
	if _route_feedback_correct:
		var pitch := lerpf(0.98, 1.24, pow(progress, 0.55))
		# Correct-route guidance is continuous and loud; a short buzzer tone
		# rides on top so the player can hear it immediately.
		if route_audio != null:
			route_audio.stream = MAZE_CORRECT_AUDIO
			route_audio.volume_db = clampf(route_volume_db(progress), 6.0, 18.0)
			route_audio.pitch_scale = clampf(pitch, 0.72, 1.35)
			if not route_audio.playing:
				route_audio.play()
		_route_feedback_beep_timer -= delta
		if _route_feedback_beep_timer <= 0.0:
			AudioManager.play_tone(920.0 + progress * 220.0, 0.05)
			_route_feedback_beep_timer = lerpf(0.08, 0.022, progress)
		return
	if _route_feedback_timer > 0.0:
		return
	else:
		_play_navigation_cue(route_audio, MAZE_WRONG_AUDIO, 12.0, 0.72, 0.16)
		AudioManager.play_tone(1760.0, 0.07)
		_route_feedback_timer = 0.14

func _set_navigation_source(target: Vector2) -> void:
	# Direction is represented by the active route segment and compass UI.
	# The audio itself is non-positional so walls cannot make the guidance
	# disappear.
	return

func _play_navigation_cue(channel: AudioStreamPlayer, stream: AudioStream, volume_db: float, pitch_scale: float, duration: float) -> void:
	if channel == null or stream == null:
		return
	channel.stop()
	channel.stream = stream
	channel.volume_db = clampf(volume_db, -3.0, 8.0)
	channel.pitch_scale = clampf(pitch_scale, 0.72, 1.35)
	channel.play()
	if channel == compass_audio:
		_compass_cue_remaining = duration
	else:
		_route_cue_remaining = duration

func _update_navigation_cue(delta: float) -> void:
	_compass_cue_remaining -= delta
	_route_cue_remaining -= delta
	if _compass_cue_remaining <= 0.0 and compass_audio != null:
		compass_audio.stop()
	if _route_cue_remaining <= 0.0 and route_audio != null and route_audio.stream != MAZE_CORRECT_AUDIO:
		route_audio.stop()

func _laser_focus_completed() -> bool:
	if bool(maze_state.get("hidden_door_opened", false)):
		return true
	var completed: Array = maze_state.get("completed_levels", []) as Array
	return completed.has("laser_focus")

func _try_open_hidden_chest() -> void:
	if not _hidden_door_is_open():
		_show_maze_toast("石门仍然封闭，远处的激光装置也许能唤醒它。")
		return
	if not _get_maze_keys().has("maze_key"):
		_show_maze_toast("宝箱锁住了。先找到迷宫里的钥匙，再回来打开它。")
		return
	var first_open := GameData.open_hidden_chest(maze_state)
	var ending_pending := bool(maze_state.get("ending_pending", false))
	if not first_open and not ending_pending:
		_show_maze_toast("宝箱已经打开，旧物安静地留在纪念相册里。")
		return
	ProfileManager.save_state(maze_state)
	_refresh_compass_ui()
	if hidden_chest_sprite != null:
		var chest_tween := create_tween()
		chest_tween.tween_property(hidden_chest_sprite, "scale", Vector2(1.08, 0.9), 0.18)
		chest_tween.tween_property(hidden_chest_sprite, "scale", Vector2.ONE, 0.24)
	AudioManager.play_sfx("chest_open")
	await _play_formal_ending()

func _update_maze_key_prompt() -> void:
	if maze_key_label == null:
		return
	var key_available := not _get_maze_keys().has("maze_key") and not bool(maze_state.get("hidden_chest_opened", false))
	maze_key_label.visible = key_available and runtime_player != null and runtime_player.global_position.distance_to($Markers/Key.global_position) < 150.0
	if maze_key_sprite != null:
		maze_key_sprite.visible = key_available

func _play_formal_ending() -> void:
	if _ending_playing:
		return
	_ending_playing = true
	_stop_maze_bgm()
	runtime_player.suspend_for_interaction()
	var camera := runtime_player.get_node_or_null("MazeCamera") as Camera2D
	if camera != null:
		var camera_tween := create_tween()
		camera_tween.tween_property(camera, "zoom", Vector2(1.25, 1.25), 0.8)
		await camera_tween.finished

	var ending_canvas := CanvasLayer.new()
	ending_canvas.name = "MindscapeEnding"
	ending_canvas.layer = 3000
	add_child(ending_canvas)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("#071018", 0.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	ending_canvas.add_child(backdrop)
	var fade_in := create_tween()
	fade_in.tween_property(backdrop, "color:a", 0.98, 0.9)
	await fade_in.finished

	var title := _make_ending_label("隐藏宝箱打开了", Vector2(0, 44), Vector2(1280, 48), 28, Color("#ffe8a0"))
	ending_canvas.add_child(title)
	var chest := TextureRect.new()
	chest.texture = CHEST_TEXTURE
	chest.position = Vector2(560, 500)
	chest.size = Vector2(160, 160)
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chest.modulate = Color(1, 1, 1, 0)
	ending_canvas.add_child(chest)
	var chest_in := create_tween()
	chest_in.tween_property(chest, "modulate:a", 1.0, 0.45)
	chest_in.parallel().tween_property(chest, "position:y", 430.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await chest_in.finished

	var item_targets: Array[Vector2] = [Vector2(270, 150), Vector2(520, 150), Vector2(770, 150), Vector2(270, 330), Vector2(520, 330), Vector2(770, 330)]
	var photo_target: Vector2 = item_targets[0] + Vector2(110, 80)
	for index in range(6):
		var atlas := AtlasTexture.new()
		atlas.atlas = ending_keepsakes_texture
		atlas.region = Rect2((index % 3) * 512, floori(float(index) / 3.0) * 512, 512, 512)
		var item := TextureRect.new()
		item.texture = atlas
		item.position = Vector2(555, 450)
		item.size = Vector2(170, 135)
		item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		item.modulate = Color(1, 1, 1, 0)
		ending_canvas.add_child(item)
		var item_tween := create_tween()
		item_tween.tween_property(item, "modulate:a", 1.0, 0.22)
		item_tween.parallel().tween_property(item, "position", item_targets[index], 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await item_tween.finished
		await get_tree().create_timer(0.32).timeout

	var compass := TextureRect.new()
	compass.texture = compass_texture
	compass.position = Vector2(590, 535)
	compass.size = Vector2(100, 100)
	compass.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ending_canvas.add_child(compass)
	var compass_angle: float = (photo_target - (compass.position + compass.size * 0.5)).angle() + PI * 0.5
	var compass_tween := create_tween()
	compass_tween.tween_property(compass, "rotation", TAU * 2.0 + compass_angle, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await compass_tween.finished
	title.text = "指南针不再寻找出口。它指向了那张旧合照。"
	await get_tree().create_timer(2.1).timeout

	var note_panel := Panel.new()
	note_panel.position = Vector2(220, 100)
	note_panel.size = Vector2(840, 510)
	var note_style := StyleBoxFlat.new()
	note_style.bg_color = Color("#241c14", 0.97)
	note_style.border_color = Color("#b89055")
	note_style.set_border_width_all(2)
	note_style.set_corner_radius_all(6)
	note_panel.add_theme_stylebox_override("panel", note_style)
	note_panel.modulate.a = 0.0
	ending_canvas.add_child(note_panel)
	var note_title := _make_ending_label("纸条上留下了四种笔迹", Vector2(40, 26), Vector2(760, 40), 25, Color("#ffe8a0"))
	note_panel.add_child(note_title)
	var message_one := _make_ending_label("手写体一：我希望人们能互相理解", Vector2(70, 98), Vector2(700, 38), 21, Color("#e8d6bd"))
	note_panel.add_child(message_one)
	var message_two := _make_ending_label("手写体二：我们要永远理解彼此", Vector2(70, 158), Vector2(700, 38), 21, Color("#d8e7d1"))
	note_panel.add_child(message_two)
	var braille := _make_ending_label("⠕⠄\t⠓⠊⠁⠶⠆\t⠚⠴⠂⠍⠴\t⠝⠼⠂\t⠓⠥⠆⠓⠭⠁\n⠇⠊⠄⠛⠑⠄", Vector2(70, 226), Vector2(700, 64), 20, Color("#8deaf0"))
	note_panel.add_child(braille)
	var braille_translation := _make_ending_label("盲文译文：我希望人们能互相理解", Vector2(70, 306), Vector2(700, 38), 20, Color("#8deaf0"))
	braille_translation.modulate.a = 0.0
	note_panel.add_child(braille_translation)
	var message_four := _make_ending_label("歪斜彩铅字：我们要永远理解彼此", Vector2(70, 374), Vector2(700, 38), 21, Color("#f1b6cf"))
	note_panel.add_child(message_four)
	var note_in := create_tween()
	note_in.tween_property(note_panel, "modulate:a", 1.0, 0.6)
	await note_in.finished
	await get_tree().create_timer(2.0).timeout
	var translation_in := create_tween()
	translation_in.tween_property(braille_translation, "modulate:a", 1.0, 0.7)
	await translation_in.finished
	await get_tree().create_timer(2.2).timeout
	var note_out := create_tween()
	note_out.tween_property(note_panel, "modulate:a", 0.0, 0.7)
	await note_out.finished
	note_panel.queue_free()

	var light_colors := [Color("#79d8ff"), Color("#ffd36b"), Color("#ff8fb0"), Color("#9bea9b")]
	var light_starts := [Vector2(80, 110), Vector2(1200, 110), Vector2(80, 650), Vector2(1200, 650)]
	for index in range(light_colors.size()):
		var light := _make_light_particle(light_colors[index])
		light.position = light_starts[index]
		ending_canvas.add_child(light)
		var light_tween := create_tween()
		light_tween.tween_property(light, "position", Vector2(640, 330), 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		light_tween.parallel().tween_property(light, "scale", Vector2(2.5, 2.5), 1.4)
	await get_tree().create_timer(1.6).timeout
	title.text = "每个人都拥有看见世界的一种方式。\n\n而理解，\n是愿意停下来看看对方眼中的风景。"
	title.position = Vector2(190, 190)
	title.size = Vector2(900, 280)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	await get_tree().create_timer(5.0).timeout

	GameData.complete_ending(maze_state)
	ProfileManager.save_state(maze_state)
	get_tree().set_meta("mindscape_open_profiles_after_ending", true)
	var final_fade := ColorRect.new()
	final_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	final_fade.color = Color(0, 0, 0, 0)
	final_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	ending_canvas.add_child(final_fade)
	var fade_out := create_tween()
	fade_out.tween_property(final_fade, "color:a", 1.0, 0.9)
	await fade_out.finished
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _make_ending_label(text_value: String, position_value: Vector2, size_value: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_light_particle(color: Color) -> Polygon2D:
	var light := Polygon2D.new()
	var points := PackedVector2Array()
	for index in range(20):
		var angle := TAU * float(index) / 20.0
		points.append(Vector2(cos(angle), sin(angle)) * 12.0)
	light.polygon = points
	light.color = color
	return light

func _leave_to_main(target_position: Vector2) -> void:
	if _leaving_maze:
		return
	_leaving_maze = true
	_stop_maze_bgm()
	var profile: Dictionary = ProfileManager.get_current_profile()
	var state: Dictionary = profile.get("state", {}) as Dictionary
	state["position"] = target_position
	state["return_to_game"] = true
	ProfileManager.save_state(state)
	var fade_canvas := CanvasLayer.new()
	fade_canvas.name = "MazeTransition"
	fade_canvas.layer = 2000
	add_child(fade_canvas)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_canvas.add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.38)
	await tween.finished
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _collect_maze_key() -> void:
	if _maze_key_granted:
		return
	if bool(maze_state.get("hidden_chest_opened", false)):
		return
	_maze_key_granted = true
	var state := maze_state
	var keys: Array = state.get("collected_keys", []) as Array
	if not keys.has("maze_key"):
		keys.append("maze_key")
		state["collected_keys"] = keys
		ProfileManager.save_state(state)
		_show_maze_toast("🔑 获得迷宫钥匙")
	_update_maze_key_prompt()

func _get_maze_keys() -> Array:
	var keys: Array = maze_state.get("collected_keys", []) as Array
	return keys

func _make_key_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(8, 24):
		for x in range(8, 20):
			image.set_pixel(x, y, Color("#f4cf5a"))
	for x in range(18, 25):
		for y in range(12, 20):
			image.set_pixel(x, y, Color("#f4cf5a"))
	for y in range(10, 22):
		image.set_pixel(12, y, Color("#8c6a22"))
	image.set_pixel(16, 16, Color("#fff3b0"))
	return ImageTexture.create_from_image(image)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or runtime_player == null:
		return
	ladder_detach_cooldown = maxf(0.0, ladder_detach_cooldown - delta)
	_update_ladder_climb(delta)

func _update_reference_visibility() -> void:
	if is_instance_valid(reference_image):
		reference_image.visible = Engine.is_editor_hint() and show_reference_in_editor

func _spawn_runtime_player() -> void:
	runtime_player = MindscapePlayer.create_with_outfit("underground")
	runtime_player.name = "RuntimePlayer"
	var debug_target := str(maze_state.get("debug_spawn_target", ""))
	var target_marker := $Markers.get_node_or_null(debug_target) as Marker2D
	if target_marker != null and bool(maze_state.get("is_debug_profile", false)):
		runtime_player.global_position = target_marker.global_position + (DEBUG_SPAWN_OFFSETS.get(debug_target, Vector2.ZERO) as Vector2)
		maze_state["debug_spawn_target"] = ""
		ProfileManager.save_state(maze_state)
	else:
		runtime_player.global_position = player_spawn.global_position
	add_child(runtime_player)
	var profile: Dictionary = ProfileManager.get_current_profile()
	var saved_state: Dictionary = profile.get("state", {}) as Dictionary
	current_view = str(saved_state.get("current_view", "normal"))
	runtime_player.set_view(current_view)

	var camera := Camera2D.new()
	camera.name = "MazeCamera"
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map_size.x)
	camera.limit_bottom = int(map_size.y)
	runtime_player.add_child(camera)

func _make_debug_toolbar() -> void:
	if not OS.is_debug_build() or not ProfileManager.is_current_profile_debug():
		return
	var canvas := CanvasLayer.new()
	canvas.name = "MazeDebugToolbar"
	canvas.layer = 1800
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(870, 12)
	panel.size = Vector2(398, 52)
	canvas.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var title := Label.new()
	title.text = "TEST"
	title.add_theme_color_override("font_color", Color("#ffe08a"))
	row.add_child(title)
	for marker_name in ["PlayerSpawn", "HiddenDoor", "Chest", "PortalExit"]:
		var button := Button.new()
		button.text = {"PlayerSpawn": "起点", "HiddenDoor": "暗门", "Chest": "宝箱", "PortalExit": "出口"}[marker_name]
		button.pressed.connect(_debug_teleport_marker.bind(marker_name))
		row.add_child(button)
	var back := Button.new()
	back.text = "主世界"
	back.pressed.connect(_debug_return_to_main)
	row.add_child(back)

func _debug_teleport_marker(marker_name: String) -> void:
	if not ProfileManager.is_current_profile_debug():
		return
	var marker := $Markers.get_node_or_null(marker_name) as Marker2D
	if marker != null:
		runtime_player.global_position = marker.global_position + (DEBUG_SPAWN_OFFSETS.get(marker_name, Vector2.ZERO) as Vector2)

func _debug_return_to_main() -> void:
	if not ProfileManager.is_current_profile_debug():
		return
	_stop_maze_bgm()
	maze_state["position"] = GameData.PLAYER_START
	maze_state["return_to_game"] = true
	ProfileManager.save_state(maze_state)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _make_blind_vision() -> void:
	blind_vision_canvas = CanvasLayer.new()
	blind_vision_canvas.name = "BlindVisionCanvas"
	blind_vision_canvas.layer = 500
	blind_vision_canvas.follow_viewport_enabled = false
	add_child(blind_vision_canvas)

	blind_vision = ColorRect.new()
	blind_vision.name = "BlindVision"
	blind_vision.set_anchors_preset(Control.PRESET_FULL_RECT)
	blind_vision.color = Color.WHITE
	blind_vision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_vision_material = ShaderMaterial.new()
	blind_vision_material.shader = BLIND_VISION_SHADER if current_view == "blind" else UNDERGROUND_DARKNESS_SHADER
	blind_vision_material.set_shader_parameter("player_screen_uv", Vector2(0.5, 0.5))
	blind_vision_material.set_shader_parameter("radius_px", MindscapeWorld.BLIND_VISION_WORLD_RADIUS)
	blind_vision_material.set_shader_parameter("feather_px", MindscapeWorld.BLIND_VISION_FEATHER)
	blind_vision.material = blind_vision_material
	blind_vision_canvas.add_child(blind_vision)
	_update_blind_vision()

func get_vision_radius_px() -> float:
	var camera := runtime_player.get_node_or_null("MazeCamera") as Camera2D if runtime_player != null else null
	var camera_zoom := absf(camera.zoom.x) if camera != null else 1.0
	return MindscapeWorld.BLIND_VISION_WORLD_RADIUS * MindscapeWorld._view_effect_scale_for_transform(
		get_viewport().get_stretch_transform(),
		camera_zoom
	)

func get_vision_feather_px() -> float:
	var camera := runtime_player.get_node_or_null("MazeCamera") as Camera2D if runtime_player != null else null
	var camera_zoom := absf(camera.zoom.x) if camera != null else 1.0
	return MindscapeWorld.BLIND_VISION_FEATHER * MindscapeWorld._view_effect_scale_for_transform(
		get_viewport().get_stretch_transform(),
		camera_zoom
	)

func _update_blind_vision() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var screen_position := runtime_player.get_global_transform_with_canvas().origin
	var player_screen_uv := Vector2(
		screen_position.x / viewport_size.x,
		screen_position.y / viewport_size.y
	)
	blind_vision_material.set_shader_parameter("player_screen_uv", player_screen_uv)
	blind_vision_material.set_shader_parameter("radius_px", get_vision_radius_px())
	blind_vision_material.set_shader_parameter("feather_px", get_vision_feather_px())

func get_ladder_at_point(point: Vector2) -> Area2D:
	for child in ladders.get_children():
		var ladder := child as Area2D
		if ladder != null and ladder.has_method("contains_world_point") and bool(ladder.call("contains_world_point", point)):
			return ladder
	return null

func is_drop_through_tile(tile_pos: Vector2i) -> bool:
	return is_drop_through_at(Vector2(tile_pos * 16) + Vector2(8, 8))

func is_drop_through_at(point: Vector2) -> bool:
	var map_position := one_way_stairs.local_to_map(one_way_stairs.to_local(point))
	for offset in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if one_way_stairs.get_cell_source_id(map_position + offset) >= 0:
			return true
	return false

func _update_ladder_climb(delta: float) -> void:
	var up_held := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_action_pressed("ui_up")
	var down_held := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down")
	var left_held := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right_held := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	var jump_pressed := Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_SPACE)

	if active_ladder == null:
		runtime_player.is_on_ladder = false
		if ladder_detach_cooldown > 0.0 or (not up_held and not down_held):
			return
		active_ladder = get_ladder_at_point(runtime_player.global_position)
		if active_ladder == null:
			return

	if left_held or right_held or jump_pressed or not bool(active_ladder.call("contains_world_point", runtime_player.global_position)):
		_detach_from_ladder(jump_pressed)
		return

	runtime_player.is_on_ladder = true
	runtime_player.global_position.x = lerpf(runtime_player.global_position.x, active_ladder.global_position.x, 0.4)
	var vertical_axis := float(int(down_held) - int(up_held))
	runtime_player.global_position.y += vertical_axis * CLIMB_SPEED * delta
	var top_y := float(active_ladder.call("top_world_y"))
	var bottom_y := float(active_ladder.call("bottom_world_y"))
	runtime_player.global_position.y = clampf(runtime_player.global_position.y, top_y, bottom_y)
	runtime_player.velocity.y = 0.0

func _detach_from_ladder(jump_off: bool) -> void:
	runtime_player.is_on_ladder = false
	if jump_off:
		runtime_player.velocity.y = MindscapePlayer.JUMP_VELOCITY
		runtime_player.velocity.x = 120.0 * runtime_player.facing_dir
	active_ladder = null
	ladder_detach_cooldown = 0.15
