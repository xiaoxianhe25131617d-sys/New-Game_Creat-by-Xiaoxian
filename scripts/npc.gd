extends Area2D
class_name MindscapeNPC

const NPC_ATLAS_PATH := "res://assets/characters/generated/npc_atlas.png"
const NPC_ATLAS_COLUMNS := 5
const NPC_ATLAS_ROWS := 4
const NPC_DISPLAY_SCALE := Vector2(0.28, 0.28)
const NPC_FOOT_Y := 0.0
const IDLE_DURATION_MIN := 4.5
const IDLE_DURATION_MAX := 10.0
const WALK_RADIUS := 70.0

var npc_id: String = ""
var display_name: String = ""
var portrait_color: Color = Color.WHITE
var sign_only: bool = false
var blind_npc: bool = false
var spawn_pos: Vector2 = Vector2.ZERO  # 原始生成位置
var sprite_index: int = 0

# ── 随机走动 ──
var walk_timer: float = 0.0
var walk_interval: float = 3.0
var walk_target: Vector2 = Vector2.ZERO
var walk_speed: float = 25.0
var is_walking: bool = false
var label_node: Label
var character_sprite: Sprite2D

func setup(data: Dictionary) -> void:
	npc_id = str(data.get("id", ""))
	display_name = str(data.get("name", ""))
	portrait_color = Color(str(data.get("portrait", "#ffffff")))
	sign_only = bool(data.get("sign_only", false))
	blind_npc = bool(data.get("blind_npc", false))
	sprite_index = int(data.get("sprite_index", 0))
	position = data.get("pos", Vector2.ZERO) as Vector2
	spawn_pos = position
	name = "NPC_%s" % npc_id
	add_to_group("interactable")
	set_meta("kind", "npc")
	set_meta("id", npc_id)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 48
	shape.shape = circle
	shape.position = Vector2(0, -28)
	add_child(shape)

	character_sprite = _create_atlas_sprite(sprite_index)
	if character_sprite != null:
		add_child(character_sprite)
	else:
		add_child(_create_pixel_figure())

	label_node = Label.new()
	label_node.text = ""
	label_node.position = Vector2(-60, -72)
	label_node.size = Vector2(120, 28)
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.add_theme_font_size_override("font_size", 18)
	add_child(label_node)
	
	walk_target = spawn_pos
	walk_interval = randf_range(IDLE_DURATION_MIN, IDLE_DURATION_MAX)
	walk_timer = walk_interval

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	
	# NPC 的地面基准永远固定，移动只发生在 X 轴。
	position.y = spawn_pos.y
	if is_walking:
		var previous_x := position.x
		position.x = move_toward(position.x, walk_target.x, walk_speed * delta)
		if character_sprite != null and not is_equal_approx(previous_x, position.x):
			character_sprite.flip_h = position.x < previous_x
		if is_equal_approx(position.x, walk_target.x):
			_begin_idle()
		return

	walk_timer -= delta
	if walk_timer <= 0.0:
		_pick_new_walk_target()

func _pick_new_walk_target() -> void:
	var direction := -1.0 if randf() < 0.5 else 1.0
	var offset := direction * randf_range(28.0, WALK_RADIUS)
	walk_target = Vector2(spawn_pos.x + offset, spawn_pos.y)
	is_walking = true

func _begin_idle() -> void:
	is_walking = false
	walk_target = Vector2(position.x, spawn_pos.y)
	walk_interval = randf_range(IDLE_DURATION_MIN, IDLE_DURATION_MAX)
	walk_timer = walk_interval

func _create_atlas_sprite(index: int) -> Sprite2D:
	var atlas := load(NPC_ATLAS_PATH) as Texture2D
	if atlas == null:
		push_warning("NPC atlas not found: %s" % NPC_ATLAS_PATH)
		return null
	var safe_index := clampi(index, 0, NPC_ATLAS_COLUMNS * NPC_ATLAS_ROWS - 1)
	var col := safe_index % NPC_ATLAS_COLUMNS
	var row := safe_index / NPC_ATLAS_COLUMNS
	var atlas_size := atlas.get_size()
	var left := roundi(col * atlas_size.x / NPC_ATLAS_COLUMNS)
	var right := roundi((col + 1) * atlas_size.x / NPC_ATLAS_COLUMNS)
	var top := roundi(row * atlas_size.y / NPC_ATLAS_ROWS)
	var bottom := roundi((row + 1) * atlas_size.y / NPC_ATLAS_ROWS)
	var region := Rect2(left, top, right - left, bottom - top)

	var frame := AtlasTexture.new()
	frame.atlas = atlas
	frame.region = region
	var result := Sprite2D.new()
	result.name = "CharacterTexture"
	result.texture = frame
	result.scale = NPC_DISPLAY_SCALE
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.z_index = 3
	_align_sprite_to_feet(result, atlas.get_image(), region)
	return result

func _align_sprite_to_feet(sprite: Sprite2D, image: Image, region: Rect2) -> void:
	var min_x := int(region.size.x)
	var max_x := -1
	var max_y := -1
	for y in range(int(region.size.y)):
		for x in range(int(region.size.x)):
			var pixel := image.get_pixel(int(region.position.x) + x, int(region.position.y) + y)
			if pixel.a <= 0.25:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_y < 0:
		return
	var frame_center := (region.size - Vector2.ONE) * 0.5
	var opaque_center_x := (min_x + max_x) * 0.5
	sprite.position.x = -(opaque_center_x - frame_center.x) * sprite.scale.x
	sprite.position.y = NPC_FOOT_Y - (max_y - frame_center.y) * sprite.scale.y
	sprite.set_meta("visual_foot_y", NPC_FOOT_Y)

func _create_pixel_figure() -> Node2D:
	var root := Node2D.new()
	root.name = "PixelFigure"
	root.position = Vector2(0, -10)
	root.scale = Vector2(2.0, 2.0)
	root.z_index = 3
	var skin := Color("#f1c7a5")
	var hair := portrait_color.darkened(0.45)
	var cloth := portrait_color.lightened(0.1)
	var cloth_shadow := portrait_color.darkened(0.25)
	var outline := Color("#2f3138")
	var shoe := Color("#3a2c24")
	_add_px(root, Rect2(-6, -16, 12, 16), outline)
	_add_px(root, Rect2(-4, -14, 8, 12), cloth_shadow)
	_add_px(root, Rect2(-3, -15, 6, 10), cloth)
	_add_px(root, Rect2(-5, -21, 10, 7), outline)
	_add_px(root, Rect2(-4, -20, 8, 7), skin)
	_add_px(root, Rect2(-5, -23, 10, 4), hair)
	_add_px(root, Rect2(-4, -22, 3, 2), hair.lightened(0.18))
	_add_px(root, Rect2(-3, -18, 1, 1), Color("#2c2a28"))
	_add_px(root, Rect2(2, -18, 1, 1), Color("#2c2a28"))
	_add_px(root, Rect2(-8, -13, 3, 9), outline)
	_add_px(root, Rect2(5, -13, 3, 9), outline)
	_add_px(root, Rect2(-7, -12, 2, 7), skin.darkened(0.05))
	_add_px(root, Rect2(5, -12, 2, 7), skin.darkened(0.05))
	_add_px(root, Rect2(-4, -3, 3, 8), outline)
	_add_px(root, Rect2(1, -3, 3, 8), outline)
	_add_px(root, Rect2(-4, 4, 4, 2), shoe)
	_add_px(root, Rect2(1, 4, 4, 2), shoe)
	return root

func _add_px(parent: Node2D, rect: Rect2, color: Color) -> void:
	var px := ColorRect.new()
	px.position = rect.position
	px.size = rect.size
	px.color = color
	parent.add_child(px)
