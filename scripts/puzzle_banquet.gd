extends Area2D
class_name PuzzleBanquetPainting
# ════════════════════════════════════════════════════════════
#  关卡3：宴会厅油画 (Banquet Hall Painting)
#  位置：左侧第三场景
#  规则：
#    油画上小人在跳舞（自闭症/抑郁症模式可见6个按钮位置）
#    记录舞蹈顺序 → 在地面按钮踩出相同顺序
#    额外：旁边大坑需ADHD跳跃模式通过
#  产出：钥匙1
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false

# 舞蹈序列配置
@export var dance_sequence: Array[String] = ["A", "C", "B", "D", "A", "B"]
var sequence_memorized: bool = false    # 是否已记住序列
var current_input_index: int = 0        # 当前输入到第几个

# 地面按钮定义（A-F 六个位置）
var buttons: Dictionary = {}
const BUTTON_POSITIONS: Dictionary = {
	"A": Vector2(-60, 50),
	"B": Vector2(-20, 50),
	"C": Vector2(20, 50),
	"D": Vector2(60, 50),
}

# 舞者位置（对应按钮）
var dancers: Dictionary = {}
const DANCER_OFFSETS: Dictionary = {
	"A": Vector2(-45, -35),
	"B": Vector2(-15, -30),
	"C": Vector2(15, -28),
	"D": Vector2(45, -33),
}

# 油画视觉
var painting_visual: Polygon2D
var dancer_nodes: Dictionary = {}
var button_nodes: Dictionary = {}

# 跳跃坑
var pit_area: Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_painting_room()
	_make_floor_buttons()
	_make_pit()

func _make_painting_room() -> void:
	# 宴会厅建筑
	var hall := Polygon2D.new()
	var size := Vector2(200, 160)
	hall.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y)
	])
	hall.color = Color("#9a8068")
	hall.offset = -size / 2.0
	add_child(hall)
	
	# 油画框
	var frame := ColorRect.new()
	frame.position = Vector2(-70, -65)
	frame.size = Vector2(140, 85)
	frame.color = Color("#6a5040")
	add_child(frame)
	
	# 油画布面
	var canvas := ColorRect.new()
	canvas.position = Vector2(-64, -59)
	canvas.size = Vector2(128, 73)
	canvas.color = Color("#e8d8c8")
	canvas.name = "PaintingCanvas"
	add_child(canvas)
	painting_visual = canvas
	
	# 舞者标记（在油画上的小点）
	for key in DANCER_OFFSETS.keys():
		var dancer := Polygon2D.new()
		var dp := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * i / 6.0
			dp.append(DANCER_OFFSETS[key] + Vector2(cos(a) * 6, sin(a) * 6))
		dancer.polygon = dp
		dancer.color = Color.TRANSPARENT
		canvas.add_child(dancer)
		dancer_nodes[key] = dancer
	
	# 提示文字
	var title := Label.new()
	title.text = "[ 宴会厅油画 ]"
	title.position = Vector2(-55, -95)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)
	
	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = "按 [E] 观察油画"
	hint.position = Vector2(-60, 70)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#ffe8a0"))
	add_child(hint)

func _make_floor_buttons() -> void:
	# 四个地面按钮
	for key in BUTTON_POSITIONS.keys():
		var btn := Area2D.new()
		btn.name = "Btn_" + key
		btn.position = BUTTON_POSITIONS[key]
		add_child(btn)
		
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 14
		shape.shape = circle
		btn.add_child(shape)
		
		var visual := Polygon2D.new()
		var vp := PackedVector2Array()
		for i in range(8):
			var a: float = TAU * i / 8.0
			vp.append(Vector2(cos(a) * 14, sin(a) * 14))
		visual.polygon = vp
		visual.color = Color("#c0a060")
		btn.add_child(visual)
		
		var label := Label.new()
		label.text = key
		label.position = Vector2(-5, -8)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color("#fff8e0"))
		btn.add_child(label)
		
		buttons[key] = btn
		button_nodes[key] = visual

func _make_pit() -> void:
	# ADHD跳跃大坑（在宴会厅右边）
	pit_area = Area2D.new()
	pit_area.name = "ADHD_Pit"
	pit_area.position = Vector2(130, 15)
	add_child(pit_area)
	
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(30, 60)
	shape.shape = box
	pit_area.add_child(shape)
	
	# 坑的视觉
	var pit_vis := ColorRect.new()
	pit_vis.position = Vector2(-15, -30)
	pit_vis.size = Vector2(30, 60)
	pit_vis.color = Color("#1a1020")
	pit_area.add_child(pit_vis)
	
	var pit_label := Label.new()
	pit_label.text = "宽坑\n(ADHD跳过)"
	pit_label.position = Vector2(-22, -48)
	pit_label.add_theme_font_size_override("font_size", 9)
	pit_label.add_theme_color_override("font_color", Color("#ff8888"))
	pit_area.add_child(pit_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
	_update_hint()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	
	if event.is_action_pressed("interact"):
		if not sequence_memorized:
			_start_observing()
		else:
			hint_updated.emit("已经记住了序列！去踩地面的按钮吧。")

func _start_observing() -> void:
	hint_updated.emit("观察油画中舞者的舞蹈顺序...")
	_get_hint_label().text = "观察舞蹈中..."
	_play_dance_animation()

func _play_dance_animation() -> void:
	# 按序列依次高亮舞者
	for i in range(dance_sequence.size()):
		var step_key: String = dance_sequence[i]
		var delay: float = float(i) * 1.2
		
		get_tree().create_timer(delay).timeout.connect(func():
			_highlight_dancer(step_key)
		)
	
	# 序列播放完毕
	get_tree().create_timer(float(dance_sequence.size()) * 1.2 + 0.5).timeout.connect(func():
		if not sequence_memorized:
			sequence_memorized = true
			hint_updated.emit("舞蹈序列：%s → 去按地面按钮！" % str(dance_sequence))
			_get_hint_label().text = "序列: %s" % str(dance_sequence)
	)

func _highlight_dancer(key: String) -> void:
	if not is_instance_valid(dancer_nodes.get(key)):
		return
	var dancer: Polygon2D = dancer_nodes[key]
	var tween := create_tween()
	tween.tween_property(dancer, "color", Color("#ff44aa"), 0.2)
	tween.tween_property(dancer, "color", Color.TRANSPARENT, 0.4)
	
	# 同时闪烁对应地面按钮
	if is_instance_valid(button_nodes.get(key)):
		var btn_vis: Polygon2D = button_nodes[key]
		var bt := create_tween()
		bt.tween_property(btn_vis, "color", Color("#ffd700"), 0.2)
		bt.tween_property(btn_vis, "color", Color("#c0a060"), 0.4)

func _process(_delta: float) -> void:
	# 检测玩家是否踩到地面按钮（通过玩家位置碰撞检测）
	if not player_in_range or is_completed or not sequence_memorized:
		return
	var player: Node2D = _get_player()
	if player == null:
		return
	
	for key in buttons.keys():
		var btn: Area2D = buttons[key]
		if btn.get_overlapping_bodies().has(player):
			_on_button_pressed(key)

var pressed_cooldown: Dictionary = {}

func _on_button_pressed(key: String) -> void:
	# 冷却防重复触发
	if pressed_cooldown.get(key, 0.0) > Time.get_ticks_msec():
		return
	pressed_cooldown[key] = Time.get_ticks_msec() + 500
	
	var expected: String = dance_sequence[current_input_index]
	
	if key == expected:
		# 正确！
		current_input_index += 1
		hint_updated.emit("✓ 按钮%s正确！(%d/%d)" % [key, current_input_index, dance_sequence.size()])
		_get_hint_label().text = "%s ✓ (%d/%d)" % [key, current_input_index, dance_sequence.size()]
		_flash_button(key, Color("#80e080"))
		
		if current_input_index >= dance_sequence.size():
			_complete_puzzle()
	else:
		# 错误
		current_input_index = 0
		hint_updated.emit("✗ 顺序错误！从头再来。")
		_get_hint_label().text = "✗ 错误! 重来 (%d/%d)" % [0, dance_sequence.size()]
		_flash_button(key, Color("#e08080"))

func _flash_button(key: String, flash_color: Color) -> void:
	if not is_instance_valid(button_nodes.get(key)):
		return
	var vis: Polygon2D = button_nodes[key]
	var tween := create_tween()
	tween.tween_property(vis, "color", flash_color, 0.12)
	tween.tween_property(vis, "color", Color("#c0a060"), 0.3)

func _complete_puzzle() -> void:
	is_completed = true
	_get_hint_label().text = "✨ 获得钥匙1（宴会厅钥匙）！"
	hint_updated.emit("✨ 你获得了钥匙1！")
	puzzle_completed.emit("key_1")
	
	var tween := create_tween()
	tween.tween_property(painting_visual, "color", Color("#ffd700"), 0.5)

func _update_hint() -> void:
	var lbl: Label = _get_hint_label()
	if is_completed:
		lbl.text = "✓ 已完成 — 钥匙1已获取"
	elif sequence_memorized:
		lbl.text = "踩按钮! (%d/%d)" % [current_input_index, dance_sequence.size()]
	else:
		lbl.text = "按 [E] 观察油画"

func _get_hint_label() -> Label:
	return get_node_or_null("HintLabel") as Label

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func is_solved() -> bool:
	return is_completed
