extends Area2D
class_name MindscapeMonster

signal player_touched(monster_type: String)

var monster_id: String = ""
var monster_type: String = ""
var home: Vector2 = Vector2.ZERO
var time: float = 0.0
var target_alpha: float = 1.0
var current_alpha: float = 1.0
var view_key: String = ""
var is_active: bool = false  # true when correct view is active
var damage_cooldown: float = 0.0  # prevent damage spam

@onready var body_node: Polygon2D = $Body
@onready var label_node: Label = $Label

func setup(id: String, kind: String, pos: Vector2) -> void:
	monster_id = id
	monster_type = kind
	home = pos
	position = pos
	name = "Monster_%s" % id
	set_meta("kind", "monster")
	set_meta("id", id)
	add_to_group("monster")
	
	# Define which view this monster belongs to
	match kind:
		"noise": view_key = "blind"
		"silent_mouth": view_key = "autism"
		"shadow": view_key = "depression"
	
	# Start invisible — will become visible when correct view is active
	target_alpha = 0.0
	current_alpha = 0.0
	
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 42
	shape.shape = circle
	add_child(shape)
	
	var body := Polygon2D.new()
	body.name = "Body"
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a), sin(a)) * (30.0 + 8.0 * sin(i)))
	body.polygon = pts
	body.color = _color_for_type(kind)
	body.modulate.a = 0.0
	add_child(body)
	body_node = body
	
	var label := Label.new()
	label.name = "Label"
	label.text = _label_for_type(kind)
	label.position = Vector2(-46, -64)
	label.add_theme_font_size_override("font_size", 16)
	label.modulate.a = 0.0
	add_child(label)
	label_node = label

func _process(delta: float) -> void:
	time += delta
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	position = home + Vector2(sin(time * 1.5) * 20.0, cos(time * 1.1) * 12.0)
	rotation = sin(time) * 0.08
	
	# Smooth alpha transition
	current_alpha = lerp(current_alpha, target_alpha, delta * 6.0)
	if body_node != null:
		body_node.modulate.a = current_alpha
	if label_node != null:
		label_node.modulate.a = current_alpha
	
	# Continuous damage check when monster is active and visible
	if is_active and current_alpha > 0.5 and damage_cooldown <= 0.0:
		for body in get_overlapping_bodies():
			if body is MindscapePlayer:
				_on_player_contact(body)
				break

func on_view_changed(view: String) -> void:
	# Monster only visible/active in its associated view
	if view == view_key:
		target_alpha = 1.0
		is_active = true
		set_deferred("monitoring", true)
		set_deferred("monitorable", true)
	else:
		target_alpha = 0.0
		current_alpha = 0.0
		if body_node != null:
			body_node.modulate.a = 0.0
		if label_node != null:
			label_node.modulate.a = 0.0
		is_active = false
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)

func _on_player_contact(player: MindscapePlayer) -> void:
	damage_cooldown = 0.8  # damage tick every 0.8s
	player_touched.emit(monster_type)
	# Apply mechanical effects
	match monster_type:
		"shadow":
			# Slow the player significantly
			player.velocity.x *= 0.35
		"noise":
			# Disorient: randomize player velocity slightly
			player.velocity.x += randf_range(-80.0, 80.0)
		"silent_mouth":
			# Push player back
			player.velocity.x += signf(player.global_position.x - global_position.x) * 200.0
			player.velocity.y = -180.0

func _color_for_type(type: String) -> Color:
	match type:
		"noise":
			return Color("#4fc8ff")
		"silent_mouth":
			return Color("#d4e4f4")
		"shadow":
			return Color("#2a2d38")
	return Color.WHITE

func _label_for_type(type: String) -> String:
	match type:
		"noise":
			return "信息噪音球"
		"silent_mouth":
			return "无声嘴巴"
		"shadow":
			return "阴影"
	return "怪物"
