extends Area2D
class_name PuzzleBanquetPainting

# ════════════════════════════════════════════════════════════
#  油画舞步 — 地面可踩按钮 + 小画布循环播放示范
#  6个地面按钮（无文字），玩家走上去踩
#  画布中火柴人循环播放：向前走→向前大跳→向后跳→向后走→向前跳→向前跳
#  答案 ABECBDF（7步），全部对才通关，无单步反馈
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)
signal room_toggled(open: bool)

# ── 6个地面按钮→6种舞步 ──
# 按钮0=A:向前走 1=B:向前跳 2=C:向后跳 3=D:向后走 4=E:向前大跳 5=F:向后大跳
const MOVE_COLORS := [
	Color("#ff7755"), Color("#55cc55"), Color("#5588ff"),
	Color("#aacc44"), Color("#ffaa22"), Color("#aa44ff"),
]
const MOVE_IDS := ["fwd_walk","fwd_jump","bwd_jump","bwd_walk","fwd_big","bwd_big"]

# 答案 ABECBDF → idx: 0,1,4,2,1,3,5
const CORRECT_SEQ: Array = [0, 1, 4, 2, 1, 3, 5]
# 示范动画循环: 向前走→向前大跳→向后跳→向后走→向前跳→向前跳
const DEMO_SEQ: Array = [0, 4, 2, 3, 1, 1]

const ANSWER_LEN := 7
const DEMO_LEN := 6
const DEMO_STEP_DURATION := 1.1
const DEMO_GAP_DURATION := 0.28
const BUTTON_SETTLE_TIME := 0.18
const BUTTON_CENTER_MARGIN := 0.70
const BUTTON_PRESS_OFFSET := 4.0

# 画布尺寸
const CANVAS_W := 280.0
const CANVAS_H := 170.0
const GROUND_Y := 140.0

# 布局
const BTN_W := 56.0
const BTN_H := 18.0
const BTN_SPACING := 64.0
const BTN_Y := 55.0
const RESET_PEDESTAL_W := 32.0
const FRAME_Y := -170.0
const FRAME_H := 180.0

var circle_x: Array[float] = []

# 状态
var player_in_range := false
var is_completed := false
var current_view := "normal"
var step_buffer: Array[int] = []
var is_demo_playing := false
var demo_step := 0
var demo_timer := 0.0
var is_waiting_input := false
var demo_complete_count := 0   # 示范完整播放次数（需≥1才能按E开始踩）
var _is_blanking := false       # 循环结束后短暂空白一帧（标记循环边界）
var _shake_timer := 0.0
var _last_stepped := -1
var _vfx_t := 0.0

# 世界节点
var paint_canvas: Control = null
var check_icon: Label = null
var status_label: Label = null
var button_glows: Array[ColorRect] = []
var button_tops: Array[ColorRect] = []   # 每个按钮的顶面（踩下时下移）
var button_sensors: Array[Area2D] = []
var button_press_timers: Array[float] = []
var button_pressed: Array[bool] = []
var step_dots: Array[ColorRect] = []
var reset_zone: Area2D = null
var near_reset: bool = false
var _house_front: Sprite2D
var _house_back: Sprite2D

const HOUSE_FRONT_TEXTURE := preload("res://assets/houses/banquet_gallery_front.png")
const HOUSE_BACK_TEXTURE := preload("res://assets/houses/banquet_gallery_back.png")
const ABSTRACT_PAINTING_TEXTURE := preload("res://assets/environment/generated/banquet_abstract_painting.svg")
const DANCE_HALL_SCALE := Vector2(0.52, 0.52)
const DANCE_HALL_POSITION := Vector2(-327.0, -452.0)
const DANCE_HALL_BACK_SCALE := Vector2(0.521353, 0.494392)
const DANCE_HALL_BACK_POSITION := Vector2(-328.108, -434.666)


# ═══════════════ 骨骼姿势（6种舞步，方向用左右脚不对称表现）═══════════════
# 向前 = 左脚竖直锚定，右脚向前/右迈出（从玩家视角看，左脚是"这边"，右脚往外跨）
# 向后 = 右脚竖直锚定，左脚向后/左迈出
# 大跳 = 迈出的脚跨得更开 + 身体腾空更高

func _get_pose(move_id: String) -> Dictionary:
	match move_id:
		# 向前走：左脚近身竖直，右脚向前迈出
		"fwd_walk": return _p(
			0,-50, 0,-40, 0,0,
			-10,-32, 10,-32,
			-10,-18, 16,-20,
			-12,-6, 22,-8,
			-4,14, 12,16,
			-6,30, 24,32)
		# 向前小跳：左脚竖直锚地，右脚向前跨出跳跃
		"fwd_jump": return _p(
			0,-58, 0,-48, 0,-6,
			-10,-40, 10,-40,
			-10,-28, 18,-30,
			-14,-18, 26,-20,
			-4,6, 16,8,
			-8,24, 30,26)
		# 向前大跳：左脚竖直，右脚大跨 + 身体高高腾空
		"fwd_big": return _p(
			0,-66, 0,-56, 0,-12,
			-12,-48, 12,-48,
			-12,-38, 22,-40,
			-18,-28, 30,-30,
			-6,-2, 20,2,
			-10,16, 40,18)
		# 向后走：右脚近身竖直，左脚向后迈出
		"bwd_walk": return _p(
			0,-50, 0,-40, 0,0,
			-10,-32, 10,-32,
			-16,-20, 10,-18,
			-22,-8, 12,-6,
			-12,16, 4,14,
			-24,32, 6,30)
		# 向后小跳：右脚竖直，左脚向后跨出
		"bwd_jump": return _p(
			0,-58, 0,-48, 0,-6,
			-10,-40, 10,-40,
			-18,-30, 10,-28,
			-26,-20, 14,-18,
			-16,8, 4,6,
			-30,26, 8,24)
		# 向后大跳：右脚竖直，左脚大跨 + 腾空
		"bwd_big": return _p(
			0,-66, 0,-56, 0,-12,
			-12,-48, 12,-48,
			-22,-40, 12,-38,
			-30,-30, 18,-28,
			-20,2, 6,-2,
			-40,18, 10,16)
	return {}

func _p(hx,hy, nx,ny, hpx,hpy, slx,sly, srx,sry, elx,ely, erx,ery, hlx,hly, hrx,hry, klx,kly, krx,kry, flx,fly, frx,fry) -> Dictionary:
	return {"head":V2(hx,hy),"neck":V2(nx,ny),"hip":V2(hpx,hpy),"shld_l":V2(slx,sly),"shld_r":V2(srx,sry),
		"elb_l":V2(elx,ely),"elb_r":V2(erx,ery),"hand_l":V2(hlx,hly),"hand_r":V2(hrx,hry),
		"knee_l":V2(klx,kly),"knee_r":V2(krx,kry),"foot_l":V2(flx,fly),"foot_r":V2(frx,fry)}


# ═══════════════ _ready ═══════════════

func _ready() -> void:
	add_to_group("interactable")
	z_index = 10
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(440, 260)
	shape.shape = rect
	shape.position = Vector2(0, -20)
	add_child(shape)
	_make_house_layers()

	# 画布内6个圆圈X位置
	var total_w := BTN_SPACING * 5.0
	var sx := (CANVAS_W - total_w) / 2.0
	for i in range(6):
		circle_x.append(sx + i * BTN_SPACING)

	_build_painting()
	_build_ground_buttons()
	_build_status_ui()
	_build_reset_pedestal()
	# 一创建就开始循环示范动画，不需要走近触发
	if not is_completed and not is_demo_playing and not is_waiting_input:
		_start_demo()
	call_deferred("_sync_initial_view")

func _make_house_layers() -> void:
	_house_back = Sprite2D.new()
	_house_back.name = "HouseBackboard"
	_house_back.texture = HOUSE_BACK_TEXTURE
	_house_back.centered = false
	_house_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_back.scale = DANCE_HALL_BACK_SCALE
	_house_back.position = DANCE_HALL_BACK_POSITION
	_house_back.modulate.a = 0.0
	_house_back.z_index = -6
	add_child(_house_back)

	_house_front = Sprite2D.new()
	_house_front.name = "HouseFront"
	_house_front.texture = HOUSE_FRONT_TEXTURE
	_house_front.centered = false
	_house_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_front.scale = DANCE_HALL_SCALE
	_house_front.position = DANCE_HALL_POSITION
	_house_front.z_index = 12
	add_child(_house_front)

func _set_house_inside(inside: bool) -> void:
	_house_front.modulate.a = 0.0 if inside else 1.0
	_house_back.modulate.a = 1.0 if inside else 0.0


# ═══════════════ 构建小画布 ═══════════════

func _build_painting() -> void:
	var outer := ColorRect.new()
	outer.position = Vector2(-CANVAS_W/2-10, FRAME_Y-10)
	outer.size = Vector2(CANVAS_W+20, FRAME_H+20)
	outer.color = Color("#4a3020")
	outer.z_index = -1
	add_child(outer)

	var inner := ColorRect.new()
	inner.position = Vector2(-CANVAS_W/2-4, FRAME_Y-4)
	inner.size = Vector2(CANVAS_W+8, FRAME_H+8)
	inner.color = Color("#6a5040")
	inner.z_index = -1
	add_child(inner)

	paint_canvas = Control.new()
	paint_canvas.position = Vector2(-CANVAS_W/2, FRAME_Y)
	paint_canvas.size = Vector2(CANVAS_W, FRAME_H)
	paint_canvas.z_index = 0
	paint_canvas.draw.connect(_on_paint_draw)
	paint_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paint_canvas)

	# ✓
	check_icon = Label.new()
	check_icon.position = Vector2(CANVAS_W/2-24, FRAME_Y-6)
	check_icon.add_theme_font_size_override("font_size", 22)
	check_icon.add_theme_color_override("font_color", Color("#55ff88"))
	check_icon.visible = false
	check_icon.z_index = 1
	add_child(check_icon)

	var ttl := Label.new()
	ttl.text = "油画"
	ttl.position = Vector2(-20, FRAME_Y-22)
	ttl.add_theme_font_size_override("font_size", 13)
	ttl.add_theme_color_override("font_color", Color("#d4c4a4"))
	ttl.z_index = 1
	add_child(ttl)


# ═══════════════ 构建6个地面按钮 ═══════════════

func _build_ground_buttons() -> void:
	var total := BTN_SPACING * 5.0
	var sx := -total / 2.0

	for i in range(6):
		var bx := sx + i * BTN_SPACING

		# 地面标记
		var mark := ColorRect.new()
		mark.position = Vector2(bx-BTN_W/2, BTN_Y-2)
		mark.size = Vector2(BTN_W, 6)
		mark.color = Color("#8a7a6a", 0.4)
		mark.z_index = -1
		add_child(mark)

		# 可站立碰撞体
		var body := StaticBody2D.new()
		body.position = Vector2(bx, BTN_Y)
		body.collision_layer = 1
		body.collision_mask = 0
		var cshape := CollisionShape2D.new()
		var crect := RectangleShape2D.new()
		crect.size = Vector2(BTN_W, BTN_H)
		cshape.shape = crect
		cshape.position = Vector2(0, BTN_H/2)
		body.add_child(cshape)
		var top := ColorRect.new()
		top.position = Vector2(-BTN_W/2, 0)
		top.size = Vector2(BTN_W, BTN_H)
		top.color = MOVE_COLORS[i]; top.color.a = 0.25
		body.add_child(top)
		button_tops.append(top)
		add_child(body)

		# 高亮层
		var glow := ColorRect.new()
		glow.name = "Glow"
		glow.position = Vector2(bx-BTN_W/2-2, BTN_Y-4)
		glow.size = Vector2(BTN_W+4, BTN_H+8)
		glow.color = MOVE_COLORS[i]; glow.color.a = 0.0
		glow.z_index = 1
		add_child(glow)
		button_glows.append(glow)

		# 感应区（缩小：只覆盖按钮正上方，防止空中路过误触）
		var sensor := Area2D.new()
		sensor.position = Vector2(bx, BTN_Y+BTN_H/2)
		sensor.collision_layer = 0
		sensor.collision_mask = 1
		sensor.set_meta("btn_idx", i)
		var sshape := CollisionShape2D.new()
		var srect := RectangleShape2D.new()
		# 宽度缩小到 BTN_W+4（去掉多余边距），高度缩小到 BTN_H+6（只检测站立）
		srect.size = Vector2(BTN_W+4, BTN_H+6)
		sshape.shape = srect
		sensor.add_child(sshape)
		var btn_idx_cap := i
		var sensor_cap := sensor
		button_sensors.append(sensor)
		button_press_timers.append(0.0)
		button_pressed.append(false)
		sensor.body_entered.connect(func(b: Node2D):
			_on_sensor_entered(b, btn_idx_cap, sensor_cap))
		sensor.body_exited.connect(func(b: Node2D):
			_on_sensor_exited(b, btn_idx_cap))
		add_child(sensor)


# ═══════════════ 底部状态UI ═══════════════

func _build_status_ui() -> void:
	step_dots.clear()
	var dot_total := ANSWER_LEN * 18.0
	var dot_sx := -dot_total/2.0 + 9
	for i in range(ANSWER_LEN):
		var dot := ColorRect.new()
		dot.position = Vector2(dot_sx+i*18-6, BTN_Y+30)
		dot.size = Vector2(12, 12)
		dot.color = Color("#3a2a1a", 0.7)
		add_child(dot)
		step_dots.append(dot)

	status_label = Label.new()
	status_label.position = Vector2(-200, BTN_Y+50)
	status_label.size = Vector2(400, 24)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#887766"))
	status_label.visible = false
	add_child(status_label)

	# 重置提示
	var reset_tip := Label.new()
	reset_tip.text = "旁边重置台：靠近按E重置当前输入"
	reset_tip.visible = false
	reset_tip.position = Vector2(-200, BTN_Y+70)
	reset_tip.size = Vector2(400, 20)
	reset_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset_tip.add_theme_font_size_override("font_size", 11)
	reset_tip.add_theme_color_override("font_color", Color("#aaa080"))
	add_child(reset_tip)


# ═══════════════ 画布绘制 ═══════════════

func _on_paint_draw() -> void:
	# 只有在自闭症/抑郁视角下才能看到小人跳舞
	var can_see := (current_view == "autism" or current_view == "depression")
	# 普通状态也保留整幅混乱的舞蹈抽象画；特殊视角只是褪色，
	# 不再把画布变成空白，避免玩家无法确认这里确实有一幅画。
	var paint_tint := Color(1.0, 1.0, 1.0, 0.44 if can_see else 1.0)
	paint_canvas.draw_texture_rect(ABSTRACT_PAINTING_TEXTURE, Rect2(Vector2.ZERO, Vector2(CANVAS_W, FRAME_H)), false, paint_tint)

	if not can_see:
		return

	# 特殊视角下叠加一层很淡的纸面，让动作示范仍然清楚可辨。
	paint_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(CANVAS_W, FRAME_H)), Color("#f0e4d4", 0.28))
	# 画地平线
	paint_canvas.draw_line(Vector2(10, GROUND_Y), Vector2(CANVAS_W-10, GROUND_Y), Color("#998877"), 1.0)

	# 循环结束时的空白帧（不画小人）—— 标识循环开头
	if is_demo_playing and _is_blanking:
		return

	# 中央小人舞步展示 —— 永远使用demo序列，与玩家输入无关
	var move_id := "fwd_walk"
	if is_demo_playing:
		var mi: int = DEMO_SEQ[demo_step]
		move_id = MOVE_IDS[mi]

	var center := Vector2(CANVAS_W/2, GROUND_Y-30)
	match move_id:
		"fwd_walk", "bwd_walk": center.y = GROUND_Y-50
		"fwd_jump", "bwd_jump": center.y = GROUND_Y-58
		"fwd_big", "bwd_big":   center.y = GROUND_Y-66

	_draw_stick(paint_canvas, move_id, center, 1.3, 1.0)





# ═══════════════ 画小人 ═══════════════

func _draw_stick(cv: Control, move_id: String, center: Vector2, ps: float, ls: float = 1.0) -> void:
	var p: Dictionary = _get_pose(move_id)
	if p.is_empty(): p = _get_pose("fwd_walk")
	var body := Color("#3a3028"); var s := ps*ls

	cv.draw_circle(center+p["head"]*s, 8*s, Color("#5a4a38"))
	cv.draw_arc(center+p["head"]*s, 7*s, 0, TAU, 16, body, 1.6*s)
	cv.draw_line(center+p["neck"]*s, center+p["hip"]*s, body, 2.5*s)
	cv.draw_line(center+p["shld_l"]*s, center+p["shld_r"]*s, body, 2*s)
	cv.draw_line(center+p["shld_l"]*s, center+p["elb_l"]*s, body, 2*s)
	cv.draw_line(center+p["elb_l"]*s, center+p["hand_l"]*s, body, 2*s)
	cv.draw_line(center+p["shld_r"]*s, center+p["elb_r"]*s, body, 2*s)
	cv.draw_line(center+p["elb_r"]*s, center+p["hand_r"]*s, body, 2*s)
	cv.draw_line(center+p["hip"]*s, center+p["knee_l"]*s, body, 2.5*s)
	cv.draw_line(center+p["knee_l"]*s, center+p["foot_l"]*s, body, 2.5*s)
	cv.draw_line(center+p["hip"]*s, center+p["knee_r"]*s, body, 2.5*s)
	cv.draw_line(center+p["knee_r"]*s, center+p["foot_r"]*s, body, 2.5*s)
	if "foot_l" in p: cv.draw_circle(center+p["foot_l"]*s, 3.5*s, body)
	if "foot_r" in p: cv.draw_circle(center+p["foot_r"]*s, 3.5*s, body)


# ═══════════════ 玩家靠近/离开 ═══════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_set_house_inside(true)
		room_toggled.emit(true)
		_sync_view()
		# demo 在 _ready 已启动且永不停止，不需要这里再触发

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_set_house_inside(false)
		room_toggled.emit(false)


func _input(event: InputEvent) -> void:
	if is_completed: return
	if event.is_action_pressed("interact"):
		# 重置台优先
		if near_reset:
			_reset_sequence()
			get_viewport().set_input_as_handled()
			return
		# 原有逻辑：靠近谜题后按E开始输入
		if player_in_range and not is_waiting_input:
			_stop_demo_start_input()


# ═══════════════ 地面按钮踩踏 ═══════════════

func _on_button_stepped(idx: int) -> void:
	if is_completed: return
	# 还没按E开始输入？只高亮，不记录
	if not is_waiting_input:
		_highlight_button(idx)
		status_label.text = "按 [E] 开始踩按钮"
		return
	# 输入模式：记录踩踏，demo 同时在画布上继续循环
	_highlight_button(idx)
	if step_buffer.size() == 0 or step_buffer[step_buffer.size()-1] != idx:
		step_buffer.append(idx)
		_last_stepped = idx
		_update_progress_dots()
		if step_buffer.size() >= ANSWER_LEN:
			_check_answer()

func _on_button_left() -> void:
	for i in range(button_glows.size()):
		button_glows[i].color.a = 0.0

func _build_reset_pedestal() -> void:
	# 在按钮区左侧放一个明显的重置台，避免和最后一个按钮混在一起。
	reset_zone = Area2D.new()
	reset_zone.position = Vector2(-BTN_SPACING * 3.2, BTN_Y)
	reset_zone.collision_layer = 0
	reset_zone.collision_mask = 1
	var sshape := CollisionShape2D.new()
	var srect := RectangleShape2D.new()
	srect.size = Vector2(RESET_PEDESTAL_W, 90)
	sshape.shape = srect
	reset_zone.add_child(sshape)

	# 台面视觉
	var base := ColorRect.new()
	base.position = Vector2(-RESET_PEDESTAL_W / 2.0, -10)
	base.size = Vector2(RESET_PEDESTAL_W, 14)
	base.color = Color("#3a3a4a")
	reset_zone.add_child(base)
	var top := ColorRect.new()
	top.position = Vector2(-RESET_PEDESTAL_W / 2.0, -14)
	top.size = Vector2(RESET_PEDESTAL_W, 4)
	top.color = Color("#5a5a6a")
	reset_zone.add_child(top)
	var label := Label.new()
	label.text = "按 E 重置"
	label.position = Vector2(-47, -62)
	label.size = Vector2(94, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#ffaa44"))
	reset_zone.add_child(label)

	reset_zone.body_entered.connect(func(b: Node2D):
		if b.is_in_group("player"):
			near_reset = true
	)
	reset_zone.body_exited.connect(func(b: Node2D):
		if b.is_in_group("player"):
			near_reset = false
	)
	add_child(reset_zone)

func _reset_sequence() -> void:
	step_buffer.clear()
	_last_stepped = -1
	for i in range(button_sensors.size()):
		button_press_timers[i] = 0.0
		button_pressed[i] = false
		_set_button_visual(i, false)
	_update_progress_dots()
	paint_canvas.queue_redraw()
	status_label.text = "已重置 · 重新开始踩按钮"
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))

func _highlight_button(idx: int) -> void:
	for i in range(button_glows.size()):
		if i == idx and i < button_pressed.size() and button_pressed[i]:
			button_glows[i].color.a = 0.6
		else:
			button_glows[i].color.a = 0.0

func _set_button_visual(idx: int, pressed: bool) -> void:
	if idx < 0 or idx >= button_tops.size():
		return
	var top := button_tops[idx]
	if not is_instance_valid(top):
		return
	top.position.y = BUTTON_PRESS_OFFSET if pressed else 0.0
	top.color.a = 0.75 if pressed else 0.25
	if idx < button_glows.size() and is_instance_valid(button_glows[idx]):
		button_glows[idx].color.a = 0.6 if pressed else 0.0


# ═══════════════ 示范动画 ═══════════════

func _start_demo() -> void:
	status_label.visible = true
	is_demo_playing = true
	is_waiting_input = false
	# 先空白一下，再进入第一个舞步，避免“开始”一按就直接接上动作。
	demo_step = DEMO_SEQ.size() - 1
	demo_timer = 0.0
	demo_complete_count = 0
	_is_blanking = true
	step_buffer.clear()
	_last_stepped = -1
	for g in button_glows: g.color.a = 0.0
	_update_progress_dots()
	check_icon.visible = true
	check_icon.text = "✓"
	status_label.text = "按 [E] 开始踩按钮 · 先看看舞步示范"
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_updated.emit("观察油画中小人的舞步顺序……")
	paint_canvas.queue_redraw()

func _stop_demo_start_input() -> void:
	status_label.visible = true
	# 不停止 demo！demo 始终循环示范，输入独立跟踪
	is_waiting_input = true
	step_buffer.clear()
	_last_stepped = -1
	check_icon.visible = false
	_update_progress_dots()
	status_label.text = "踩按钮！（%d步）· 对照画上顺序" % ANSWER_LEN
	status_label.add_theme_color_override("font_color", Color("#55ff88"))
	hint_updated.emit("开始踩按钮……")
	paint_canvas.queue_redraw()


# ═══════════════ 答案检查 ═══════════════

func _check_answer() -> void:
	var ok := true
	for i in range(ANSWER_LEN):
		if i >= step_buffer.size() or step_buffer[i] != CORRECT_SEQ[i]:
			ok = false; break

	if ok:
		_on_complete()
	else:
		_shake_timer = 0.45
		status_label.text = "不对……注意看画上的顺序！"
		status_label.add_theme_color_override("font_color", Color("#ff6666"))
		hint_updated.emit("舞步不对，重新尝试……")
		_reset_sequence()
		get_tree().create_timer(0.6).timeout.connect(func():
			if not is_completed and is_waiting_input:
				status_label.text = "踩按钮！（%d步）· 对照画上顺序" % ANSWER_LEN
				status_label.add_theme_color_override("font_color", Color("#ffe8a0")))

func _update_progress_dots() -> void:
	for i in range(ANSWER_LEN):
		if i < step_dots.size(): step_dots[i].color = Color("#3a2a1a", 0.7)
	for i in range(step_buffer.size()):
		if i < step_dots.size():
			step_dots[i].color = MOVE_COLORS[step_buffer[i]]

func _on_complete() -> void:
	is_completed = true
	is_demo_playing = false
	is_waiting_input = false
	check_icon.visible = false
	for g in button_glows: g.color.a = 0.0
	status_label.text = "✓ 全部正确！"
	status_label.add_theme_color_override("font_color", Color("#ffd700"))
	hint_updated.emit("你获得了钥匙1！")
	paint_canvas.queue_redraw()
	puzzle_completed.emit("key_1")


# ═══════════════ 视角 ═══════════════

func _sync_view() -> void:
	var player := _get_player()
	if player != null and "current_view" in player:
		update_on_view_change(str(player.current_view))

func update_on_view_change(view: String) -> void:
	current_view = view
	paint_canvas.queue_redraw()
	if is_completed: return
	var can_see := (view == "autism" or view == "depression")
	if player_in_range:
		if can_see:
			# demo 始终在运行，切回来自然能看到
			status_label.text = "按 [E] 开始踩按钮 · 先看看舞步示范"
			status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
		else:
			# 任何模式都能踩，但舞蹈只在自闭/抑郁视角可见
			status_label.text = "按 [E] 开始踩按钮（切换视角可看到舞步示范）"
			status_label.add_theme_color_override("font_color", Color("#ffe8a0"))

func _sync_initial_view() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_view"):
		update_on_view_change(main.get_view())


# ═══════════════ _process ═══════════════

func _process(delta: float) -> void:
	if is_completed: return
	_vfx_t += delta
	_update_button_pressure(delta)

	# 抖动
	if _shake_timer > 0:
		_shake_timer -= delta
		var sx := sin(_vfx_t*40)*4.0
		paint_canvas.position = Vector2(-CANVAS_W/2+sx, FRAME_Y+cos(_vfx_t*37)*3.0)
	else:
		paint_canvas.position = Vector2(-CANVAS_W/2, FRAME_Y)

	# 示范动画：动作之间有短暂空白，循环结束也保留一次空白，
	# 让相邻的两个舞步不会连成一个难以分辨的动作。
	# demo 始终循环，与输入模式无关
	if is_demo_playing:
		demo_timer += delta
		var frame_duration := DEMO_GAP_DURATION if _is_blanking else DEMO_STEP_DURATION
		if demo_timer >= frame_duration:
			demo_timer -= frame_duration
			if _is_blanking:
				_is_blanking = false
				demo_step += 1
				if demo_step >= DEMO_SEQ.size():
					demo_step = 0
					demo_complete_count += 1
			else:
				_is_blanking = true
		paint_canvas.queue_redraw()

	# ✓ 闪烁
	if check_icon.visible:
		check_icon.modulate.a = 0.6+sin(_vfx_t*3.0)*0.4


# ═══════════════ 辅助 ═══════════════

func V2(x: float, y: float) -> Vector2:
	return Vector2(x, y)

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func is_solved() -> bool:
	return is_completed

# ── 感应区辅助方法（避免嵌套 lambda 解析问题）──
func _on_sensor_entered(b: Node2D, btn_idx: int, sensor: Area2D) -> void:
	if not b.is_in_group("player") or is_completed:
		return
	# Entering the sensor only arms the button. Pressure is confirmed in
	# _update_button_pressure after the player is grounded and centered.

func _on_button_stepped_deferred(btn_idx: int) -> void:
	_on_button_stepped(btn_idx)

func _on_sensor_exited(b: Node2D, btn_idx: int) -> void:
	if not b.is_in_group("player"):
		return
	button_press_timers[btn_idx] = 0.0
	button_pressed[btn_idx] = false
	_set_button_visual(btn_idx, false)
	if _last_stepped == btn_idx:
		_on_button_left()

func _update_button_pressure(delta: float) -> void:
	var player := _get_player()
	if player == null or not player is CharacterBody2D:
		return
	var character := player as CharacterBody2D
	for i in range(button_sensors.size()):
		var sensor := button_sensors[i]
		var valid_stance := false
		if is_instance_valid(sensor) and sensor.has_overlapping_bodies():
			var local_x := player.global_position.x - global_position.x
			var button_x := -BTN_SPACING * 2.5 + i * BTN_SPACING
			# The inner portion prevents a player standing between two buttons
			# from arming either one through the sensor overlap.
			# BTN_W is the full width; use half-width for the center test.
			valid_stance = absf(local_x - button_x) <= BTN_W * 0.5 * BUTTON_CENTER_MARGIN
			valid_stance = valid_stance and character.is_on_floor()
			valid_stance = valid_stance and absf(character.velocity.x) <= 55.0
		if valid_stance:
			button_press_timers[i] = minf(BUTTON_SETTLE_TIME, button_press_timers[i] + delta)
		else:
			button_press_timers[i] = 0.0
			if button_pressed[i]:
				button_pressed[i] = false
				_set_button_visual(i, false)
		if button_press_timers[i] >= BUTTON_SETTLE_TIME and not button_pressed[i]:
			button_pressed[i] = true
			_set_button_visual(i, true)
			_on_button_stepped(i)
