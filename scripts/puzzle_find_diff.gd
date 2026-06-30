extends Area2D
class_name PuzzleFindDifference
# ════════════════════════════════════════════════════════════
#  关卡2：找不同密室 — 左右双画面
#  7个差异分布在不同视角中
#  点击差异位置来标记
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false
var room_open: bool = false

# 7个差异
const DIFFERENCES: Array = [
	{"id": 0, "view": "normal", "pos": Vector2(-140, -30), "shape": "star", "desc": "左图多了一颗星"},
	{"id": 1, "view": "adhd",    "pos": Vector2(60, -50), "shape": "circle", "desc": "右图窗边多了一个圆"},
	{"id": 2, "view": "depression","pos": Vector2(-50, 40), "shape": "triangle", "desc": "左图角落阴影形状不同"},
	{"id": 3, "view": "autism",  "pos": Vector2(120, 20), "shape": "diamond", "desc": "右图地板花纹缺一块"},
	{"id": 4, "view": "normal",	"pos": Vector2(0, -60), "shape": "star", "desc": "屋顶颜色微差"},
	{"id": 5, "view": "adhd",    "pos": Vector2(-100, 10), "shape": "circle", "desc": "左图墙壁多了一条裂缝"},
	{"id": 6, "view": "depression","pos": Vector2(80, -20), "shape": "triangle", "desc": "右图烟囱冒烟方向相反"},
]

var found_ids: Array[int] = []

var room_container: Node2D
var left_scene: Control
var right_scene: Control
var diff_buttons: Array[Button] = []
var status_label: Label
var title_label: Label

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(280, 220)
	shape.shape = rect
	shape.position = Vector2(0, -20)
	add_child(shape)
	_build_ui()
	_add_exterior_decor()

func _add_exterior_decor() -> void:
	title_label = Label.new()
	title_label.text = "[ 找不同密室 ]"
	title_label.position = Vector2(-50, -125)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title_label)
	# 小楼外观
	var building := Polygon2D.new()
	building.polygon = PackedVector2Array([
		Vector2(-70, -60), Vector2(70, -60),
		Vector2(70, 50), Vector2(-70, 50)
	])
	building.color = Color("#8a7060")
	add_child(building)
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-80, -60), Vector2(80, -60), Vector2(0, -110)
	])
	roof.color = Color("#b04030")
	add_child(roof)

func _build_ui() -> void:
	room_container = Node2D.new()
	room_container.name = "RoomUI"
	room_container.visible = false
	add_child(room_container)

	# 背景大板
	var bg := ColorRect.new()
	bg.position = Vector2(-190, -170)
	bg.size = Vector2(380, 280)
	bg.color = Color(0.05, 0.05, 0.1, 0.94)
	room_container.add_child(bg)

	# 左画面
	left_scene = Control.new()
	left_scene.position = Vector2(-175, -150)
	left_scene.size = Vector2(160, 200)
	room_container.add_child(left_scene)
	var lbg := ColorRect.new()
	lbg.position = Vector2(0, 20)
	lbg.size = Vector2(160, 180)
	lbg.color = Color(0.15, 0.18, 0.22)
	left_scene.add_child(lbg)
	_draw_scene(left_scene, false)  # 基准场景

	# 右画面
	right_scene = Control.new()
	right_scene.position = Vector2(15, -150)
	right_scene.size = Vector2(160, 200)
	room_container.add_child(right_scene)
	var rbg := ColorRect.new()
	rbg.position = Vector2(0, 20)
	rbg.size = Vector2(160, 180)
	rbg.color = Color(0.15, 0.18, 0.22)
	right_scene.add_child(rbg)
	_draw_scene(right_scene, true)  # 变体场景

	# "左图"/"右图"标签
	var ll := Label.new()
	ll.text = "左图"
	ll.position = Vector2(-120, -145)
	ll.add_theme_font_size_override("font_size", 14)
	ll.add_theme_color_override("font_color", Color("#8888cc"))
	room_container.add_child(ll)
	var rl := Label.new()
	rl.text = "右图"
	rl.position = Vector2(70, -145)
	rl.add_theme_font_size_override("font_size", 14)
	rl.add_theme_color_override("font_color", Color("#88cc88"))
	room_container.add_child(rl)

	# 差异点（可点击按钮）
	for diff in DIFFERENCES:
		var btn := Button.new()
		btn.flat = true
		var dpos: Vector2 = diff["pos"]
		btn.position = dpos + Vector2(10, 40)
		btn.size = Vector2(18, 18)
		btn.text = ""
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.15)
		sb.set_corner_radius_all(9)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", _make_hover_style(Color.YELLOW))
		btn.visible = false
		btn.pressed.connect(_on_diff_clicked.bind(diff["id"]))
		btn.set_meta("diff_id", diff["id"])
		btn.set_meta("diff_view", diff["view"])
		room_container.add_child(btn)
		diff_buttons.append(btn)

	# 状态标签
	status_label = Label.new()
	status_label.position = Vector2(-175, 70)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "按 [E] 进入密室"
	add_child(status_label)

func _make_hover_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.5)
	sb.set_corner_radius_all(9)
	return sb

func _draw_scene(container: Control, is_variant: bool) -> void:
	var off_y := 20
	# 天空
	var sky := ColorRect.new()
	sky.position = Vector2(5, 0 + off_y)
	sky.size = Vector2(150, 60)
	sky.color = Color("#3a5a8a") if not is_variant else Color("#3a5a8c")
	container.add_child(sky)
	# 月亮
	var moon := Polygon2D.new()
	var mp := PackedVector2Array()
	for i in range(12):
		var a := TAU * i / 12.0
		mp.append(Vector2(cos(a) * 10, sin(a) * 10))
	moon.polygon = mp
	moon.position = Vector2(120, 15 + off_y) if not is_variant else Vector2(30, 12 + off_y)
	moon.color = Color("#ffddaa") if not is_variant else Color("#ffeecc")
	container.add_child(moon)
	# 星星
	for i in range(5):
		var star := Polygon2D.new()
		star.polygon = PackedVector2Array([
			Vector2(0, -3), Vector2(1, -1), Vector2(3, -1),
			Vector2(1, 0), Vector2(1, 2), Vector2(0, 1),
			Vector2(-1, 2), Vector2(-1, -1), Vector2(-3, -1), Vector2(-1, -1)
		])
		star.position = Vector2(20 + i * 28, 8 + off_y + (i % 3) * 6)
		star.color = Color("#ffffff")
		star.scale = Vector2(0.8, 0.8)
		container.add_child(star)
	# 左图多一颗星 (diff 0) — 只在variant中显示
	if is_variant:
		var extra_star := Polygon2D.new()
		extra_star.polygon = PackedVector2Array([
			Vector2(0, -4), Vector2(1, -1), Vector2(4, -1),
			Vector2(1, 0), Vector2(2, 3), Vector2(0, 1),
			Vector2(-2, 3), Vector2(-1, 0), Vector2(-4, -1), Vector2(-1, -1)
		])
		extra_star.position = Vector2(140, 5 + off_y)
		extra_star.color = Color("#ffffaa")
		container.add_child(extra_star)

	# 地面
	var ground := ColorRect.new()
	ground.position = Vector2(5, 120 + off_y)
	ground.size = Vector2(150, 60)
	ground.color = Color("#2a3a22") if not is_variant else Color("#2a3824")
	container.add_child(ground)
	# 右图地面花纹缺一块 (diff 3)
	if is_variant:
		var patch := ColorRect.new()
		patch.position = Vector2(120, 130 + off_y)
		patch.size = Vector2(8, 8)
		patch.color = Color("#1a2a12")
		container.add_child(patch)  # 缺块

	# 房子
	var house := ColorRect.new()
	house.position = Vector2(40, 50 + off_y)
	house.size = Vector2(80, 80)
	house.color = Color("#6a5440") if not is_variant else Color("#6a5442")
	container.add_child(house)
	# 屋顶
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(32, 50 + off_y), Vector2(128, 50 + off_y), Vector2(80, 20 + off_y)
	])
	roof.color = Color("#a03020") if not is_variant else Color("#a03022")
	container.add_child(roof)

	# 窗户
	for wx in [12, 52]:
		var win := ColorRect.new()
		win.position = Vector2(40 + wx, 70 + off_y)
		win.size = Vector2(20, 20)
		win.color = Color("#aad4e8") if not is_variant else Color("#aad4ea")
		container.add_child(win)
	# 右图窗边多了圆 (diff 1) — 只在variant中
	if is_variant:
		var circle := Polygon2D.new()
		var cp := PackedVector2Array()
		for i in range(8):
			var a := TAU * i / 8.0
			cp.append(Vector2(cos(a) * 6, sin(a) * 6))
		circle.polygon = cp
		circle.position = Vector2(60, 40 + off_y)
		circle.color = Color("#55ccff")
		container.add_child(circle)

	# 门
	var door := ColorRect.new()
	door.position = Vector2(70, 95 + off_y)
	door.size = Vector2(18, 35)
	door.color = Color("#3a2010")
	container.add_child(door)

	# 烟囱
	var chimney := ColorRect.new()
	chimney.position = Vector2(105, 30 + off_y)
	chimney.size = Vector2(10, 25)
	chimney.color = Color("#705040")
	container.add_child(chimney)
	# 烟囱烟 — 方向不同 (diff 6)
	var smoke := Polygon2D.new()
	if not is_variant:
		smoke.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(15, -8), Vector2(10, -16), Vector2(5, -10)
		])
	else:
		smoke.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(-15, -8), Vector2(-10, -16), Vector2(-5, -10)
		])
	smoke.position = Vector2(110, 28 + off_y)
	smoke.color = Color("#aaaaaa", 0.5)
	container.add_child(smoke)

	# 墙壁裂缝 (diff 5) — 只在variant中
	if is_variant:
		var crack := ColorRect.new()
		crack.position = Vector2(42, 88 + off_y)
		crack.size = Vector2(2, 14)
		crack.color = Color("#3a2010", 0.6)
		container.add_child(crack)

	# 角落阴影 (diff 2) — 只在variant中
	if is_variant:
		var shadow := Polygon2D.new()
		shadow.polygon = PackedVector2Array([
			Vector2(5, 170 + off_y), Vector2(25, 170 + off_y),
			Vector2(15, 150 + off_y)
		])
		shadow.color = Color(0, 0, 0, 0.3)
		container.add_child(shadow)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		status_label.text = "按 [E] 进入密室"

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed: return
	if event.is_action_pressed("interact"):
		if room_open:
			room_open = false
			room_container.visible = false
			status_label.text = "按 [E] 再次进入密室 (%d/7)" % found_ids.size()
		else:
			_open_room()

func _open_room() -> void:
	room_open = true
	room_container.visible = true
	status_label.text = "找出左右图差异! (点击) %d/7" % found_ids.size()
	hint_updated.emit("进入密室！左右两图有7处差异——切换视角(TAB)发现隐藏的。")
	_update_diff_visibility()

func _update_diff_visibility() -> void:
	var view := _get_current_view()
	for btn in diff_buttons:
		var dv: String = btn.get_meta("diff_view")
		var did: int = btn.get_meta("diff_id")
		if found_ids.has(did):
			btn.visible = false
		elif dv == view or dv == "normal":
			btn.visible = true
		else:
			btn.visible = false

func _on_diff_clicked(diff_id: int) -> void:
	if found_ids.has(diff_id): return
	found_ids.append(diff_id)
	var diff: Dictionary = DIFFERENCES[diff_id]
	hint_updated.emit("发现差异！%s (%d/7)" % [diff["desc"], found_ids.size()])
	status_label.text = "发现 %d/7" % found_ids.size()

	# 标记已发现的差异按钮
	for btn in diff_buttons:
		if btn.get_meta("diff_id") == diff_id:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 1, 0, 0.4)
			sb.set_corner_radius_all(9)
			btn.add_theme_stylebox_override("normal", sb)
			btn.disabled = true
			break

	_play_found_effect(diff_id)
	AudioManager.play_tone(660.0 + diff_id * 60, 0.2)

	if found_ids.size() >= 7:
		_complete()

func _play_found_effect(diff_id: int) -> void:
	var spark := Polygon2D.new()
	var sp := PackedVector2Array()
	for i in range(8):
		var a := TAU * i / 8.0
		sp.append(Vector2(cos(a) * 8, sin(a) * 8))
	spark.polygon = sp
	spark.color = Color("#ffd700")
	spark.position = DIFFERENCES[diff_id]["pos"] + Vector2(10, 40)
	room_container.add_child(spark)
	var t := create_tween()
	t.tween_property(spark, "scale", Vector2(2, 2), 0.4)
	t.parallel().tween_property(spark, "modulate:a", 0.0, 0.4)
	t.tween_callback(spark.queue_free)

func _complete() -> void:
	is_completed = true
	room_open = false
	room_container.visible = false
	status_label.text = "✨ 全部7个差异找到！获得激光装置1！"
	hint_updated.emit("✨ 全部7个差异已发现！获得激光装置1！")
	puzzle_completed.emit("laser_device_1")

func _get_current_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"

func update_on_view_change(_view: String) -> void:
	if room_open and not is_completed:
		_update_diff_visibility()

func is_solved() -> bool:
	return is_completed
