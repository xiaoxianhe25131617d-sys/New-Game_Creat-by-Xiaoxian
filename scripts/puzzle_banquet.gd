extends Area2D
class_name PuzzleBanquetPainting

# ════════════════════════════════════════════════════════════
#  油画舞步 — 跟着画中小人学跳舞
#  6个按钮：→ 向前走 / ↑ 向前跳 / ↑+→ 向前大跳
#          ← 向后走 / ↓ 向后跳 / ↓+← 向后大跳
#  不显示字母，不做单步对错判断，全部对了才通关
#  正确答案（7步）：A→B↑E↓C↑+→B↑D←F↓+←
#  普通模式：乱糟糟的衣服花纹
#  抑郁/自闭模式：小人演示舞步动画
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)
signal room_toggled(open: bool)

# ── 6种舞步定义 ──
# A:向前走  B:向前跳  C:向前大跳  D:向后走  E:向后跳  F:向后大跳
const DANCE_KEYS := [KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_LEFT]
const DANCE_MOVES: Array[Dictionary] = [
	{"id": "fwd_walk",   "arrow": "→",   "combo": [KEY_RIGHT],               "color": Color("#ff7755"), "hint_ka": "→",      "desc": "向前走"},
	{"id": "fwd_jump",   "arrow": "↑",   "combo": [KEY_UP],                  "color": Color("#55cc55"), "hint_ka": "↑",      "desc": "向前跳"},
	{"id": "fwd_big",    "arrow": "↗",   "combo": [KEY_UP, KEY_RIGHT],       "color": Color("#ffaa22"), "hint_ka": "↑+→",   "desc": "向前大跳"},
	{"id": "bwd_walk",   "arrow": "←",   "combo": [KEY_LEFT],                "color": Color("#5588ff"), "hint_ka": "←",      "desc": "向后走"},
	{"id": "bwd_jump",   "arrow": "↓",   "combo": [KEY_DOWN],                "color": Color("#ff55aa"), "hint_ka": "↓",      "desc": "向后跳"},
	{"id": "bwd_big",    "arrow": "↙",   "combo": [KEY_DOWN, KEY_LEFT],      "color": Color("#aa44ff"), "hint_ka": "↓+←",   "desc": "向后大跳"},
]

# 正确答案 ABECBDF = 向前走 向前跳 向后跳 向前大跳 向前跳 向后走 向后大跳
const CORRECT_SEQ: Array = [0, 1, 4, 2, 1, 3, 5]  # A B E C B D F

# 示范动画 (6步)：向前走 向前大跳 向后跳 向后走 向前跳 向前跳
const DEMO_SEQ: Array = [0, 2, 4, 3, 1, 1]  # A C E D B B

const ANSWER_LEN := 7
const DEMO_LEN := 6

# ── 状态 ──
var player_in_range := false
var is_completed := false
var room_open := false
var current_view := "normal"

var input_buffer: Array[int] = []   # 玩家输入的舞步索引序列
var is_demo_playing := false
var demo_step := 0
var demo_timer := 0.0
const DEMO_STEP_DURATION := 1.2

# 多键检测
var _held: Array[int] = []
var _peak_held: Array[int] = []
var _shake_timer := 0.0

# ── UI ──
var overlay: CanvasLayer = null
var paint_canvas: Control = null
var step_label: Label = null
var move_btns: Array[Control] = []
var input_dots: Array[ColorRect] = []
var _vfx_t := 0.0

# 小人画布大小
const FIGURE_W := 200.0
const FIGURE_H := 140.0
const FIGURE_CX := 100.0
const FIGURE_CY := 80.0


# ════════════════════════════════════════════════════════════
#  小人关节姿势
# ════════════════════════════════════════════════════════════

func _get_pose(move_id: String) -> Dictionary:
	match move_id:
		"fwd_walk":
			return {"head": V2(12,-48), "neck": V2(8,-37), "hip": V2(6,5),
				"shld_l": V2(-8,-30), "shld_r": V2(18,-28),
				"elb_l": V2(-14,-12), "elb_r": V2(26,-8),
				"hand_l": V2(-10,2),  "hand_r": V2(30,10),
				"knee_l": V2(-4,24),  "knee_r": V2(16,24),
				"foot_l": V2(-2,42),  "foot_r": V2(20,44)}
		"fwd_jump":
			return {"head": V2(4,-56), "neck": V2(4,-46), "hip": V2(2,-5),
				"shld_l": V2(-12,-40), "shld_r": V2(16,-38),
				"elb_l": V2(-18,-52), "elb_r": V2(24,-50),
				"hand_l": V2(-14,-64), "hand_r": V2(28,-62),
				"knee_l": V2(-4,12),  "knee_r": V2(10,14),
				"foot_l": V2(-8,26),  "foot_r": V2(14,28)}
		"fwd_big":
			return {"head": V2(10,-64), "neck": V2(8,-54), "hip": V2(6,-12),
				"shld_l": V2(-10,-46), "shld_r": V2(22,-44),
				"elb_l": V2(-16,-60), "elb_r": V2(32,-56),
				"hand_l": V2(-12,-74), "hand_r": V2(38,-68),
				"knee_l": V2(2,8),   "knee_r": V2(18,12),
				"foot_l": V2(-6,24),  "foot_r": V2(22,28)}
		"bwd_walk":
			return {"head": V2(-12,-48), "neck": V2(-8,-37), "hip": V2(-6,5),
				"shld_l": V2(-18,-28), "shld_r": V2(8,-30),
				"elb_l": V2(-26,-8), "elb_r": V2(14,-12),
				"hand_l": V2(-30,10), "hand_r": V2(10,2),
				"knee_l": V2(-16,24), "knee_r": V2(4,24),
				"foot_l": V2(-20,44), "foot_r": V2(2,42)}
		"bwd_jump":
			return {"head": V2(-4,-56), "neck": V2(-4,-46), "hip": V2(-2,-5),
				"shld_l": V2(-16,-38), "shld_r": V2(12,-40),
				"elb_l": V2(-24,-50), "elb_r": V2(18,-52),
				"hand_l": V2(-28,-62), "hand_r": V2(14,-64),
				"knee_l": V2(-10,14), "knee_r": V2(4,12),
				"foot_l": V2(-14,28), "foot_r": V2(8,26)}
		"bwd_big":
			return {"head": V2(-10,-64), "neck": V2(-8,-54), "hip": V2(-6,-12),
				"shld_l": V2(-22,-44), "shld_r": V2(10,-46),
				"elb_l": V2(-32,-56), "elb_r": V2(16,-60),
				"hand_l": V2(-38,-68), "hand_r": V2(12,-74),
				"knee_l": V2(-18,12), "knee_r": V2(-2,8),
				"foot_l": V2(-22,28), "foot_r": V2(6,24)}
	return {}


# ════════════════════════════════════════════════════════════
#  _ready
# ════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("interactable")
	z_index = 10

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(240, 190)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)

	_make_world_appearance()
	_make_overlay()
	call_deferred("_sync_initial_view")


# ════════════════════════════════════════════════════════════
#  世界中的油画建筑外观
# ════════════════════════════════════════════════════════════

func _make_world_appearance() -> void:
	var hall := Polygon2D.new()
	hall.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(180, 0),
		Vector2(180, 140), Vector2(0, 140)
	])
	hall.color = Color("#8a7060")
	hall.offset = Vector2(-90, -105)
	add_child(hall)

	var frame := ColorRect.new()
	frame.position = Vector2(-68, -80)
	frame.size = Vector2(136, 100)
	frame.color = Color("#5a4030")
	add_child(frame)

	var cb := ColorRect.new()
	cb.position = Vector2(-60, -72)
	cb.size = Vector2(120, 84)
	cb.color = Color("#e8d8c8")
	add_child(cb)

	# 普通模式下的乱衣预览
	var preview := Control.new()
	preview.name = "WorldPreview"
	preview.position = Vector2(-60, -72)
	preview.size = Vector2(120, 84)
	preview.draw.connect(_on_world_preview_draw.bind(preview))
	add_child(preview)

	var title := Label.new()
	title.text = "油画"
	title.position = Vector2(-30, -94)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)


func _on_world_preview_draw(cv: Control) -> void:
	if current_view == "normal":
		_draw_messy_clothes(cv, Vector2(60, 48), 0.55)
	else:
		var move_id := DANCE_MOVES[CORRECT_SEQ[0]]["id"]
		_draw_stick(cv, move_id, Vector2(60, 48), 0.6)


# ════════════════════════════════════════════════════════════
#  Overlay
# ════════════════════════════════════════════════════════════

func _make_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 10
	overlay.visible = false
	add_child(overlay)

	var bg := ColorRect.new()
	bg.size = Vector2(1152, 648)
	bg.color = Color(0, 0, 0, 0.6)
	overlay.add_child(bg)

	# 主面板
	var panel := Panel.new()
	panel.position = Vector2(251, 64)
	panel.size = Vector2(650, 520)
	var ps := StyleBoxFlat.new()
	ps.set_corner_radius_all(14)
	ps.bg_color = Color("#2a2218")
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#6a5040")
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var ttl := Label.new()
	ttl.text = "🖼 油画 — 跟着小人学跳舞"
	ttl.position = Vector2(20, 14)
	ttl.add_theme_font_size_override("font_size", 18)
	ttl.add_theme_color_override("font_color", Color("#d4c4a4"))
	panel.add_child(ttl)

	# ── 画框+小人 ──
	var outer := ColorRect.new()
	outer.position = Vector2(20, 46)
	outer.size = Vector2(FIGURE_W + 16, FIGURE_H + 16)
	outer.color = Color("#4a3020")
	panel.add_child(outer)
	var inner := ColorRect.new()
	inner.position = Vector2(26, 52)
	inner.size = Vector2(FIGURE_W + 4, FIGURE_H + 4)
	inner.color = Color("#6a4a30")
	panel.add_child(inner)

	paint_canvas = Control.new()
	paint_canvas.name = "PaintCanvas"
	paint_canvas.position = Vector2(28, 54)
	paint_canvas.size = Vector2(FIGURE_W, FIGURE_H)
	var cnv_bg := ColorRect.new()
	cnv_bg.position = Vector2.ZERO
	cnv_bg.size = Vector2(FIGURE_W, FIGURE_H)
	cnv_bg.color = Color("#f0e4d4")
	paint_canvas.add_child(cnv_bg)
	paint_canvas.draw.connect(_on_paint_draw)
	paint_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(paint_canvas)

	# ── 步骤提示 ──
	step_label = Label.new()
	step_label.position = Vector2(20, 200)
	step_label.size = Vector2(610, 26)
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_label.add_theme_font_size_override("font_size", 17)
	step_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	step_label.text = "切换抑郁/自闭视角后，观察示范动画"
	panel.add_child(step_label)

	# ── 6个箭头按钮 ──
	_make_arrow_buttons(panel)

	# ── 7步输入进度 ──
	input_dots.clear()
	for i in range(ANSWER_LEN):
		var dot := ColorRect.new()
		dot.position = Vector2(250 + i * 30, 430)
		dot.size = Vector2(18, 18)
		dot.color = Color("#4a3a30")
		panel.add_child(dot)
		input_dots.append(dot)

	# 提示
	var hint := Label.new()
	hint.name = "HintLabel"
	hint.position = Vector2(20, 462)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#887766"))
	hint.text = "按箭头顺序踩下按键。按 E 关闭。全部对才通关！"
	panel.add_child(hint)

	var close := Button.new()
	close.text = "✕ 关闭"
	close.position = Vector2(580, 12)
	close.size = Vector2(56, 28)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(_close_room)
	panel.add_child(close)


func _on_paint_draw() -> void:
	if is_demo_playing:
		var move_id: String = DANCE_MOVES[DEMO_SEQ[demo_step]]["id"]
		_draw_stick(paint_canvas, move_id, Vector2(100, 80), 1.05)
	elif input_buffer.size() > 0:
		var last := input_buffer[input_buffer.size() - 1]
		var move_id: String = DANCE_MOVES[last]["id"]
		_draw_stick(paint_canvas, move_id, Vector2(100, 80), 1.05)
	elif current_view == "normal":
		_draw_messy_clothes(paint_canvas, Vector2(100, 70), 1.0)
	else:
		_draw_stick(paint_canvas, "fwd_walk", Vector2(100, 80), 1.05)
	# 地面线
	paint_canvas.draw_line(Vector2(10, 120), Vector2(190, 120), Color("#ccbbaa"), 1.0)


# ════════════════════════════════════════════════════════════
#  乱衣绘制（普通模式）
# ════════════════════════════════════════════════════════════

func _draw_messy_clothes(cv: Control, center: Vector2, scl: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # 固定种子让每次绘制一致

	# 杂乱的布料色块
	var cloth_colors: Array[Color] = [
		Color("#c04040"), Color("#4080c0"), Color("#c0a040"),
		Color("#40c060"), Color("#8040a0"), Color("#c06020"),
		Color("#2090a0"), Color("#a06080")
	]

	# 不规则多边形模拟褶皱
	for _k in range(18):
		var cc := cloth_colors[rng.randi() % cloth_colors.size()]
		cc.a = 0.55 + rng.randf() * 0.35
		var cx := center.x + (rng.randf() - 0.5) * 160.0 * scl
		var cy := center.y + (rng.randf() - 0.5) * 110.0 * scl
		var pts := PackedVector2Array()
		var n := 3 + rng.randi() % 4
		for j in range(n):
			var a := TAU * j / float(n) + rng.randf() * 0.5
			var r := (12 + rng.randf() * 35) * scl
			pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
		cv.draw_colored_polygon(pts, cc)

	# 散乱的线条
	for _k in range(20):
		var lc := Color(0.1, 0.1, 0.15, 0.3 + rng.randf() * 0.3)
		var x1 := center.x + (rng.randf() - 0.5) * 170 * scl
		var y1 := center.y + (rng.randf() - 0.5) * 120 * scl
		var x2 := x1 + (rng.randf() - 0.5) * 60 * scl
		var y2 := y1 + (rng.randf() - 0.5) * 50 * scl
		cv.draw_line(Vector2(x1, y1), Vector2(x2, y2), lc, 1.0 + rng.randf() * 2.5, true)

	# 零星的纽扣/装饰
	for _k in range(5):
		var cx := center.x + (rng.randf() - 0.5) * 140 * scl
		var cy := center.y + (rng.randf() - 0.5) * 90 * scl
		cv.draw_circle(Vector2(cx, cy), 3 + rng.randf() * 3, Color("#ddd8cc"), true, 2.0)


# ════════════════════════════════════════════════════════════
#  画小人
# ════════════════════════════════════════════════════════════

func _draw_stick(cv: Control, move_id: String, center: Vector2, scl: float) -> void:
	var p: Dictionary = _get_pose(move_id)
	if p.is_empty():
		p = _get_pose("fwd_walk")

	var body := Color("#3a3028")
	var hl := Color("#ffaa66", 0.5)

	var head_key := "head"
	var neck_key := "neck"
	# keys in pose
	cv.draw_circle(center + p["head"] * scl, 9.0 * scl, Color("#5a4a38"))
	cv.draw_arc(center + p["head"] * scl, 8.0 * scl, 0, TAU, 16, body, 1.8 * scl)
	# body
	cv.draw_line(center + p["neck"] * scl, center + p["hip"] * scl, body, 3.0 * scl)
	cv.draw_line(center + p["shld_l"] * scl, center + p["shld_r"] * scl, body, 2.5 * scl)

	# arms
	cv.draw_line(center + p["shld_l"] * scl, center + p["elb_l"] * scl, body, 2.5 * scl)
	cv.draw_line(center + p["elb_l"] * scl, center + p["hand_l"] * scl, body, 2.5 * scl)
	cv.draw_line(center + p["shld_r"] * scl, center + p["elb_r"] * scl, body, 2.5 * scl)
	cv.draw_line(center + p["elb_r"] * scl, center + p["hand_r"] * scl, body, 2.5 * scl)

	# legs
	cv.draw_line(center + p["hip"] * scl, center + p["knee_l"] * scl, body, 3.0 * scl)
	cv.draw_line(center + p["knee_l"] * scl, center + p["foot_l"] * scl, body, 3.0 * scl)
	cv.draw_line(center + p["hip"] * scl, center + p["knee_r"] * scl, body, 3.0 * scl)
	cv.draw_line(center + p["knee_r"] * scl, center + p["foot_r"] * scl, body, 3.0 * scl)

	# joints
	for k in ["elb_l","elb_r","knee_l","knee_r"]:
		if k in p:
			cv.draw_circle(center + p[k] * scl, 3.5 * scl, hl)

	# feet
	if "foot_l" in p:
		cv.draw_circle(center + p["foot_l"] * scl, 4.0 * scl, body)
	if "foot_r" in p:
		cv.draw_circle(center + p["foot_r"] * scl, 4.0 * scl, body)


# ════════════════════════════════════════════════════════════
#  6个箭头按钮
# ════════════════════════════════════════════════════════════

func _make_arrow_buttons(panel: Panel) -> void:
	move_btns.clear()
	var btn_w := 180.0
	var btn_h := 54.0
	var start_y := 236.0
	var gap := 6.0
	# 2列 × 3行
	var cols := 2
	for i in range(DANCE_MOVES.size()):
		var dm := DANCE_MOVES[i]
		var col := i % cols
		var row := i / cols
		var bx := 20.0 + col * (btn_w + 20)
		var by := start_y + row * (btn_h + gap)

		var btn := Control.new()
		btn.position = Vector2(bx, by)
		btn.size = Vector2(btn_w, btn_h)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.draw.connect(_on_btn_draw.bind(btn, i))
		panel.add_child(btn)
		move_btns.append(btn)


func _on_btn_draw(btn: Control, idx: int) -> void:
	if idx >= DANCE_MOVES.size(): return
	var dm := DANCE_MOVES[idx]
	var w := btn.size.x
	var h := btn.size.y
	var color: Color = dm["color"]
	var bg := Color("#282018")
	var border := Color("#4a3a30")

	# 判断是否高亮
	var hl := false
	if is_demo_playing and demo_step < DEMO_SEQ.size() and DEMO_SEQ[demo_step] == idx:
		hl = true

	if hl:
		bg = color.darkened(0.6)
		border = color
		border.a = 0.9

	# 背景
	btn.draw_rect(Rect2(Vector2.ZERO, btn.size), bg)
	btn.draw_rect(Rect2(Vector2(1, 1), btn.size - Vector2(2, 2)), border, false, 2.0)

	if hl:
		btn.draw_rect(Rect2(Vector2(0, 0), btn.size), color, false, 3.0)

	# 大箭头 + 说明文字
	var arrow := str(dm["arrow"])
	var ka := str(dm["hint_ka"])
	var desc := str(dm["desc"])
	var text_color := Color.WHITE if hl else color

	# 左半边：大箭头
	var arrow_x := 12.0
	var arrow_size := 32
	btn.draw_string(ThemeDB.fallback_font, Vector2(arrow_x, (h - arrow_size) / 2.0 + 6), arrow,
		HORIZONTAL_ALIGNMENT_LEFT, -1, arrow_size, text_color)

	# 右半边：按键提示 + 说明
	btn.draw_string(ThemeDB.fallback_font, Vector2(60, 8), ka,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, text_color)
	btn.draw_string(ThemeDB.fallback_font, Vector2(60, 32), desc,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#998877") if not hl else Color("#d4c4a4"))


# ════════════════════════════════════════════════════════════
#  交互
# ════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_held.clear()
		_peak_held.clear()


func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed: return

	if event.is_action_pressed("interact"):
		if room_open:
			_close_room()
		else:
			_open_room()
		return

	if not room_open or is_demo_playing: return

	if event is InputEventKey:
		var kc: Key = event.keycode
		if not (kc in DANCE_KEYS): return

		if event.pressed and not event.echo:
			if not _held.has(kc):
				_held.append(kc)
			_peak_held = _held.duplicate()
		elif not event.pressed:
			_held.erase(kc)
			if _held.size() == 0 and _peak_held.size() > 0:
				_on_key_combo(_peak_held)
				_peak_held.clear()


func _on_key_combo(combo: Array) -> void:
	# 匹配舞步
	var match_idx := -1
	for i in range(DANCE_MOVES.size()):
		var expected: Array = DANCE_MOVES[i]["combo"]
		if _arrays_equal(expected, combo):
			match_idx = i
			break
	if match_idx == -1: return

	input_buffer.append(match_idx)
	_update_input_dots()
	paint_canvas.queue_redraw()
	# 按钮闪一下
	for btn in move_btns:
		if is_instance_valid(btn):
			btn.queue_redraw()

	if input_buffer.size() >= ANSWER_LEN:
		_check_answer()


func _check_answer() -> void:
	var correct := true
	for i in range(ANSWER_LEN):
		if input_buffer[i] != CORRECT_SEQ[i]:
			correct = false
			break

	if correct:
		_on_complete()
	else:
		# 错误：重置，画布抖动
		_shake_timer = 0.4
		step_label.text = "好像不太对……再试一次"
		step_label.add_theme_color_override("font_color", Color("#ff6666"))
		hint_updated.emit("舞步不对，重新尝试……")
		input_buffer.clear()
		_update_input_dots()
		get_tree().create_timer(0.5).timeout.connect(func():
			if room_open and not is_completed and not is_demo_playing:
				step_label.text = "按箭头顺序踩下按键 (%d步)" % ANSWER_LEN
				step_label.add_theme_color_override("font_color", Color("#ffe8a0"))
		)


func _update_input_dots() -> void:
	for i in range(ANSWER_LEN):
		if i < input_dots.size():
			input_dots[i].color = Color("#4a3a30")
	for i in range(input_buffer.size()):
		if i < input_dots.size():
			var mi := input_buffer[i]
			if mi >= 0 and mi < DANCE_MOVES.size():
				input_dots[i].color = DANCE_MOVES[mi]["color"]


# ════════════════════════════════════════════════════════════
#  房间开关
# ════════════════════════════════════════════════════════════

func _open_room() -> void:
	room_open = true
	overlay.visible = true
	_freeze_player(true)
	room_toggled.emit(true)

	var player := _get_player()
	if player != null and "current_view" in player:
		current_view = str(player.current_view)

	input_buffer.clear()
	_held.clear()
	_peak_held.clear()
	_update_input_dots()

	if current_view == "normal":
		# 普通模式：乱衣
		step_label.text = "画上只是一团乱衣……换个视角试试"
		step_label.add_theme_color_override("font_color", Color("#887766"))
		hint_updated.emit("油画上的图案模糊不清——去记忆长椅换抑郁/自闭视角")
	else:
		# 抑郁/自闭：播放示范动画
		_start_demo()


func _close_room() -> void:
	room_open = false
	is_demo_playing = false
	overlay.visible = false
	_freeze_player(false)
	room_toggled.emit(false)
	_held.clear()
	_peak_held.clear()


func _start_demo() -> void:
	is_demo_playing = true
	demo_step = 0
	demo_timer = 0.0
	input_buffer.clear()
	_update_input_dots()
	step_label.text = "观察示范舞步…（第1步）"
	step_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_updated.emit("仔细观察油画中小人的舞步顺序……")


# ════════════════════════════════════════════════════════════
#  _process
# ════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not room_open or is_completed: return

	_vfx_t += delta

	# 抖动效果
	if _shake_timer > 0:
		_shake_timer -= delta
		var sx := sin(_vfx_t * 40) * 4.0
		var sy := cos(_vfx_t * 37) * 3.0
		if is_instance_valid(paint_canvas):
			paint_canvas.position = Vector2(28 + sx, 54 + sy)
	elif is_instance_valid(paint_canvas):
		paint_canvas.position = Vector2(28, 54)

	# 示范动画
	if is_demo_playing:
		demo_timer += delta
		if demo_timer >= DEMO_STEP_DURATION:
			demo_timer -= DEMO_STEP_DURATION
			demo_step += 1
			if demo_step >= DEMO_SEQ.size():
				# 示范结束，进入输入模式
				is_demo_playing = false
				demo_step = 0
				input_buffer.clear()
				_held.clear()
				_peak_held.clear()
				_update_input_dots()
				for btn in move_btns:
					if is_instance_valid(btn): btn.queue_redraw()
				step_label.text = "现在跟着跳！（%d步）" % ANSWER_LEN
				step_label.add_theme_color_override("font_color", Color("#55ff88"))
				hint_updated.emit("现在该你了！按箭头顺序踩按键。")
			else:
				step_label.text = "观察示范舞步…（第%d步）" % [demo_step + 1]
				for btn in move_btns:
					if is_instance_valid(btn): btn.queue_redraw()

		paint_canvas.queue_redraw()
		# 示范时高亮对应按钮
		for btn in move_btns:
			if is_instance_valid(btn): btn.queue_redraw()


# ════════════════════════════════════════════════════════════
#  完成
# ════════════════════════════════════════════════════════════

func _on_complete() -> void:
	is_completed = true
	step_label.text = "✨ 全部正确！舞步完成！"
	step_label.add_theme_color_override("font_color", Color("#ffd700"))
	input_buffer.clear()
	_update_input_dots()
	paint_canvas.queue_redraw()
	hint_updated.emit("✨ 你获得了钥匙1！")

	var hlb: Label = overlay.get_node_or_null("HintLabel") as Label
	if is_instance_valid(hlb):
		hlb.text = "✓ 完成 — 获得宴会厅钥匙"

	get_tree().create_timer(2.0).timeout.connect(func():
		if room_open:
			_close_room()
	)
	puzzle_completed.emit("key_1")


# ════════════════════════════════════════════════════════════
#  视角同步
# ════════════════════════════════════════════════════════════

func update_on_view_change(view: String) -> void:
	current_view = view
	var preview: Control = get_node_or_null("WorldPreview") as Control
	if is_instance_valid(preview):
		preview.queue_redraw()
	# 如果房间开着，重新根据视角决定显示内容
	if room_open:
		if view != "normal":
			if not is_demo_playing and input_buffer.size() == 0 and not is_completed:
				_start_demo()
		else:
			is_demo_playing = false
			step_label.text = "画上只是一团乱衣……换个视角试试"
			step_label.add_theme_color_override("font_color", Color("#887766"))


func _sync_initial_view() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_view"):
		update_on_view_change(main.get_view())


# ════════════════════════════════════════════════════════════
#  辅助
# ════════════════════════════════════════════════════════════

func V2(x: float, y: float) -> Vector2:
	return Vector2(x, y)

func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	var sa := a.duplicate(); sa.sort()
	var sb := b.duplicate(); sb.sort()
	return sa == sb

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
