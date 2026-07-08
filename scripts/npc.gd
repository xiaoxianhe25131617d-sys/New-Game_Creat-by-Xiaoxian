extends Area2D
class_name MindscapeNPC

var npc_id: String = ""
var display_name: String = ""
var portrait_color: Color = Color.WHITE
var sign_only: bool = false
var blind_npc: bool = false
var spawn_pos: Vector2 = Vector2.ZERO  # 原始生成位置

# ── 随机走动 ──
var walk_timer: float = 0.0
var walk_interval: float = 3.0
var walk_target: Vector2 = Vector2.ZERO
var walk_speed: float = 25.0
var is_walking: bool = false
var label_node: Label

func setup(data: Dictionary) -> void:
	npc_id = str(data.get("id", ""))
	display_name = str(data.get("name", ""))
	portrait_color = Color(str(data.get("portrait", "#ffffff")))
	sign_only = bool(data.get("sign_only", false))
	blind_npc = bool(data.get("blind_npc", false))
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
	add_child(shape)

	var figure := Polygon2D.new()
	figure.polygon = PackedVector2Array([Vector2(-18, 24), Vector2(-12, -22), Vector2(0, -36), Vector2(12, -22), Vector2(18, 24)])
	figure.color = portrait_color
	figure.visible = false
	add_child(figure)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/characters/npc.svg")
	sprite.scale = Vector2(0.58, 0.58)
	sprite.position = Vector2(0, -10)
	sprite.modulate = portrait_color.lightened(0.15)
	add_child(sprite)

	label_node = Label.new()
	label_node.text = display_name
	label_node.position = Vector2(-46, -78)
	label_node.add_theme_font_size_override("font_size", 18)
	add_child(label_node)
	
	# 初始化随机走动间隔
	walk_interval = randf_range(2.0, 5.0)
	walk_timer = randf_range(0.0, walk_interval)

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	
	# 随机走动计时器
	walk_timer -= delta
	if walk_timer <= 0.0:
		_pick_new_walk_target()
		walk_timer = randf_range(2.5, 5.5)
	
	# 移动到目标
	if is_walking and walk_target.distance_to(position) > 2.0:
		var dir := (walk_target - position).normalized()
		position += dir * walk_speed * delta
		
		# 让名字标签跟随（Labels 是子节点所以自动跟随）
		# 限制走动范围不超过 spawn_pos 周围 80px
		if position.distance_to(spawn_pos) > 80.0:
			walk_target = spawn_pos + Vector2(randf_range(-60, 60), randf_range(-15, 15))
	else:
		is_walking = false

func _pick_new_walk_target() -> void:
	# 在 spawn_pos 周围随机移动，范围 ±70px 水平，±10px 垂直
	walk_target = spawn_pos + Vector2(randf_range(-70, 70), randf_range(-12, 12))
	is_walking = true
