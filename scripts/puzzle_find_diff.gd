extends Area2D
class_name PuzzleFindDifference

# ════════════════════════════════════════════════════════════
#  找不同密室 — v4
#  通过记忆长椅切换视角，不同视角看到5个物体的状态不同。
#  每个物体有2个视角状态一致 = 正确答案，玩家需要去记忆长椅对比推理。
#  只有普通视角能点击切换物体状态。
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)
signal room_toggled(open: bool)

# ── 视角 ──
const PERSPECTIVES: Array[Dictionary] = [
	{"id": "normal",     "label": "普通", "color": Color.WHITE,       "short": "普"},
	{"id": "adhd",       "label": "ADHD",  "color": Color("#ffde4a"), "short": "A"},
	{"id": "depression", "label": "抑郁",  "color": Color("#8899aa"), "short": "D"},
	{"id": "autism",     "label": "自闭",  "color": Color("#77aaff"), "short": "Z"},
	{"id": "blind",      "label": "盲人",  "color": Color("#cc99ff"), "short": "盲"},
]

# ── 物体：5个视角分别看到的状态 ──
# Object 1: 自闭=抑郁=2 (正确), 普通=0, ADHD=0, 盲人=1
# Object 2: 抑郁=ADHD=0 (正确), 普通=1, 自闭=2, 盲人=1
# Object 3: 盲人=自闭=0 (正确), 普通=2, ADHD=1, 抑郁=1
# Object 4: 自闭=抑郁=1 (正确), ADHD=0, 普通=0, 盲人=2
# Object 5: 盲人=ADHD=1 (正确), 普通=2, 自闭=0, 抑郁=2
const OBJECTS: Array[Dictionary] = [
	{
		"id": "flower", "name": "花瓶", "states": ["开放", "闭合", "枯萎"],
		"views": {"normal": 0, "adhd": 0, "depression": 2, "autism": 2, "blind": 1},
		"correct": 2, "color_a": Color("#ff6677"), "color_b": Color("#cc4455"), "color_c": Color("#886644"),
	},
	{
		"id": "frame", "name": "画框", "states": ["风景", "人物", "抽象"],
		"views": {"normal": 1, "adhd": 0, "depression": 0, "autism": 2, "blind": 1},
		"correct": 0, "color_a": Color("#77aa66"), "color_b": Color("#cc9966"), "color_c": Color("#9966cc"),
	},
	{
		"id": "clock", "name": "时钟", "states": ["快", "慢", "准确"],
		"views": {"normal": 2, "adhd": 1, "depression": 0, "autism": 0, "blind": 0},
		"correct": 0, "color_a": Color("#dd5544"), "color_b": Color("#5588cc"), "color_c": Color("#ddaa33"),
	},
	{
		"id": "window_obj", "name": "窗户", "states": ["打开", "关闭", "半开"],
		"views": {"normal": 2, "adhd": 0, "depression": 1, "autism": 1, "blind": 2},
		"correct": 1, "color_a": Color("#66aadd"), "color_b": Color("#2a2a35"), "color_c": Color("#dd9966"),
	},
	{
		"id": "book", "name": "书本", "states": ["打开", "合上", "半开"],
		"views": {"normal": 0, "adhd": 1, "depression": 1, "autism": 2, "blind": 1},
		"correct": 1, "color_a": Color("#f5eed8"), "color_b": Color("#8b3a3a"), "color_c": Color("#d4b896"),
	},
]

# ── 物体在房间中的位置 ──
const OBJ_POS: Array[Vector2] = [
	Vector2(120, 230),
	Vector2(240, 140),
	Vector2(380, 140),
	Vector2(560, 140),
	Vector2(660, 230),
]

# ── 状态 ──
var player_in_range: bool = false
var is_completed: bool = false
var room_open: bool = false
var current_view: String = "normal"  # 由记忆长椅同步的全局视角
var object_states: Array[int] = []  # 玩家在普通视角设置的状态, -1=未设置

# ── UI 节点 ──
var room_overlay: CanvasLayer = null
var progress_label: Label = null
var mode_hint_label: Label = null
var exterior_label: Label = null
var view_label: Label = null  # 显示当前视角的标签
var obj_zones: Array[Control] = []
var obj_visuals: Array[Control] = []
var obj_state_labels: Array[Label] = []
var obj_view_labels: Array[Array] = []  # 每个物体下的5个视角小标签

const OW: float = 840.0
const OH: float = 540.0


# ════════════════════════════════════════════════════════════
#  初始化
# ════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("interactable")
	z_index = 10
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160, 100)
	shape.shape = rect
	shape.position = Vector2(0, 20)
	add_child(shape)

	for i in range(OBJECTS.size()):
		object_states.append(-1)

	_make_exterior()
	_make_room_ui()


# ════════════════════════════════════════════════════════════
#  世界地图上的房子外观 — 质感升级
# ════════════════════════════════════════════════════════════

func _make_exterior() -> void:
	# 主墙体：暖棕色砖墙
	var wall := ColorRect.new()
	wall.position = Vector2(-55, -30); wall.size = Vector2(110, 80)
	wall.color = Color("#8a6e5c"); add_child(wall)
	# 砖缝纹理
	for bi in range(6):
		var brick := ColorRect.new()
		brick.position = Vector2(-55 + (bi % 2) * 5, -30 + bi * 14)
		brick.size = Vector2(108, 2)
		brick.color = Color("#7a5e4c", 0.5); add_child(brick)

	# 屋顶：深红色三角顶 + 瓦片纹理
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([Vector2(-65, -30), Vector2(65, -30), Vector2(0, -75)])
	roof.color = Color("#a04030"); add_child(roof)
	# 屋顶高光边
	var roof_edge := Line2D.new()
	roof_edge.width = 2.5
	roof_edge.default_color = Color("#c06048", 0.7)
	roof_edge.add_point(Vector2(-65, -30)); roof_edge.add_point(Vector2(0, -75))
	roof_edge.add_point(Vector2(65, -30)); add_child(roof_edge)

	# 门
	var door := ColorRect.new()
	door.position = Vector2(-10, 10); door.size = Vector2(20, 40)
	door.color = Color("#5a3820"); add_child(door)
	# 门把手
	var knob := ColorRect.new()
	knob.position = Vector2(4, 28); knob.size = Vector2(4, 4)
	knob.color = Color("#ddaa44"); add_child(knob)

	# 两扇窗户
	for wx in [-40, 24]:
		var win_frame := ColorRect.new()
		win_frame.position = Vector2(wx - 2, -12); win_frame.size = Vector2(20, 20)
		win_frame.color = Color("#6a5040"); add_child(win_frame)
		var win_glass := ColorRect.new()
		win_glass.position = Vector2(wx, -10); win_glass.size = Vector2(16, 16)
		win_glass.color = Color("#99ccdd", 0.8); add_child(win_glass)
		# 十字窗格
		var wm_v := ColorRect.new()
		wm_v.position = Vector2(wx + 7, -10); wm_v.size = Vector2(2, 16)
		wm_v.color = Color("#6a5040"); add_child(wm_v)
		var wm_h := ColorRect.new()
		wm_h.position = Vector2(wx, -3); wm_h.size = Vector2(16, 2)
		wm_h.color = Color("#6a5040"); add_child(wm_h)
		# 暖光透出
		var warm := ColorRect.new()
		warm.position = Vector2(wx + 2, -8); warm.size = Vector2(12, 12)
		warm.color = Color("#ffdd88", 0.15); add_child(warm)

	# 烟囱
	var chimney := ColorRect.new()
	chimney.position = Vector2(30, -55); chimney.size = Vector2(10, 25)
	chimney.color = Color("#6a5440"); add_child(chimney)

	var title := Label.new()
	title.text = "[ 找不同密室 ]"
	title.position = Vector2(-50, -100)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)

	exterior_label = Label.new()
	exterior_label.text = "按 [E] 进入密室"
	exterior_label.position = Vector2(-50, 58)
	exterior_label.add_theme_font_size_override("font_size", 12)
	exterior_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	add_child(exterior_label)


# ════════════════════════════════════════════════════════════
#  房间 UI — 5个视角按钮 + 房间内景 + 5个物体
# ════════════════════════════════════════════════════════════

func _make_room_ui() -> void:
	room_overlay = CanvasLayer.new()
	room_overlay.layer = 100
	room_overlay.visible = false
	add_child(room_overlay)

	# 半透明背景
	var shade := ColorRect.new()
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.color = Color(0, 0, 0, 0.72)
	shade.gui_input.connect(_on_shade_input)
	room_overlay.add_child(shade)

	# 主面板 — 深色木框 + 暖暗底
	var panel := Panel.new()
	panel.name = "Panel"
	var vs := get_viewport().get_visible_rect().size
	panel.position = Vector2((vs.x - OW) / 2.0, (vs.y - OH) / 2.0)
	panel.size = Vector2(OW, OH)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#261c12")
	ps.set_corner_radius_all(14)
	ps.border_width_left = 4; ps.border_width_right = 4
	ps.border_width_top = 4; ps.border_width_bottom = 4
	ps.border_color = Color("#6a5a44")
	ps.shadow_size = 20
	ps.shadow_color = Color(0, 0, 0, 0.5)
	panel.add_theme_stylebox_override("panel", ps)
	room_overlay.add_child(panel)

	# 房间绘制
	_draw_room_bg(panel)

	# 标题
	var title := Label.new()
	title.text = "找不同密室 — 对比各个视角的观察"
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#ffe8a0"))
	panel.add_child(title)

	# 说明
	var desc := Label.new()
	desc.text = "每个视角看到的物体状态不一样。对比各视角，相同状态最多的是正确答案。"
	desc.position = Vector2(20, 36)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color("#998877"))
	panel.add_child(desc)

	# 当前视角标签
	view_label = Label.new()
	view_label.position = Vector2(20, 64)
	view_label.add_theme_font_size_override("font_size", 13)
	view_label.add_theme_color_override("font_color", Color("#88cc88"))
	view_label.text = "当前视角: 普通 — 点击物体切换状态"
	panel.add_child(view_label)

	# ── 5个物体 ──
	_make_objects(panel)

	# ── 底部信息 ──
	progress_label = Label.new()
	progress_label.position = Vector2(20, OH - 30)
	progress_label.add_theme_font_size_override("font_size", 14)
	progress_label.add_theme_color_override("font_color", Color("#aa9988"))
	progress_label.text = "已设置: 0/5"
	panel.add_child(progress_label)

	mode_hint_label = Label.new()
	mode_hint_label.position = Vector2(280, OH - 30)
	mode_hint_label.add_theme_font_size_override("font_size", 13)
	mode_hint_label.add_theme_color_override("font_color", Color("#88cc88"))
	mode_hint_label.text = "✓ 普通视角 — 点击物体切换状态"
	panel.add_child(mode_hint_label)

	# 退出按钮
	var exit_btn := Button.new()
	exit_btn.text = "✕ 退出"
	exit_btn.position = Vector2(OW - 80, 10)
	exit_btn.size = Vector2(60, 28)
	var es := StyleBoxFlat.new()
	es.bg_color = Color("#884444"); es.set_corner_radius_all(5)
	exit_btn.add_theme_stylebox_override("normal", es)
	var esh := StyleBoxFlat.new()
	esh.bg_color = Color("#aa5555"); esh.set_corner_radius_all(5)
	exit_btn.add_theme_stylebox_override("hover", esh)
	exit_btn.add_theme_color_override("font_color", Color.WHITE)
	exit_btn.add_theme_font_size_override("font_size", 13)
	exit_btn.pressed.connect(_on_exit)
	panel.add_child(exit_btn)


# ════════════════════════════════════════════════════════════
#  视角标签辅助
# ════════════════════════════════════════════════════════════

func _get_view_label() -> String:
	for p in PERSPECTIVES:
		if str(p["id"]) == current_view:
			return str(p["label"])
	return current_view

func _get_view_color() -> Color:
	for p in PERSPECTIVES:
		if str(p["id"]) == current_view:
			return p["color"]
	return Color.WHITE


# ════════════════════════════════════════════════════════════
#  房间背景绘制
# ════════════════════════════════════════════════════════════

func _draw_room_bg(panel: Panel) -> void:
	# ── 后墙：暖棕壁纸感 + 竖向条纹纹理 ──
	var back := ColorRect.new()
	back.position = Vector2(0, 120)
	back.size = Vector2(OW, 240)
	back.color = Color("#3a2e22")
	panel.add_child(back)
	# 壁纸竖向纹理
	for i in range(21):
		var stripe := ColorRect.new()
		stripe.position = Vector2(8 + i * 40, 120)
		stripe.size = Vector2(3, 240)
		stripe.color = Color("#4a3a2a", 0.3)
		back.add_child(stripe)
	# 交替宽条纹的暗纹
	for i in range(10):
		var wide := ColorRect.new()
		wide.position = Vector2(20 + i * 80, 120)
		wide.size = Vector2(40, 240)
		wide.color = Color("#352820", 0.2)
		back.add_child(wide)

	# ── 左墙柱：更立体 ──
	var lw := ColorRect.new()
	lw.position = Vector2(0, 120); lw.size = Vector2(30, OH - 120)
	lw.color = Color("#241a12"); panel.add_child(lw)
	var lw_hl := ColorRect.new()
	lw_hl.position = Vector2(24, 120); lw_hl.size = Vector2(6, OH - 120)
	lw_hl.color = Color("#3a2a1a", 0.5); panel.add_child(lw_hl)

	# ── 右墙柱 ──
	var rw := ColorRect.new()
	rw.position = Vector2(OW - 30, 120); rw.size = Vector2(30, OH - 120)
	rw.color = Color("#241a12"); panel.add_child(rw)
	var rw_hl := ColorRect.new()
	rw_hl.position = Vector2(OW - 30, 120); rw_hl.size = Vector2(6, OH - 120)
	rw_hl.color = Color("#3a2a1a", 0.5); panel.add_child(rw_hl)

	# ── 腰线装饰条 ──
	var trim := ColorRect.new()
	trim.position = Vector2(30, 296); trim.size = Vector2(OW - 60, 6)
	trim.color = Color("#7a5a40"); panel.add_child(trim)
	var trim2 := ColorRect.new()
	trim2.position = Vector2(30, 290); trim2.size = Vector2(OW - 60, 3)
	trim2.color = Color("#5a3a28"); panel.add_child(trim2)

	# ── 墙裙：木镶板风格 ──
	var wain := ColorRect.new()
	wain.position = Vector2(30, 302); wain.size = Vector2(OW - 60, 58)
	wain.color = Color("#4a3525"); panel.add_child(wain)
	# 镶板竖条
	for i in range(17):
		var vp := ColorRect.new()
		vp.position = Vector2(34 + i * 46, 302)
		vp.size = Vector2(4, 58)
		vp.color = Color("#3a2818", 0.6); panel.add_child(vp)

	# ── 木地板：深色交错纹理 ──
	var floor := ColorRect.new()
	floor.position = Vector2(30, 360); floor.size = Vector2(OW - 60, OH - 360)
	floor.color = Color("#4a2a18"); panel.add_child(floor)
	# 随机宽地板条
	for i in range(16):
		var plank := ColorRect.new()
		plank.position = Vector2(30, 360 + i * 11)
		plank.size = Vector2(OW - 60, 3)
		plank.color = Color("#5a3620") if i % 3 == 0 else Color("#3a2010", 0.6)
		floor.add_child(plank)
	# 地板对角纹理
	for i in range(8):
		var grain := ColorRect.new()
		grain.position = Vector2(40 + i * 100, 364 + i * 22)
		grain.size = Vector2(80, 1)
		grain.color = Color("#6a4028", 0.3); floor.add_child(grain)

	# ── 壁灯：两侧各一盏 ──
	for wx in [50, OW - 80]:
		var sconce := Polygon2D.new()
		sconce.polygon = PackedVector2Array([
			Vector2(wx - 8, 180), Vector2(wx + 8, 180),
			Vector2(wx + 5, 175), Vector2(wx - 5, 175),
		])
		sconce.color = Color("#ccaa44"); panel.add_child(sconce)
		var glow := ColorRect.new()
		glow.position = Vector2(wx - 24, 160); glow.size = Vector2(48, 24)
		glow.color = Color("#ffdd88", 0.08); panel.add_child(glow)

	# ── 桌子：更厚的台面 ──
	var table := ColorRect.new()
	table.position = Vector2(50, 348); table.size = Vector2(OW - 100, 14)
	table.color = Color("#8a6240"); panel.add_child(table)
	# 桌边高光
	var table_hl := ColorRect.new()
	table_hl.position = Vector2(50, 348); table_hl.size = Vector2(OW - 100, 3)
	table_hl.color = Color("#a08060", 0.6); panel.add_child(table_hl)
	# 桌腿
	for lx in [70, OW - 120]:
		var leg := ColorRect.new()
		leg.position = Vector2(lx, 362); leg.size = Vector2(12, 36)
		leg.color = Color("#5a3a24"); panel.add_child(leg)
		# 爪脚
		var foot := ColorRect.new()
		foot.position = Vector2(lx - 3, 392); foot.size = Vector2(18, 6)
		foot.color = Color("#4a2a18"); panel.add_child(foot)


# ════════════════════════════════════════════════════════════
#  5个可交互物体
# ════════════════════════════════════════════════════════════

func _make_objects(panel: Panel) -> void:
	obj_zones.clear()
	obj_visuals.clear()
	obj_state_labels.clear()
	obj_view_labels.clear()

	for i in range(OBJECTS.size()):
		_make_one_object(panel, i)


func _make_one_object(panel: Panel, idx: int) -> void:
	var obj: Dictionary = OBJECTS[idx]
	var bp: Vector2 = OBJ_POS[idx]
	var ow: float = 130.0

	# 物体名
	var nl := Label.new()
	nl.text = obj["name"]
	nl.position = Vector2(bp.x, bp.y - 18)
	nl.size = Vector2(ow, 16)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 12)
	nl.add_theme_color_override("font_color", Color("#ccaa88"))
	panel.add_child(nl)

	# 物体绘制容器（不拦截鼠标，让点击穿透到zone）
	var vis := Control.new()
	vis.position = bp + Vector2(0, 6)
	vis.size = Vector2(ow, 110)
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vis)

	# 可点击区域（整个物体卡片，从名称到状态文字都覆盖）
	var zone := ColorRect.new()
	zone.position = bp + Vector2(-4, -18)
	zone.size = Vector2(ow + 8, 158)
	zone.mouse_filter = Control.MOUSE_FILTER_STOP
	zone.color = Color(1, 1, 1, 0.001)
	zone.gui_input.connect(_on_obj_input.bind(idx))
	zone.mouse_entered.connect(func():
		if not is_completed and current_view == "normal":
			zone.color = Color(1, 0.84, 0.3, 0.12)
	)
	zone.mouse_exited.connect(func():
		zone.color = Color(1, 1, 1, 0.001)
	)
	panel.add_child(zone)
	obj_zones.append(zone)
	obj_visuals.append(vis)

	# 视角小标签行
	var view_row: Array[Label] = []
	var vx := bp.x
	var vy := bp.y + 120
	for vi in range(PERSPECTIVES.size()):
		var vl := Label.new()
		vl.position = Vector2(vx + vi * 26, vy)
		vl.size = Vector2(25, 13)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.add_theme_font_size_override("font_size", 9)
		vl.add_theme_color_override("font_color", PERSPECTIVES[vi]["color"])
		vl.text = PERSPECTIVES[vi]["short"] + ":?"
		panel.add_child(vl)
		view_row.append(vl)
	obj_view_labels.append(view_row)

	# 当前状态文字
	var st := Label.new()
	st.position = Vector2(bp.x, vy + 16)
	st.size = Vector2(ow, 16)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 12)
	st.add_theme_color_override("font_color", Color("#ffffff"))
	st.text = "未设置"
	panel.add_child(st)
	obj_state_labels.append(st)

	_refresh_object_draw(idx)
	_refresh_view_tags(idx)


# ════════════════════════════════════════════════════════════
#  物体图形绘制（基于当前选中视角的状态）
# ════════════════════════════════════════════════════════════

func _get_display_state(idx: int) -> int:
	# 返回物体idx在当前全局视角下应该显示的状态
	var obj: Dictionary = OBJECTS[idx]
	var persp_id: String = current_view
	if persp_id == "normal":
		# 普通视角：显示玩家设置的状态，未设置则显示原始普通视角状态
		if object_states[idx] >= 0:
			return object_states[idx]
	return obj["views"][persp_id]


func _refresh_object_draw(idx: int) -> void:
	if idx >= obj_visuals.size():
		return
	var vis: Control = obj_visuals[idx]
	if not is_instance_valid(vis):
		return
	for c in vis.get_children():
		c.queue_free()

	var state := _get_display_state(idx)
	if state < 0:
		var q := Label.new()
		q.text = "?"
		q.position = Vector2(40, 20)
		q.size = Vector2(50, 50)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.add_theme_font_size_override("font_size", 42)
		q.add_theme_color_override("font_color", Color("#554433"))
		vis.add_child(q)
		return

	var obj := OBJECTS[idx]
	var colors: Array = [obj["color_a"], obj["color_b"], obj["color_c"]]
	var sc: Color = colors[state]

	match obj["id"]:
		"flower":      _draw_flower(vis, state, sc)
		"frame":       _draw_frame(vis, state, sc)
		"clock":       _draw_clock(vis, state, sc)
		"window_obj":  _draw_window_obj(vis, state, sc)
		"book":        _draw_book(vis, state, sc)


func _refresh_view_tags(idx: int) -> void:
	if idx >= obj_view_labels.size():
		return
	var obj := OBJECTS[idx]
	var views: Dictionary = obj["views"]
	var labels: Array = obj_view_labels[idx]
	for vi in range(PERSPECTIVES.size()):
		var lbl: Label = labels[vi]
		if not is_instance_valid(lbl):
			continue
		var persp_id: String = PERSPECTIVES[vi]["id"]
		var state_idx: int
		if persp_id == "normal" and object_states[idx] >= 0:
			state_idx = object_states[idx]
		else:
			state_idx = views[persp_id]
		var sn: String = obj["states"][state_idx]
		lbl.text = PERSPECTIVES[vi]["short"] + ":" + sn


# ── 花瓶 ──
func _draw_flower(vis: Control, state: int, color: Color) -> void:
	var pot := ColorRect.new()
	pot.position = Vector2(60, 58); pot.size = Vector2(24, 30); pot.color = Color("#8a6040")
	vis.add_child(pot)
	var rim := ColorRect.new()
	rim.position = Vector2(55, 55); rim.size = Vector2(34, 6); rim.color = Color("#a07050")
	vis.add_child(rim)

	var cx := 72.0; var cy := 50.0
	match state:
		0:
			for ai in range(8):
				var a := TAU * ai / 8.0
				var p := Polygon2D.new()
				var pts := PackedVector2Array()
				pts.append(Vector2(cx, cy))
				var r := 14.0
				pts.append(Vector2(cx + cos(a - 0.2) * r, cy + sin(a - 0.2) * r))
				pts.append(Vector2(cx + cos(a) * r * 1.5, cy + sin(a) * r * 1.5))
				pts.append(Vector2(cx + cos(a + 0.2) * r, cy + sin(a + 0.2) * r))
				p.polygon = pts; p.color = color; vis.add_child(p)
			var ctr := ColorRect.new()
			ctr.position = Vector2(cx - 8, cy - 8); ctr.size = Vector2(16, 16)
			ctr.color = Color("#ffdd44"); vis.add_child(ctr)
		1:
			var bud := Polygon2D.new()
			bud.polygon = PackedVector2Array([
				Vector2(cx, cy - 16), Vector2(cx - 14, cy), Vector2(cx, cy + 4), Vector2(cx + 14, cy)
			])
			bud.color = color.darkened(0.3); vis.add_child(bud)
			var stem := ColorRect.new()
			stem.position = Vector2(cx - 2, cy); stem.size = Vector2(4, 10)
			stem.color = Color("#558844"); vis.add_child(stem)
		2:
			for ai in range(6):
				var a := TAU * ai / 6.0 + 1.2
				var p := Polygon2D.new()
				var pts := PackedVector2Array()
				pts.append(Vector2(cx, cy))
				var r := 10.0
				pts.append(Vector2(cx + cos(a - 0.15) * r, cy + sin(a - 0.15) * r))
				pts.append(Vector2(cx + cos(a) * r * 1.2, cy + sin(a) * r * 1.2))
				pts.append(Vector2(cx + cos(a + 0.15) * r, cy + sin(a + 0.15) * r))
				p.polygon = pts; p.color = color.darkened(0.5); vis.add_child(p)


# ── 画框 ──
func _draw_frame(vis: Control, state: int, color: Color) -> void:
	var f := ColorRect.new()
	f.position = Vector2(18, 8); f.size = Vector2(94, 76); f.color = Color("#8a6a44")
	vis.add_child(f)
	var canvas := ColorRect.new()
	canvas.position = Vector2(26, 16); canvas.size = Vector2(78, 60); canvas.color = color
	vis.add_child(canvas)

	match state:
		0:
			var sky := ColorRect.new()
			sky.position = Vector2(26, 16); sky.size = Vector2(78, 30)
			sky.color = Color("#88bbdd"); vis.add_child(sky)
			var mt := Polygon2D.new()
			mt.polygon = PackedVector2Array([
				Vector2(65, 36), Vector2(26, 76), Vector2(104, 76),
				Vector2(85, 36), Vector2(75, 56), Vector2(55, 56),
			])
			mt.color = Color("#559944"); vis.add_child(mt)
			var sun := ColorRect.new()
			sun.position = Vector2(70, 22); sun.size = Vector2(10, 10)
			sun.color = Color("#ffdd44"); vis.add_child(sun)
		1:
			var bg := ColorRect.new()
			bg.position = Vector2(26, 16); bg.size = Vector2(78, 60)
			bg.color = Color("#eeddcc"); vis.add_child(bg)
			var head := ColorRect.new()
			head.position = Vector2(53, 24); head.size = Vector2(24, 24)
			head.color = Color("#e8c8a0"); vis.add_child(head)
			var body := ColorRect.new()
			body.position = Vector2(45, 48); body.size = Vector2(40, 24)
			body.color = Color("#5566aa"); vis.add_child(body)
		2:
			var r1 := ColorRect.new()
			r1.position = Vector2(34, 20); r1.size = Vector2(30, 22)
			r1.color = Color("#ff4444"); vis.add_child(r1)
			var r2 := ColorRect.new()
			r2.position = Vector2(60, 30); r2.size = Vector2(35, 28)
			r2.color = Color("#4488ff"); vis.add_child(r2)
			var r3 := ColorRect.new()
			r3.position = Vector2(42, 48); r3.size = Vector2(40, 16)
			r3.color = Color("#ffcc44"); vis.add_child(r3)


# ── 时钟 (3种完全不同的视觉风格) ──
func _draw_clock(vis: Control, state: int, sc: Color) -> void:
	var cx := 65.0; var cy := 45.0
	var rim_color: Color; var face_color: Color
	var ha: float; var ma: float

	match state:
		0:  # 快 — 红色急促风格，闹钟造型
			rim_color = Color("#cc4433"); face_color = Color("#fff0e8")
			ha = -1.8; ma = -2.5
		1:  # 慢 — 蓝色沉稳风格，方形挂钟
			rim_color = Color("#335588"); face_color = Color("#e8eff8")
			ha = -0.3; ma = -0.6
		2:  # 准确 — 金色精致风格，圆形壁钟
			rim_color = Color("#c89933"); face_color = Color("#fffdf0")
			ha = -0.9; ma = -1.6

	match state:
		1:  # 方形挂钟
			var sq := ColorRect.new()
			sq.position = Vector2(22, 4); sq.size = Vector2(86, 86)
			sq.color = rim_color; vis.add_child(sq)
			var sqf := ColorRect.new()
			sqf.position = Vector2(26, 8); sqf.size = Vector2(78, 78)
			sqf.color = face_color; vis.add_child(sqf)
			# 方形表盘刻度
			for i in range(4):
				var tick := ColorRect.new()
				var tx: int = [32, 62, 32, 62][i]
				var ty: int = [14, 14, 66, 66][i]
				tick.position = Vector2(tx, ty); tick.size = Vector2(6, 6)
				tick.color = Color("#335588", 0.6); vis.add_child(tick)
			cx = 65.0; cy = 47.0
		_:
			# 圆形时钟（状态0和2）
			var rim := ColorRect.new()
			rim.position = Vector2(28, 8); rim.size = Vector2(74, 74)
			rim.color = rim_color; vis.add_child(rim)
			var face := ColorRect.new()
			face.position = Vector2(31, 11); face.size = Vector2(68, 68)
			face.color = face_color; vis.add_child(face)
			# 圆形装饰（金色表盘加罗马数字记号）
			if state == 2:
				for i in range(12):
					var mark := ColorRect.new()
					var a := TAU * i / 12.0
					mark.position = Vector2(cx + cos(a) * 26 - 1, cy + sin(a) * 26 - 1)
					mark.size = Vector2(3, 3)
					mark.color = Color("#c8a050", 0.7); vis.add_child(mark)
			else:
				# 红色闹钟加顶部铃铛
				for lx in [38, 70]:
					var bell := ColorRect.new()
					bell.position = Vector2(lx, 2); bell.size = Vector2(10, 8)
					bell.color = Color("#eecc66"); vis.add_child(bell)

	# 中心点
	var dot := ColorRect.new()
	dot.position = Vector2(cx - 3, cy - 3); dot.size = Vector2(6, 6)
	dot.color = Color("#2a2a2a"); vis.add_child(dot)

	# 时针
	var hh := Polygon2D.new()
	hh.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx + cos(ha) * 22, cy + sin(ha) * 22),
		Vector2(cx + cos(ha + 0.1) * 15, cy + sin(ha + 0.1) * 15),
	])
	hh.color = Color("#2a2a2a"); vis.add_child(hh)

	# 分针
	var mh := Polygon2D.new()
	mh.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx + cos(ma) * 32, cy + sin(ma) * 32),
		Vector2(cx + cos(ma + 0.08) * 16, cy + sin(ma + 0.08) * 16),
	])
	mh.color = Color("#444"); vis.add_child(mh)


# ── 窗户 (3种完全不同的窗外景色) ──
func _draw_window_obj(vis: Control, state: int, sc: Color) -> void:
	match state:
		0:  # 打开 — 蓝天白云、阳光明媚
			# 窗框
			var frame := ColorRect.new()
			frame.position = Vector2(20, 10); frame.size = Vector2(90, 70)
			frame.color = Color("#8a7050"); vis.add_child(frame)
			# 蓝天
			var sky := ColorRect.new()
			sky.position = Vector2(26, 16); sky.size = Vector2(78, 58)
			sky.color = Color("#5599dd"); vis.add_child(sky)
			# 太阳
			var sun := ColorRect.new()
			sun.position = Vector2(80, 22); sun.size = Vector2(14, 14)
			sun.color = Color("#ffdd44"); vis.add_child(sun)
			# 云
			for ci in range(2):
				var cloud := ColorRect.new()
				cloud.position = Vector2(34 + ci * 22, 30 + ci * 8)
				cloud.size = Vector2(18, 6); cloud.color = Color(1, 1, 1, 0.7)
				vis.add_child(cloud)
			# 竖框
			var vm := ColorRect.new()
			vm.position = Vector2(63, 16); vm.size = Vector2(4, 58)
			vm.color = Color("#6a5040"); vis.add_child(vm)
			# 底部绿色山丘
			var hill := Polygon2D.new()
			hill.polygon = PackedVector2Array([
				Vector2(26, 74), Vector2(50, 58), Vector2(104, 74)
			])
			hill.color = Color("#66aa44"); vis.add_child(hill)
			# 窗台
			var sill := ColorRect.new()
			sill.position = Vector2(15, 80); sill.size = Vector2(100, 8)
			sill.color = Color("#9a7a54"); vis.add_child(sill)

		1:  # 关闭 — 深色木百叶窗，夜晚
			# 窗框
			var df := ColorRect.new()
			df.position = Vector2(20, 10); df.size = Vector2(90, 70)
			df.color = Color("#3a2a1a"); vis.add_child(df)
			# 深色玻璃
			var dg := ColorRect.new()
			dg.position = Vector2(26, 16); dg.size = Vector2(78, 58)
			dg.color = Color("#1a1620"); vis.add_child(dg)
			# 竖框
			var dvm := ColorRect.new()
			dvm.position = Vector2(63, 16); dvm.size = Vector2(4, 58)
			dvm.color = Color("#2a2018"); vis.add_child(dvm)
			# 月亮和星星
			var moon := ColorRect.new()
			moon.position = Vector2(80, 20); moon.size = Vector2(10, 10)
			moon.color = Color("#eeeedd"); vis.add_child(moon)
			for si in range(3):
				var star := ColorRect.new()
				star.position = Vector2(32 + si * 16, 22 + si * 10)
				star.size = Vector2(2, 2); star.color = Color(1, 1, 1, 0.7)
				vis.add_child(star)
			# 横向百叶
			for ri in range(4):
				var slat := ColorRect.new()
				slat.position = Vector2(26, 28 + ri * 12); slat.size = Vector2(78, 4)
				slat.color = Color("#5a3a20"); vis.add_child(slat)
			# 窗台
			var dsill := ColorRect.new()
			dsill.position = Vector2(15, 80); dsill.size = Vector2(100, 8)
			dsill.color = Color("#3a2a1a"); vis.add_child(dsill)

		2:  # 半开 — 黄昏橙光，半掩的窗帘
			# 窗框
			var hf := ColorRect.new()
			hf.position = Vector2(20, 10); hf.size = Vector2(90, 70)
			hf.color = Color("#8a7050"); vis.add_child(hf)
			# 黄昏天空
			var hg := ColorRect.new()
			hg.position = Vector2(26, 16); hg.size = Vector2(78, 58)
			hg.color = Color("#ee9966"); vis.add_child(hg)
			# 夕阳
			var dusk_sun := ColorRect.new()
			dusk_sun.position = Vector2(40, 30); dusk_sun.size = Vector2(16, 10)
			dusk_sun.color = Color("#ff6633", 0.8); vis.add_child(dusk_sun)
			# 竖框
			var hvm := ColorRect.new()
			hvm.position = Vector2(63, 16); hvm.size = Vector2(4, 58)
			hvm.color = Color("#6a5040"); vis.add_child(hvm)
			# 左边窗帘（半掩）
			var curtain_l := ColorRect.new()
			curtain_l.position = Vector2(26, 16); curtain_l.size = Vector2(28, 58)
			curtain_l.color = Color("#cc9966", 0.65); vis.add_child(curtain_l)
			# 窗帘褶皱
			for fi in range(3):
				var fold := ColorRect.new()
				fold.position = Vector2(30 + fi * 6, 16); fold.size = Vector2(2, 58)
				fold.color = Color("#aa7744", 0.4); vis.add_child(fold)
			# 窗台
			var hsill := ColorRect.new()
			hsill.position = Vector2(15, 80); hsill.size = Vector2(100, 8)
			hsill.color = Color("#9a7a54"); vis.add_child(hsill)


# ── 书本 (3种明显不同的外观) ──
func _draw_book(vis: Control, state: int, sc: Color) -> void:
	match state:
		0:  # 打开 — 摊开的书，左右两页，奶白色纸张
			var bg := ColorRect.new()
			bg.position = Vector2(24, 22); bg.size = Vector2(82, 58)
			bg.color = Color("#887755"); vis.add_child(bg)
			var spine := ColorRect.new()
			spine.position = Vector2(63, 22); spine.size = Vector2(4, 58)
			spine.color = Color("#665544"); vis.add_child(spine)
			var lp := ColorRect.new()
			lp.position = Vector2(28, 24); lp.size = Vector2(35, 54)
			lp.color = Color("#fffdf5"); vis.add_child(lp)
			var rp := ColorRect.new()
			rp.position = Vector2(67, 24); rp.size = Vector2(35, 54)
			rp.color = Color("#fffdf5"); vis.add_child(rp)
			# 文字行
			for ly in [30, 38, 46, 54, 62]:
				var l1 := ColorRect.new()
				l1.position = Vector2(32, ly); l1.size = Vector2(26, 2)
				l1.color = Color("#aaa"); vis.add_child(l1)
				var l2 := ColorRect.new()
				l2.position = Vector2(71, ly); l2.size = Vector2(24, 2)
				l2.color = Color("#aaa"); vis.add_child(l2)
			# 红色书签绳
			var ribbon := ColorRect.new()
			ribbon.position = Vector2(62, 64); ribbon.size = Vector2(3, 14)
			ribbon.color = Color("#cc4444"); vis.add_child(ribbon)

		1:  # 合上 — 深红色精装书，金箔标题
			var cv := ColorRect.new()
			cv.position = Vector2(26, 20); cv.size = Vector2(78, 60)
			cv.color = Color("#8b3a3a"); vis.add_child(cv)
			# 金箔边框
			var border := ColorRect.new()
			border.position = Vector2(32, 26); border.size = Vector2(66, 48)
			border.color = Color("#ddaa44", 0.3); vis.add_child(border)
			# 书脊
			var spine := ColorRect.new()
			spine.position = Vector2(22, 20); spine.size = Vector2(8, 60)
			spine.color = Color("#6a2020"); vis.add_child(spine)
			# 金箔标题横线
			for ti in range(3):
				var gold_line := ColorRect.new()
				gold_line.position = Vector2(38, 38 + ti * 12); gold_line.size = Vector2(54 - ti * 6, 3)
				gold_line.color = Color("#ddaa44"); vis.add_child(gold_line)
			# 封面装饰圆
			var gem := ColorRect.new()
			gem.position = Vector2(60, 54); gem.size = Vector2(8, 8)
			gem.color = Color("#dd3344"); vis.add_child(gem)

		2:  # 半开 — 翻到一半，露出书签和书页
			var bg2 := ColorRect.new()
			bg2.position = Vector2(24, 24); bg2.size = Vector2(80, 54)
			bg2.color = Color("#a09070"); vis.add_child(bg2)
			# 左半：闭合的封面
			var lc := ColorRect.new()
			lc.position = Vector2(26, 26); lc.size = Vector2(30, 50)
			lc.color = Color("#d4b896"); vis.add_child(lc)
			# 右半：打开的页面
			var rp2 := ColorRect.new()
			rp2.position = Vector2(58, 26); rp2.size = Vector2(42, 50)
			rp2.color = Color("#fff8ee"); vis.add_child(rp2)
			# 书脊
			var spine2 := ColorRect.new()
			spine2.position = Vector2(56, 24); spine2.size = Vector2(4, 54)
			spine2.color = Color("#887766"); vis.add_child(spine2)
			# 右页文字行
			for ly2 in [32, 40, 48, 56, 64]:
				var lt := ColorRect.new()
				lt.position = Vector2(62, ly2); lt.size = Vector2(32, 2)
				lt.color = Color("#bbb"); vis.add_child(lt)
			# 蓝色书签
			var mark := ColorRect.new()
			mark.position = Vector2(80, 44); mark.size = Vector2(4, 14)
			mark.color = Color("#4488cc"); vis.add_child(mark)


# ════════════════════════════════════════════════════════════
#  交互逻辑
# ════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	if event.is_action_pressed("interact"):
		if room_open:
			_close_room()
		else:
			_open_room()


func _open_room() -> void:
	room_open = true
	room_overlay.visible = true
	_freeze_player(true)
	room_toggled.emit(true)
	# 从玩家读取当前全局视角
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and "current_view" in player:
		current_view = str(player.current_view)
	else:
		current_view = "normal"
	_refresh_all()
	_update_view_label()
	_update_progress()


func _close_room() -> void:
	room_open = false
	room_overlay.visible = false
	_freeze_player(false)
	room_toggled.emit(false)


func _on_exit() -> void:
	_close_room()


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_room()


func _on_obj_input(event: InputEvent, idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if is_completed:
		return

	if current_view != "normal":
		_show_locked_hint()
		return

	if object_states[idx] < 0:
		object_states[idx] = 0
	else:
		object_states[idx] = (object_states[idx] + 1) % 3

	_refresh_object_draw(idx)
	_refresh_view_tags(idx)
	_refresh_state_text(idx)
	_update_progress()

	if _all_correct():
		_on_complete()


func _show_locked_hint() -> void:
	if not is_instance_valid(mode_hint_label):
		return
	mode_hint_label.text = "⚠ 当前为%s视角，只能观察。请去记忆长椅切换到普通视角再操作" % _get_view_label()
	mode_hint_label.add_theme_color_override("font_color", Color("#ff8866"))
	var t := create_tween()
	t.tween_callback(func():
		if is_instance_valid(mode_hint_label):
			_update_view_label()
	).set_delay(1.8)


func _all_correct() -> bool:
	for i in range(OBJECTS.size()):
		if object_states[i] != OBJECTS[i]["correct"]:
			return false
	return true


func _refresh_all() -> void:
	for i in range(OBJECTS.size()):
		_refresh_object_draw(i)
		_refresh_view_tags(i)
		_refresh_state_text(i)


func _refresh_state_text(idx: int) -> void:
	if idx >= obj_state_labels.size():
		return
	var lbl := obj_state_labels[idx]
	if not is_instance_valid(lbl):
		return
	var obj := OBJECTS[idx]
	# 显示当前视角看到的状态名
	var state := _get_display_state(idx)
	if state >= 0:
		lbl.text = obj["states"][state]
	else:
		lbl.text = "未设置"


func _update_view_label() -> void:
	if not is_instance_valid(view_label):
		return
	if current_view == "normal":
		view_label.text = "当前视角: 普通 — 点击物体切换状态"
		view_label.add_theme_color_override("font_color", Color("#88cc88"))
	else:
		view_label.text = "当前视角: %s — 只能观察，请去记忆长椅切换到普通视角" % _get_view_label()
		view_label.add_theme_color_override("font_color", Color("#ff8866"))


func _update_progress() -> void:
	if not is_instance_valid(progress_label):
		return
	var n := 0
	for s in object_states:
		if s >= 0:
			n += 1
	progress_label.text = "已设置: %d/5" % n


func _on_complete() -> void:
	if is_completed:
		return
	is_completed = true
	_close_room()

	var cl := Label.new()
	cl.text = "✨ 全部正确！获得激光装置1！"
	cl.position = Vector2(-100, -140)
	cl.add_theme_font_size_override("font_size", 20)
	cl.add_theme_color_override("font_color", Color("#ffd700"))
	add_child(cl)
	var t := create_tween()
	t.tween_property(cl, "modulate:a", 0.0, 2.5).set_delay(1.0)
	t.tween_callback(cl.queue_free)

	puzzle_completed.emit("laser_device_1")


func _freeze_player(freeze: bool) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if "controls_enabled" in node:
			node.controls_enabled = not freeze


func update_on_view_change(view: String) -> void:
	current_view = view
	if room_open:
		_refresh_all()
		_update_view_label()


func is_solved() -> bool:
	return is_completed
