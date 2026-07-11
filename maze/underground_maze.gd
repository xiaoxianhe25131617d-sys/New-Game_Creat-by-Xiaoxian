@tool
extends Node2D
class_name UndergroundMaze

const MAP_SIZE := Vector2(3096, 1758)
const CLIMB_SPEED := 180.0
const BLIND_VISION_SHADER := preload("res://shaders/blind_vision.gdshader")

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

var runtime_player: MindscapePlayer
var active_ladder: Area2D
var ladder_detach_cooldown := 0.0
var blind_vision_canvas: CanvasLayer
var blind_vision: ColorRect
var blind_vision_material: ShaderMaterial

func _ready() -> void:
	add_to_group("world")
	_update_reference_visibility()
	if Engine.is_editor_hint():
		return
	_spawn_runtime_player()
	_make_blind_vision()
	process_priority = 1000

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or runtime_player == null or blind_vision_material == null:
		return
	_update_blind_vision()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or runtime_player == null:
		return
	ladder_detach_cooldown = maxf(0.0, ladder_detach_cooldown - delta)
	_update_ladder_climb(delta)

func _update_reference_visibility() -> void:
	if is_instance_valid(reference_image):
		reference_image.visible = Engine.is_editor_hint() and show_reference_in_editor

func _spawn_runtime_player() -> void:
	runtime_player = MindscapePlayer.create()
	runtime_player.name = "RuntimePlayer"
	runtime_player.global_position = player_spawn.global_position
	add_child(runtime_player)
	runtime_player.set_view("blind")

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
	blind_vision_material.shader = BLIND_VISION_SHADER
	blind_vision_material.set_shader_parameter("player_screen_uv", Vector2(0.5, 0.5))
	blind_vision_material.set_shader_parameter("radius_px", MindscapeWorld.BLIND_VISION_WORLD_RADIUS)
	blind_vision_material.set_shader_parameter("feather_px", MindscapeWorld.BLIND_VISION_FEATHER)
	blind_vision.material = blind_vision_material
	blind_vision_canvas.add_child(blind_vision)
	_update_blind_vision()

func _update_blind_vision() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var screen_position := runtime_player.get_global_transform_with_canvas().origin
	var player_screen_uv := Vector2(
		screen_position.x / viewport_size.x,
		screen_position.y / viewport_size.y
	)
	var camera := runtime_player.get_node_or_null("MazeCamera") as Camera2D
	var zoom_scale := 1.0
	if camera != null:
		zoom_scale = maxf(absf(camera.zoom.x), 0.001)
	blind_vision_material.set_shader_parameter("player_screen_uv", player_screen_uv)
	blind_vision_material.set_shader_parameter("radius_px", MindscapeWorld.BLIND_VISION_WORLD_RADIUS * zoom_scale)
	blind_vision_material.set_shader_parameter("feather_px", MindscapeWorld.BLIND_VISION_FEATHER * zoom_scale)

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
