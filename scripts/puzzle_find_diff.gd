extends Area2D
class_name PuzzleFindDifference

# ════════════════════════════════════════════════════════════
#  找不同密室 — v2 完整重写
#  5个物体，各3种状态。不同视角看到不同状态。
#  只有普通视角能切换状态。没有任何单题正确提示。
#  全部正确才能通关。
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)
signal room_toggled(open: bool)

# ── 物体定义 ──
const OBJECTS: Array[Dictionary] = [
	{
		"id": "flower", "name": "花瓶",
		"states": ["开放", "闭合", "枯萎"],
		"view_states": {"adhd": 1, "depression": 1, "autism": 0},
		"correct": 1,
		"color_a": Color("#ff6677"),   # 状态0
		"color_b": Color("#cc4455"),   # 状态1
		"color_c": Color("#886644"),   # 状态2
	},
	{
		"id": "window_obj", "name": "窗户",
		"states": ["打开", "关闭", "半开"],
		"view_states": {"adhd": 2, "depression": 0, "autism": 2},
		"correct": 2,
		"color_a": Color("#88ccee"),
		"color_b": Color("#334455"),
		"color_c": Color("#6699aa"),
	},
	{
		"id": "clock", "name": "时钟",
		"states": ["快", "慢", "准确"],
		"view_states": {"adhd": 2, "depression": 1, "autism": 1},
		"correct": 1,
		"color_a": Color("#ffcc00"),
		"color_b": Color("#aa8800"),
		"color_c": Color("#ffee66"),
	},
	{
		"id": "book", "name": "书本",
		"states": ["打开", "合上", "半开"],
		"view_states": {"adhd": 1, "depression": 1, "autism": 2},
		"correct": 1,
		"color_a": Color("#ddccaa"),
		"color_b": Color("#aa9977"),
		"color_c": Color("#c8b898"),
	},
	{
		"id": "frame", "name": "画框",
		"states": ["风景", "人物", "抽象"],
		"view_states": {"adhd": 0, "depression": 0, "autism": 0},
		"correct": 0,
		"color_a": Color("#77aa66"),
		"color_b": Color("#cc9966"),
		"color_c": Color("#9966cc"),
	},
]

const VIEW_SHORT: Dictionary = {"adhd": "A", "depression": "D", "autism": "Z"}
const VIEW_LABEL: Dictionary = {"adhd": "ADHD", "depression": "抑郁", "autism": "自闭"}
const VIEW_COLORS: Dictionary = {
	"adhd": Color("#ffde4a"), "depression": Color("#8899aa"), "autism": Color("#77aaff")
}

# ── 状态 ──
var player_in_range: bool = false
var is_completed: bool = false
var room_open: bool = false
var current_view: String = "normal"

var object_player_states: Array[int] = []  # -1=未设置

# ── 房间UI ──
var room_overlay: CanvasLayer
var progress_label: Label
var exterior_label: Label
var exit_btn: Button
var obj_click_zones: Array[Control] = []
var obj_visuals: Array[Control] = []  # 物体可视化容器
var obj_view_labels: Array = []  # [{adhd:Label, depression:Label, autism:Label}]
var obj_state_texts: Array[Label] = []  # 当前状态文字

const OVERLAY_W: float = 780.0
const OVERLAY_H: float = 520.0

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
		object_player_states.append(-1)

	_make_exterior_house()
	_make_room_overlay()

# ════════════════════════════════════════════════════════════
#  世界地图上的房子外观
# ════════════════════════════════════════════════════════════
func _make_exterior_house() -> void:
	# 房子主体
	var wall := ColorRect.new()
	wall.position = Vector2(-55, -30)
	wall.size = Vector2(110, 80)
	wall.color = Color("#8a6e5c")
	add_child(wall)

	# 屋顶三角形
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-65, -30), Vector2(65, -30), Vector2(0, -75)
	])
	roof.color = Color("#a04030")
	add_child(roof)

	# 门
	var door := ColorRect.new()
	door.position = Vector2(-10, 10)
	door.size = Vector2(20, 40)
	door.color = Color("#4a3020")
	add_child(door)

	# 窗户
	for wx in [-40, 24]:
		var win := ColorRect.new()
		win.position = Vector2(wx, -10)
		win.size = Vector2(16, 16)
		win.color = Color("#aad4e8")
		add_child(win)

	# 烟囱
	var chimney := ColorRect.new()
	chimney.position = Vector2(30, -55)
	chimney.size = Vector2(8, 25)
	chimney.color = Color("#605040")
	add_child(chimney)

	# 标题
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
#  房间内景 — 画成一间真正的房间
# ════════════════════════════════════════════════════════════
func _make_room_overlay() -> void:
	room_overlay = CanvasLayer.new()
	room_overlay.name = "Room"
	room_overlay.layer = 100
	room_overlay.visible = false
	add_child(room_overlay)

	# 半透明遮罩（点击退出）
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.color = Color(0, 0, 0, 0.72)
	shade.gui_input.connect(_on_shade_input)
	room_overlay.add_child(shade)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.position = _panel_position()
	panel.size = Vector2(OVERLAY_W, OVERLAY_H)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#2a1f14")
	ps.set_corner_radius_all(16)
	ps.border_width_left = 3
	ps.border_width_right = 3
	ps.border_width_top = 3
	ps.border_width_bottom = 3
	ps.border_color = Color("#5a4a3a")
	panel.add_theme_stylebox_override("panel", ps)
	room_overlay.add_child(panel)

	# ── 绘制房间内景 ──
	_draw_room_walls(panel)
	_draw_room_floor(panel)
	_draw_room_table(panel)
	_draw_room_window(panel)

	# ── 标题 ──
	var title := Label.new()
	title.text = "找不同密室"
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#ffe8a0"))
	panel.add_child(title)

	# ── 说明 ──
	var desc := Label.new()
	desc.text = "每个物体有3种状态，A/D/Z视角分别看到不同样子。用普通视角点击物体切换状态。"
	desc.position = Vector2(20, 34)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color("#998877"))
	panel.add_child(desc)

	# ── 5个物体 ──
	_create_all_objects(panel)

	# ── 底部进度 ──
	progress_label = Label.new()
	progress_label.name = "Progress"
	progress_label.position = Vector2(20, OVERLAY_H - 32)
	progress_label.add_theme_font_size_override("font_size", 14)
	progress_label.add_theme_color_override("font_color", Color("#aa9988"))
	progress_label.text = "已确认: 0/5"
	panel.add_child(progress_label)

	# ── 模式提示 ──
	var mode_hint := Label.new()
	mode_hint.name = "ModeHint"
	mode_hint.position = Vector2(200, OVERLAY_H - 32)
	mode_hint.add_theme_font_size_override("font_size", 12)
	mode_hint.add_theme_color_override("font_color", Color("#ff8866"))
	mode_hint.text = "⚠ 请切换到普通视角才能操作物体"
	panel.add_child(mode_hint)

	# ── 退出按钮 ──
	exit_btn = Button.new()
	exit_btn.text = "✕ 退出"
	exit_btn.position = Vector2(OVERLAY_W - 80, 10)
	exit_btn.size = Vector2(60, 28)
	var es := StyleBoxFlat.new()
	es.bg_color = Color("#884444")
	es.set_corner_radius_all(5)
	exit_btn.add_theme_stylebox_override("normal", es)
	var esh := StyleBoxFlat.new()
	esh.bg_color = Color("#aa5555")
	esh.set_corner_radius_all(5)
	exit_btn.add_theme_stylebox_override("hover", esh)
	exit_btn.add_theme_color_override("font_color", Color.WHITE)
	exit_btn.add_theme_font_size_override("font_size", 13)
	exit_btn.pressed.connect(_on_exit)
	panel.add_child(exit_btn)

# ── 房间绘制元素 ──
func _draw_room_walls(panel: Panel) -> void:
	# 后墙 - 暖米色壁纸
	var back := ColorRect.new()
	back.position = Vector2(0, 0)
	back.size = Vector2(OVERLAY_W, 280)
	back.color = Color("#3d3328")
	panel.add_child(back)

	# 壁纸条纹装饰
	for i in range(15):
		var stripe := ColorRect.new()
		stripe.position = Vector2(10 + i * 52, 0)
		stripe.size = Vector2(2, 280)
		stripe.color = Color("#4a3d30", 0.4)
		back.add_child(stripe)

	# 左墙 - 稍暗的侧墙
	var left_wall := ColorRect.new()
	left_wall.position = Vector2(0, 0)
	left_wall.size = Vector2(30, OVERLAY_H)
	left_wall.color = Color("#2a1f14")
	panel.add_child(left_wall)

	# 右墙
	var right_wall := ColorRect.new()
	right_wall.position = Vector2(OVERLAY_W - 30, 0)
	right_wall.size = Vector2(30, OVERLAY_H)
	right_wall.color = Color("#2a1f14")
	panel.add_child(right_wall)

	# 墙裙 - 下半段深色
	var wainscot := ColorRect.new()
	wainscot.position = Vector2(30, 200)
	wainscot.size = Vector2(OVERLAY_W - 60, 80)
	wainscot.color = Color("#4a3728")
	panel.add_child(wainscot)

	# 墙裙装饰线
	var trim := ColorRect.new()
	trim.position = Vector2(30, 196)
	trim.size = Vector2(OVERLAY_W - 60, 4)
	trim.color = Color("#6a5040")
	panel.add_child(trim)

func _draw_room_floor(panel: Panel) -> void:
	# 木地板
	var floor := ColorRect.new()
	floor.position = Vector2(30, 280)
	floor.size = Vector2(OVERLAY_W - 60, OVERLAY_H - 280)
	floor.color = Color("#5a3a20")
	panel.add_child(floor)

	# 地板木条
	for i in range(20):
		var plank := ColorRect.new()
		plank.position = Vector2(30, 280 + i * 13)
		plank.size = Vector2(OVERLAY_W - 60, 2)
		plank.color = Color("#4a2e18", 0.5)
		floor.add_child(plank)

func _draw_room_table(panel: Panel) -> void:
	# 桌子 - 放在地板与墙交界处
	var table_top := ColorRect.new()
	table_top.position = Vector2(60, 268)
	table_top.size = Vector2(OVERLAY_W - 120, 14)
	table_top.color = Color("#8a6a4a")
	panel.add_child(table_top)

	# 桌腿
	for lx in [80, OVERLAY_W - 110]:
		var leg := ColorRect.new()
		leg.position = Vector2(lx, 282)
		leg.size = Vector2(10, 40)
		leg.color = Color("#6a4a30")
		panel.add_child(leg)

func _draw_room_window(panel: Panel) -> void:
	# 房间后墙的装饰性窗户区域 — 只是一个窗框（不是可点击的窗户物体）
	var wf := ColorRect.new()
	wf.position = Vector2(OVERLAY_W - 120, 40)
	wf.size = Vector2(80, 60)
	wf.color = Color("#446688")
	panel.add_child(wf)

	var wf_border := ColorRect.new()
	wf_border.position = Vector2(OVERLAY_W - 124, 36)
	wf_border.size = Vector2(88, 68)
	wf_border.color = Color("#6a5040")
	panel.add_child(wf_border)
	# 把窗户内容挪到前面
	wf_border.add_child(wf)
	wf.position = Vector2(4, 4)

	# 十字窗格
	var wv := ColorRect.new()
	wv.position = Vector2(38, 0)
	wv.size = Vector2(4, 60)
	wv.color = Color("#3a2a14")
	wf.add_child(wv)
	var wh := ColorRect.new()
	wh.position = Vector2(0, 28)
	wh.size = Vector2(80, 4)
	wh.color = Color("#3a2a14")
	wf.add_child(wh)

func _panel_position() -> Vector2:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return Vector2((vs.x - OVERLAY_W) / 2.0, (vs.y - OVERLAY_H) / 2.0)

# ════════════════════════════════════════════════════════════
#  5个可点击物体 — 画在房间内
# ════════════════════════════════════════════════════════════

const OBJ_POSITIONS: Array[Vector2] = [
	Vector2(120, 240),   # 花瓶 — 桌上左侧
	Vector2(560, 155),   # 窗户 — 墙上右侧
	Vector2(380, 155),   # 时钟 — 墙上中间
	Vector2(660, 240),   # 书本 — 桌上右侧
	Vector2(240, 155),   # 画框 — 墙上左侧
]

func _create_all_objects(panel: Panel) -> void:
	obj_click_zones.clear()
	obj_visuals.clear()
	obj_view_labels.clear()
	obj_state_texts.clear()

	for i in range(OBJECTS.size()):
		_create_one_object(panel, i)

func _create_one_object(panel: Panel, idx: int) -> void:
	var obj: Dictionary = OBJECTS[idx]
	var base_pos: Vector2 = OBJ_POSITIONS[idx]
	var obj_w: float = 120.0
	var obj_h: float = 160.0

	# ── 可点区域（透明） ──
	var zone := ColorRect.new()
	zone.name = "Zone_" + obj["id"]
	zone.position = base_pos
	zone.size = Vector2(obj_w, obj_h)
	zone.color = Color(1, 1, 1, 0.001)  # 几乎透明但可接收点击
	zone.gui_input.connect(_on_obj_zone_input.bind(idx))
	zone.mouse_entered.connect(func():
		if not is_completed and _get_current_view() == "normal":
			zone.color = Color(1, 0.84, 0.3, 0.12)
	)
	zone.mouse_exited.connect(func():
		zone.color = Color(1, 1, 1, 0.001)
	)
	panel.add_child(zone)
	obj_click_zones.append(zone)

	# ── 物体名称 ──
	var name_lbl := Label.new()
	name_lbl.text = obj["name"]
	name_lbl.position = Vector2(base_pos.x, base_pos.y - 18)
	name_lbl.size = Vector2(obj_w, 16)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color("#ccaa88"))
	panel.add_child(name_lbl)

	# ── 物体可视容器 ──
	var vis := Control.new()
	vis.name = "Vis_" + obj["id"]
	vis.position = base_pos + Vector2(0, 2)
	vis.size = Vector2(obj_w, 110)
	panel.add_child(vis)
	obj_visuals.append(vis)

	# ── 状态文字 ──
	var state_txt := Label.new()
	state_txt.position = Vector2(base_pos.x, base_pos.y + 114)
	state_txt.size = Vector2(obj_w, 16)
	state_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_txt.add_theme_font_size_override("font_size", 12)
	state_txt.add_theme_color_override("font_color", Color("#ffffff"))
	state_txt.text = "未设置"
	panel.add_child(state_txt)
	obj_state_texts.append(state_txt)

	# ── 视角指示行 ──
	var view_keys: Array = ["adhd", "depression", "autism"]
	var view_dict: Dictionary = {}
	var vy: float = base_pos.y + 132
	for vk in view_keys:
		var vl := Label.new()
		vl.position = Vector2(base_pos.x + 4, vy)
		vl.size = Vector2(obj_w - 8, 14)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.add_theme_font_size_override("font_size", 10)
		vl.add_theme_color_override("font_color", VIEW_COLORS[vk])
		vl.text = "%s: ??" % VIEW_SHORT[vk]
		panel.add_child(vl)
		view_dict[vk] = vl
		vy += 15
	obj_view_labels.append(view_dict)

	# 初始渲染
	_refresh_object_visual(idx)
	_refresh_view_labels(idx)

# ── 物体图形绘制 ──
func _refresh_object_visual(idx: int) -> void:
	if idx >= obj_visuals.size():
		return
	var vis: Control = obj_visuals[idx]
	if not is_instance_valid(vis):
		return

	# 清除旧绘制
	for c in vis.get_children():
		c.queue_free()

	var state: int = object_player_states[idx]  # -1, 0, 1, 2
	var obj: Dictionary = OBJECTS[idx]
	var colors: Array = [obj["color_a"], obj["color_b"], obj["color_c"]]

	if state < 0:
		# 未设置 — 显示问号
		var q := Label.new()
		q.text = "?"
		q.position = Vector2(35, 15)
		q.size = Vector2(50, 50)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.add_theme_font_size_override("font_size", 42)
		q.add_theme_color_override("font_color", Color("#554433"))
		vis.add_child(q)
		return

	var sc: Color = colors[state]

	match obj["id"]:
		"flower":
			_draw_flower(vis, state, sc)
		"window_obj":
			_draw_window_obj(vis, state, sc)
		"clock":
			_draw_clock(vis, state, sc)
		"book":
			_draw_book(vis, state, sc)
		"frame":
			_draw_frame(vis, state, sc)

func _draw_flower(vis: Control, state: int, color: Color) -> void:
	# 花盆
	var pot := ColorRect.new()
	pot.position = Vector2(55, 55)
	pot.size = Vector2(24, 30)
	pot.color = Color("#8a6040")
	vis.add_child(pot)

	var pot_rim := ColorRect.new()
	pot_rim.position = Vector2(50, 52)
	pot_rim.size = Vector2(34, 6)
	pot_rim.color = Color("#a07050")
	vis.add_child(pot_rim)

	match state:
		0:  # 开放 — 大花
			var petal_center := Vector2(67, 48)
			for a_idx in range(8):
				var a: float = TAU * a_idx / 8.0
				var p := Polygon2D.new()
				var pts := PackedVector2Array()
				pts.append(petal_center)
				var r := 14.0
				pts.append(petal_center + Vector2(cos(a - 0.2) * r, sin(a - 0.2) * r))
				pts.append(petal_center + Vector2(cos(a) * r * 1.5, sin(a) * r * 1.5))
				pts.append(petal_center + Vector2(cos(a + 0.2) * r, sin(a + 0.2) * r))
				p.polygon = pts
				p.color = color
				vis.add_child(p)
			# 花蕊
			var ctr := ColorRect.new()
			ctr.position = Vector2(59, 40)
			ctr.size = Vector2(16, 16)
			ctr.color = Color("#ffdd44")
			vis.add_child(ctr)
		1:  # 闭合 — 花苞
			var bud := Polygon2D.new()
			bud.polygon = PackedVector2Array([
				Vector2(67, 32), Vector2(55, 50), Vector2(67, 52), Vector2(79, 50)
			])
			bud.color = color.darkened(0.3)
			vis.add_child(bud)
			# 茎
			var stem := ColorRect.new()
			stem.position = Vector2(65, 50)
			stem.size = Vector2(4, 10)
			stem.color = Color("#558844")
			vis.add_child(stem)
		2:  # 枯萎 — 低垂
			var wilt_center := Vector2(67, 44)
			for a_idx in range(6):
				var a: float = TAU * a_idx / 6.0 + 1.2
				var p := Polygon2D.new()
				var pts := PackedVector2Array()
				pts.append(wilt_center)
				var r := 10.0
				pts.append(wilt_center + Vector2(cos(a - 0.15) * r, sin(a - 0.15) * r))
				pts.append(wilt_center + Vector2(cos(a) * r * 1.2, sin(a) * r * 1.2))
				pts.append(wilt_center + Vector2(cos(a + 0.15) * r, sin(a + 0.15) * r))
				p.polygon = pts
				p.color = color.darkened(0.5)
				vis.add_child(p)

func _draw_window_obj(vis: Control, state: int, color: Color) -> void:
	# 窗框
	var frame := ColorRect.new()
	frame.position = Vector2(15, 10)
	frame.size = Vector2(90, 70)
	frame.color = Color("#6a5040")
	vis.add_child(frame)

	# 玻璃
	var glass := ColorRect.new()
	glass.position = Vector2(21, 16)
	glass.size = Vector2(78, 58)
	glass.color = color
	vis.add_child(glass)

	# 十字分隔
	var vm := ColorRect.new()
	vm.position = Vector2(58, 16)
	vm.size = Vector2(4, 58)
	vm.color = Color("#4a3020")
	vis.add_child(vm)

	# 两扇窗的开合状态
	var gap: float = 0.0
	match state:
		0: gap = 20.0  # 打开
		1: gap = 0.0   # 关闭
		2: gap = 10.0  # 半开

	if gap > 0:
		# 左扇向左移，右扇向右移
		var left_panel := ColorRect.new()
		left_panel.position = Vector2(21 - gap, 16)
		left_panel.size = Vector2(35, 58)
		left_panel.color = Color("#88ccee")
		vis.add_child(left_panel)
		var right_panel := ColorRect.new()
		right_panel.position = Vector2(64 + gap, 16)
		right_panel.size = Vector2(35, 58)
		right_panel.color = Color("#88ccee")
		vis.add_child(right_panel)

	# 窗台
	var sill := ColorRect.new()
	sill.position = Vector2(10, 80)
	sill.size = Vector2(100, 8)
	sill.color = Color("#7a5a44")
	vis.add_child(sill)

func _draw_clock(vis: Control, state: int, color: Color) -> void:
	# 时钟面
	var face := ColorRect.new()
	face.position = Vector2(25, 8)
	face.size = Vector2(70, 70)
	face.color = Color("#f5f0e0")
	vis.add_child(face)

	# 边框
	var rim := ColorRect.new()
	rim.position = Vector2(22, 5)
	rim.size = Vector2(76, 76)
	rim.color = Color("#8a6a44")
	vis.add_child(rim)
	# 重新加面到前面
	rim.add_child(face)
	face.position = Vector2(3, 3)

	# 中心点
	var dot := ColorRect.new()
	dot.position = Vector2(58, 41)
	dot.size = Vector2(6, 6)
	dot.color = Color("#333")
	vis.add_child(dot)

	# 时针（不同状态指向不同角度）
	var hour_ang: float = 0.0
	var min_ang: float = 0.0
	match state:
		0:  # 快
			hour_ang = -1.8
			min_ang = -2.5
		1:  # 慢
			hour_ang = -0.3
			min_ang = -0.6
		2:  # 准确
			hour_ang = -0.9
			min_ang = -1.6

	var hh_len := 22.0
	var mh_len := 32.0
	var cx := 61.0
	var cy := 44.0

	var hour_hand := Polygon2D.new()
	hour_hand.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx + cos(hour_ang) * hh_len, cy + sin(hour_ang) * hh_len),
		Vector2(cx + cos(hour_ang + 0.1) * hh_len * 0.7, cy + sin(hour_ang + 0.1) * hh_len * 0.7),
	])
	hour_hand.color = Color("#333")
	vis.add_child(hour_hand)

	var min_hand := Polygon2D.new()
	min_hand.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx + cos(min_ang) * mh_len, cy + sin(min_ang) * mh_len),
		Vector2(cx + cos(min_ang + 0.08) * mh_len * 0.5, cy + sin(min_ang + 0.08) * mh_len * 0.5),
	])
	min_hand.color = Color("#555")
	vis.add_child(min_hand)

func _draw_book(vis: Control, state: int, color: Color) -> void:
	# 书本主体
	var book_bg := ColorRect.new()
	book_bg.position = Vector2(18, 20)
	book_bg.size = Vector2(84, 60)
	book_bg.color = color
	vis.add_child(book_bg)

	# 书脊
	var spine := ColorRect.new()
	spine.position = Vector2(18, 20)
	spine.size = Vector2(6, 60)
	spine.color = color.darkened(0.2)
	vis.add_child(spine)

	match state:
		0:  # 打开 — 两页分开
			book_bg.color = Color("#eeeecc")
			var left_page := ColorRect.new()
			left_page.position = Vector2(24, 20)
			left_page.size = Vector2(36, 60)
			left_page.color = Color("#fff8e8")
			vis.add_child(left_page)
			var right_page := ColorRect.new()
			right_page.position = Vector2(62, 20)
			right_page.size = Vector2(36, 60)
			right_page.color = Color("#fff8e8")
			vis.add_child(right_page)
			# 文字线条
			for ly in [28, 38, 48, 58]:
				var line := ColorRect.new()
				line.position = Vector2(28, ly)
				line.size = Vector2(28, 2)
				line.color = Color("#aaa")
				vis.add_child(line)
				var line2 := ColorRect.new()
				line2.position = Vector2(66, ly)
				line2.size = Vector2(28, 2)
				line2.color = Color("#aaa")
				vis.add_child(line2)
		1:  # 合上 — 闭合
			# 封面装饰
			var cover_line := ColorRect.new()
			cover_line.position = Vector2(30, 45)
			cover_line.size = Vector2(60, 3)
			cover_line.color = color.darkened(0.4)
			vis.add_child(cover_line)
			var cover_line2 := ColorRect.new()
			cover_line2.position = Vector2(35, 52)
			cover_line2.size = Vector2(50, 3)
			cover_line2.color = color.darkened(0.4)
			vis.add_child(cover_line2)
		2:  # 半开 — 中间状态
			book_bg.color = Color("#ddd8c0")
			var half_page := ColorRect.new()
			half_page.position = Vector2(24, 22)
			half_page.size = Vector2(38, 56)
			half_page.color = Color("#fff5e0")
			vis.add_child(half_page)
			for ly in [30, 40, 50]:
				var line := ColorRect.new()
				line.position = Vector2(28, ly)
				line.size = Vector2(30, 2)
				line.color = Color("#bbb")
				vis.add_child(line)

func _draw_frame(vis: Control, state: int, color: Color) -> void:
	# 画框
	var f := ColorRect.new()
	f.position = Vector2(12, 8)
	f.size = Vector2(96, 76)
	f.color = Color("#8a6a44")
	vis.add_child(f)

	# 画布
	var canvas := ColorRect.new()
	canvas.position = Vector2(20, 16)
	canvas.size = Vector2(80, 60)
	canvas.color = color
	vis.add_child(canvas)

	match state:
		0:  # 风景 — 山水画
			# 天空渐变效果（用几个矩形模拟）
			var sky := ColorRect.new()
			sky.position = Vector2(20, 16)
			sky.size = Vector2(80, 30)
			sky.color = Color("#88bbdd")
			vis.add_child(sky)
			cvs_to_front(canvas, vis)
			# 山
			var mt := Polygon2D.new()
			mt.polygon = PackedVector2Array([
				Vector2(60, 36), Vector2(20, 76), Vector2(100, 76),
				Vector2(80, 36), Vector2(70, 56), Vector2(50, 56),
			])
			mt.color = Color("#559944")
			vis.add_child(mt)
			# 太阳
			var sun := ColorRect.new()
			sun.position = Vector2(65, 22)
			sun.size = Vector2(10, 10)
			sun.color = Color("#ffdd44")
			vis.add_child(sun)
		1:  # 人物 — 肖像
			var bg := ColorRect.new()
			bg.position = Vector2(20, 16)
			bg.size = Vector2(80, 60)
			bg.color = Color("#eeddcc")
			vis.add_child(bg)
			# 头像圈
			var head := ColorRect.new()
			head.position = Vector2(48, 24)
			head.size = Vector2(24, 24)
			head.color = Color("#e8c8a0")
			vis.add_child(head)
			# 身体
			var body := ColorRect.new()
			body.position = Vector2(40, 48)
			body.size = Vector2(40, 24)
			body.color = Color("#5566aa")
			vis.add_child(body)
		2:  # 抽象 — 色块
			var r1 := ColorRect.new()
			r1.position = Vector2(28, 20)
			r1.size = Vector2(30, 22)
			r1.color = Color("#ff4444")
			vis.add_child(r1)
			var r2 := ColorRect.new()
			r2.position = Vector2(55, 30)
			r2.size = Vector2(35, 28)
			r2.color = Color("#4488ff")
			vis.add_child(r2)
			var r3 := ColorRect.new()
			r3.position = Vector2(36, 48)
			r3.size = Vector2(40, 16)
			r3.color = Color("#ffcc44")
			vis.add_child(r3)

func cvs_to_front(canvas: ColorRect, vis: Control) -> void:
	vis.remove_child(canvas)
	vis.add_child(canvas)

# ── 视角标签刷新 ──
func _refresh_view_labels(idx: int) -> void:
	if idx >= obj_view_labels.size():
		return
	var obj: Dictionary = OBJECTS[idx]
	var view_states: Dictionary = obj["view_states"]
	var labels: Dictionary = obj_view_labels[idx]
	for vk in ["adhd", "depression", "autism"]:
		var lbl: Label = labels.get(vk)
		if is_instance_valid(lbl):
			var state_idx: int = view_states[vk]
			var state_name: String = obj["states"][state_idx]
			lbl.text = "%s: %s" % [VIEW_SHORT[vk], state_name]

# ── 交互 ──
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
	_refresh_all_objects()
	_update_mode_hint()
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

func _on_obj_zone_input(event: InputEvent, idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if is_completed:
		return

	# ── 只有普通视角能切换 ──
	var view := _get_current_view()
	if view != "normal":
		_show_view_locked_hint(view)
		return

	# 循环状态: -1→0→1→2→0→1→2→...
	if object_player_states[idx] < 0:
		object_player_states[idx] = 0
	else:
		object_player_states[idx] = (object_player_states[idx] + 1) % 3

	_refresh_object_visual(idx)
	_refresh_view_labels(idx)
	_refresh_object_state_text(idx)
	_update_progress()

	# 检查是否全部正确
	if _count_correct() >= OBJECTS.size():
		_complete()

func _show_view_locked_hint(view: String) -> void:
	var panel := room_overlay.get_node_or_null("Panel")
	if not is_instance_valid(panel):
		return
	var hint := panel.get_node_or_null("ModeHint") as Label
	if is_instance_valid(hint):
		var vn: String = VIEW_LABEL.get(view, view)
		hint.text = "⚠ %s视角只能观察，请切换到普通视角才能操作物体" % vn
		hint.add_theme_color_override("font_color", Color("#ff8866"))
		var t := create_tween()
		t.tween_callback(func():
			if is_instance_valid(hint):
				hint.text = "⚠ 请切换到普通视角才能操作物体"
				hint.add_theme_color_override("font_color", Color("#ff8866"))
		).set_delay(1.8)

func _count_correct() -> int:
	var count := 0
	for i in range(OBJECTS.size()):
		if object_player_states[i] == OBJECTS[i]["correct"]:
			count += 1
	return count

func _refresh_all_objects() -> void:
	for i in range(OBJECTS.size()):
		_refresh_object_visual(i)
		_refresh_view_labels(i)
		_refresh_object_state_text(i)

func _refresh_object_state_text(idx: int) -> void:
	if idx >= obj_state_texts.size():
		return
	var lbl: Label = obj_state_texts[idx]
	if not is_instance_valid(lbl):
		return
	var obj: Dictionary = OBJECTS[idx]
	if object_player_states[idx] >= 0:
		lbl.text = obj["states"][object_player_states[idx]]
	else:
		lbl.text = "未设置"

func _update_mode_hint() -> void:
	var panel := room_overlay.get_node_or_null("Panel")
	if not is_instance_valid(panel):
		return
	var hint := panel.get_node_or_null("ModeHint") as Label
	if not is_instance_valid(hint):
		return
	var view := _get_current_view()
	if view == "normal":
		hint.text = "✓ 普通视角 — 点击物体切换状态"
		hint.add_theme_color_override("font_color", Color("#88cc88"))
	else:
		var vn: String = VIEW_LABEL.get(view, view)
		hint.text = "⚠ %s视角只能观察，请切换到普通视角才能操作物体" % vn
		hint.add_theme_color_override("font_color", Color("#ff8866"))

func _update_progress() -> void:
	if not is_instance_valid(progress_label):
		return
	# 不显示具体正确数量！只显示已确认的物品数
	var set_count := 0
	for i in range(OBJECTS.size()):
		if object_player_states[i] >= 0:
			set_count += 1
	progress_label.text = "已设置: %d/5" % set_count

func _complete() -> void:
	if is_completed:
		return
	is_completed = true
	_close_room()

	# 完成提示
	var cl := Label.new()
	cl.name = "DoneLabel"
	cl.text = "✨ 全部正确！获得激光装置1！"
	cl.position = Vector2(-100, -140)
	cl.add_theme_font_size_override("font_size", 18)
	cl.add_theme_color_override("font_color", Color("#ffd700"))
	add_child(cl)

	var t := create_tween()
	t.tween_property(cl, "modulate:a", 0.0, 2.5).set_delay(1.0)
	t.tween_callback(cl.queue_free)

	puzzle_completed.emit("laser_device_1")

func _freeze_player(freeze: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		player.controls_enabled = not freeze

# ── 视角 ──
func _get_current_view() -> String:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("get_view"):
		return main.get_view()
	return "normal"

func update_on_view_change(_view: String) -> void:
	current_view = _view
	if room_open:
		_refresh_all_view_indicators()
		_update_mode_hint()

func _refresh_all_view_indicators() -> void:
	for i in range(OBJECTS.size()):
		_refresh_view_labels(i)

func is_solved() -> bool:
	return is_completed
