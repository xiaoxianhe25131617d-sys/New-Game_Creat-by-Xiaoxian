extends Area2D
class_name PuzzleLaserFocus
# ════════════════════════════════════════════════════════════
#  激光双人聚焦游戏
#  两个激光装置需要同时调整角度，聚焦到同一个移动目标点
#  10个随机目标点，普通/抑郁/自闭：0.2秒/点（极难）
#  ADHD：5倍慢，1秒/点（清晰可控）
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false
var challenge_active: bool = false
var lasers_placed: bool = false
var _slot1_filled: bool = false
var _slot2_filled: bool = false

# ── 游戏参数 ──
const TOTAL_TARGETS := 10
const TIME_FAST: float = 1.5        # 普通/抑郁/自闭模式（原0.2秒，现1.5秒，更宽松）
const TIME_ADHD: float = 3.0        # ADHD模式（3秒/点）
const HIT_THRESHOLD: float = 40.0   # 命中判定距离(px)
const ANGLE_SPEED: float = 4.0      # 键盘旋转速度(rad/s)

# ── 激光状态 ──
var laser1_angle: float = 0.0
var laser2_angle: float = 0.0
var laser1_origin := Vector2.ZERO   # 世界坐标系中的激光1位置
var laser2_origin := Vector2.ZERO   # 世界坐标系中的激光2位置

# ── 游戏状态 ──
var current_target := Vector2.ZERO
var targets_hit: int = 0
var targets_attempted: int = 0
var round_timer: float = 0.0
var time_limit: float = TIME_FAST
var game_over: bool = false

# ── UI 节点 ──
var overlay: CanvasLayer
var game_panel: Control
var timer_bar: ColorRect
var timer_bg: ColorRect
var score_label: Label
var status_label: Label
var hint_label: Label
var target_sprite: ColorRect
var beam1_draw: Line2D
var beam2_draw: Line2D
var laser1_handle: Control
var laser2_handle: Control
var _house_front: Sprite2D
var _house_back: Sprite2D

const HOUSE_FRONT_TEXTURE := preload("res://assets/houses/puzzle_house_matched_front.png")
const HOUSE_BACK_TEXTURE := preload("res://assets/houses/puzzle_house_matched_back.png")
const HOUSE_POSITION := Vector2(0.0, -84.5)

# ── 拖拽状态 ──
var dragging_laser: int = 0  # 0=none, 1=laser1, 2=laser2
var drag_start_angle: float = 0.0
var drag_start_mouse_angle: float = 0.0
var device1_screen_center := Vector2.ZERO
var device2_screen_center := Vector2.ZERO

# ── 粒子效果 ──
var particles: Array[ColorRect] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(180, 160)
	shape.shape = rect
	shape.position = Vector2(0, -60)
	add_child(shape)
	_make_hint_label()
	_make_exterior_visual()


func _make_exterior_visual() -> void:
	# The puzzle lives inside a small illustrated house. The backboard stays
	# behind the player while the front facade hides the device from outside.
	_house_back = Sprite2D.new()
	_house_back.name = "HouseBackboard"
	_house_back.texture = HOUSE_BACK_TEXTURE
	_house_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_back.scale = Vector2(0.28, 0.28)
	_house_back.position = HOUSE_POSITION
	_house_back.modulate.a = 0.0
	_house_back.z_index = 3
	add_child(_house_back)

	_house_front = Sprite2D.new()
	_house_front.name = "HouseFront"
	_house_front.texture = HOUSE_FRONT_TEXTURE
	_house_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_front.scale = Vector2(0.28, 0.28)
	_house_front.position = HOUSE_POSITION
	_house_front.z_index = 5
	add_child(_house_front)

	# 世界空间中的台面外观（在门内仍能看到）
	var platform := ColorRect.new()
	platform.position = Vector2(-90, -10)
	platform.size = Vector2(180, 14)
	platform.color = Color("#3a3a4a")
	platform.z_index = -2
	add_child(platform)

	var top_surface := ColorRect.new()
	top_surface.position = Vector2(-90, -14)
	top_surface.size = Vector2(180, 4)
	top_surface.color = Color("#5a5a6a")
	top_surface.z_index = -1
	add_child(top_surface)

	# 凹槽1（左）
	var slot1 := ColorRect.new()
	slot1.position = Vector2(-50, -6)
	slot1.size = Vector2(24, 20)
	slot1.color = Color("#181820")
	slot1.z_index = -1
	slot1.name = "Slot1"
	add_child(slot1)

	var slot1_border := ColorRect.new()
	slot1_border.position = Vector2(-52, -8)
	slot1_border.size = Vector2(28, 24)
	slot1_border.color = Color("#444466", 0.0)
	slot1_border.z_index = -2
	add_child(slot1_border)

	# 凹槽2（右）
	var slot2 := ColorRect.new()
	slot2.position = Vector2(26, -6)
	slot2.size = Vector2(24, 20)
	slot2.color = Color("#181820")
	slot2.z_index = -1
	slot2.name = "Slot2"
	add_child(slot2)

	var slot2_border := ColorRect.new()
	slot2_border.position = Vector2(24, -8)
	slot2_border.size = Vector2(28, 24)
	slot2_border.color = Color("#444466", 0.0)
	slot2_border.z_index = -2
	add_child(slot2_border)

	var title := Label.new()
	title.text = "激光聚焦台"
	title.position = Vector2(-50, -54)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#88ccff"))
	add_child(title)


func _make_hint_label() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-135, -92)
	hint_label.size = Vector2(270, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.text = "靠近后将激光装置拖入凹槽"
	add_child(hint_label)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_set_house_inside(true)
		if not is_completed:
			_update_exterior_hint()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_set_house_inside(false)
		if _install_open:
			_close_install_panel()

func _set_house_inside(inside: bool) -> void:
	if is_instance_valid(_house_front):
		_house_front.modulate.a = 0.0 if inside else 1.0
	if is_instance_valid(_house_back):
		_house_back.modulate.a = 1.0 if inside else 0.0


func _update_exterior_hint() -> void:
	if lasers_placed:
		hint_label.text = "按 [E] 开始聚焦挑战！"
	else:
		var has_l1 := _has_laser_device("laser_device_1")
		var has_l2 := _has_laser_device("laser_device_2")
		if has_l1 and has_l2:
			hint_label.text = "两台激光装置已就绪\n点击凹槽安装装置"
		elif has_l1:
			hint_label.text = "缺少激光装置2 — 去石台拼图获得"
		elif has_l2:
			hint_label.text = "缺少激光装置1 — 去找不同密室获得"
		else:
			hint_label.text = "需要两台激光装置 — 完成找不同和石台拼图"
	_update_slot_click_areas()


func _has_laser_device(id: String) -> bool:
	var main_node := _get_main()
	if main_node == null:
		return false
	return bool(main_node.call("is_laser_available_for_focus", id))

func restore_installation_state(state: Dictionary) -> void:
	_slot1_filled = bool(state.get("laser_focus_1_installed", false))
	_slot2_filled = bool(state.get("laser_focus_2_installed", false))
	lasers_placed = _slot1_filled and _slot2_filled


func _get_main() -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		var parent := node.get_parent()
		if parent != null and parent.has_method("autosave"):
			return parent
	return null


# ═══════════════════════════════════════════════════════
#  输入处理
# ═══════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# ESC 随时可用：关闭安装面板 or 退出关卡
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _install_open:
			_close_install_panel()
			get_viewport().set_input_as_handled()
			return
		if challenge_active:
			_close_overlay()
			challenge_active = false
			game_over = false
			_disable_player(false)
			get_viewport().set_input_as_handled()
			return

	if not player_in_range or is_completed:
		return

	if not challenge_active:
		if event.is_action_pressed("interact"):
			_try_start()
			get_viewport().set_input_as_handled()
		return

	# ── 游戏中：鼠标拖拽旋转激光 ──
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_start_drag(event.position)
			else:
				_end_drag()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and dragging_laser != 0:
		_update_drag(event.position)
		get_viewport().set_input_as_handled()

	# ── 键盘快速旋转 ──
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_A: _rotate_laser(1, -ANGLE_SPEED * 0.05)
			KEY_D: _rotate_laser(1, ANGLE_SPEED * 0.05)
			KEY_LEFT:  _rotate_laser(2, -ANGLE_SPEED * 0.05)
			KEY_RIGHT: _rotate_laser(2, ANGLE_SPEED * 0.05)


var _install_overlay: CanvasLayer = null  # 安装面板（按E时显示）
var _install_open: bool = false


func _try_start() -> void:
	if not lasers_placed:
		# 打开安装面板
		if _install_open:
			_close_install_panel()
		else:
			_open_install_panel()
		return
	_start_challenge()


## ── 安装面板 ──

func _open_install_panel() -> void:
	if _install_open:
		return
	_install_open = true
	_disable_player(true)

	_install_overlay = CanvasLayer.new()
	_install_overlay.name = "LaserInstallPanel"
	_install_overlay.layer = 150
	get_tree().root.add_child(_install_overlay)

	var vs := get_viewport().get_visible_rect().size
	var pw := 400.0; var ph := 220.0
	var px := (vs.x - pw) / 2.0; var py := (vs.y - ph) / 2.0

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	_install_overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(px, py)
	panel.size = Vector2(pw, ph)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#1a1a2e"); ps.set_corner_radius_all(12)
	ps.border_width_left = 2; ps.border_width_right = 2
	ps.border_width_top = 2; ps.border_width_bottom = 2
	ps.border_color = Color("#3355aa")
	panel.add_theme_stylebox_override("panel", ps)
	_install_overlay.add_child(panel)

	var title := Label.new()
	title.text = "将激光装置拖入凹槽"
	title.position = Vector2(0, 14); title.size = Vector2(pw, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#88ccff"))
	panel.add_child(title)

	# 凹槽1
	_make_install_slot(panel, 1, Vector2(40, 70), Color("#ff4444"), "激光装置 1\n(红)", _slot1_filled)
	# 凹槽2
	_make_install_slot(panel, 2, Vector2(230, 70), Color("#44aaff"), "激光装置 2\n(蓝)", _slot2_filled)

	var hint := Label.new()
	hint.text = "点击凹槽放入装置 | E/ESC 关闭"
	hint.position = Vector2(0, ph - 32); hint.size = Vector2(pw, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#667788"))
	panel.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(pw - 34, 8); close_btn.size = Vector2(26, 26)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#553333"); cs.set_corner_radius_all(4)
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.pressed.connect(_close_install_panel)
	panel.add_child(close_btn)


func _make_install_slot(panel: Panel, slot_idx: int, pos: Vector2, color: Color, label_text: String, filled: bool) -> void:
	var has_device := _has_laser_device("laser_device_%d" % slot_idx)

	var slot_bg := ColorRect.new()
	slot_bg.position = pos; slot_bg.size = Vector2(130, 100)
	slot_bg.color = Color("#252535") if not filled else Color("#2a2a4a")
	panel.add_child(slot_bg)

	var border := ColorRect.new()
	border.position = pos - Vector2(2, 2); border.size = Vector2(134, 104)
	border.color = color if filled else Color("#445566")
	border.z_index = -1
	panel.add_child(border)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.position = pos + Vector2(0, 8); lbl.size = Vector2(130, 40)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)

	if filled:
		var filled_lbl := Label.new()
		filled_lbl.text = "✓ 已安装"
		filled_lbl.position = pos + Vector2(0, 58); filled_lbl.size = Vector2(130, 24)
		filled_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		filled_lbl.add_theme_font_size_override("font_size", 14)
		filled_lbl.add_theme_color_override("font_color", Color("#44ff88"))
		panel.add_child(filled_lbl)
	elif has_device:
		var btn := Button.new()
		btn.text = "▼ 放入凹槽"
		btn.position = pos + Vector2(15, 58); btn.size = Vector2(100, 30)
		var bs := StyleBoxFlat.new()
		bs.bg_color = color.darkened(0.3); bs.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", bs)
		var bsh := StyleBoxFlat.new()
		bsh.bg_color = color; bsh.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("hover", bsh)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_slot_clicked.bind(slot_idx))
		panel.add_child(btn)
	else:
		var no_lbl := Label.new()
		no_lbl.text = "未获得"
		no_lbl.position = pos + Vector2(0, 62); no_lbl.size = Vector2(130, 22)
		no_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_lbl.add_theme_font_size_override("font_size", 12)
		no_lbl.add_theme_color_override("font_color", Color("#886655"))
		panel.add_child(no_lbl)


func _close_install_panel() -> void:
	_install_open = false
	_disable_player(false)
	if _install_overlay != null and is_instance_valid(_install_overlay):
		_install_overlay.queue_free()
		_install_overlay = null


func _on_slot_clicked(slot_idx: int) -> void:
	var main_node := _get_main()
	if main_node == null or not bool(main_node.call("install_laser_in_focus", slot_idx)):
		hint_updated.emit("该激光装置已放置在其他位置。")
		_close_install_panel()
		return
	if slot_idx == 1:
		_slot1_filled = true
	else:
		_slot2_filled = true
	_update_slot_visuals()
	_close_install_panel()
	if _slot1_filled and _slot2_filled:
		lasers_placed = true
		hint_label.text = "两台装置安装完毕！按 [E] 开始挑战"
		hint_updated.emit("按E开始激光聚焦挑战！")
	else:
		var missing := 2 if _slot1_filled else 1
		hint_label.text = "还需安装激光装置%d，按E再次打开安装面板" % missing


func _update_slot_click_areas() -> void:
	pass  # 不再需要，使用 _install_overlay 面板替代


func _update_slot_visuals() -> void:
	# 清理旧的装置图标
	for ch in get_children():
		if ch.name == "Device1Visual" or ch.name == "Device2Visual":
			ch.queue_free()

	if _slot1_filled:
		for ch in get_children():
			if ch is ColorRect and ch.name == "Slot1":
				ch.color = Color("#2a2a40")
		var d1 := ColorRect.new()
		d1.position = Vector2(-46, -10)
		d1.size = Vector2(16, 16)
		d1.color = Color("#ff4444", 0.9)
		d1.name = "Device1Visual"
		add_child(d1)

	if _slot2_filled:
		for ch in get_children():
			if ch is ColorRect and ch.name == "Slot2":
				ch.color = Color("#2a2a40")
		var d2 := ColorRect.new()
		d2.position = Vector2(30, -10)
		d2.size = Vector2(16, 16)
		d2.color = Color("#44aaff", 0.9)
		d2.name = "Device2Visual"
		add_child(d2)


# ═══════════════════════════════════════════════════════
#  游戏流程
# ═══════════════════════════════════════════════════════

func _start_challenge() -> void:
	challenge_active = true
	game_over = false
	targets_hit = 0
	targets_attempted = 0
	round_timer = 0.0

	var view := _get_view()
	if view == "adhd":
		time_limit = TIME_ADHD
	else:
		time_limit = TIME_FAST

	_disable_player(true)
	_make_game_overlay()
	_setup_laser_origins()
	_spawn_next_target()


func _setup_laser_origins() -> void:
	var vs := get_viewport().get_visible_rect().size
	# 激光原点位于游戏面板内，左/右两侧
	var panel_center := Vector2(vs.x * 0.5, vs.y * 0.78)
	laser1_origin = Vector2(panel_center.x - 160, panel_center.y)
	laser2_origin = Vector2(panel_center.x + 160, panel_center.y)
	laser1_angle = 0.0
	laser2_angle = 0.0


func _make_game_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "LaserFocusOverlay"
	overlay.layer = 200
	# 必须挂到场景根节点，挂到 Area2D 下 CanvasLayer 会跟随世界相机偏移
	get_tree().root.add_child(overlay)

	# 暗背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	bg.name = "OverlayBG"
	overlay.add_child(bg)

	var vs := get_viewport().get_visible_rect().size

	# ── 游戏面板 ──
	game_panel = Control.new()
	game_panel.name = "GamePanel"
	game_panel.position = Vector2(140, 40)
	game_panel.size = Vector2(vs.x - 280, vs.y - 80)
	overlay.add_child(game_panel)

	# 面板背景
	var panel_bg := ColorRect.new()
	panel_bg.position = Vector2.ZERO
	panel_bg.size = game_panel.size
	panel_bg.color = Color("#0d0d1a", 0.9)
	game_panel.add_child(panel_bg)

	var panel_border := ColorRect.new()
	panel_border.position = Vector2(-2, -2)
	panel_border.size = game_panel.size + Vector2(4, 4)
	panel_border.color = Color("#334466")
	game_panel.add_child(panel_border)

	# ── 标题 ──
	var title := Label.new()
	title.text = "◆ 激光聚焦挑战 ◆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 8)
	title.size = Vector2(game_panel.size.x, 30)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#88ccff"))
	game_panel.add_child(title)

	# ── 分数 ──
	score_label = Label.new()
	score_label.text = "命中：0 / %d" % TOTAL_TARGETS
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(0, 44)
	score_label.size = Vector2(game_panel.size.x, 24)
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", Color("#ffd760"))
	game_panel.add_child(score_label)

	# ── 计时条 ──
	timer_bg = ColorRect.new()
	timer_bg.position = Vector2(20, 80)
	timer_bg.size = Vector2(game_panel.size.x - 40, 12)
	timer_bg.color = Color("#1a1a2e")
	game_panel.add_child(timer_bg)

	timer_bar = ColorRect.new()
	timer_bar.position = Vector2(20, 80)
	timer_bar.size = Vector2(game_panel.size.x - 40, 12)
	timer_bar.color = Color("#ff4444")
	game_panel.add_child(timer_bar)

	# ── 状态文本 ──
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(0, 100)
	status_label.size = Vector2(game_panel.size.x, 24)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("#ffa0a0"))
	game_panel.add_child(status_label)

	# ── 激光束（使用 draw 方式）──
	beam1_draw = Line2D.new()
	beam1_draw.name = "Beam1"
	beam1_draw.width = 3.0
	beam1_draw.default_color = Color("#ff4444", 0.6)
	beam1_draw.z_index = 5
	beam1_draw.add_point(Vector2.ZERO)
	beam1_draw.add_point(Vector2.ZERO)
	game_panel.add_child(beam1_draw)

	beam2_draw = Line2D.new()
	beam2_draw.name = "Beam2"
	beam2_draw.width = 3.0
	beam2_draw.default_color = Color("#44aaff", 0.6)
	beam2_draw.z_index = 5
	beam2_draw.add_point(Vector2.ZERO)
	beam2_draw.add_point(Vector2.ZERO)
	game_panel.add_child(beam2_draw)

	# ── 目标点 ──
	target_sprite = ColorRect.new()
	target_sprite.name = "Target"
	target_sprite.size = Vector2(16, 16)
	target_sprite.color = Color("#ffd700")
	target_sprite.visible = false
	game_panel.add_child(target_sprite)

	# ── 激光手柄 ──
	laser1_handle = _make_laser_handle(Color("#ff4444"), "L1")
	game_panel.add_child(laser1_handle)

	laser2_handle = _make_laser_handle(Color("#44aaff"), "L2")
	game_panel.add_child(laser2_handle)

	# ── 旋转提示标签（手柄旁边显示） ──
	var rot_hint1 := Label.new()
	rot_hint1.name = "RotHint1"
	rot_hint1.text = "← A/D →\n拖拽旋转"
	rot_hint1.add_theme_font_size_override("font_size", 11)
	rot_hint1.add_theme_color_override("font_color", Color("#ff6666", 0.8))
	rot_hint1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rot_hint1.size = Vector2(70, 30)
	game_panel.add_child(rot_hint1)

	var rot_hint2 := Label.new()
	rot_hint2.name = "RotHint2"
	rot_hint2.text = "← ← →\n拖拽旋转"
	rot_hint2.add_theme_font_size_override("font_size", 11)
	rot_hint2.add_theme_color_override("font_color", Color("#6699ff", 0.8))
	rot_hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rot_hint2.size = Vector2(70, 30)
	game_panel.add_child(rot_hint2)

	# ── 底部提示 ──
	var bottom_hint := Label.new()
	bottom_hint.text = "拖拽红色/蓝色手柄旋转激光 | A/D 调左束  ← → 调右束 | ESC退出"
	bottom_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_hint.position = Vector2(0, game_panel.size.y - 36)
	bottom_hint.size = Vector2(game_panel.size.x, 24)
	bottom_hint.add_theme_font_size_override("font_size", 14)
	bottom_hint.add_theme_color_override("font_color", Color("#667788"))
	game_panel.add_child(bottom_hint)

	# ── 退出按钮（明显位置）──
	var quit_btn := Button.new()
	quit_btn.text = "✕ 退出"
	quit_btn.position = Vector2(game_panel.size.x - 80, 8)
	quit_btn.size = Vector2(70, 30)
	var qs := StyleBoxFlat.new()
	qs.bg_color = Color("#662222"); qs.set_corner_radius_all(6)
	quit_btn.add_theme_stylebox_override("normal", qs)
	var qsh := StyleBoxFlat.new()
	qsh.bg_color = Color("#993333"); qsh.set_corner_radius_all(6)
	quit_btn.add_theme_stylebox_override("hover", qsh)
	quit_btn.add_theme_color_override("font_color", Color.WHITE)
	quit_btn.add_theme_font_size_override("font_size", 13)
	quit_btn.pressed.connect(func():
		_close_overlay()
		challenge_active = false
		game_over = false
		_disable_player(false)
	)
	game_panel.add_child(quit_btn)

	# ── 粒子父节点 ──
	var particle_parent := Control.new()
	particle_parent.name = "ParticleLayer"
	particle_parent.set_anchors_preset(Control.PRESET_FULL_RECT)
	particle_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(particle_parent)

	# 存储粒子引用
	for i in range(20):
		var p := ColorRect.new()
		p.size = Vector2(4, 4)
		p.color = Color("#ffd700", 0.0)
		p.visible = false
		particle_parent.add_child(p)
		particles.append(p)


func _make_laser_handle(color: Color, label_text: String) -> Control:
	var handle := Control.new()
	handle.size = Vector2(40, 40)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.z_index = 10

	var dot := ColorRect.new()
	dot.position = Vector2(12, 12)
	dot.size = Vector2(16, 16)
	dot.color = color
	handle.add_child(dot)

	var ring := ColorRect.new()
	ring.position = Vector2(8, 8)
	ring.size = Vector2(24, 24)
	ring.color = Color(color.r, color.g, color.b, 0.25)
	handle.add_child(ring)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.position = Vector2(0, 34)
	lbl.size = Vector2(40, 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color.lightened(0.3))
	handle.add_child(lbl)

	return handle


# ═══════════════════════════════════════════════════════
#  目标生成
# ═══════════════════════════════════════════════════════

func _spawn_next_target() -> void:
	if targets_attempted >= TOTAL_TARGETS:
		_complete_game()
		return

	# 在激光原点之间的区域随机生成目标点
	var mid_x: float = (laser1_origin.x + laser2_origin.x) / 2.0
	var spread_x: float = abs(laser2_origin.x - laser1_origin.x) * 0.35
	var target_x: float = mid_x + randf_range(-spread_x, spread_x)

	# 目标y在面板上方区域
	var target_y := randf_range(140.0, 300.0)

	current_target = Vector2(target_x, target_y)

	target_sprite.position = current_target - target_sprite.size / 2.0
	target_sprite.visible = true

	round_timer = 0.0
	status_label.text = "目标 #%d 出现！" % (targets_attempted + 1)
	status_label.add_theme_color_override("font_color", Color("#ffd760"))
	update_timer_bar()


func update_timer_bar() -> void:
	if timer_bar == null:
		return
	timer_bar.size.x = timer_bg.size.x


# ═══════════════════════════════════════════════════════
#  拖拽控制
# ═══════════════════════════════════════════════════════

func _try_start_drag(screen_pos: Vector2) -> void:
	if game_over:
		return

	# 检测点击哪个手柄
	if _point_in_rect(screen_pos, laser1_handle):
		dragging_laser = 1
		_start_handle_drag(screen_pos, 1)
	elif _point_in_rect(screen_pos, laser2_handle):
		dragging_laser = 2
		_start_handle_drag(screen_pos, 2)


func _start_handle_drag(screen_pos: Vector2, laser_idx: int) -> void:
	var origin := laser1_origin if laser_idx == 1 else laser2_origin
	# 将屏幕坐标转为相对于游戏面板的坐标
	var local_pos := screen_pos - game_panel.global_position
	drag_start_mouse_angle = (local_pos - origin).angle()
	drag_start_angle = laser1_angle if laser_idx == 1 else laser2_angle


func _update_drag(screen_pos: Vector2) -> void:
	var origin := laser1_origin if dragging_laser == 1 else laser2_origin
	var local_pos := screen_pos - game_panel.global_position
	var cur_angle := (local_pos - origin).angle()
	var delta := cur_angle - drag_start_mouse_angle
	var new_angle := drag_start_angle + delta

	if dragging_laser == 1:
		laser1_angle = new_angle
	else:
		laser2_angle = new_angle

	_update_beams()
	_check_hit()


func _end_drag() -> void:
	dragging_laser = 0


func _rotate_laser(laser_idx: int, delta: float) -> void:
	if game_over:
		return
	if laser_idx == 1:
		laser1_angle += delta
	else:
		laser2_angle += delta
	_update_beams()
	_check_hit()


# ═══════════════════════════════════════════════════════
#  命中检测
# ═══════════════════════════════════════════════════════

func _update_beams() -> void:
	if beam1_draw == null or beam2_draw == null:
		return

	var beam_len := 600.0

	beam1_draw.set_point_position(0, laser1_origin)
	beam1_draw.set_point_position(1, laser1_origin + Vector2(cos(laser1_angle), sin(laser1_angle)) * beam_len)

	beam2_draw.set_point_position(0, laser2_origin)
	beam2_draw.set_point_position(1, laser2_origin + Vector2(cos(laser2_angle), sin(laser2_angle)) * beam_len)

	# 更新手柄位置
	if laser1_handle:
		laser1_handle.position = laser1_origin - laser1_handle.size / 2.0
		# 旋转提示跟随手柄
		var rh1 := game_panel.find_child("RotHint1", false, false) as Label
		if rh1 != null:
			rh1.position = laser1_origin + Vector2(-35, -50)
	if laser2_handle:
		laser2_handle.position = laser2_origin - laser2_handle.size / 2.0
		var rh2 := game_panel.find_child("RotHint2", false, false) as Label
		if rh2 != null:
			rh2.position = laser2_origin + Vector2(-35, -50)


func _check_hit() -> void:
	if game_over or current_target == Vector2.ZERO:
		return

	var hit1 := _ray_point_dist(laser1_origin, laser1_angle, current_target) < HIT_THRESHOLD
	var hit2 := _ray_point_dist(laser2_origin, laser2_angle, current_target) < HIT_THRESHOLD

	# 视觉反馈：接近时目标发光
	var d1 := _ray_point_dist(laser1_origin, laser1_angle, current_target)
	var d2 := _ray_point_dist(laser2_origin, laser2_angle, current_target)
	var closeness := clampf(1.0 - maxf(d1, d2) / 200.0, 0.0, 1.0)
	target_sprite.color = Color(1.0, 0.84 + closeness * 0.16, closeness * 0.5 + 0.1)

	if hit1 and hit2:
		_on_target_hit()


func _ray_point_dist(origin: Vector2, angle: float, point: Vector2) -> float:
	var dir := Vector2(cos(angle), sin(angle))
	var to_point := point - origin
	var proj := to_point.dot(dir)
	if proj < 0:
		return 1e9  # 点在射线后方
	var closest := origin + dir * proj
	return closest.distance_to(point)


func _on_target_hit() -> void:
	_record_attempt(true)
	status_label.text = "✓ 命中！（%d/%d）" % [targets_hit, TOTAL_TARGETS]
	status_label.add_theme_color_override("font_color", Color("#44ff44"))

	# 粒子爆发
	_spawn_particles(current_target)

	# 音效
	AudioManager.play_tone(660.0, 0.08)
	AudioManager.play_tone(880.0, 0.08)
	score_label.text = "命中：%d / %d" % [targets_hit, TOTAL_TARGETS]

	current_target = Vector2.ZERO
	target_sprite.visible = false

	# 短暂延迟后生成下一个目标
	var timer := get_tree().create_timer(0.15)
	timer.timeout.connect(_spawn_next_target)


func _spawn_particles(center: Vector2) -> void:
	# 使用 game_panel 的坐标
	for i in range(min(particles.size(), 12)):
		var p := particles[i]
		p.position = center - p.size / 2.0
		p.color = Color("#ffd700", 0.9)
		p.visible = true

		var angle := randf() * TAU
		var dist := randf_range(20.0, 60.0)
		var target := center + Vector2(cos(angle), sin(angle)) * dist

		var tween := create_tween().set_parallel(true)
		tween.tween_property(p, "position", target, 0.35)
		tween.tween_property(p, "color", Color("#ff8844", 0.0), 0.35)
		tween.tween_callback(func(): p.visible = false)


# ═══════════════════════════════════════════════════════
#  计时 & 超时
# ═══════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not challenge_active or game_over:
		return

	round_timer += delta

	# 更新计时条
	if timer_bar != null and timer_bg != null:
		var ratio := clampf(1.0 - round_timer / time_limit, 0.0, 1.0)
		timer_bar.size.x = timer_bg.size.x * ratio
		# 颜色从绿→黄→红
		if ratio > 0.5:
			timer_bar.color = Color(0.3 + (1.0 - ratio) * 1.4, 1.0, 0.2)
		else:
			timer_bar.color = Color(1.0, ratio * 2.0, 0.1)

	# 超时
	if round_timer >= time_limit and current_target != Vector2.ZERO:
		_on_timeout()


func _on_timeout() -> void:
	if current_target == Vector2.ZERO:
		return

	current_target = Vector2.ZERO
	_record_attempt(false)
	target_sprite.visible = false

	# 红色闪烁
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.0, 0.0, 0.3)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "color", Color(1.0, 0.0, 0.0, 0.0), 0.3)
	ft.tween_callback(flash.queue_free)

	status_label.text = "✗ 超时！下一个..."
	status_label.add_theme_color_override("font_color", Color("#ff6666"))

	var timer := get_tree().create_timer(0.2)
	timer.timeout.connect(_spawn_next_target)

func _record_attempt(hit: bool) -> void:
	targets_attempted += 1
	if hit:
		targets_hit += 1


func _complete_game() -> void:
	game_over = true
	challenge_active = false

	var hit_rate := float(targets_hit) / float(TOTAL_TARGETS) * 100.0
	var result_text: String
	var reward: String

	if hit_rate >= 80.0:
		result_text = "完美！（%d/%d - %.0f%%）" % [targets_hit, TOTAL_TARGETS, hit_rate]
		reward = "laser_focus_master"
	elif hit_rate >= 50.0:
		result_text = "不错！（%d/%d - %.0f%%）" % [targets_hit, TOTAL_TARGETS, hit_rate]
		reward = "laser_focus_pass"
	else:
		result_text = "继续努力！（%d/%d - %.0f%%）" % [targets_hit, TOTAL_TARGETS, hit_rate]
		reward = "laser_focus_pass"

	status_label.text = result_text
	status_label.add_theme_color_override("font_color", Color("#ffd760"))
	score_label.text = "完成！命中率：%.0f%%" % hit_rate

	# ── 显示结果按钮（再玩一次 / 退出）──
	if game_panel == null or not is_instance_valid(game_panel):
		return

	var result_box := ColorRect.new()
	result_box.name = "ResultBox"
	result_box.color = Color("#0a0a18", 0.95)
	var vs2 := get_viewport().get_visible_rect().size
	var bw := 320.0; var bh := 160.0
	var panel_size := Vector2(vs2.x - 280, vs2.y - 80)
	result_box.position = Vector2((panel_size.x - bw) / 2.0, (panel_size.y - bh) / 2.0)
	result_box.size = Vector2(bw, bh)
	game_panel.add_child(result_box)

	var rl := Label.new()
	rl.text = result_text
	rl.position = Vector2(0, 16); rl.size = Vector2(bw, 36)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 20)
	rl.add_theme_color_override("font_color", Color("#ffd760"))
	result_box.add_child(rl)

	var rl2 := Label.new()
	rl2.text = "命中率：%.0f%%" % hit_rate
	rl2.position = Vector2(0, 52); rl2.size = Vector2(bw, 24)
	rl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl2.add_theme_font_size_override("font_size", 16)
	rl2.add_theme_color_override("font_color", Color("#88ddff"))
	result_box.add_child(rl2)

	# 再玩一次
	var retry_btn := Button.new()
	retry_btn.text = "再玩一次"
	retry_btn.position = Vector2(30, 100); retry_btn.size = Vector2(120, 40)
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#224488"); rs.set_corner_radius_all(8)
	retry_btn.add_theme_stylebox_override("normal", rs)
	var rsh := StyleBoxFlat.new()
	rsh.bg_color = Color("#3355aa"); rsh.set_corner_radius_all(8)
	retry_btn.add_theme_stylebox_override("hover", rsh)
	retry_btn.add_theme_color_override("font_color", Color.WHITE)
	retry_btn.add_theme_font_size_override("font_size", 15)
	retry_btn.pressed.connect(func():
		result_box.queue_free()
		# 重置并重新开始
		game_over = false
		challenge_active = false
		targets_hit = 0
		targets_attempted = 0
		round_timer = 0.0
		current_target = Vector2.ZERO
		if target_sprite != null:
			target_sprite.visible = false
		_setup_laser_origins()
		_update_beams()
		challenge_active = true
		_spawn_next_target()
	)
	result_box.add_child(retry_btn)

	# 退出
	var exit_btn := Button.new()
	exit_btn.text = "退出关卡"
	exit_btn.position = Vector2(170, 100); exit_btn.size = Vector2(120, 40)
	var es2 := StyleBoxFlat.new()
	es2.bg_color = Color("#442222"); es2.set_corner_radius_all(8)
	exit_btn.add_theme_stylebox_override("normal", es2)
	var esh2 := StyleBoxFlat.new()
	esh2.bg_color = Color("#663333"); esh2.set_corner_radius_all(8)
	exit_btn.add_theme_stylebox_override("hover", esh2)
	exit_btn.add_theme_color_override("font_color", Color.WHITE)
	exit_btn.add_theme_font_size_override("font_size", 15)
	exit_btn.pressed.connect(func():
		_close_overlay()
		is_completed = true
		_disable_player(false)
		puzzle_completed.emit(reward)
		if is_instance_valid(hint_label):
			hint_label.text = result_text
	)
	result_box.add_child(exit_btn)


func _close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	# 清理引用
	game_panel = null
	timer_bar = null
	timer_bg = null
	score_label = null
	status_label = null
	target_sprite = null
	beam1_draw = null
	beam2_draw = null
	laser1_handle = null
	laser2_handle = null
	particles.clear()


# ═══════════════════════════════════════════════════════
#  工具方法
# ═══════════════════════════════════════════════════════

func _point_in_rect(point: Vector2, control: Control) -> bool:
	if control == null:
		return false
	var rect := Rect2(control.global_position, control.size)
	return rect.has_point(point)


func _disable_player(v: bool) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if "controls_enabled" in node:
			node.controls_enabled = not v


func _get_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"


func is_solved() -> bool:
	return is_completed
