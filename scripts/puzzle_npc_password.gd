extends Area2D
class_name PuzzleNPCPassword

# ════════════════════════════════════════════════════════════
#  许愿堂密码台 — 密码本 + 5位数字密码锁
#  5个NPC独立分散在世界中，玩家走近按E对话。
#  密码本: 正常模式=普通文字, 自闭模式=标记字红色高亮
#  密码锁: 5位旋转数字锁, 正确答案 3 7 1 4 6
#  视觉: 一个大房子取代原来的许愿堂背景
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

# ── 密码本正文（10个标记字：出 到 错 小 怎 请 别 笑 神 早）──
const CIPHER_TEXT: String = (
	"意义之「出」其离原初语境，即已渗入他者之符号系统，彼之「到」达，"
	+ "实为结构之暴力转译。误读非「错」误，乃语言之宿命——每「小」我皆囚于自身语义之网，"
	+ "网目细密，外人莫窥其隙。「怎」可冀望对谈即通？余尝「请」观日常言说之际，辞气往来，"
	+ "宛如隔雾相呼，而所指之实，恒在雾后三寸。「别」以共鸣为真，共识不过统计之偶然。"
	+ "世人或「笑」此论为玄虚，然此正近于「神」秘主义者之洞见——理解之幻象，"
	+ "乃认知自设之绊锁。「早」于胡塞尔言「生活世界」时，已暗伏此叹："
	+ "他者之心，终是现象学之剩余，可悬置，不可拥有。"
)

const MARKER_CHARS: Array[String] = ["出","到","错","小","怎","请","别","笑","神","早"]
const CORRECT_PASSWORD: Array[int] = [3, 7, 1, 4, 6]
const PASSWORD_LEN := 5

# ── 状态 ──
var player_in_range := false
var is_completed := false
var cipher_zoom_open := false
var lock_open := false
var lock_digits: Array[int] = [0, 0, 0, 0, 0]

# ── UI 节点 ──
var _ui_canvas: CanvasLayer
var _world_visual: Node2D
var zoom_overlay: CanvasLayer
var lock_overlay: CanvasLayer


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
	rect.size = Vector2(260, 180)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)

	_make_world_visual()
	_make_ui_panel()
	_make_zoom_overlay()
	_make_lock_overlay()

	set_process(true)  # 用于锁的自动检测计时


# ════════════════════════════════════════════════════════════
#  世界中的标记（房子本体由 world.gd 用贴图绘制）
# ════════════════════════════════════════════════════════════

func _make_world_visual() -> void:
	_world_visual = Node2D.new()
	_world_visual.name = "WorldVisual"
	_world_visual.z_index = 4
	add_child(_world_visual)

	# 只保留一个小标记，房子由背景层的房子贴图负责
	var marker := Label.new()
	marker.text = "密码台"
	marker.position = Vector2(-24, -80)
	marker.add_theme_font_size_override("font_size", 16)
	marker.add_theme_color_override("font_color", Color("#a080f0"))
	_world_visual.add_child(marker)


# ════════════════════════════════════════════════════════════
#  UI 面板（CanvasLayer）：玩家靠近时显示两个大按钮
# ════════════════════════════════════════════════════════════

func _make_ui_panel() -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.name = "UICanvas"
	_ui_canvas.layer = 11
	_ui_canvas.visible = false
	add_child(_ui_canvas)

	# 面板背景
	var panel := Panel.new()
	panel.name = "UIPanel"
	panel.position = Vector2(280, 540)
	panel.size = Vector2(590, 90)
	var ps := StyleBoxFlat.new()
	ps.set_corner_radius_all(10)
	ps.bg_color = Color("#1a1520", 0.88)
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color("#6a5080")
	panel.add_theme_stylebox_override("panel", ps)
	_ui_canvas.add_child(panel)

	# 标题
	var ui_title := Label.new()
	ui_title.text = "许愿堂 · 密码台"
	ui_title.position = Vector2(20, 10)
	ui_title.add_theme_font_size_override("font_size", 16)
	ui_title.add_theme_color_override("font_color", Color("#b0a0f0"))
	panel.add_child(ui_title)

	# ── 密码本按钮 ──
	var book_btn := Button.new()
	book_btn.name = "BookBtn"
	book_btn.text = "密码本"
	book_btn.position = Vector2(20, 38)
	book_btn.size = Vector2(260, 36)
	book_btn.add_theme_font_size_override("font_size", 15)
	book_btn.pressed.connect(_open_zoom)
	_style_button(book_btn, Color("#6a5080"), Color("#d4c4ff"))
	panel.add_child(book_btn)

	# ── 密码锁按钮 ──
	var lock_btn := Button.new()
	lock_btn.name = "LockBtn"
	lock_btn.text = "密码锁"
	lock_btn.position = Vector2(300, 38)
	lock_btn.size = Vector2(270, 36)
	lock_btn.add_theme_font_size_override("font_size", 15)
	lock_btn.pressed.connect(_open_lock)
	_style_button(lock_btn, Color("#5a3050"), Color("#e0b0d0"))
	panel.add_child(lock_btn)

	# 提示
	var tip := Label.new()
	tip.text = "走进按下 E 也可交互 · 点击按钮或按 E 键"
	tip.position = Vector2(20, 46)
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color("#807080"))
	panel.add_child(tip)


func _style_button(btn: Button, bg: Color, fg: Color) -> void:
	var nb := StyleBoxFlat.new()
	nb.set_corner_radius_all(6)
	nb.bg_color = bg
	nb.border_width_left = 1; nb.border_width_right = 1
	nb.border_width_top = 1; nb.border_width_bottom = 1
	nb.border_color = bg.lightened(0.3)
	btn.add_theme_stylebox_override("normal", nb)

	var hb := StyleBoxFlat.new()
	hb.set_corner_radius_all(6)
	hb.bg_color = bg.lightened(0.2)
	hb.border_width_left = 2; hb.border_width_right = 2
	hb.border_width_top = 2; hb.border_width_bottom = 2
	hb.border_color = bg.lightened(0.5)
	btn.add_theme_stylebox_override("hover", hb)

	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)


# ════════════════════════════════════════════════════════════
#  密码本放大覆盖层（古书风格，无emoji装饰）
# ════════════════════════════════════════════════════════════

func _make_zoom_overlay() -> void:
	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 12
	zoom_overlay.visible = false
	add_child(zoom_overlay)

	var bg := ColorRect.new()
	bg.size = Vector2(1152, 648)
	bg.color = Color(0, 0, 0, 0.72)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_zoom()
	)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_overlay.add_child(bg)

	var page := Panel.new()
	page.position = Vector2(126, 54)
	page.size = Vector2(900, 540)
	page.name = "ZoomPage"
	var ps := StyleBoxFlat.new()
	ps.set_corner_radius_all(12)
	ps.bg_color = Color("#3a2a1a")
	ps.border_width_left = 4; ps.border_width_right = 4
	ps.border_width_top = 4; ps.border_width_bottom = 4
	ps.border_color = Color("#6a5040")
	page.add_theme_stylebox_override("panel", ps)
	zoom_overlay.add_child(page)

	# 内页（浅色纸）
	var inner := Panel.new()
	inner.position = Vector2(20, 20)
	inner.size = Vector2(860, 500)
	inner.name = "InnerPage"
	var ips := StyleBoxFlat.new()
	ips.set_corner_radius_all(6)
	ips.bg_color = Color("#e8dcc8")
	ips.border_width_left = 1; ips.border_width_right = 1
	ips.border_width_top = 1; ips.border_width_bottom = 1
	ips.border_color = Color("#8a7060", 0.3)
	inner.add_theme_stylebox_override("panel", ips)
	page.add_child(inner)

	var zt := Label.new()
	zt.text = "许愿堂铭文 — 密码本"
	zt.position = Vector2(40, 38)
	zt.add_theme_font_size_override("font_size", 24)
	zt.add_theme_color_override("font_color", Color("#1a1008"))
	page.add_child(zt)

	var sep := ColorRect.new()
	sep.position = Vector2(40, 74)
	sep.size = Vector2(820, 2)
	sep.color = Color("#6a5040", 0.5)
	page.add_child(sep)

	var content := RichTextLabel.new()
	content.name = "CipherContent"
	content.position = Vector2(40, 92)
	content.size = Vector2(820, 370)
	content.bbcode_enabled = true
	content.add_theme_font_size_override("normal_font_size", 20)
	content.add_theme_color_override("default_color", Color("#1a1008"))
	content.selection_enabled = false
	page.add_child(content)

	var ztip := Label.new()
	ztip.name = "ZoomTip"
	ztip.text = "点击空白处关闭 · 按E键也可关闭"
	ztip.position = Vector2(40, 496)
	ztip.add_theme_font_size_override("font_size", 14)
	ztip.add_theme_color_override("font_color", Color("#6a5040"))
	page.add_child(ztip)


func _refresh_zoom_content() -> void:
	var content: RichTextLabel = zoom_overlay.get_node_or_null("ZoomPage/CipherContent") as RichTextLabel
	if not is_instance_valid(content): return

	var view := _get_current_view()
	content.clear()

	if view == "autism":
		_append_highlighted_content(content)
	else:
		content.add_theme_color_override("default_color", Color("#1a1008"))
		content.append_text(CIPHER_TEXT)

	var ztip: Label = zoom_overlay.get_node_or_null("ZoomPage/ZoomTip") as Label
	if is_instance_valid(ztip):
		if view == "autism":
			ztip.text = "自闭视角：标记字已红色高亮 · 点击空白处关闭"
		else:
			ztip.text = "点击空白处关闭 · 按E键也可关闭"


func _append_highlighted_content(content: RichTextLabel) -> void:
	# 逐段分析 CIPHER_TEXT，遇到「X」标记字则红色加粗显示
	var remaining := CIPHER_TEXT
	while remaining.length() > 0:
		var bracket_open := remaining.find("「")
		if bracket_open == -1:
			content.add_theme_color_override("default_color", Color("#1a1008"))
			content.append_text(remaining)
			break
		# 输出「之前的部分
		if bracket_open > 0:
			content.add_theme_color_override("default_color", Color("#1a1008"))
			content.append_text(remaining.substr(0, bracket_open))
		# 找「」
		var bracket_close := remaining.find("」", bracket_open + 1)
		if bracket_close == -1:
			content.add_theme_color_override("default_color", Color("#1a1008"))
			content.append_text(remaining.substr(bracket_open))
			break
		var marker := remaining.substr(bracket_open + 1, bracket_close - bracket_open - 1)
		if marker in MARKER_CHARS:
			content.push_color(Color("#e03030"))
			content.push_bold()
			content.append_text("「" + marker + "」")
			content.pop()
			content.pop()
		else:
			content.add_theme_color_override("default_color", Color("#1a1008"))
			content.append_text(remaining.substr(bracket_open, bracket_close - bracket_open + 1))
		remaining = remaining.substr(bracket_close + 1)


func _highlight_all_markers(text: String) -> String:
	# 已重构为 _append_highlighted_content，此函数保留兼容
	return text


# ════════════════════════════════════════════════════════════
#  密码锁覆盖层（5位旋转轮盘锁）
#  每次转动后 0.8 秒自动检测，正确即解锁，无需确认按钮
# ════════════════════════════════════════════════════════════

const LOCK_DIAL_R := 48          # 轮盘半径
const LOCK_DIAL_GAP := 24        # 轮盘间距
const LOCK_PANEL_W := 600
const LOCK_PANEL_H := 300
var _auto_check_timer: float = -1.0  # -1 表示不检测

func _make_lock_overlay() -> void:
	lock_overlay = CanvasLayer.new()
	lock_overlay.layer = 13
	lock_overlay.visible = false
	add_child(lock_overlay)

	var bg := ColorRect.new()
	bg.size = Vector2(1152, 648)
	bg.color = Color(0, 0, 0, 0.72)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_lock()
	)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	lock_overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2((1152 - LOCK_PANEL_W) / 2.0, (648 - LOCK_PANEL_H) / 2.0)
	panel.size = Vector2(LOCK_PANEL_W, LOCK_PANEL_H)
	panel.name = "LockPanel"
	var ps := StyleBoxFlat.new()
	ps.set_corner_radius_all(14)
	ps.bg_color = Color("#1a1028")
	ps.border_width_left = 3; ps.border_width_right = 3
	ps.border_width_top = 3; ps.border_width_bottom = 3
	ps.border_color = Color("#4a3060")
	panel.add_theme_stylebox_override("panel", ps)
	lock_overlay.add_child(panel)

	# 标题
	var tl := Label.new()
	tl.text = "五位密码锁"
	tl.position = Vector2(20, 14)
	tl.add_theme_font_size_override("font_size", 22)
	tl.add_theme_color_override("font_color", Color("#c0a0e0"))
	panel.add_child(tl)

	# 副标题：锁体纹理
	var sub := Label.new()
	sub.text = "旋转每个轮盘至正确数字"
	sub.position = Vector2(20, 42)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#706090"))
	panel.add_child(sub)

	# 5个旋转轮盘
	var total_w := PASSWORD_LEN * (LOCK_DIAL_R * 2) + (PASSWORD_LEN - 1) * LOCK_DIAL_GAP
	var dx0 := (LOCK_PANEL_W - total_w) / 2.0
	for d in range(PASSWORD_LEN):
		_draw_lock_dial(panel, d, dx0 + d * (LOCK_DIAL_R * 2 + LOCK_DIAL_GAP))

	# 提示文字
	var tip := Label.new()
	tip.name = "LockTip"
	tip.text = "点击上下箭头旋转数字 0-9"
	tip.position = Vector2(20, LOCK_PANEL_H - 30)
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color("#706090"))
	panel.add_child(tip)


# 画一个旋转轮盘（圆形锁风格）
func _draw_lock_dial(panel: Panel, digit_idx: int, cx: float) -> void:
	var cy := 130.0  # 轮盘中心Y

	# 轮盘背景圆（用Panel + 全圆角模拟）
	var dial_bg := Panel.new()
	dial_bg.name = "DialBg_%d" % digit_idx
	dial_bg.position = Vector2(cx - LOCK_DIAL_R, cy - LOCK_DIAL_R)
	dial_bg.size = Vector2(LOCK_DIAL_R * 2, LOCK_DIAL_R * 2)
	var bs := StyleBoxFlat.new()
	bs.set_corner_radius_all(LOCK_DIAL_R)
	bs.bg_color = Color("#0d0818")
	bs.border_width_left = 2; bs.border_width_right = 2
	bs.border_width_top = 2; bs.border_width_bottom = 2
	bs.border_color = Color("#4a3060")
	dial_bg.add_theme_stylebox_override("panel", bs)
	dial_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dial_bg)

	# 数字标签
	var label := Label.new()
	label.name = "DialVal_%d" % digit_idx
	label.text = "0"
	label.position = Vector2(cx - LOCK_DIAL_R, cy - 18)
	label.size = Vector2(LOCK_DIAL_R * 2, 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color("#ffe8a0"))
	panel.add_child(label)

	# 上箭头按钮
	var up := Button.new()
	up.name = "UpBtn_%d" % digit_idx
	up.text = "▴"
	up.flat = true
	up.position = Vector2(cx - 16, cy - LOCK_DIAL_R - 28)
	up.size = Vector2(32, 24)
	up.add_theme_font_size_override("font_size", 14)
	up.add_theme_color_override("font_color", Color("#a080d0"))
	up.add_theme_color_override("font_hover_color", Color("#ffffff"))
	up.pressed.connect(_on_digit_up.bind(digit_idx))
	panel.add_child(up)

	# 下箭头按钮
	var dn := Button.new()
	dn.name = "DnBtn_%d" % digit_idx
	dn.text = "▾"
	dn.flat = true
	dn.position = Vector2(cx - 16, cy + LOCK_DIAL_R + 4)
	dn.size = Vector2(32, 24)
	dn.add_theme_font_size_override("font_size", 14)
	dn.add_theme_color_override("font_color", Color("#a080d0"))
	dn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	dn.pressed.connect(_on_digit_down.bind(digit_idx))
	panel.add_child(dn)

	# 序号标签
	var idxl := Label.new()
	idxl.text = str(digit_idx + 1)
	idxl.position = Vector2(cx - 12, cy + LOCK_DIAL_R + 32)
	idxl.size = Vector2(24, 16)
	idxl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idxl.add_theme_font_size_override("font_size", 12)
	idxl.add_theme_color_override("font_color", Color("#504070"))
	panel.add_child(idxl)


func _on_digit_up(idx: int) -> void:
	lock_digits[idx] = (lock_digits[idx] + 1) % 10
	_refresh_lock_display()
	_schedule_auto_check()
	AudioManager.play_sfx("lock_turn")

func _on_digit_down(idx: int) -> void:
	lock_digits[idx] = (lock_digits[idx] + 9) % 10
	_refresh_lock_display()
	_schedule_auto_check()
	AudioManager.play_sfx("lock_turn")

func _refresh_lock_display() -> void:
	var panel := lock_overlay.get_node_or_null("LockPanel") as Panel
	if not is_instance_valid(panel): return
	for d in range(PASSWORD_LEN):
		var lbl: Label = panel.get_node_or_null("DialVal_%d" % d) as Label
		if is_instance_valid(lbl):
			lbl.text = str(lock_digits[d])

# 每次转动后延迟 0.8s 自动检测密码
func _schedule_auto_check() -> void:
	_auto_check_timer = 0.8  # 每次转动重置计时器

func _process(delta: float) -> void:
	if _auto_check_timer > 0:
		_auto_check_timer -= delta
		if _auto_check_timer <= 0:
			_auto_check_timer = -1.0
			_do_auto_check()

# 自动检测密码是否正确
func _do_auto_check() -> void:
	var ok := true
	for i in range(PASSWORD_LEN):
		if lock_digits[i] != CORRECT_PASSWORD[i]:
			ok = false; break
	if ok:
		# 轮盘变绿
		var panel := lock_overlay.get_node_or_null("LockPanel") as Panel
		if is_instance_valid(panel):
			for d in range(PASSWORD_LEN):
				var lbl: Label = panel.get_node_or_null("DialVal_%d" % d) as Label
				if is_instance_valid(lbl):
					lbl.add_theme_color_override("font_color", Color("#80ff80"))
		await get_tree().create_timer(0.4).timeout
		_close_lock()
		_complete_puzzle()


func _open_lock() -> void:
	if is_completed: return
	if cipher_zoom_open:
		return  # 不自动切换，用户需先关闭密码本
	lock_open = true
	lock_digits = [0, 0, 0, 0, 0]
	_refresh_lock_display()
	lock_overlay.visible = true
	var player := _get_player()
	if player != null and "controls_enabled" in player:
		player.controls_enabled = false
	hint_updated.emit("密码锁已打开 — 需要5位数字密码")


func _close_lock() -> void:
	lock_open = false
	lock_overlay.visible = false
	var player := _get_player()
	if player != null and "controls_enabled" in player:
		player.controls_enabled = true


# ════════════════════════════════════════════════════════════
#  密码本显示
# ════════════════════════════════════════════════════════════

func _open_zoom() -> void:
	if is_completed: return
	if lock_open:
		return  # 不自动切换，用户需先关闭密码锁
	cipher_zoom_open = true
	_refresh_zoom_content()
	zoom_overlay.visible = true
	hint_updated.emit("打开了密码本 — 注意观察引号中的字")
	var player := _get_player()
	if player != null and "controls_enabled" in player:
		player.controls_enabled = false

func _close_zoom() -> void:
	cipher_zoom_open = false
	zoom_overlay.visible = false
	var player := _get_player()
	if player != null and "controls_enabled" in player:
		player.controls_enabled = true


# ════════════════════════════════════════════════════════════
#  交互
# ════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_ui_canvas.visible = true
		hint_updated.emit("按E或点击按钮：密码本 / 密码锁")

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_ui_canvas.visible = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed: return
	if event.is_action_pressed("interact"):
		if cipher_zoom_open:
			_close_zoom()
			get_viewport().set_input_as_handled()
			return
		if lock_open:
			_close_lock()
			get_viewport().set_input_as_handled()
			return
		# 普通状态：按E打开密码本
		_open_zoom()
		get_viewport().set_input_as_handled()


# ════════════════════════════════════════════════════════════
#  完成
# ════════════════════════════════════════════════════════════

func _complete_puzzle() -> void:
	is_completed = true
	if cipher_zoom_open: _close_zoom()
	if lock_open: _close_lock()
	_ui_canvas.visible = false
	hint_updated.emit("你获得了钥匙4！")
	puzzle_completed.emit("key_4")


# ════════════════════════════════════════════════════════════
#  辅助
# ════════════════════════════════════════════════════════════

func _get_current_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func is_solved() -> bool:
	return is_completed
