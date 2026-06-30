extends Area2D
class_name PuzzleFindDifference
# ════════════════════════════════════════════════════════════
#  关卡2：找不同密室 (Find Difference Room)
#  位置：纹理墙之后，左侧第二场景
#  规则：不同视角观察同一场景→找出差异→输入密码获得激光装置1
#  产出：激光装置1
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false
var found_differences: Array[int] = []     # 已发现的差异ID
var current_view_for_diff: String = ""     # 用于找差异的视角

# 差异数据：每个差异只在特定视角下可见
# 差异对应"故事书"中的数字/符号
const DIFFERENCES: Array = [
	{"id": 0, "view": "adhd", "position_offset": Vector2(30, -20), "symbol": "★", "hint": "ADHD视角：左上角多了一颗星"},
	{"id": 1, "view": "depression", "position_offset": Vector2(-25, 15), "symbol": "◆", "hint": "抑郁视角：右侧阴影形状不同"},
	{"id": 2, "view": "adhd", "position_offset": Vector2(10, 30), "symbol": "●", "hint": "ADHD视角：地面有一个隐藏圆点"},
	{"id": 3, "view": "depression", "position_offset": Vector2(-40, -10), "symbol": "▲", "hint": "抑郁视角：窗户边框缺了一角"},
]

# 正确密码 = 收集到的符号对应的数字
const SYMBOL_CODE: Dictionary = {"★": "1", "◆": "3", "●": "5", "▲": "7"}
# 正确答案：根据发现顺序排列（这里假设全部找到后按 id 排序 = 1375）
const CORRECT_PASSWORD: String = "1375"

var input_password: String = ""
var room_visual: Node2D             # 房间场景可视化
var diff_markers: Dictionary = {}   # 差异标记节点
var ui_panel: Panel                 # UI面板（密码输入）
var status_label: Label

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_room_visual()
	_make_ui_panel()

func _make_room_visual() -> void:
	# 密室外观 — 小楼建筑
	var building := Polygon2D.new()
	var size := Vector2(160, 180)
	building.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0),
		Vector2(size.x, size.y), Vector2(0, size.y)
	])
	building.color = Color("#8a7060")
	building.offset = -size / 2.0
	add_child(building)
	room_visual = building
	
	# 屋顶三角
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-90, -90), Vector2(90, -90), Vector2(0, -140)
	])
	roof.color = Color("#a04030")
	add_child(roof)
	
	# 门
	var door := ColorRect.new()
	door.position = Vector2(-20, 30)
	door.size = Vector2(40, 70)
	door.color = Color("#4a3020")
	add_child(door)
	
	# 窗户
	for wx in [-55, 35]:
		var win := ColorRect.new()
		win.position = Vector2(wx, -45)
		win.size = Vector2(30, 30)
		win.color = Color("#c0d0e8")
		add_child(win)
	
	# 标题
	var title := Label.new()
	title.text = "[ 找不同密室 ]"
	title.position = Vector2(-55, -125)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)
	
	# 初始化差异标记（默认不可见）
	for diff in DIFFERENCES:
		var marker := Label.new()
		marker.text = diff["symbol"]
		marker.position = diff["position_offset"]
		marker.add_theme_font_size_override("font_size", 24)
		marker.add_theme_color_override("font_color", Color.RED)
		marker.visible = false
		marker.modulate.a = 0.0
		add_child(marker)
		diff_markers[diff["id"]] = marker

func _make_ui_panel() -> void:
	status_label = Label.new()
	status_label.position = Vector2(-75, 105)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "按 [E] 进入密室"
	add_child(status_label)
	
	ui_panel = Panel.new()
	ui_panel.visible = false
	ui_panel.position = Vector2(-130, -170)
	ui_panel.size = Vector2(260, 150)
	add_child(ui_panel)
	
	var plabel := Label.new()
	plabel.name = "PanelLabel"
	plabel.text = "输入密码（符号对应的数字）:"
	plabel.position = Vector2(10, 10)
	plabel.size = Vector2(240, 20)
	ui_panel.add_child(plabel)
	
	var pinput := LineEdit.new()
	pinput.name = "PasswordInput"
	pinput.position = Vector2(10, 40)
	pinput.size = Vector2(240, 30)
	ui_panel.add_child(pinput)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		status_label.text = "按 [E] 进入密室"

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if not is_completed:
			status_label.text = "按 [E] 进入密室"

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	if event.is_action_pressed("interact"):
		if ui_panel.visible:
			_submit_password()
		else:
			_open_room()

func _open_room() -> void:
	status_label.text = "切换视角寻找差异... (Tab)"
	hint_updated.emit("进入密室！用不同视角寻找场景中的异常处。")
	# 显示当前视角下的差异
	_show_current_view_differences()

func _show_current_view_differences() -> void:
	var current_view: String = _get_current_view()
	for diff in DIFFERENCES:
		var marker: Label = diff_markers[diff["id"]]
		if diff["view"] == current_view and not found_differences.has(diff["id"]):
			# 这个视角能看到这个差异
			marker.visible = true
			var tween := create_tween()
			tween.tween_property(marker, "modulate:a", 1.0, 0.5)
			tween.tween_callback(_on_difference_visible.bind(diff["id"]))
		else:
			marker.visible = false
			marker.modulate.a = 0.0

func _on_difference_visible(diff_id: int) -> void:
	if not found_differences.has(diff_id):
		found_differences.append(diff_id)
		hint_updated.emit("发现差异 #%d！共%d/%d" % [diff_id + 1, found_differences.size(), DIFFERENCES.size()])
		status_label.text = "发现 %d/%d 个差异" % [found_differences.size(), DIFFERENCES.size()]
		
		if found_differences.size() >= DIFFERENCES.size():
			_all_found()

func _all_found() -> void:
	status_label.text = "全部差异已发现！显示密码面板..."
	hint_updated.emit("所有差异已找到！请输入收集到的符号密码。")
	ui_panel.visible = true

func _submit_password() -> void:
	var input: LineEdit = ui_panel.get_node_or_null("PasswordInput") as LineEdit
	if input == null:
		return
	input_password = input.text.strip_edges()
	
	if input_password == CORRECT_PASSWORD:
		_complete_puzzle()
	else:
		status_label.text = "密码错误...再仔细看看符号"
		hint_updated.emit("密码错误。每个符号对应一个数字。")
		input.text = ""

func _complete_puzzle() -> void:
	is_completed = true
	ui_panel.visible = false
	status_label.text = "✨ 获得激光装置1！"
	hint_updated.emit("✨ 恭喜！你获得了激光装置1！")
	puzzle_completed.emit("laser_device_1")
	
	# 成功特效
	var tween := create_tween()
	tween.tween_property(room_visual, "color", Color("#ffd700"), 0.5)

func _get_current_view() -> String:
	# 从主场景获取当前视角
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world and world.has_method("get_current_view"):
		return world.get_current_view()
	return "normal"

func update_on_view_change(view: String) -> void:
	if player_in_range and not is_completed:
		current_view_for_diff = view
		_show_current_view_differences()

# ── 外部接口 ──
func get_found_count() -> int:
	return found_differences.size()

func is_solved() -> bool:
	return is_completed
