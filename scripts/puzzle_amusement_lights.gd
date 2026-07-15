extends Area2D
class_name PuzzleAmusementLights
# ════════════════════════════════════════════════════════════
#  关卡6：游乐园灯板 — 3×3 浮空灯板
#  核心玩法：
#   - 自由模式：跳到平台 → 按E点亮 → 5秒后自动熄灭
#   - 闯关模式（按开始）：限时点亮正确图案，错一个就失败
#   - 盲人模式：每块正确灯板有专属音高，靠耳朵记忆
#   - 正确图案：1,2,5,7,9（非规律形，需要记忆）
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

# ── 状态 ──
var player_in_range: bool = false
var platform_active: int = -1
var is_completed: bool = false

# 正确图案：位置 1,2,5,7,9（九宫格编号 1-9）
const CORRECT: Array = [1, 1, 0, 0, 1, 0, 1, 0, 1]
var lights: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]

# 闯关状态
var challenge_active: bool = false
var wrong_pressed: bool = false
var challenge_time_left: float = 0.0
const CHALLENGE_DURATION: float = 20.0

# 自由模式自动熄灭定时器
var off_timers: Array[SceneTreeTimer] = []
var off_timer_callables: Array[Callable] = []  # 对应每个 timer 的 callback，用于正确 disconnect

# ── 音色（盲人模式：正确灯发出不同音高）──
const TONES: Array[float] = [
	262.0, 294.0, 330.0,   # C4, D4, E4
	349.0, 392.0, 440.0,   # F4, G4, A4
	494.0, 523.0, 587.0,   # B4, C5, D5
]
const WRONG_TONE: float = 150.0      # 盲人模式按错灯的沉闷音

# ── 布局 ──
const PLAT_W := 100                          # 平台宽度
const PLAT_H := 20                           # 碰撞厚度
const COL_SPACING := 160                     # 灯板列间距 → 间隙60px (玩家34px可穿过)
# ═══════════════════════════════════════════════════════
#  主灯板：3行，105px间距（保持原有设计，不修改）
#  侧面阶梯：4级，松散排列，55px竖直间距 + 60px水平错开
# ═══════════════════════════════════════════════════════
const HEIGHTS := [-35.0, -140.0, -245.0]     # 主灯板行（不修改！）
# 侧面阶梯：与灯板错开高度，介于主行之间，Z字折返
const SIDE_STEPS := [-30.0, -85.0, -195.0]   # 4级→3级，移除-140避免挡主灯板跳跃
const SIDE_BASE_X := 230.0                   # 基础 x
const SIDE_STAGGER := 60.0                   # 相邻台阶水平错开量
const SIDE_W := 68                           # 侧面平台宽度

# ── UI 节点 ──
var light_nodes: Array[ColorRect] = []        # 灯体本体
var light_halos: Array[ColorRect] = []        # 灯体外发光框
var platform_bodies: Array[StaticBody2D] = []
var platform_sensors: Array[Area2D] = []
var platform_glows: Array[ColorRect] = []     # 平台顶部发光条
var status_label: Label
var timer_label: Label
var start_zone: Area2D
var end_zone: Area2D
var start_glow_e: ColorRect
var end_glow_e: ColorRect
var _last_interact_frame: int = -1  # 防止同一帧 InputEventKey + InputEventAction 双重触发
var _start_btn_top: ColorRect = null            # start 按钮顶面（凹陷动画）
var _end_btn_top: ColorRect = null              # end 按钮顶面（凹陷动画）
var _house_front: Sprite2D
var _house_back: Sprite2D

const HOUSE_FRONT_TEXTURE := preload("res://assets/houses/lightboard_factory_matched_front.png")
const HOUSE_BACK_TEXTURE := preload("res://assets/houses/lightboard_factory_matched_back.png")
const FACTORY_DISPLAY_SIZE := Vector2(920.0, 620.0)
# Both layers share the same source canvas and transform. The alpha bottom of
# that canvas lands on the existing park floor (y = 3200) without changing the
# size of the playable light-board when the player enters it.
const FACTORY_DISPLAY_ORIGIN := Vector2(-460.0, -524.5)

# ═══════════════════════════════════════════════════
#  初始化
# ═══════════════════════════════════════════════════
func _ready() -> void:
	for i in range(9):
		off_timers.append(null)
		off_timer_callables.append(Callable())

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 扩大感应区以容纳更宽布局 + 侧面阶梯
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(820, 580)
	shape.shape = rect
	shape.position = Vector2(0, -60)
	add_child(shape)

	_make_house_layers()
	_build_platforms()
	_build_buttons()
	_build_ui()

func _make_house_layers() -> void:
	_house_back = Sprite2D.new()
	_house_back.name = "HouseBackboard"
	_house_back.texture = HOUSE_BACK_TEXTURE
	_house_back.centered = false
	_house_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_back.scale = FACTORY_DISPLAY_SIZE / HOUSE_BACK_TEXTURE.get_size()
	_house_back.position = FACTORY_DISPLAY_ORIGIN
	_house_back.modulate.a = 0.0
	_house_back.z_index = -6
	add_child(_house_back)
	_house_front = Sprite2D.new()
	_house_front.name = "HouseFront"
	_house_front.texture = HOUSE_FRONT_TEXTURE
	_house_front.centered = false
	_house_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_front.scale = FACTORY_DISPLAY_SIZE / HOUSE_FRONT_TEXTURE.get_size()
	_house_front.position = FACTORY_DISPLAY_ORIGIN
	_house_front.z_index = 12
	add_child(_house_front)

func _set_house_inside(inside: bool) -> void:
	if is_instance_valid(_house_front):
		_house_front.modulate.a = 0.0 if inside else 1.0
	if is_instance_valid(_house_back):
		_house_back.modulate.a = 1.0 if inside else 0.0

# ═══════════════════════════════════════════════════
#  构建 3×3 灯板平台 + 侧面阶梯平台
# ═══════════════════════════════════════════════════
func _build_platforms() -> void:
	# ── 3×3 灯板 ──
	for row in range(3):
		var py: float = HEIGHTS[row]
		for col in range(3):
			var idx := row * 3 + col
			var px := (col - 1) * COL_SPACING

			# 碰撞平台 StaticBody2D
			var body := _make_static_body(px, py, PLAT_W, PLAT_H, true)
			platform_bodies.append(body)

			# 感应区
			_add_platform_sensor(px, py, idx, PLAT_W)

			# 灯 — 外发光框 + 内部灯体（总尺寸56×34）
			# 外发光框（点亮时变为金色，始终可见边缘）
			var halo := ColorRect.new()
			halo.position = Vector2(px - 28, py - 40)
			halo.size = Vector2(56, 34)
			halo.color = Color("#ffdd44", 0.0)
			halo.z_index = 4
			add_child(halo)
			light_halos.append(halo)

			# 灯体
			var light := ColorRect.new()
			light.position = Vector2(px - 25, py - 37)
			light.size = Vector2(50, 28)
			light.color = Color("#1a0f25")
			light.z_index = 10   # 确保在背景和平台之上
			light.pivot_offset = Vector2(25, 14)  # 居中 pivot
			add_child(light)
			light_nodes.append(light)

			# 编号
			var num := Label.new()
			num.text = str(idx + 1)
			num.position = Vector2(px - 6, py - 24)
			num.add_theme_font_size_override("font_size", 14)
			num.add_theme_color_override("font_color", Color("#aaaacc"))
			num.z_index = 4
			add_child(num)

	# ── 左侧阶梯：Z字折返，60px水平错开 ──
	for i in range(SIDE_STEPS.size()):
		var sx := -(SIDE_BASE_X + SIDE_STAGGER * (i % 2))
		_add_side_platform(sx, SIDE_STEPS[i], i)
	# ── 右侧阶梯：镜像 ──
	for i in range(SIDE_STEPS.size()):
		var sx := SIDE_BASE_X + SIDE_STAGGER * (i % 2)
		_add_side_platform(sx, SIDE_STEPS[i], i)


# ── 侧面阶梯平台（颜色偏灰，不干扰灯板视觉）──
func _add_side_platform(x: float, y: float, step: int) -> void:
	var body := _make_static_body(x, y, SIDE_W, PLAT_H, false)
	# 编号
	var num := Label.new()
	num.text = "⬆%d" % (step + 1)
	num.position = Vector2(x - 10, y - 24)
	num.add_theme_font_size_override("font_size", 11)
	num.add_theme_color_override("font_color", Color("#667788"))
	num.z_index = 4
	add_child(num)


func _make_static_body(px: float, py: float, w: float, h: float, is_light: bool) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = Vector2(px, py)
	body.collision_layer = 1
	body.collision_mask = 0
	body.z_index = 1

	var cshape := CollisionShape2D.new()
	var crect := RectangleShape2D.new()
	crect.size = Vector2(w, h)
	cshape.shape = crect
	cshape.position = Vector2(0, h * 0.5)
	body.add_child(cshape)

	# 平台顶面
	var plat := ColorRect.new()
	plat.position = Vector2(-w * 0.5, 0)
	plat.size = Vector2(w, 14)
	plat.color = Color("#6b5b4a") if is_light else Color("#4a4a55")
	body.add_child(plat)

	# 高亮上沿
	var top_line := ColorRect.new()
	top_line.position = Vector2(-w * 0.5, 0)
	top_line.size = Vector2(w, 3)
	top_line.color = Color("#ffcc66", 0.55) if is_light else Color("#aabbcc", 0.3)
	body.add_child(top_line)

	# 平台厚度
	var thick := ColorRect.new()
	thick.position = Vector2(-w * 0.5, 3)
	thick.size = Vector2(w, h - 3)
	thick.color = Color("#4a3a2a") if is_light else Color("#3a3a44")
	body.add_child(thick)

	if is_light:
		# 亮灯发光层（覆盖整个平台顶面，点亮时高亮度可见）
		var glow := ColorRect.new()
		glow.position = Vector2(-w * 0.5, -2)
		glow.size = Vector2(w, 18)
		glow.color = Color("#ffdd44", 0.0)
		glow.z_index = 2
		body.add_child(glow)
		platform_glows.append(glow)

	add_child(body)
	return body


func _add_platform_sensor(px: float, py: float, idx: int, w: float) -> void:
	var sensor := Area2D.new()
	sensor.position = Vector2(px, py)
	sensor.collision_layer = 0
	sensor.collision_mask = 1          # 必须匹配玩家的 collision_layer=1，否则 body_entered 永远不触发！
	sensor.set_meta("platform_idx", idx)

	var sshape := CollisionShape2D.new()
	var srect := RectangleShape2D.new()
	# 宽度只比平台宽20px，避免相邻平台感应区重叠导致 platform_active 互相覆盖
	srect.size = Vector2(w + 20, 48)
	sshape.shape = srect
	sshape.position = Vector2(0, -18)
	sensor.add_child(sshape)

	sensor.body_entered.connect(func(b: Node2D):
		if b.is_in_group("player"):
			platform_active = idx
	)
	sensor.body_exited.connect(func(b: Node2D):
		if b.is_in_group("player") and platform_active == idx:
			platform_active = -1
	)
	add_child(sensor)
	platform_sensors.append(sensor)

# ═══════════════════════════════════════════════════
#  构建 开始/结束 按钮
# ═══════════════════════════════════════════════════
func _build_buttons() -> void:
	# ── START 按钮 ──
	start_zone = _make_button(Vector2(-110, 100), "▶ 开始闯关", Color("#44aa44"))
	start_zone.set_meta("button", "start")
	add_child(start_zone)
	start_glow_e = start_zone.get_node("Glow") as ColorRect
	_start_btn_top = start_zone.get_node("BtnTop") as ColorRect

	start_zone.body_entered.connect(func(b: Node2D):
		if not b.is_in_group("player") or is_completed:
			return
		_press_button_visual(start_glow_e, _start_btn_top, Color("#44aa44"), true)
		call_deferred("_on_start_btn_confirm")
	)
	start_zone.body_exited.connect(func(b: Node2D):
		if not b.is_in_group("player"):
			return
		_press_button_visual(start_glow_e, _start_btn_top, Color("#44aa44"), false)
	)

	# ── END 按钮 ──
	end_zone = _make_button(Vector2(110, 100), "■ 结束闯关", Color("#cc4444"))
	end_zone.set_meta("button", "end")
	add_child(end_zone)
	end_glow_e = end_zone.get_node("Glow") as ColorRect
	_end_btn_top = end_zone.get_node("BtnTop") as ColorRect

	end_zone.body_entered.connect(func(b: Node2D):
		if not b.is_in_group("player") or is_completed:
			return
		_press_button_visual(end_glow_e, _end_btn_top, Color("#cc4444"), true)
		call_deferred("_on_end_btn_confirm")
	)
	end_zone.body_exited.connect(func(b: Node2D):
		if not b.is_in_group("player"):
			return
		_press_button_visual(end_glow_e, _end_btn_top, Color("#cc4444"), false)
	)

# ── 凹陷视觉（按下/松开） ──
func _press_button_visual(glow: ColorRect, top: ColorRect, color: Color, pressed: bool) -> void:
	if glow != null and is_instance_valid(glow):
		glow.color = Color(color, 0.6) if pressed else Color(color, 0.0)
	if top != null and is_instance_valid(top):
		# 凹陷：把顶面往下移2px，模拟被踩下去
		top.position.y = 2.0 if pressed else 0.0
		top.color = color.lightened(0.3) if pressed else color

func _on_start_btn_confirm() -> void:
	_start_challenge()

func _on_end_btn_confirm() -> void:
	if challenge_active:
		_cancel_challenge()


func _make_button(pos: Vector2, label_text: String, btn_color: Color) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1

	var sshape := CollisionShape2D.new()
	var srect := RectangleShape2D.new()
	srect.size = Vector2(200, 80)
	sshape.shape = srect
	area.add_child(sshape)

	# 发光背景（踩下时亮）
	var bg := ColorRect.new()
	bg.name = "Glow"
	bg.position = Vector2(-80, -16)
	bg.size = Vector2(160, 32)
	bg.color = Color(btn_color, 0.0)
	bg.z_index = 0
	area.add_child(bg)

	# 按钮边框（底座）
	var border := ColorRect.new()
	border.position = Vector2(-80, -16)
	border.size = Vector2(160, 32)
	border.color = Color(btn_color, 0.25)
	border.z_index = 1
	area.add_child(border)

	# 按钮顶面（踩下时会下移 2px 模拟凹陷）
	var top := ColorRect.new()
	top.name = "BtnTop"
	top.position = Vector2(-80, -20)
	top.size = Vector2(160, 6)
	top.color = btn_color
	top.z_index = 3
	area.add_child(top)

	# 按钮文字
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(-70, -13)
	label.size = Vector2(140, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(btn_color, 0.8))
	label.z_index = 2
	area.add_child(label)

	return area

# ═══════════════════════════════════════════════════
#  构建 UI 文字
# ═══════════════════════════════════════════════════
func _build_ui() -> void:
	# 标题
	var title := Label.new()
	title.text = "[ 游乐园灯板 ]"
	title.position = Vector2(-65, -275)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#ffd760"))
	add_child(title)

	# 状态提示
	status_label = Label.new()
	status_label.position = Vector2(-260, 120)
	status_label.size = Vector2(520, 50)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	_set_status_text("跳上平台 → 按 E 键点亮灯板\n侧面阶梯可助你爬升 | 按 R 开始闯关 / ESC 取消")
	status_label.visible = false
	add_child(status_label)

	# 计时器
	timer_label = Label.new()
	timer_label.position = Vector2(-30, -288)
	timer_label.size = Vector2(60, 24)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 16)
	timer_label.add_theme_color_override("font_color", Color("#ffdd44"))
	timer_label.visible = false
	add_child(timer_label)

	# 操作提示
	var tip := Label.new()
	tip.text = "自由模式：灯 1.5秒后熄灭 | 按 R 开始闯关 | 侧面阶梯助你爬升"
	tip.visible = false
	tip.position = Vector2(-260, 148)
	tip.size = Vector2(520, 24)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color("#777788"))
	add_child(tip)

# ═══════════════════════════════════════════════════
#  每帧
# ═══════════════════════════════════════════════════
func _process(delta: float) -> void:
	if not challenge_active:
		if timer_label.visible:
			timer_label.visible = false
		return

	# 闯关倒计时
	challenge_time_left -= delta
	timer_label.text = "%.1f" % maxf(challenge_time_left, 0.0)
	timer_label.visible = true

	if challenge_time_left <= 3.0 and challenge_time_left > 0:
		timer_label.add_theme_color_override("font_color", Color("#ff6644"))

	if challenge_time_left <= 0.0:
		_fail_challenge("⏰ 时间到！挑战失败。再试一次吧。")
		return

# ═══════════════════════════════════════════════════
#  玩家进入/离开
# ═══════════════════════════════════════════════════
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_set_house_inside(true)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_set_house_inside(false)
		# 不在这里清 platform_active，由各平台感应区自己管理

# ═══════════════════════════════════════════════════
#  输入处理
# ═══════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if is_completed:
		return
	# player_in_range 有时因边界问题不准，用距离兜底
	if not player_in_range:
		var _p := get_tree().get_first_node_in_group("player")
		if _p == null or global_position.distance_to(_p.global_position) > 550.0:
			return

	# E 键 / interact action（排除 echo 重复事件）
	var is_e_press: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E)
	var is_interact: bool = (event.is_action_pressed("interact") and not event.is_echo())
	var is_r_press: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R)
	var is_esc_press: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE)

	if is_e_press or is_interact:
		var cur := Engine.get_process_frames()
		if cur != _last_interact_frame:
			_last_interact_frame = cur
			_handle_e_key()
		return
	if is_r_press:
		if not is_completed:
			_start_challenge()
		return
	if is_esc_press:
		if challenge_active:
			_cancel_challenge()
		return

	# 数字键 1-9 保留
	if not (event is InputEventKey):
		return
	var kn := -1
	if event.keycode >= KEY_0 and event.keycode <= KEY_9:
		kn = event.keycode - KEY_0
	elif event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
		kn = event.keycode - KEY_KP_0
	if kn >= 1 and kn <= 9:
		_interact_platform(kn - 1)

func _handle_e_key() -> void:
	# 检查是否在按钮上
	if _player_near_button("start"):
		_start_challenge()
		return
	if _player_near_button("end"):
		if challenge_active:
			_cancel_challenge()
		return

	# 优先用感应区检测到的平台，否则兜底找最近平台
	var target_idx := platform_active
	if target_idx < 0 or target_idx >= 9:
		target_idx = _get_nearest_platform()
	if target_idx >= 0:
		_interact_platform(target_idx)

# 兜底：找距离玩家最近（且在范围内）的灯板平台
func _get_nearest_platform() -> int:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return -1
	var best_idx := -1
	var best_dist := 120.0  # 扩大到 120px
	for i in range(platform_bodies.size()):
		if not is_instance_valid(platform_bodies[i]):
			continue
		var pb := platform_bodies[i] as Node2D
		var gp: Vector2 = pb.global_position
		# 用 X 距离 + Y 距离分别判断（玩家站上方 Y 约差 30-40px，X 要对齐）
		var dx: float = abs(player.global_position.x - gp.x)
		var dy: float = abs(player.global_position.y - gp.y)
		if dx < 60.0 and dy < 80.0:
			var d: float = player.global_position.distance_to(gp)
			if d < best_dist:
				best_dist = d
				best_idx = i
	return best_idx

func _player_near_button(btn: String) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false

	var target: Area2D = start_zone if btn == "start" else end_zone
	var dist: float = player.global_position.distance_to(target.global_position)
	return dist < 120.0  # 增大到 120px（之前 80px 太严苛）

# ═══════════════════════════════════════════════════
#  平台交互核心
# ═══════════════════════════════════════════════════
func _interact_platform(idx: int) -> void:
	if challenge_active:
		_interact_challenge(idx)
	else:
		_interact_free(idx)

# ── 自由模式：点灯 → 5秒后灭 ──
func _interact_free(idx: int) -> void:
	lights[idx] = 1 - lights[idx]
	var is_on: bool = lights[idx] == 1


	# 取消旧定时器
	_cancel_off_timer(idx)

	# 播放声音
	_play_sound_for_platform(idx)

	# 视觉效果
	if is_on:
		_update_light_visual(idx, true)
		# 1.5 秒后自动关闭
		_cancel_off_timer(idx)
		var cb := _on_free_light_timeout.bind(idx)
		var tt := get_tree().create_timer(1.5)
		tt.timeout.connect(cb)
		off_timers[idx] = tt
		off_timer_callables[idx] = cb
	else:
		_update_light_visual(idx, false)

	var msg := "点亮 %d" % (idx + 1)
	if _is_blind_mode():
		msg += " ♪%.0fHz" % TONES[idx]
	_set_status_text("%s | 自由模式（5秒后熄灭）" % msg)

func _on_free_light_timeout(idx: int) -> void:
	if challenge_active:
		return  # 如果中途开始了闯关，不处理
	if lights[idx] == 1:
		lights[idx] = 0
		_update_light_visual(idx, false)

func _cancel_off_timer(idx: int) -> void:
	if off_timers[idx] != null and is_instance_valid(off_timers[idx]):
		if off_timer_callables[idx].is_valid():
			off_timers[idx].timeout.disconnect(off_timer_callables[idx])
	off_timers[idx] = null
	off_timer_callables[idx] = Callable()

# ── 闯关模式：点亮常驻 → 错一个即失败 ──
func _interact_challenge(idx: int) -> void:
	if wrong_pressed:
		# 已出错，所有其他操作无效
		_set_status_text("❌ 已按错灯，无法通关。按 ESC 重新开始。")
		return

	if lights[idx] == 1:
		# 已点亮的灯——在闯关中也可以关闭（重新按）
		lights[idx] = 0
		_update_light_visual(idx, false)
		_play_sound_for_platform(idx)
		return

	# 点亮该灯
	lights[idx] = 1
	_play_sound_for_platform(idx)
	_update_light_visual(idx, true)

	if CORRECT[idx] == 0:
		# 按错了！
		wrong_pressed = true
		_flash_wrong(idx)
		_fail_challenge("⏰ 挑战失败。请再试一次。")
		return

	# 按对了 → 检查是否全部点亮
	var all_correct_on := true
	for i in range(9):
		if CORRECT[i] == 1 and lights[i] == 0:
			all_correct_on = false
			break

	var remain := _count_remaining()
	if all_correct_on:
		_complete_puzzle()
	else:
		_set_status_text("✓ 位置 %d 正确！还差 %d 个正确灯。| 计时 %.1fs" % [idx + 1, remain, challenge_time_left])

func _flash_wrong(idx: int) -> void:
	# 错误灯极短暂微闪——几乎看不出，避免暴露答案
	if is_instance_valid(light_nodes[idx]):
		light_nodes[idx].color = Color("#3a2a15")  # 微弱暗黄，不是红色
	if is_instance_valid(light_halos[idx]):
		light_halos[idx].color = Color("#ffdd44", 0.08)
	if is_instance_valid(platform_glows[idx]):
		platform_glows[idx].color = Color("#ffdd44", 0.06)
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_callback(func():
		if is_instance_valid(light_nodes[idx]):
			light_nodes[idx].color = Color("#1a0f25")
		if is_instance_valid(light_halos[idx]):
			light_halos[idx].color = Color("#ffdd44", 0.0)
		if is_instance_valid(platform_glows[idx]):
			platform_glows[idx].color = Color("#ffdd44", 0.0)
		lights[idx] = 0
	)

func _count_remaining() -> int:
	var count := 0
	for i in range(9):
		if CORRECT[i] == 1 and lights[i] == 0:
			count += 1
	return count

# ═══════════════════════════════════════════════════
#  闯关控制
# ═══════════════════════════════════════════════════
func _start_challenge() -> void:
	if is_completed:
		return
	if challenge_active:
		# 已在闯关中，再次按开始 = 重新挑战
		_reset_all_lights()

	_reset_all_lights()
	wrong_pressed = false
	challenge_active = true
	challenge_time_left = CHALLENGE_DURATION

	# 取消所有自由模式定时器
	for i in range(9):
		_cancel_off_timer(i)

	_set_status_text("🔴 闯关开始！点亮所有正确灯板，别按错！| %.0f秒" % challenge_time_left)
	timer_label.add_theme_color_override("font_color", Color("#ffdd44"))
	timer_label.visible = true
	hint_updated.emit("灯板闯关开始！点亮5个正确灯：位置 1,2,5,7,9。不要按错！")

func _cancel_challenge() -> void:
	if not challenge_active:
		return
	challenge_active = false
	wrong_pressed = false
	timer_label.visible = false
	_reset_all_lights()
	_set_status_text("闯关已取消。自由模式 — 灯 5秒后自动熄灭。")

func _fail_challenge(msg: String) -> void:
	challenge_active = false
	timer_label.visible = false
	_set_status_text(msg + " | 按 R 重新闯关")
	hint_updated.emit(msg)

	# 延迟重置所有灯
	var tt := get_tree().create_timer(1.5)
	tt.timeout.connect(func():
		if not challenge_active and not is_completed:
			_reset_all_lights()
	)

func _reset_all_lights() -> void:
	for i in range(9):
		lights[i] = 0
		_update_light_visual(i, false)
		_cancel_off_timer(i)
	wrong_pressed = false

# ═══════════════════════════════════════════════════
#  视觉效果 — 直接设色，无复杂 tween
# ═══════════════════════════════════════════════════
func _update_light_visual(idx: int, is_on: bool) -> void:
	if not is_instance_valid(light_nodes[idx]):
		return
	
	if is_on:
		# 点亮：强制黄色（self_modulate 保证不受父节点影响）
		light_nodes[idx].color = Color(1.0, 0.9, 0.2, 1.0)
		light_nodes[idx].self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		if is_instance_valid(light_halos[idx]):
			light_halos[idx].color = Color(1.0, 0.87, 0.27, 0.8)
			light_halos[idx].self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		if is_instance_valid(platform_glows[idx]):
			platform_glows[idx].color = Color(1.0, 0.87, 0.27, 0.85)
		# 简短膨胀反馈（pivot 居中）
		light_nodes[idx].pivot_offset = light_nodes[idx].size / 2.0
		var t := create_tween()
		t.tween_property(light_nodes[idx], "scale", Vector2(1.3, 1.3), 0.06)
		t.tween_property(light_nodes[idx], "scale", Vector2(1.0, 1.0), 0.15)
	else:
		# 熄灭：变暗 + 外框透明 + 平台发光消失
		light_nodes[idx].color = Color("#1a0f25")
		light_nodes[idx].self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		if is_instance_valid(light_halos[idx]):
			light_halos[idx].color = Color("#ffdd44", 0.0)
		if is_instance_valid(platform_glows[idx]):
			platform_glows[idx].color = Color("#ffdd44", 0.0)

# ═══════════════════════════════════════════════════
#  声音系统
#  - 盲人模式：正确灯 → 专属音高；错误灯 → 沉闷泛音
#  - 其他模式：全部同一声音
# ═══════════════════════════════════════════════════
func _play_sound_for_platform(idx: int) -> void:
	if _is_blind_mode():
		# 盲人模式：每个平台有不同的音高
		if CORRECT[idx] == 1:
			AudioManager.play_tone(TONES[idx], 0.35)
			AudioManager.play_sfx("blind_correct")
		else:
			# 按错灯——沉闷的泛音提示
			AudioManager.play_tone(WRONG_TONE, 0.2)
			AudioManager.play_sfx("blind_wrong")
	else:
		# 其他模式：开灯声
		AudioManager.play_sfx("light_on")

func _is_blind_mode() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return player != null and player.current_view == "blind"

func _set_status_text(text: String) -> void:
	if status_label != null:
		status_label.text = text
		status_label.visible = challenge_active or wrong_pressed or is_completed

# ═══════════════════════════════════════════════════
#  通关
# ═══════════════════════════════════════════════════
func _complete_puzzle() -> void:
	is_completed = true
	challenge_active = false
	timer_label.visible = false

	# 清除所有定时器
	for i in range(9):
		_cancel_off_timer(i)

	# 全部亮起金色
	for i in range(9):
		if is_instance_valid(light_nodes[i]):
			light_nodes[i].color = Color("#ffd700")
		if is_instance_valid(light_halos[i]):
			light_halos[i].color = Color("#ffd700", 0.65)
		if is_instance_valid(platform_glows[i]):
			platform_glows[i].color = Color("#ffd700", 0.6)
		lights[i] = 1

	_set_status_text("✨ 灯板正确！获得钥匙2！")
	hint_updated.emit("✨ 正确！按顺序点亮所有灯，你获得钥匙2！")
	puzzle_completed.emit("key_2")

func is_solved() -> bool:
	return is_completed
