extends Area2D
class_name PuzzleBanquetPainting

# ════════════════════════════════════════════════════════════
#  油画舞步 — 画中小人教跳舞
#  6个箭头按钮用画面指示舞步（不用ABCD文字）
#  同时按下对应方向键来跳每一步
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)
signal room_toggled(open: bool)

# ── 6种舞步：箭头画面指示 + 对应按键 ──
const DANCE_MOVES: Array[Dictionary] = [
	{"id": "right",  "label": "右移", "arrow": "→",  "keys": [KEY_RIGHT],              "color": Color("#ff6644")},
	{"id": "left",   "label": "左移", "arrow": "←",  "keys": [KEY_LEFT],               "color": Color("#44aaff")},
	{"id": "jump",   "label": "跳跃", "arrow": "↑",  "keys": [KEY_UP],                 "color": Color("#44ff66")},
	{"id": "squat",  "label": "下蹲", "arrow": "↓",  "keys": [KEY_DOWN],               "color": Color("#ffaa44")},
	{"id": "diag_r", "label": "右跳", "arrow": "↗",  "keys": [KEY_UP, KEY_RIGHT],      "color": Color("#ff44aa")},
	{"id": "diag_l", "label": "左跳", "arrow": "↖",  "keys": [KEY_UP, KEY_LEFT],       "color": Color("#aa44ff")},
]

const SEQUENCE_LEN := 5

# ── 状态 ──
var player_in_range := false
var is_completed := false
var room_open := false
var current_view := "normal"

var dance_seq: Array[int] = []   # 随机生成的舞步序列（DANCE_MOVES 索引）
var cur_step := 0                # 当前第几步（0-based）

# 多键检测
var _held: Array[int] = []       # 当前按住的键
var _step_solved := false        # 当前步是否已判定
var _solve_timer := 0.0          # 解决后的短暂庆祝计时

# ── UI ──
var overlay: CanvasLayer = null
var paint_canvas: Control = null       # 油画布（画小人用）
var step_label: Label = null           # 提示当前该按什么
var progress_dots: Array[ColorRect] = []
var move_btns: Array[Control] = []    # 6个箭头按钮

# 小人动画
var pose_name := "idle"
var pose_time := 0.0
var figure_center := Vector2(90, 70)  # 小人在画布上的中心位置


# ════════════════════════════════════════════════════════════
#  小人关节姿势定义（相对 figure_center）
# ════════════════════════════════════════════════════════════

const POSES: Dictionary = {
	"idle": {
		"head": Vector2(0, -43),
		"neck": Vector2(0, -33),
		"hip": Vector2(0, 8),
		"shld_l": Vector2(-13, -26),
		"shld_r": Vector2(13, -26),
		"elb_l": Vector2(-20, -10),
		"elb_r": Vector2(20, -10),
		"hand_l": Vector2(-16, 5),
		"hand_r": Vector2(16, 5),
		"hip_l": Vector2(-7, 8),
		"hip_r": Vector2(7, 8),
		"knee_l": Vector2(-9, 28),
		"knee_r": Vector2(9, 28),
		"foot_l": Vector2(-9, 48),
		"foot_r": Vector2(9, 48),
	},
	"right": {
		"head": Vector2(6, -43),
		"neck": Vector2(6, -33),
		"hip": Vector2(4, 8),
		"shld_l": Vector2(-10, -26),
		"shld_r": Vector2(18, -26),
		"elb_l": Vector2(-16, -14),
		"elb_r": Vector2(26, -8),
		"hand_l": Vector2(-12, -2),
		"hand_r": Vector2(32, 8),
		"hip_l": Vector2(-4, 8),
		"hip_r": Vector2(10, 8),
		"knee_l": Vector2(-6, 26),
		"knee_r": Vector2(14, 30),
		"foot_l": Vector2(-6, 44),
		"foot_r": Vector2(16, 50),
	},
	"left": {
		"head": Vector2(-6, -43),
		"neck": Vector2(-6, -33),
		"hip": Vector2(-4, 8),
		"shld_l": Vector2(-18, -26),
		"shld_r": Vector2(10, -26),
		"elb_l": Vector2(-26, -8),
		"elb_r": Vector2(16, -14),
		"hand_l": Vector2(-32, 8),
		"hand_r": Vector2(12, -2),
		"hip_l": Vector2(-10, 8),
		"hip_r": Vector2(4, 8),
		"knee_l": Vector2(-14, 30),
		"knee_r": Vector2(6, 26),
		"foot_l": Vector2(-16, 50),
		"foot_r": Vector2(6, 44),
	},
	"jump": {
		"head": Vector2(0, -56),
		"neck": Vector2(0, -46),
		"hip": Vector2(0, -5),
		"shld_l": Vector2(-15, -40),
		"shld_r": Vector2(15, -40),
		"elb_l": Vector2(-22, -56),
		"elb_r": Vector2(22, -56),
		"hand_l": Vector2(-18, -70),
		"hand_r": Vector2(18, -70),
		"hip_l": Vector2(-7, -5),
		"hip_r": Vector2(7, -5),
		"knee_l": Vector2(-10, 10),
		"knee_r": Vector2(10, 10),
		"foot_l": Vector2(-12, 24),
		"foot_r": Vector2(12, 24),
	},
	"squat": {
		"head": Vector2(0, -43),
		"neck": Vector2(0, -33),
		"hip": Vector2(0, 16),
		"shld_l": Vector2(-13, -26),
		"shld_r": Vector2(13, -26),
		"elb_l": Vector2(-24, -10),
		"elb_r": Vector2(24, -10),
		"hand_l": Vector2(-28, 8),
		"hand_r": Vector2(28, 8),
		"hip_l": Vector2(-7, 16),
		"hip_r": Vector2(7, 16),
		"knee_l": Vector2(-14, 34),
		"knee_r": Vector2(14, 34),
		"foot_l": Vector2(-15, 44),
		"foot_r": Vector2(15, 44),
	},
	"diag_r": {
		"head": Vector2(6, -52),
		"neck": Vector2(6, -42),
		"hip": Vector2(4, -2),
		"shld_l": Vector2(-8, -34),
		"shld_r": Vector2(18, -36),
		"elb_l": Vector2(-14, -44),
		"elb_r": Vector2(28, -18),
		"hand_l": Vector2(-18, -54),
		"hand_r": Vector2(36, -4),
		"hip_l": Vector2(-2, -2),
		"hip_r": Vector2(10, -2),
		"knee_l": Vector2(2, 16),
		"knee_r": Vector2(18, 20),
		"foot_l": Vector2(4, 34),
		"foot_r": Vector2(24, 40),
	},
	"diag_l": {
		"head": Vector2(-6, -52),
		"neck": Vector2(-6, -42),
		"hip": Vector2(-4, -2),
		"shld_l": Vector2(-18, -36),
		"shld_r": Vector2(8, -34),
		"elb_l": Vector2(-28, -18),
		"elb_r": Vector2(14, -44),
		"hand_l": Vector2(-36, -4),
		"hand_r": Vector2(18, -54),
		"hip_l": Vector2(-10, -2),
		"hip_r": Vector2(2, -2),
		"knee_l": Vector2(-18, 20),
		"knee_r": Vector2(-2, 16),
		"foot_l": Vector2(-24, 40),
		"foot_r": Vector2(-4, 34),
	},
}


# ════════════════════════════════════════════════════════════
#  _ready
# ════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("interactable")
	z_index = 10

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 碰撞形状
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(220, 180)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)

	# 世界中的油画建筑外观
	_make_world_appearance()

	# overlay
	_make_overlay()

	call_deferred("_sync_initial_view")


# ════════════════════════════════════════════════════════════
#  世界中的建筑外观
# ════════════════════════════════════════════════════════════

func _make_world_appearance() -> void:
	var hall := Polygon2D.new()
	hall.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(160, 0),
		Vector2(160, 130), Vector2(0, 130)
	])
	hall.color = Color("#8a7060")
	hall.offset = Vector2(-80, -100)
	add_child(hall)

	# 画框
	var frame := ColorRect.new()
	frame.position = Vector2(-60, -75)
	frame.size = Vector2(120, 90)
	frame.color = Color("#5a4030")
	add_child(frame)

	var canvas_bg := ColorRect.new()
	canvas_bg.position = Vector2(-54, -69)
	canvas_bg.size = Vector2(108, 78)
	canvas_bg.color = Color("#e8d8c8")
	add_child(canvas_bg)

	# 小人预览
	var preview := Control.new()
	preview.position = Vector2(-54, -69)
	preview.size = Vector2(108, 78)
	preview.draw.connect(_on_preview_draw.bind(preview))
	# 简单旋转动画
	var pt := create_tween().set_loops()
	pt.tween_callback(func():
		if is_instance_valid(preview) and not room_open:
			pose_time += 0.016
			pose_name = "idle"
			if fmod(pose_time, 2.0) < 1.0:
				pose_name = "jump"
			preview.queue_redraw()
	).set_delay(0.016)
	add_child(preview)

	var title := Label.new()
	title.text = " 油画"
	title.position = Vector2(-30, -88)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)


func _on_preview_draw(cv: Control) -> void:
	_draw_stick(cv, "idle" if fmod(pose_time, 2.0) < 1.0 else "jump", Vector2(54, 45), 0.7)


# ════════════════════════════════════════════════════════════
#  Overlay（全屏 UI）
# ════════════════════════════════════════════════════════════

func _make_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 10
	overlay.visible = false
	add_child(overlay)

	# 半透明背景
	var bg := ColorRect.new()
	bg.size = Vector2(1152, 648)
	bg.color = Color(0, 0, 0, 0.55)
	overlay.add_child(bg)

	# 主面板
	var panel := Panel.new()
	panel.position = Vector2(276, 74)
	panel.size = Vector2(600, 500)
	var ps := StyleBoxFlat.new()
	ps.set_corner_radius_all(12)
	ps.bg_color = Color("#2a2218")
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#6a5040")
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	# 标题
	var ttl := Label.new()
	ttl.text = "🖼 油画 — 跟着小人学跳舞！"
	ttl.position = Vector2(18, 14)
	ttl.add_theme_font_size_override("font_size", 18)
	ttl.add_theme_color_override("font_color", Color("#d4c4a4"))
	panel.add_child(ttl)

	# ── 画框 ──
	var frame_outer := ColorRect.new()
	frame_outer.position = Vector2(18, 44)
	frame_outer.size = Vector2(200, 140)
	frame_outer.color = Color("#4a3020")
	panel.add_child(frame_outer)

	var frame_inner := ColorRect.new()
	frame_inner.position = Vector2(24, 50)
	frame_inner.size = Vector2(188, 128)
	frame_inner.color = Color("#6a4a30")
	panel.add_child(frame_inner)

	paint_canvas = Control.new()
	paint_canvas.position = Vector2(28, 54)
	paint_canvas.size = Vector2(180, 120)
	paint_canvas.draw.connect(_on_paint_draw)
	panel.add_child(paint_canvas)

	# 画布背景色
	var cb := ColorRect.new()
	cb.position = Vector2(0, 0)
	cb.size = Vector2(180, 120)
	cb.color = Color("#f0e4d4")
	paint_canvas.add_child(cb)

	# ── 当前指令 ──
	step_label = Label.new()
	step_label.position = Vector2(18, 192)
	step_label.size = Vector2(564, 28)
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.add_theme_font_size_override("font_size", 18)
	step_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	step_label.text = "按 E 开始跳舞！"
	panel.add_child(step_label)

	# ── 6个箭头按钮 ──
	_make_arrow_buttons(panel)

	# ── 进度点 ──
	progress_dots.clear()
	for i in range(SEQUENCE_LEN):
		var dot := ColorRect.new()
		dot.position = Vector2(250 + i * 28, 418)
		dot.size = Vector2(16, 16)
		dot.color = Color("#4a3a30")
		panel.add_child(dot)
		progress_dots.append(dot)

	# ── 提示 ──
	var hint := Label.new()
	hint.name = "HintLabel"
	hint.position = Vector2(18, 450)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#887766"))
	hint.text = "按下对应方向键，同时按多键做组合舞步！按 E 关闭"
	panel.add_child(hint)

	# 关闭按钮
	var close := Button.new()
	close.text = "✕ 关闭"
	close.position = Vector2(530, 12)
	close.size = Vector2(56, 28)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(_close_room)
	panel.add_child(close)


func _on_paint_draw() -> void:
	_draw_stick(paint_canvas, pose_name, figure_center, 0.9)
	# 地面线
	paint_canvas.draw_line(Vector2(10, 100) + Vector2(0, -46) + figure_center,
		Vector2(170, 100) + Vector2(0, -46) + figure_center, Color("#ccbbaa"), 1.0)


# ════════════════════════════════════════════════════════════
#  画小人
# ════════════════════════════════════════════════════════════

func _draw_stick(cv: Control, pn: String, center: Vector2, scl: float) -> void:
	var body := Color("#3a3028")
	var head_c := Color("#5a4a38")
	var joint_c := Color("#ffaa66", 0.5)

	var p: Dictionary = POSES.get(pn, POSES["idle"])

	for key in ["head"]:
		cv.draw_circle(center + p[key] * scl, 8.0 * scl, head_c)
		cv.draw_arc(center + p[key] * scl, 7.0 * scl, 0, TAU, 16, body, 1.5 * scl)

	# Body
	cv.draw_line(center + p["neck"] * scl, center + p["hip"] * scl, body, 2.5 * scl)
	# Shoulder line
	cv.draw_line(center + p["shld_l"] * scl, center + p["shld_r"] * scl, body, 2.0 * scl)

	# Left arm
	cv.draw_line(center + p["shld_l"] * scl, center + p["elb_l"] * scl, body, 2.0 * scl)
	cv.draw_line(center + p["elb_l"] * scl, center + p["hand_l"] * scl, body, 2.0 * scl)
	# Right arm
	cv.draw_line(center + p["shld_r"] * scl, center + p["elb_r"] * scl, body, 2.0 * scl)
	cv.draw_line(center + p["elb_r"] * scl, center + p["hand_r"] * scl, body, 2.0 * scl)

	# Left leg
	cv.draw_line(center + p["hip_l"] * scl, center + p["knee_l"] * scl, body, 2.5 * scl)
	cv.draw_line(center + p["knee_l"] * scl, center + p["foot_l"] * scl, body, 2.5 * scl)
	# Right leg
	cv.draw_line(center + p["hip_r"] * scl, center + p["knee_r"] * scl, body, 2.5 * scl)
	cv.draw_line(center + p["knee_r"] * scl, center + p["foot_r"] * scl, body, 2.5 * scl)

	# Joint dots
	for k in ["elb_l", "elb_r", "knee_l", "knee_r"]:
		cv.draw_circle(center + p[k] * scl, 3.0 * scl, joint_c)


# ════════════════════════════════════════════════════════════
#  6个箭头按钮 — 画面指示，画箭头不用文字
# ════════════════════════════════════════════════════════════

func _make_arrow_buttons(panel: Panel) -> void:
	move_btns.clear()
	var btn_w := 88.0
	var btn_h := 68.0
	var start_x := 18.0
	var start_y := 228.0
	var gap_x := 10.0
	var gap_y := 8.0

	for i in range(DANCE_MOVES.size()):
		var dm := DANCE_MOVES[i]
		var col := i % 3
		var row := i / 3
		var bx := start_x + col * (btn_w + gap_x)
		var by := start_y + row * (btn_h + gap_y)

		var btn := Control.new()
		btn.position = Vector2(bx, by)
		btn.size = Vector2(btn_w, btn_h)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不拦截键盘事件
		btn.draw.connect(_on_btn_draw.bind(btn, i))
		panel.add_child(btn)
		move_btns.append(btn)

		# 按钮底部小标签
		var lbl := Label.new()
		lbl.text = str(dm["label"])
		lbl.position = Vector2(0, btn_h - 16)
		lbl.size = Vector2(btn_w, 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color("#998877"))
		btn.add_child(lbl)


func _on_btn_draw(btn: Control, idx: int) -> void:
	if idx >= DANCE_MOVES.size():
		return
	var dm := DANCE_MOVES[idx]
	var w := btn.size.x
	var h := btn.size.y
	var is_active := room_open and cur_step < dance_seq.size() and dance_seq[cur_step] == idx
	var btn_color: Color = dm["color"]
	var bg := Color("#3a3028")
	var border := Color("#5a4a3a")

	if is_active:
		bg = btn_color.darkened(0.7)
		border = btn_color
		border.a = 0.8

	# 背景
	btn.draw_rect(Rect2(Vector2.ZERO, btn.size), bg)
	# 边框
	btn.draw_rect(Rect2(Vector2(1, 1), btn.size - Vector2(2, 2)), border, false, 2.0)
	# 圆角效果（用4个小弧线模拟）
	btn.draw_arc(Vector2(4, 4), 4, PI, 1.5 * PI, 6, border, 2.0)
	btn.draw_arc(Vector2(w - 4, 4), 4, 1.5 * PI, TAU, 6, border, 2.0)
	btn.draw_arc(Vector2(4, h - 4), 4, 0.5 * PI, PI, 6, border, 2.0)
	btn.draw_arc(Vector2(w - 4, h - 4), 4, 0, 0.5 * PI, 6, border, 2.0)
	# 发光效果
	if is_active:
		btn.draw_rect(Rect2(Vector2(0, 0), btn.size), btn_color, false, 3.0)

	# 大箭头
	var arrow_text := str(dm["arrow"])
	var arr_lbl := Label.new()
	arr_lbl.text = arrow_text
	arr_lbl.add_theme_font_size_override("font_size", 28)
	arr_lbl.add_theme_color_override("font_color", btn_color if not is_active else Color.WHITE)
	arr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arr_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arr_lbl.position = Vector2(0, 2)
	arr_lbl.size = Vector2(w, h - 16)
	# We'll use draw_string via a simpler approach
	var font_size := 28
	# Draw centered text
	var tx := (w - font_size * 0.6 * float(len(arrow_text))) / 2.0
	var ty := (h - 16 - font_size) / 2.0 + 4
	btn.draw_string(ThemeDB.fallback_font, Vector2(tx, ty), arrow_text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, btn_color if not is_active else Color.WHITE)

	# 小按键提示
	var key_hint := _get_key_hint(idx)
	btn.draw_string(ThemeDB.fallback_font, Vector2(4, h - 30), key_hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#887766"))


func _get_key_hint(idx: int) -> String:
	var keys: Array = DANCE_MOVES[idx]["keys"]
	var parts: Array[String] = []
	for k in keys:
		match k:
			KEY_UP:    parts.append("↑")
			KEY_DOWN:  parts.append("↓")
			KEY_LEFT:  parts.append("←")
			KEY_RIGHT: parts.append("→")
	if parts.size() == 1:
		return str(parts[0])
	return str(parts[0]) + "+" + str(parts[1])


# ════════════════════════════════════════════════════════════
#  玩家进入/离开
# ════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_held.clear()


# ════════════════════════════════════════════════════════════
#  交互
# ════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return

	# E 键开关房间
	if event.is_action_pressed("interact"):
		if room_open:
			_close_room()
		else:
			_open_room()
		return

	# 只在房间打开且进行中处理按键
	if not room_open:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if not _held.has(event.keycode):
				_held.append(event.keycode)
			_check_dance_input()
		elif not event.pressed:
			_held.erase(event.keycode)


func _check_dance_input() -> void:
	if _step_solved:
		return
	if cur_step >= dance_seq.size():
		return

	var expected: Array = DANCE_MOVES[dance_seq[cur_step]]["keys"]
	# 按住键必须恰好包含所需键（不多不少）
	var expected_sorted := expected.duplicate()
	expected_sorted.sort()
	var held_sorted := _held.duplicate()
	held_sorted.sort()

	if expected_sorted == held_sorted:
		_step_solved = true
		_solve_timer = 0.0
		step_label.text = "✓ 正确！太棒了！"
		step_label.add_theme_color_override("font_color", Color("#88ff88"))
		hint_updated.emit("✓ 舞步 %d/%d 完成！" % [cur_step + 1, SEQUENCE_LEN])


# ════════════════════════════════════════════════════════════
#  _process
# ════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not room_open or is_completed:
		return

	# 小人姿势动画
	pose_time += delta
	if _step_solved:
		# 解决后跳一小段动画
		var move_idx := dance_seq[cur_step] if cur_step < dance_seq.size() else 0
		var move_id: String = DANCE_MOVES[move_idx]["id"]
		pose_name = move_id
		_solve_timer += delta
		if _solve_timer > 0.8:
			_step_solved = false
			_solve_timer = 0.0
			pose_name = "idle"
			cur_step += 1
			_held.clear()
			_update_progress()
			if cur_step >= dance_seq.size():
				_on_complete()
			else:
				_show_current_step()
	else:
		# 正常呼吸动画
		pose_name = "idle"
		if fmod(pose_time, 3.0) < 0.3:
			pose_name = "jump"

	paint_canvas.queue_redraw()
	for btn in move_btns:
		if is_instance_valid(btn):
			btn.queue_redraw()


# ════════════════════════════════════════════════════════════
#  房间开关
# ════════════════════════════════════════════════════════════

func _open_room() -> void:
	room_open = true
	overlay.visible = true
	_freeze_player(true)
	room_toggled.emit(true)
	# 同步视角
	var player := _get_player()
	if player != null and "current_view" in player:
		current_view = str(player.current_view)
	# 开始跳舞
	_start_dance()


func _close_room() -> void:
	room_open = false
	overlay.visible = false
	_freeze_player(false)
	room_toggled.emit(false)
	_held.clear()
	_step_solved = false


func _start_dance() -> void:
	# 生成随机舞步序列
	dance_seq.clear()
	for _i in range(SEQUENCE_LEN):
		dance_seq.append(randi() % DANCE_MOVES.size())
	cur_step = 0
	_held.clear()
	_step_solved = false
	pose_name = "idle"
	pose_time = 0.0
	_update_progress()
	_show_current_step()
	hint_updated.emit("跟着小人学跳舞！按下箭头键来做动作")


func _show_current_step() -> void:
	if cur_step >= dance_seq.size():
		return
	var dm := DANCE_MOVES[dance_seq[cur_step]]
	step_label.text = "第 %d 步 — 同时按下:  %s" % [cur_step + 1, _get_key_hint(dance_seq[cur_step])]
	step_label.add_theme_color_override("font_color", dm["color"])
	for i in range(move_btns.size()):
		move_btns[i].queue_redraw()


func _update_progress() -> void:
	for i in range(SEQUENCE_LEN):
		if i < progress_dots.size():
			if i < cur_step:
				progress_dots[i].color = Color("#88ff88")
			elif i == cur_step and cur_step < SEQUENCE_LEN:
				progress_dots[i].color = Color("#ffaa44")
			else:
				progress_dots[i].color = Color("#4a3a30")


# ════════════════════════════════════════════════════════════
#  完成
# ════════════════════════════════════════════════════════════

func _on_complete() -> void:
	is_completed = true
	step_label.text = "✨ 舞步完成！获得宴会厅钥匙！"
	step_label.add_theme_color_override("font_color", Color("#ffd700"))
	hint_updated.emit("✨ 你获得了钥匙1！")
	pose_name = "jump"

	var hlb: Label = get_node_or_null("HintLabel") as Label
	if is_instance_valid(hlb):
		hlb.text = "✓ 已完成 — 钥匙1已获取"

	# 2秒后自动关闭
	get_tree().create_timer(2.0).timeout.connect(func():
		if room_open:
			_close_room()
	)
	puzzle_completed.emit("key_1")


# ════════════════════════════════════════════════════════════
#  视角同步（记忆长椅）
# ════════════════════════════════════════════════════════════

func update_on_view_change(view: String) -> void:
	current_view = view

func _sync_initial_view() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_view"):
		update_on_view_change(main.get_view())


# ════════════════════════════════════════════════════════════
#  辅助
# ════════════════════════════════════════════════════════════

func _freeze_player(freeze: bool) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if "controls_enabled" in node:
			node.controls_enabled = not freeze

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func is_solved() -> bool:
	return is_completed
