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

# 画布尺寸
const CANVAS_W := 280.0
const CANVAS_H := 170.0
const GROUND_Y := 140.0

# 布局
const BTN_W := 56.0
const BTN_H := 18.0
const BTN_SPACING := 64.0
const BTN_Y := 55.0
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
var _shake_timer := 0.0
var _last_stepped := -1
var _vfx_t := 0.0

# 世界节点
var paint_canvas: Control = null
var check_icon: Label = null
var status_label: Label = null
var button_glows: Array[ColorRect] = []
var step_dots: Array[ColorRect] = []


# ═══════════════ 骨骼姿势（6种舞步，画布中央展示）═══════════════
# 关键:双脚叉开程度 = 跳跃远近
#   fwd_walk: 双脚并拢,身体前倾,走步
#   fwd_jump: 双脚微叉,小跳向前
#   fwd_big:  双脚大叉,大跳向前(脚距最远)
#   bwd_walk: 双脚并拢,身体后倾,走步
#   bwd_jump: 双脚微叉,小跳向后
#   bwd_big:  双脚大叉,大跳向后

func _get_pose(move_id: String) -> Dictionary:
	# 全部基于画布中央 X=0，垂直方向由 center 偏移
	# 头部 neck hip 在中央, 脚越叉开=跳得越远
	# 参数: head_x, head_y, neck_x, neck_y, hip_x, hip_y,
	#        shld_l, shld_r, elb_l, elb_r, hand_l, hand_r,
	#        knee_l, knee_r, foot_l, foot_r
	match move_id:
		# 向前走步:重心前倾,一脚在前一脚在后
		"fwd_walk": return _p(
			0,-50, 0,-40, 0,0,                     # 头 颈 髋
			-10,-32, 10,-32,                       # 双肩
			-18,-20, 18,-20,                       # 双肘
			-22,-8, 22,-8,                         # 双手
			-8,16, 8,16,                           # 双膝
			-12,32, 12,32)                         # 双脚 (并拢落地)
		# 向前小跳:双脚微叉,身体略离地
		"fwd_jump": return _p(
			0,-58, 0,-48, 0,-6,                    # 头 颈 髋(略上抬)
			-10,-40, 10,-40,                       # 双肩
			-18,-32, 18,-32,                       # 双肘
			-22,-22, 22,-22,                       # 双手
			-12,10, 12,10,                         # 双膝 (略上)
			-18,28, 18,28)                         # 双脚 (微叉)
		# 向前大跳:双脚大叉,身体高高跃起
		"fwd_big": return _p(
			0,-66, 0,-56, 0,-12,                   # 头 颈 髋(明显上抬)
			-12,-48, 12,-48,                       # 双肩
			-22,-42, 22,-42,                       # 双肘
			-28,-32, 28,-32,                       # 双手张开
			-18,4, 18,4,                           # 双膝 (高高)
			-30,22, 30,22)                         # 双脚 (大叉=跳得远)
		# 向后走步:重心后倾
		"bwd_walk": return _p(
			0,-50, 0,-40, 0,0,
			-10,-32, 10,-32,
			-18,-20, 18,-20,
			-22,-8, 22,-8,
			-8,16, 8,16,
			-12,32, 12,32)
		# 向后小跳:双脚微叉
		"bwd_jump": return _p(
			0,-58, 0,-48, 0,-6,
			-10,-40, 10,-40,
			-18,-32, 18,-32,
			-22,-22, 22,-22,
			-12,10, 12,10,
			-18,28, 18,28)
		# 向后大跳:双脚大叉
		"bwd_big": return _p(
			0,-66, 0,-56, 0,-12,
			-12,-48, 12,-48,
			-22,-42, 22,-42,
			-28,-32, 28,-32,
			-18,4, 18,4,
			-30,22, 30,22)
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

	# 画布内6个圆圈X位置
	var total_w := BTN_SPACING * 5.0
	var sx := (CANVAS_W - total_w) / 2.0
	for i in range(6):
		circle_x.append(sx + i * BTN_SPACING)

	_build_painting()
	_build_ground_buttons()
	_build_status_ui()
	# 一创建就开始循环示范动画，不需要走近触发
	if not is_completed and not is_demo_playing and not is_waiting_input:
		_start_demo()
	call_deferred("_sync_initial_view")


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

		# 感应区
		var sensor := Area2D.new()
		sensor.position = Vector2(bx, BTN_Y+BTN_H/2)
		sensor.collision_layer = 0
		sensor.collision_mask = 1
		sensor.set_meta("btn_idx", i)
		var sshape := CollisionShape2D.new()
		var srect := RectangleShape2D.new()
		srect.size = Vector2(BTN_W+12, BTN_H+20)
		sshape.shape = srect
		sensor.add_child(sshape)
		sensor.body_entered.connect(func(b: Node2D):
			if b.is_in_group("player") and not is_completed:
				_on_button_stepped(i))
		sensor.body_exited.connect(func(b: Node2D):
			if b.is_in_group("player") and _last_stepped == i:
				_on_button_left())
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
	add_child(status_label)


# ═══════════════ 画布绘制 ═══════════════

func _on_paint_draw() -> void:
	# 只有在自闭症/抑郁视角下才能看到小人跳舞
	var can_see := (current_view == "autism" or current_view == "depression")
	
	if not can_see:
		# 非自闭/抑郁视角：画面模糊/空白
		paint_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(CANVAS_W, FRAME_H)), Color("#1a1510", 0.85))
		return
	
	# 先画背景（必须在这里画，不能用子节点否则会盖住 _draw）
	paint_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(CANVAS_W, FRAME_H)), Color("#f0e4d4"))
	# 画地平线
	paint_canvas.draw_line(Vector2(10, GROUND_Y), Vector2(CANVAS_W-10, GROUND_Y), Color("#998877"), 1.0)

	# 所有动作都在画布中央展示，不画任何圆圈/格子
	# 小人画在中央，vertical 位置取决于"跳跃高度"=脚离地距离
	var move_id := "fwd_walk"
	if is_demo_playing:
		var mi: int = DEMO_SEQ[demo_step]
		move_id = MOVE_IDS[mi]
	elif is_waiting_input and step_buffer.size() > 0:
		move_id = MOVE_IDS[step_buffer[step_buffer.size()-1]]

	# 根据 move_id 计算中心位置 (X固定=CANVAS_W/2)
	# 跳得越远 = 身体中心Y越靠上 (离地越高)
	var center := Vector2(CANVAS_W/2, GROUND_Y-30)  # 基础位置(脚落在 GROUND_Y 附近)
	match move_id:
		"fwd_walk", "bwd_walk": center.y = GROUND_Y-50  # 走路: 脚在 GROUND_Y
		"fwd_jump", "bwd_jump": center.y = GROUND_Y-58  # 小跳: 脚在 GROUND_Y-8
		"fwd_big", "bwd_big":   center.y = GROUND_Y-66  # 大跳: 脚在 GROUND_Y-16

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
		_sync_view()
		if not is_completed and not is_demo_playing and not is_waiting_input:
			_start_demo()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false


# ═══════════════ 地面按钮踩踏 ═══════════════

func _on_button_stepped(idx: int) -> void:
	if is_completed: return
	_highlight_button(idx)
	if not is_waiting_input and is_demo_playing:
		_stop_demo_start_input()
	if not is_waiting_input: return
	if step_buffer.size() == 0 or step_buffer[step_buffer.size()-1] != idx:
		step_buffer.append(idx)
		_last_stepped = idx
		_update_progress_dots()
		paint_canvas.queue_redraw()
		if step_buffer.size() >= ANSWER_LEN:
			_check_answer()

func _on_button_left() -> void:
	for i in range(button_glows.size()):
		button_glows[i].color.a = 0.0

func _highlight_button(idx: int) -> void:
	for i in range(button_glows.size()):
		button_glows[i].color.a = 0.5 if i == idx else 0.0


# ═══════════════ 示范动画 ═══════════════

func _start_demo() -> void:
	is_demo_playing = true
	is_waiting_input = false
	demo_step = 0
	demo_timer = 0.0
	step_buffer.clear()
	_last_stepped = -1
	for g in button_glows: g.color.a = 0.0
	_update_progress_dots()
	check_icon.visible = true
	check_icon.text = "✓"
	status_label.text = "示范中…踩任意按钮开始"
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_updated.emit("观察油画中小人的舞步顺序……")
	paint_canvas.queue_redraw()

func _stop_demo_start_input() -> void:
	is_demo_playing = false
	is_waiting_input = true
	step_buffer.clear()
	_last_stepped = -1
	check_icon.visible = false
	_update_progress_dots()
	status_label.text = "踩按钮！（%d步）" % ANSWER_LEN
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
		step_buffer.clear()
		_last_stepped = -1
		for g in button_glows: g.color.a = 0.0
		_update_progress_dots()
		paint_canvas.queue_redraw()
		get_tree().create_timer(0.6).timeout.connect(func():
			if not is_completed and is_waiting_input:
				status_label.text = "踩按钮！（%d步）" % ANSWER_LEN
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
	if player_in_range and not is_demo_playing and not is_waiting_input:
		if can_see:
			_start_demo()
		else:
			# 切换到非可用视角时停止
			status_label.text = "需要自闭症/抑郁视角"
			status_label.add_theme_color_override("font_color", Color("#887766"))

func _sync_initial_view() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_view"):
		update_on_view_change(main.get_view())


# ═══════════════ _process ═══════════════

func _process(delta: float) -> void:
	if is_completed: return
	_vfx_t += delta

	# 抖动
	if _shake_timer > 0:
		_shake_timer -= delta
		var sx := sin(_vfx_t*40)*4.0
		paint_canvas.position = Vector2(-CANVAS_W/2+sx, FRAME_Y+cos(_vfx_t*37)*3.0)
	else:
		paint_canvas.position = Vector2(-CANVAS_W/2, FRAME_Y)

	# 示范动画
	if is_demo_playing:
		demo_timer += delta
		if demo_timer >= DEMO_STEP_DURATION:
			demo_timer -= DEMO_STEP_DURATION
			demo_step += 1
			if demo_step >= DEMO_SEQ.size():
				demo_step = 0
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
