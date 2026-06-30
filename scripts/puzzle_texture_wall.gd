extends Area2D
class_name PuzzleTextureWall
# ════════════════════════════════════════════════════════════
#  关卡1：纹理墙（石门）
#  盲人模式下按方向键触摸纹理解锁
#  正确序列：↑ ↑ ↓ ↓ ← → (上下上下左右)
#  非盲人模式：只能摸到"凹凸不平"，无法辨别方向
# ════════════════════════════════════════════════════════════

signal puzzle_completed
signal hint_updated(text: String)

@export var correct_sequence: Array[String] = ["up", "up", "down", "down", "left", "right"]

var current_step: int = -1
var player_in_range: bool = false
var is_completed: bool = false
var wall_visual: Polygon2D
var hint_label: Label

# 每个方向对应的纹理感受描述
const DIRECTION_DESC: Dictionary = {
	"up":    "向上凸起",
	"down":  "向下凹陷",
	"left":  "向左倾斜",
	"right": "向右倾斜",
}

# 玩家按错时引导到正确方向
const HINT_GUIDE: Dictionary = {
	"up":    "纹理是向上的...按 ↑",
	"down":  "纹理是向下的...按 ↓",
	"left":  "纹理是向左的...按 ←",
	"right": "纹理是向右的...按 →",
}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(180, 260)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)
	_make_wall_visual()
	_make_hint_label()

func _make_wall_visual() -> void:
	var wall := Polygon2D.new()
	var size := Vector2(140, 240)
	wall.polygon = PackedVector2Array([
		Vector2(-size.x/2, -size.y/2), Vector2(size.x/2, -size.y/2),
		Vector2(size.x/2, size.y/2), Vector2(-size.x/2, size.y/2)
	])
	wall.color = Color("#6b5b4a")
	add_child(wall)
	wall_visual = wall

	# 纹理线条
	for i in range(10):
		var line := Line2D.new()
		line.width = 2
		line.default_color = Color("#5a4a3a")
		var y: float = -110.0 + i * 24.0
		line.add_point(Vector2(-55, y + sin(i * 2.0) * 8))
		line.add_point(Vector2(55, y + cos(i * 1.7) * 6))
		add_child(line)

	var title := Label.new()
	title.text = "[ 纹理墙 — 石门 ]"
	title.position = Vector2(-55, -135)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)

func _make_hint_label() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-110, 65)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "靠近后按 [E] 触摸墙面"
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if not is_completed:
			var view := _get_view()
			if view == "blind":
				hint_label.text = "按 [E] 用触觉感受纹理"
			else:
				hint_label.text = "上面有凹凸不平的纹理...但感觉不出来方向"

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	if current_step == -1:
		if event.is_action_pressed("interact"):
			_try_start_puzzle()
	elif event is InputEventKey and event.pressed:
		_handle_key_press(event)

func _try_start_puzzle() -> void:
	var view := _get_view()
	if view != "blind":
		hint_label.text = "凹凸不平...但什么都感觉不出来。试试盲人模式。"
		hint_updated.emit("这墙上有纹理，但不用触觉（盲人模式）根本分不清方向。")
		return
	_start_puzzle()

func _start_puzzle() -> void:
	current_step = 0
	hint_label.text = "用手触摸墙面...方向键感受凹凸纹理"
	hint_updated.emit("用方向键'触摸'墙面。感受每个纹理的方向。")
	_disable_player(true)
	_tween_wall_pulse()

func _handle_key_press(event: InputEventKey) -> void:
	var action: String = ""
	match event.keycode:
		KEY_UP, KEY_W:    action = "up"
		KEY_DOWN, KEY_S:  action = "down"
		KEY_LEFT, KEY_A:  action = "left"
		KEY_RIGHT, KEY_D: action = "right"
		_: return
	_check_input(action)

func _check_input(action: String) -> void:
	var expected: String = correct_sequence[current_step]

	if action == expected:
		# 正确！纹理匹配
		var desc: String = DIRECTION_DESC.get(action, action)
		hint_label.text = "✓ 摸到了%s的纹理！" % desc
		hint_updated.emit("✓ 感觉到了%s的纹理...(进度%d/%d)" % [desc, current_step + 1, correct_sequence.size()])
		current_step += 1
		_tween_wall_flash(Color("#a0e080"))

		if current_step >= correct_sequence.size():
			_complete_puzzle()
	else:
		# 错误 — 给方向提示
		var guide: String = HINT_GUIDE.get(expected, "再试试")
		hint_label.text = "不是这个方向...%s" % guide
		hint_updated.emit("不是这个方向的纹理...%s" % guide)
		_tween_wall_flash(Color("#e08080"))

func _complete_puzzle() -> void:
	is_completed = true
	current_step = correct_sequence.size()
	_disable_player(false)
	hint_label.text = "✨ 石门打开了！"
	hint_updated.emit("✨ 石门已解锁！前方区域开放。")
	puzzle_completed.emit()
	_tween_celebration()

func _disable_player(v: bool) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if "controls_enabled" in node:
			node.controls_enabled = not v

func _get_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"

# ── 动画 ──
func _tween_wall_pulse() -> void:
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(wall_visual, "modulate", Color("#8a7a6a"), 0.35)
	tween.tween_property(wall_visual, "modulate", Color("#6b5b4a"), 0.35)

func _tween_wall_flash(flash_color: Color) -> void:
	var tween := create_tween()
	tween.tween_property(wall_visual, "color", flash_color, 0.12)
	tween.tween_property(wall_visual, "color", Color("#6b5b4a"), 0.25)

func _tween_celebration() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wall_visual, "color", Color("#ffd700"), 0.5)
	for i in range(12):
		var spark := CPUParticles2D.new()
		spark.amount = 8
		spark.lifetime = 0.8
		spark.emitting = true
		spark.explosiveness = 0.9
		spark.gravity = Vector2(0, -40)
		spark.initial_velocity_min = 20
		spark.initial_velocity_max = 60
		spark.color = Color("#ffd700")
		spark.position = Vector2(randf_range(-50, 50), randf_range(-100, 100))
		add_child(spark)
		await get_tree().create_timer(1.5).timeout
		spark.queue_free()

func get_progress() -> int:
	return current_step

func is_solved() -> bool:
	return is_completed
