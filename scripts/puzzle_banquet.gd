extends Area2D
class_name PuzzleBanquetPainting
# ════════════════════════════════════════════════════════════
#  宴会厅油画 (Banquet Hall Painting)
#  位置：(5800, 3100) — 风向标1右侧
#  规则：
#    抑郁/自闭模式下：同时按住 4+ 个键（手掌按键盘）→ 揭示舞蹈序列
#    普通模式：按 E 观察油画
#    记住序列 → 踩地面按钮按顺序通关
#  产出：钥匙1
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false

# 舞蹈序列配置
@export var dance_sequence: Array[String] = ["A", "C", "B", "D", "A", "B"]
var sequence_memorized: bool = false
var current_input_index: int = 0

# 多键手势追踪
var _held_keys: Array[int] = []
const MULTIKEY_REQUIRED: int = 4

# 当前视角模式（由 main.gd 通过 update_on_view_change 同步）
var current_view: String = "normal"

# 地面按钮
var buttons: Dictionary = {}
const BUTTON_POSITIONS: Dictionary = {
	"A": Vector2(-60, 100),
	"B": Vector2(-20, 100),
	"C": Vector2(20, 100),
	"D": Vector2(60, 100),
}

const DANCER_OFFSETS: Dictionary = {
	"A": Vector2(-45, -35),
	"B": Vector2(-15, -30),
	"C": Vector2(15, -28),
	"D": Vector2(45, -33),
}

var painting_visual: CanvasItem
var dancer_nodes: Dictionary = {}
var button_nodes: Dictionary = {}
var multi_key_progress: ProgressBar

func _ready() -> void:
	# 加入 interactable 组，以便接收视角切换通知
	add_to_group("interactable")
	# 渲染在 TileMap 上层
	z_index = 10

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(260, 200)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)
	_make_painting_room()
	_make_floor_buttons()
	_make_multi_key_hint()
	# 延迟获取初始视角
	call_deferred("_sync_initial_view")

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

	# 舞者标记
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

	# 标题
	var title := Label.new()
	title.text = "[ 宴会厅油画 ]"
	title.position = Vector2(-55, -95)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)

	# 提示文字
	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = "走近油画…"
	hint.position = Vector2(-80, 95)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#ffe8a0"))
	add_child(hint)

func _make_floor_buttons() -> void:
	for key in BUTTON_POSITIONS.keys():
		var btn := Area2D.new()
		btn.name = "Btn_" + str(key)
		btn.position = BUTTON_POSITIONS[key]
		btn.z_index = 10
		add_child(btn)

		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 24  # 足够大，容易踩到
		shape.shape = circle
		btn.add_child(shape)

		# 地面方砖底座 — 让按钮看起来是放在地上的
		var floor_plate := ColorRect.new()
		floor_plate.position = Vector2(-22, -22)
		floor_plate.size = Vector2(44, 44)
		floor_plate.color = Color("#4a4038")
		btn.add_child(floor_plate)

		# 地砖边框
		var plate_border := ColorRect.new()
		plate_border.position = Vector2(-24, -24)
		plate_border.size = Vector2(48, 48)
		plate_border.color = Color("#706050", 0.5)
		btn.add_child(plate_border)

		# 按钮圆形底座
		var base := Polygon2D.new()
		var bp := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * i / 20.0
			bp.append(Vector2(cos(a) * 17, sin(a) * 17))
		base.polygon = bp
		base.color = Color("#605040")
		btn.add_child(base)

		# 按钮发光圈（未激活时暗色）
		var visual := Polygon2D.new()
		var vp := PackedVector2Array()
		for i in range(12):
			var a: float = TAU * i / 12.0
			vp.append(Vector2(cos(a) * 12, sin(a) * 12))
		visual.polygon = vp
		visual.color = Color("#8a7a5a")
		btn.add_child(visual)

		var label := Label.new()
		label.text = key
		label.position = Vector2(-5, -8)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("#fff8e0"))
		btn.add_child(label)

		buttons[key] = btn
		button_nodes[key] = visual

func _make_multi_key_hint() -> void:
	# 多键手势进度条（仅在抑郁/自闭模式下显示）
	multi_key_progress = ProgressBar.new()
	multi_key_progress.name = "MultiKeyProgress"
	multi_key_progress.position = Vector2(-60, -105)
	multi_key_progress.size = Vector2(120, 8)
	multi_key_progress.max_value = MULTIKEY_REQUIRED
	multi_key_progress.value = 0
	multi_key_progress.show_percentage = false
	# 用 theme override 确保进度条可见
	multi_key_progress.add_theme_color_override("font_color", Color.WHITE)
	multi_key_progress.add_theme_color_override("font_outline_color", Color.BLACK)
	var fg_style := StyleBoxFlat.new()
	fg_style.bg_color = Color("#ff6600")
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("#333333")
	multi_key_progress.add_theme_stylebox_override("fill", fg_style)
	multi_key_progress.add_theme_stylebox_override("background", bg_style)
	multi_key_progress.visible = false
	add_child(multi_key_progress)

	# 多键提示标签
	var mk_label := Label.new()
	mk_label.name = "MultiKeyLabel"
	mk_label.text = "把手放键盘上…"
	mk_label.position = Vector2(-60, -120)
	mk_label.add_theme_font_size_override("font_size", 10)
	mk_label.add_theme_color_override("font_color", Color("#ffaa44"))
	mk_label.visible = false
	add_child(mk_label)

func _sync_initial_view() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_view"):
		update_on_view_change(main.get_view())

# 外部通知视角变化
func update_on_view_change(view: String) -> void:
	current_view = view
	var is_special: bool = (view == "depression" or view == "autism")
	var mk_label: Label = get_node_or_null("MultiKeyLabel") as Label
	if is_instance_valid(mk_label):
		mk_label.visible = is_special and player_in_range and not is_completed and not sequence_memorized
	if is_instance_valid(multi_key_progress):
		multi_key_progress.visible = is_special and player_in_range and not is_completed and not sequence_memorized
	_update_hint()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		var is_special: bool = (current_view == "depression" or current_view == "autism")
		var mk_label: Label = get_node_or_null("MultiKeyLabel") as Label
		if is_instance_valid(mk_label):
			mk_label.visible = is_special and not is_completed and not sequence_memorized
		if is_instance_valid(multi_key_progress):
			multi_key_progress.visible = is_special and not is_completed and not sequence_memorized
		_update_hint()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_held_keys.clear()
		var mk_label: Label = get_node_or_null("MultiKeyLabel") as Label
		if is_instance_valid(mk_label):
			mk_label.visible = false
		if is_instance_valid(multi_key_progress):
			multi_key_progress.visible = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return

	# ── 多键手势（抑郁/自闭模式） ──
	var is_special: bool = (current_view == "depression" or current_view == "autism")
	if is_special and not sequence_memorized:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				if not _held_keys.has(event.keycode):
					_held_keys.append(event.keycode)
			elif not event.pressed:
				_held_keys.erase(event.keycode)

			var count: int = _held_keys.size()
			if is_instance_valid(multi_key_progress):
				multi_key_progress.value = count
			var mk_label: Label = get_node_or_null("MultiKeyLabel") as Label
			if is_instance_valid(mk_label):
				mk_label.text = "按住 %d/%d 个键…" % [count, MULTIKEY_REQUIRED]

			if count >= MULTIKEY_REQUIRED:
				_start_observing()
				_held_keys.clear()
				return

	# ── 普通模式 / 已记住序列 — E 键交互 ──
	if event.is_action_pressed("interact"):
		if not sequence_memorized:
			if not is_special:
				_start_observing()
			else:
				hint_updated.emit("把手放在键盘上，同时按住多个键来感受舞者的振动…")
		else:
			hint_updated.emit("已经记住了序列！去踩地面的按钮吧。")

func _start_observing() -> void:
	hint_updated.emit("观察油画中舞者的舞蹈顺序…")
	_get_hint_label().text = "观察舞蹈中…"
	# 隐藏多键提示
	var mk_label: Label = get_node_or_null("MultiKeyLabel") as Label
	if is_instance_valid(mk_label):
		mk_label.visible = false
	if is_instance_valid(multi_key_progress):
		multi_key_progress.visible = false
	_play_dance_animation()

func _play_dance_animation() -> void:
	for i in range(dance_sequence.size()):
		var step_key: String = dance_sequence[i]
		var delay: float = float(i) * 1.2
		get_tree().create_timer(delay).timeout.connect(func():
			_highlight_dancer(step_key)
		)

	get_tree().create_timer(float(dance_sequence.size()) * 1.2 + 0.5).timeout.connect(func():
		if not sequence_memorized:
			sequence_memorized = true
			hint_updated.emit("舞蹈序列：%s → 去踩地面按钮！" % str(dance_sequence))
			_get_hint_label().text = "序列: %s" % str(dance_sequence)
			# 点亮所有地面按钮
			for key in button_nodes.keys():
				if is_instance_valid(button_nodes[key]):
					var t := create_tween()
					t.tween_property(button_nodes[key], "color", Color("#ffaa00"), 0.3)
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
	if pressed_cooldown.get(key, 0.0) > Time.get_ticks_msec():
		return
	pressed_cooldown[key] = Time.get_ticks_msec() + 500

	var expected: String = dance_sequence[current_input_index]

	if key == expected:
		current_input_index += 1
		hint_updated.emit("✓ 按钮%s正确！(%d/%d)" % [key, current_input_index, dance_sequence.size()])
		_get_hint_label().text = "%s ✓ (%d/%d)" % [key, current_input_index, dance_sequence.size()]
		_flash_button(key, Color("#80e080"))

		if current_input_index >= dance_sequence.size():
			_complete_puzzle()
	else:
		current_input_index = 0
		hint_updated.emit("✗ 顺序错误！从头再来。")
		_get_hint_label().text = "✗ 错误! 重来"
		_flash_button(key, Color("#e08080"))

func _flash_button(key: String, flash_color: Color) -> void:
	if not is_instance_valid(button_nodes.get(key)):
		return
	var vis: Polygon2D = button_nodes[key]
	var tween := create_tween()
	tween.tween_property(vis, "color", flash_color, 0.12)
	tween.tween_property(vis, "color", Color("#ffaa00"), 0.3)

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
		var is_special: bool = (current_view == "depression" or current_view == "autism")
		if is_special:
			lbl.text = "同时按住 4+ 个键感受画中振动"
		else:
			lbl.text = "按 [E] 观察油画（抑郁/自闭视角揭示秘密）"

func _get_hint_label() -> Label:
	return get_node_or_null("HintLabel") as Label

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func is_solved() -> bool:
	return is_completed
