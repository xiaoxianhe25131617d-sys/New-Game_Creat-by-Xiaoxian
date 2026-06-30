extends Area2D
class_name PuzzleTextureWall
# ════════════════════════════════════════════════════════════
#  关卡1：纹理墙 (Texture Wall)
#  位置：出生点往左第一个场景
#  规则：键盘按键模拟触觉反馈，引导玩家按出正确序列
#  产出：打开石门 → 解锁左侧其他关卡
# ════════════════════════════════════════════════════════════

signal puzzle_completed
signal hint_updated(text: String)

# 正确按键序列（可自定义）
@export var correct_sequence: Array[String] = ["ui_up", "ui_up", "ui_down", "ui_down", "ui_left", "ui_right"]

var current_step: int = -1          # -1 = 未开始, >=0 = 当前步骤索引
var player_in_range: bool = false
var is_completed: bool = false
var wall_visual: Polygon2D           # 墙面视觉效果
var hint_label: Label                # 提示文字

# 每步的引导提示（按错了会提示方向）
const HINT_MAP: Dictionary = {
	"ui_up":    "再往下一点...",
	"ui_down":  "再往上一点...",
	"ui_left":  "再往右一点...",
	"ui_right": "再往左一点...",
}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_wall_visual()
	_make_hint_label()

func _make_wall_visual() -> void:
	# 纹理墙外观 — 粗糙石墙
	var wall := Polygon2D.new()
	var size := Vector2(120, 200)
	wall.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y)
	])
	wall.color = Color("#6b5b4a")
	wall.offset = -size / 2.0
	add_child(wall)
	wall_visual = wall
	
	# 凹凸纹理线条（视觉暗示）
	for i in range(8):
		var line := Line2D.new()
		line.width = 2
		line.default_color = Color("#5a4a3a")
		var y := float(i) * 25.0 + 12.0
		line.add_point(Vector2(-50, y + sin(i * 2.0) * 8))
		line.add_point(Vector2(50, y + cos(i * 1.7) * 6))
		add_child(line)
	
	# 标题标签
	var title := Label.new()
	title.text = "[ 纹理墙 ]"
	title.position = Vector2(-45, -115)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)

func _make_hint_label() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-110, 60)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "靠近后按 E 触摸墙面"
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if not is_completed:
			hint_label.text = "按 [E] 开始触摸墙面"

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if current_step == -1:
			hint_label.text = "靠近后按 E 触摸墙面"

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	if current_step == -1:
		if event.is_action_pressed("interact"):
			_start_puzzle()
	elif event is InputEventKey and event.pressed:
		_handle_key_press(event)

func _start_puzzle() -> void:
	current_step = 0
	hint_label.text = "表面凹凸不平...用方向键感受纹理"
	hint_updated.emit("表面凹凸不平...用方向键摸索")
	# 墙面脉动效果提示开始
	_tween_wall_pulse()

func _handle_key_press(event: InputEventKey) -> void:
	var key_name: String = event.as_text_key_label()
	
	# 映射键盘输入到动作名
	var action: String = ""
	match key_name:
		"↑", "W", "w":
			action = "ui_up"
		"↓", "S", "s":
			action = "ui_down"
		"←", "A", "a":
			action = "ui_left"
		"→", "D", "d":
			action = "ui_right"
		_: return  # 忽略非方向键
	
	_check_input(action)

func _check_input(action: String) -> void:
	var expected: String = correct_sequence[current_step]
	
	if action == expected:
		# 正确！
		hint_label.text = "对！就是这个感觉...再按一下"
		hint_updated.emit("✓ 正确！继续...")
		current_step += 1
		
		# 正确反馈动画
		_tween_wall_flash(Color("#a0e080"))
		
		if current_step >= correct_sequence.size():
			_complete_puzzle()
	else:
		# 错误 — 引导向正确方向
		var hint: String = HINT_MAP.get(expected, "再试试别的方向")
		hint_label.text = hint
		hint_updated.emit("✗ " + hint)
		_tween_wall_flash(Color("#e08080"))

func _complete_puzzle() -> void:
	is_completed = true
	current_step = correct_sequence.size()
	hint_label.text = "✨ 石门打开了！"
	hint_updated.emit("✨ 石门已解锁！左侧区域可通过。")
	puzzle_completed.emit()
	
	# 成功特效
	_tween_celebration()

# ── 动画效果 ──
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
	# 发光粒子效果
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

# 外部查询状态
func get_progress() -> int:
	return current_step

func is_solved() -> bool:
	return is_completed
