extends Area2D
class_name PuzzleNPCPassword

# ════════════════════════════════════════════════════════════
#  NPC密码台 — 站台旁5个NPC + 可点击放大的密码本
#  密码本：一段奇怪的话，含10位数字
#  自闭模式：前5位（对应NPC顺序）被高亮
#  抑郁模式：NPC透露线索
#  正确密码：1234567890
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

# ── 密码本内容 ──
const CIPHER_LINES: Array[String] = [
	"石台上刻着一段谁也读不懂的话——",
	" 1 扇门在你身后轻轻合上，",
	"有 2 个人同时说起不同的梦，",
	"台阶上有 3 道裂缝延伸到深处，",
	"井水映出第 4 个倒影却没有人站在井边，",
	"而 5 根手指都沾了墨，怎么也洗不掉。",
	"",
	"后面还刻着——",
	"第 6 夜有人敲门但无人应答，",
	" 7 根弦突然断了3根，剩下的还在颤动，",
	"墙上的 8 字在慢慢转动像要倒下来，",
	" 9 片羽毛从半空中落下来没有声音，",
	" 0 点的钟声会响起，让所有人都醒过来。",
]

const CIPHER_DIGITS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
const HIGHLIGHT_COUNT := 5  # 自闭模式高亮前5位
const PASSWORD_LEN := 10
const CORRECT_PASSWORD: String = "1234567890"

# ── NPC数据（无标签，仅位置和潜台词） ──
const NPC_DATA: Array[Dictionary] = [
	{"visible_text": "我守在这里很久了。",         "subtext": "第一个位置，像门一样"},
	{"visible_text": "知识有时是负担。",           "subtext": "第二个人，梦总是一对"},
	{"visible_text": "工具比人更诚实。",           "subtext": "第三道裂痕最危险"},
	{"visible_text": "旅途没有终点。",             "subtext": "第四个倒影无人认领"},
	{"visible_text": "倾听是最难的修行。",         "subtext": "第五根手指，沾满墨迹"},
]

# ── 状态 ──
var player_in_range := false
var is_completed := false
var npc_talked: Array[bool] = [false, false, false, false, false]
var input_digits: Array[String] = []
var cipher_zoom_open := false

# ── UI ──
var npc_markers: Array[Polygon2D] = []
var dialogue_label: RichTextLabel
var status_label: Label
var cipher_book_btn: Area2D
var zoom_overlay: CanvasLayer
var input_panel: Panel


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
	rect.size = Vector2(260, 200)
	shape.shape = rect
	shape.position = Vector2(0, -40)
	add_child(shape)

	_make_world_console()
	_make_zoom_overlay()
	_make_input_panel()


# ════════════════════════════════════════════════════════════
#  世界中的控制台
# ════════════════════════════════════════════════════════════

func _make_world_console() -> void:
	# 底座
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-100, -10), Vector2(100, -10),
		Vector2(100, 40), Vector2(-100, 40),
	])
	base.color = Color("#5a5060")
	add_child(base)

	# 控制台面板
	var panel := ColorRect.new()
	panel.position = Vector2(-100, -55)
	panel.size = Vector2(200, 44)
	panel.color = Color("#3a3050")
	add_child(panel)

	# 5个NPC站位标记（无名字标签！）
	npc_markers.clear()
	for i in range(NPC_DATA.size()):
		var nx := -75.0 + float(i) * 38.0
		var marker := Polygon2D.new()
		var pts := PackedVector2Array()
		for j in range(6):
			var a := TAU * j / 6.0
			pts.append(Vector2(cos(a) * 10, sin(a) * 10))
		marker.polygon = pts
		marker.position = Vector2(nx, -38)
		marker.color = Color("#8080a0")
		add_child(marker)
		npc_markers.append(marker)

		# 仅序号小点
		var dot := ColorRect.new()
		dot.position = Vector2(nx - 3, -52)
		dot.size = Vector2(6, 6)
		dot.color = Color("#c0c0e0", 0.4)
		add_child(dot)

	# 对话显示区
	dialogue_label = RichTextLabel.new()
	dialogue_label.name = "DialogueArea"
	dialogue_label.position = Vector2(-95, -12)
	dialogue_label.size = Vector2(190, 48)
	dialogue_label.bbcode_enabled = true
	dialogue_label.text = "按 [E] 与NPC对话"
	dialogue_label.fit_content = true
	add_child(dialogue_label)

	# 标题
	var title := Label.new()
	title.text = "[ NPC密码台 ]"
	title.position = Vector2(-48, -82)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#b0a0f0"))
	add_child(title)

	# ── 可点击密码本区域 ──
	cipher_book_btn = Area2D.new()
	cipher_book_btn.position = Vector2(65, -55)
	var bk_shape := CollisionShape2D.new()
	var bk_rect := RectangleShape2D.new()
	bk_rect.size = Vector2(32, 40)
	bk_shape.shape = bk_rect
	cipher_book_btn.add_child(bk_shape)
	cipher_book_btn.input_pickable = true
	cipher_book_btn.input_event.connect(_on_cipher_book_click)
	add_child(cipher_book_btn)

	var book_icon := ColorRect.new()
	book_icon.position = Vector2(48, -55)
	book_icon.size = Vector2(32, 40)
	book_icon.color = Color("#6a5080")
	add_child(book_icon)

	var book_lbl := Label.new()
	book_lbl.text = "密码本"
	book_lbl.position = Vector2(42, -38)
	book_lbl.add_theme_font_size_override("font_size", 9)
	book_lbl.add_theme_color_override("font_color", Color("#d4c4ff"))
	add_child(book_lbl)

	# 状态
	status_label = Label.new()
	status_label.position = Vector2(-95, 50)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "按 [E] 开始对话 · 点击右下密码本"
	add_child(status_label)


# ════════════════════════════════════════════════════════════
#  密码本放大覆盖层
# ════════════════════════════════════════════════════════════

func _make_zoom_overlay() -> void:
	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 12
	zoom_overlay.visible = false
	add_child(zoom_overlay)

	# 半透明背景
	var bg := ColorRect.new()
	bg.size = Vector2(1152, 648)
	bg.color = Color(0, 0, 0, 0.7)
	# 点击背景关闭
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_zoom()
	)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_overlay.add_child(bg)

	# 书页面板
	var page := Panel.new()
	page.position = Vector2(176, 64)
	page.size = Vector2(800, 520)
	var ps := StyleBoxFlat.new()
	ps.set_corner_radius_all(10)
	ps.bg_color = Color("#f5eed8")
	ps.border_width_left = 4; ps.border_width_right = 4
	ps.border_width_top = 4; ps.border_width_bottom = 4
	ps.border_color = Color("#8a7060")
	page.add_theme_stylebox_override("panel", ps)
	page.name = "ZoomPage"
	zoom_overlay.add_child(page)

	# 标题
	var zt := Label.new()
	zt.text = "《石台铭文》 — 密码本"
	zt.position = Vector2(30, 18)
	zt.add_theme_font_size_override("font_size", 22)
	zt.add_theme_color_override("font_color", Color("#3a2a1a"))
	page.add_child(zt)

	# 分隔线
	var sep := ColorRect.new()
	sep.position = Vector2(30, 52)
	sep.size = Vector2(740, 2)
	sep.color = Color("#8a7060", 0.4)
	page.add_child(sep)

	# 铭文内容
	var content := RichTextLabel.new()
	content.name = "CipherContent"
	content.position = Vector2(30, 68)
	content.size = Vector2(740, 400)
	content.bbcode_enabled = true
	content.add_theme_font_size_override("font_size", 18)
	content.add_theme_color_override("font_color", Color("#2a2018"))
	content.add_theme_font_size_override("normal_font_size", 18)
	page.add_child(content)

	# 底部提示
	var ztip := Label.new()
	ztip.text = "点击任意处关闭"
	ztip.position = Vector2(30, 480)
	ztip.add_theme_font_size_override("font_size", 14)
	ztip.add_theme_color_override("font_color", Color("#8a7060"))
	page.add_child(ztip)


func _refresh_zoom_content() -> void:
	var content: RichTextLabel = zoom_overlay.get_node_or_null("ZoomPage/CipherContent") as RichTextLabel
	if not is_instance_valid(content): return

	var view := _get_current_view()
	var lines := PackedStringArray()
	for i in range(CIPHER_LINES.size()):
		var line := CIPHER_LINES[i]
		if view == "autism":
			# 自闭模式：给前5行（含数字的）高亮对应数字
			line = _highlight_digits_in_line(line, i)
		lines.append(line)
	content.text = "\n".join(lines)

	var ztip: Label = zoom_overlay.get_node_or_null("ZoomPage/Label") as Label
	if is_instance_valid(ztip) and view == "autism":
		ztip.text = "注意：前5个数字（对应NPC站位顺序）被高亮 · 点击任意处关闭"


func _highlight_digits_in_line(line: String, line_idx: int) -> String:
	# 找出该行对应的数字（1-5），如果在CIPHER_DIGITS的前HIGHLIGHT_COUNT中
	for d in range(HIGHLIGHT_COUNT):
		var digit := str(CIPHER_DIGITS[d])
		if digit in line:
			# 只高亮空格包围的数字（避免高亮3根中的3等）
			var idx := line.find(" " + digit + " ")
			if idx != -1:
				line = line.replace(" " + digit + " ", " [color=#ff6644][b] " + digit + " [/b][/color] ")
				break
	return line


# ════════════════════════════════════════════════════════════
#  输入面板（世界内显示）
# ════════════════════════════════════════════════════════════

func _make_input_panel() -> void:
	input_panel = Panel.new()
	input_panel.visible = false
	input_panel.position = Vector2(-130, -100)
	input_panel.size = Vector2(260, 74)
	var ips := StyleBoxFlat.new()
	ips.set_corner_radius_all(8)
	ips.bg_color = Color("#2a2040")
	ips.border_width_left = 2; ips.border_width_right = 2
	ips.border_width_top = 2; ips.border_width_bottom = 2
	ips.border_color = Color("#6a5080")
	input_panel.add_theme_stylebox_override("panel", ips)
	add_child(input_panel)

	var ilbl := Label.new()
	ilbl.text = "输入10位密码："
	ilbl.position = Vector2(14, 8)
	ilbl.size = Vector2(232, 16)
	ilbl.add_theme_color_override("font_color", Color("#d4c4ff"))
	ilbl.add_theme_font_size_override("font_size", 13)
	input_panel.add_child(ilbl)

	var input := LineEdit.new()
	input.name = "AnswerInput"
	input.position = Vector2(14, 30)
	input.size = Vector2(232, 30)
	input.placeholder_text = "10位数字…"
	input.add_theme_font_size_override("font_size", 15)
	input_panel.add_child(input)


# ════════════════════════════════════════════════════════════
#  交互
# ════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false


func _on_cipher_book_click(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not player_in_range or is_completed: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_zoom()


func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed: return

	# 关闭放大
	if cipher_zoom_open and event.is_action_pressed("interact"):
		_close_zoom()
		return

	if cipher_zoom_open: return

	# 输入面板中的按键处理
	if input_panel.visible and event is InputEventKey and event.pressed:
		var inp: LineEdit = input_panel.get_node_or_null("AnswerInput") as LineEdit
		if not is_instance_valid(inp): return

		var key: String = event.as_text_key_label()
		if key in ["0","1","2","3","4","5","6","7","8","9"]:
			if inp.text.length() < PASSWORD_LEN:
				inp.text += key
				if inp.text.length() == PASSWORD_LEN:
					_submit_answer()
			return
		elif key == "BackSpace":
			if inp.text.length() > 0:
				inp.text = inp.text.left(inp.text.length() - 1)
			return
		elif key == "Return":
			_submit_answer()
			return

	# E键交互
	if event.is_action_pressed("interact"):
		if input_panel.visible:
			_submit_answer()
		else:
			_talk_to_next_npc()


func _talk_to_next_npc() -> void:
	var next_idx := -1
	for i in range(npc_talked.size()):
		if not npc_talked[i]:
			next_idx = i
			break

	if next_idx == -1:
		# 全对话过 → 打开输入
		_open_input()
		return

	var data: Dictionary = NPC_DATA[next_idx]
	var view := _get_current_view()

	if is_instance_valid(dialogue_label):
		match view:
			"depression":
				dialogue_label.text = "[color=#ffa0a0]%s[/color]\n[color=#a0c0ff](心想: %s)[/color]" % [data["visible_text"], data["subtext"]]
				hint_updated.emit("NPC %d 的心声: %s" % [next_idx + 1, data["subtext"]])
			"autism":
				dialogue_label.text = "[color=#c0d0ff]%s[/color]\n[color=#ffff88]位置%d — 仔细看密码本[/color]" % [data["visible_text"], next_idx + 1]
				hint_updated.emit("NPC %d: 自闭视角下注意密码本高亮的数字顺序" % [next_idx + 1])
			_:
				dialogue_label.text = "[color=#c0c0c0]%s[/color]\n[color=gray](换个视角也许能看到更多…)[/color]" % [data["visible_text"]]
				hint_updated.emit("第%d个人说了些什么…去看密码本" % [next_idx + 1])

	npc_talked[next_idx] = true
	_highlight_marker(next_idx)

	var talked := 0
	for t in npc_talked: if t: talked += 1
	status_label.text = "已对话 %d/5 · 点击密码本查看" % talked


func _open_input() -> void:
	input_panel.visible = true
	var inp: LineEdit = input_panel.get_node_or_null("AnswerInput") as LineEdit
	if is_instance_valid(inp): inp.text = ""
	status_label.text = "输入10位密码（全部对话完成）"
	hint_updated.emit("密码本中按顺序排列的10个数字就是密码")


func _submit_answer() -> void:
	var inp: LineEdit = input_panel.get_node_or_null("AnswerInput") as LineEdit
	if not is_instance_valid(inp): return
	var ans := inp.text.strip_edges()

	if ans == CORRECT_PASSWORD:
		_complete_puzzle()
	else:
		status_label.text = "密码不对……再仔细看看密码本"
		hint_updated.emit("密码错误。看清楚密码本中的10个数字顺序。")
		inp.text = ""


func _complete_puzzle() -> void:
	is_completed = true
	input_panel.visible = false
	if cipher_zoom_open: _close_zoom()
	status_label.text = "✨ 获得钥匙4（天文台钥匙）！"
	for m in npc_markers:
		if is_instance_valid(m): m.color = Color("#ffd700")
	hint_updated.emit("✨ 你获得了钥匙4！")
	puzzle_completed.emit("key_4")


# ════════════════════════════════════════════════════════════
#  密码本放大
# ════════════════════════════════════════════════════════════

func _open_zoom() -> void:
	cipher_zoom_open = true
	_refresh_zoom_content()
	zoom_overlay.visible = true
	hint_updated.emit("打开了密码本 — 仔细观察铭文中的数字")
	var player := _get_player()
	if player != null and "controls_enabled" in player:
		player.controls_enabled = false


func _close_zoom() -> void:
	cipher_zoom_open = false
	zoom_overlay.visible = false
	var player := _get_player()
	if player != null and "controls_enabled" in player:
		player.controls_enabled = true
	# 如果所有NPC对话完成且输入面板未打开，提示
	var all_talked := true
	for t in npc_talked: if not t: all_talked = false
	if all_talked and not input_panel.visible and not is_completed:
		_open_input()


# ════════════════════════════════════════════════════════════
#  辅助
# ════════════════════════════════════════════════════════════

func _highlight_marker(idx: int) -> void:
	if idx < npc_markers.size():
		var m := npc_markers[idx]
		var t := create_tween()
		t.tween_property(m, "color", Color("#ffd700"), 0.25)
		t.tween_property(m, "color", Color("#80a0c0"), 0.5)


func _get_current_view() -> String:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world and world.has_method("get_current_view"):
		return world.get_current_view()
	return "normal"


func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null


func is_solved() -> bool:
	return is_completed
