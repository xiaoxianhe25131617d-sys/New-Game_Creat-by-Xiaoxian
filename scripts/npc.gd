extends Area2D
class_name MindscapeNPC

var npc_id: String = ""
var display_name: String = ""
var portrait_color: Color = Color.WHITE
var sign_only: bool = false
var blind_npc: bool = false

func setup(data: Dictionary) -> void:
	npc_id = str(data.get("id", ""))
	display_name = str(data.get("name", ""))
	portrait_color = Color(str(data.get("portrait", "#ffffff")))
	sign_only = bool(data.get("sign_only", false))
	blind_npc = bool(data.get("blind_npc", false))
	position = data.get("pos", Vector2.ZERO) as Vector2
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

	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-46, -78)
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
