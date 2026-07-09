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
		"views": {"normal": 2, "adhd": 1, "depression": 1, "autism": 0, "blind": 0},
		"correct": 0, "color_a": Color("#ffcc00"), "color_b": Color("#aa8800"), "color_c": Color("#ffee66"),
	},
	{
		"id": "window_obj", "name": "窗户", "states": ["打开", "关闭", "半开"],
		"views": {"normal": 0, "adhd": 0, "depression": 1, "autism": 1, "blind": 2},
		"correct": 1, "color_a": Color("#88ccee"), "color_b": Color("#334455"), "color_c": Color("#6699aa"),
	},
	{
		"id": "book", "name": "书本", "states": ["打开", "合上", "半开"],
		"views": {"normal": 2, "adhd": 1, "depression": 2, "autism": 0, "blind": 1},
		"correct": 1, "color_a": Color("#ddccaa"), "color_b": Color("#aa9977"), "color_c": Color("#c8b898"),
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
#  世界地图上的房子外观
# ════════════════════════════════════════════════════════════

func _make_exterior() -> void:
	var wall := ColorRect.new()
	wall.position = Vector2(-55, -30)
	wall.size = Vector2(110, 80)
	wall.color = Color("#8a6e5c")
	add_child(wall)

	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([Vector2(-65, -30), Vector2(65, -30), Vector2(0, -75)])
	roof.color = Color("#a04030")
	add_child(roof)

	var door := ColorRect.new()
	door.position = Vector2(-10, 10)
	door.size = Vector2(20, 40)
	door.color = Color("#4a3020")
	add_child(door)

	for wx in [-40, 24]:
		var win := ColorRect.new()
		win.position = Vector2(wx, -10)
		win.size = Vector2(16, 16)
		win.color = Color("#aad4e8")
		add_child(win)

	var chimney := ColorRect.new()
	chimney.position = Vector2(30, -55)
	chimney.size = Vector2(8, 25)
	chimney.color = Color("#605040")
	add_child(chimney)

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

	# 主面板
	var panel := Panel.new()
	panel.name = "Panel"
	var vs := get_viewport().get_visible_rect().size
	panel.position = Vector2((vs.x - OW) / 2.0, (vs.y - OH) / 2.0)
	panel.size = Vector2(OW, OH)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#2a1f14")
	ps.set_corner_radius_all(16)
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#5a4a3a")
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
	# 后墙
	var back := ColorRect.new()
	back.position = Vector2(0, 120)
	back.size = Vector2(OW, 240)
	back.color = Color("#3d3328")
	panel.add_child(back)

	for i in range(17):
		var stripe := ColorRect.new()
		stripe.position = Vector2(10 + i * 50, 120)
		stripe.size = Vector2(2, 240)
		stripe.color = Color("#4a3d30", 0.35)
		back.add_child(stripe)

	# 左墙柱
	var lw := ColorRect.new()
	lw.position = Vector2(0, 120)
	lw.size = Vector2(30, OH - 120)
	lw.color = Color("#2a1f14")
	panel.add_child(lw)

	# 右墙柱
	var rw := ColorRect.new()
	rw.position = Vector2(OW - 30, 120)
	rw.size = Vector2(30, OH - 120)
	rw.color = Color("#2a1f14")
	panel.add_child(rw)

	# 墙裙
	var wain := ColorRect.new()
	wain.position = Vector2(30, 300)
	wain.size = Vector2(OW - 60, 60)
	wain.color = Color("#4a3728")
	panel.add_child(wain)

	var trim := ColorRect.new()
	trim.position = Vector2(30, 296)
	trim.size = Vector2(OW - 60, 4)
	trim.color = Color("#6a5040")
	panel.add_child(trim)

	# 木地板
	var floor := ColorRect.new()
	floor.position = Vector2(30, 360)
	floor.size = Vector2(OW - 60, OH - 360)
	floor.color = Color("#5a3a20")
	panel.add_child(floor)

	for i in range(20):
		var plank := ColorRect.new()
		plank.position = Vector2(30, 360 + i * 9)
		plank.size = Vector2(OW - 60, 2)
		plank.color = Color("#4a2e18", 0.5)
		floor.add_child(plank)

	# 桌子
	var table := ColorRect.new()
	table.position = Vector2(50, 348)
	table.size = Vector2(OW - 100, 14)
	table.color = Color("#8a6a4a")
	panel.add_child(table)

	for lx in [70, OW - 100]:
		var leg := ColorRect.new()
		leg.position = Vector2(lx, 362)
		leg.size = Vector2(10, 36)
		leg.color = Color("#6a4a30")
		panel.add_child(leg)


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


# ── 时钟 ──
func _draw_clock(vis: Control, state: int, _color: Color) -> void:
	var rim := ColorRect.new()
	rim.position = Vector2(28, 8); rim.size = Vector2(74, 74); rim.color = Color("#8a6a44")
	vis.add_child(rim)
	var face := ColorRect.new()
	face.position = Vector2(31, 11); face.size = Vector2(68, 68); face.color = Color("#f5f0e0")
	vis.add_child(face)

	var dot := ColorRect.new()
	dot.position = Vector2(63, 43); dot.size = Vector2(6, 6); dot.color = Color("#333")
	vis.add_child(dot)

	var ha: float; var ma: float
	match state:
		0: ha = -1.8; ma = -2.5
		1: ha = -0.3; ma = -0.6
		2: ha = -0.9; ma = -1.6

	var cx := 65.0; var cy := 45.0
	var hh := Polygon2D.new()
	hh.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx + cos(ha) * 22, cy + sin(ha) * 22),
		Vector2(cx + cos(ha + 0.1) * 15, cy + sin(ha + 0.1) * 15),
	])
	hh.color = Color("#333"); vis.add_child(hh)

	var mh := Polygon2D.new()
	mh.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx + cos(ma) * 32, cy + sin(ma) * 32),
		Vector2(cx + cos(ma + 0.08) * 16, cy + sin(ma + 0.08) * 16),
	])
	mh.color = Color("#555"); vis.add_child(mh)


# ── 窗户 ──
func _draw_window_obj(vis: Control, state: int, color: Color) -> void:
	var frame := ColorRect.new()
	frame.position = Vector2(20, 10); frame.size = Vector2(90, 70); frame.color = Color("#6a5040")
	vis.add_child(frame)
	var glass := ColorRect.new()
	glass.position = Vector2(26, 16); glass.size = Vector2(78, 58); glass.color = color
	vis.add_child(glass)
	var vm := ColorRect.new()
	vm.position = Vector2(63, 16); vm.size = Vector2(4, 58); vm.color = Color("#4a3020")
	vis.add_child(vm)
	var sill := ColorRect.new()
	sill.position = Vector2(15, 80); sill.size = Vector2(100, 8); sill.color = Color("#7a5a44")
	vis.add_child(sill)

	var gap: float
	match state:
		0: gap = 20.0
		1: gap = 0.0
		2: gap = 10.0
	if gap > 0:
		var lp := ColorRect.new()
		lp.position = Vector2(26 - gap, 16); lp.size = Vector2(35, 58)
		lp.color = Color("#88ccee"); vis.add_child(lp)
		var rp := ColorRect.new()
		rp.position = Vector2(69 + gap, 16); rp.size = Vector2(35, 58)
		rp.color = Color("#88ccee"); vis.add_child(rp)


# ── 书本 ──
func _draw_book(vis: Control, state: int, color: Color) -> void:
	var bg := ColorRect.new()
	bg.position = Vector2(24, 22); bg.size = Vector2(82, 58); bg.color = color
	vis.add_child(bg)
	var spine := ColorRect.new()
	spine.position = Vector2(24, 22); spine.size = Vector2(6, 58)
	spine.color = color.darkened(0.2); vis.add_child(spine)

	match state:
		0:
			bg.color = Color("#eeeecc")
			var lp := ColorRect.new()
			lp.position = Vector2(30, 22); lp.size = Vector2(34, 58)
			lp.color = Color("#fff8e8"); vis.add_child(lp)
			var rp := ColorRect.new()
			rp.position = Vector2(66, 22); rp.size = Vector2(34, 58)
			rp.color = Color("#fff8e8"); vis.add_child(rp)
			for ly in [30, 40, 50, 60]:
				var l1 := ColorRect.new()
				l1.position = Vector2(34, ly); l1.size = Vector2(26, 2)
				l1.color = Color("#aaa"); vis.add_child(l1)
				var l2 := ColorRect.new()
				l2.position = Vector2(70, ly); l2.size = Vector2(26, 2)
				l2.color = Color("#aaa"); vis.add_child(l2)
		1:
			var cl1 := ColorRect.new()
			cl1.position = Vector2(36, 44); cl1.size = Vector2(58, 3)
			cl1.color = color.darkened(0.4); vis.add_child(cl1)
			var cl2 := ColorRect.new()
			cl2.position = Vector2(42, 52); cl2.size = Vector2(46, 3)
			cl2.color = color.darkened(0.4); vis.add_child(cl2)
		2:
			bg.color = Color("#ddd8c0")
			var hp := ColorRect.new()
			hp.position = Vector2(30, 24); hp.size = Vector2(36, 54)
			hp.color = Color("#fff5e0"); vis.add_child(hp)
			for ly in [32, 42, 52]:
				var l := ColorRect.new()
				l.position = Vector2(34, ly); l.size = Vector2(28, 2)
				l.color = Color("#bbb"); vis.add_child(l)


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
