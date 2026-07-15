extends Area2D
class_name PuzzleNineGrid
# ════════════════════════════════════════════════════════════
#  石台拼图 (3x3 Sliding Puzzle)
#  鼠标点击方块 → 滑入空位
#  使用切片图片纹理替代纯色方块
#  抑郁模式：全屏大号正确答案间隔性弹出供记忆
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)
signal room_toggled(open: bool)

var player_in_range: bool = false
var is_completed: bool = false
var challenge_active: bool = false

const CORRECT_LAYOUT: Array = [1, 2, 3, 4, 5, 6, 7, 8, 0]
var current_layout: Array = []

# ── 预加载切片图片纹理（用 var，Godot4 const 数组不支持 preload）──
var TILE_TEXTURES: Array = []
const FULL_IMAGE := preload("res://assets/grid_tiles/full.png")  # 完整图（抑郁模式展示）

const CELL_SIZE := 50  # 扩大格子以显示清楚图片
var grid_container: Node2D
var tile_nodes: Array = []
var hint_label: Label
var fullscreen_overlay: CanvasLayer  # 抑郁模式全屏密码
var fullscreen_root: Control
var fullscreen_title: Label
var fullscreen_grid_bg: ColorRect
var fullscreen_hint: Label
var fullscreen_cells: Array[Control] = []
var depression_timer: float = 0.0  # 抑郁模式间隔计时

# ── 抑郁模式全屏间隔参数 ──
const DEPRESSION_SHOW_DURATION: float = 5.0   # 展示 5 秒
const DEPRESSION_HIDE_DURATION: float = 10.0  # 隐藏 10 秒
var depression_fullscreen_visible: bool = false
var _was_in_depression: bool = false  # 上一帧是否在抑郁视角

# ── 同时按超过3键驱散机制 ──
var _keys_held: Dictionary = {}        # 当前按住的键集合 {keycode: true}
var _dismiss_hint_label: Label = null  # 显示"挥手让负面回忆驱散"的标签
var _house_front: Sprite2D
var _house_back: Sprite2D

const HOUSE_FRONT_TEXTURE := preload("res://assets/houses/dam_workshop_front.png")
const HOUSE_BACK_TEXTURE := preload("res://assets/houses/dam_workshop_back.png")
const WORKSHOP_SCALE := Vector2(620.0 / 1528.0, 620.0 / 1528.0)
const WORKSHOP_ORIGIN := Vector2(-310.0, -359.0)

# ── 闪动参数 ──
var _flash_timer: float = 0.0
const FLASH_PERIOD: float = 1.2       # 每隔 1.2 秒切换一次显隐（慢闪，容易看清）

static func should_dismiss_for_key_count(key_count: int) -> bool:
	return key_count > 3

static func should_show_depression_answer(completed: bool, view: String, modal_open: bool) -> bool:
	return not completed and view == "depression" and not modal_open

static func is_live_canvas_item(value: Variant) -> bool:
	return value != null and is_instance_valid(value) and value is CanvasItem

func _ready() -> void:
	# 初始化纹理数组（必须在 _ready 里，不能在 const 数组中 preload）
	TILE_TEXTURES = [
		preload("res://assets/grid_tiles/tile_0.png"),
		preload("res://assets/grid_tiles/tile_1.png"),
		preload("res://assets/grid_tiles/tile_2.png"),
		preload("res://assets/grid_tiles/tile_3.png"),
		preload("res://assets/grid_tiles/tile_4.png"),
		preload("res://assets/grid_tiles/tile_5.png"),
		preload("res://assets/grid_tiles/tile_6.png"),
		preload("res://assets/grid_tiles/tile_7.png"),
		preload("res://assets/grid_tiles/tile_8.png"),
	]
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(190, 210)  # 配合 CELL_SIZE=50 的放大尺寸
	shape.shape = rect
	shape.position = Vector2(0, -30)
	add_child(shape)
	_make_house_layers()
	_solvable_shuffle()
	# 注意：_validate_layout 必须在 _make_grid 之后调用，否则 grid_container 为 null
	_make_grid()       # 先建格子（初始化 grid_container）
	_validate_layout() # 再验证/修复布局（此时 grid_container 已就绪）
	_make_hint()
	_make_fullscreen_overlay()

func _make_house_layers() -> void:
	_house_back = Sprite2D.new()
	_house_back.name = "HouseBackboard"
	_house_back.texture = HOUSE_BACK_TEXTURE
	_house_back.centered = false
	_house_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_back.scale = WORKSHOP_SCALE
	_house_back.position = WORKSHOP_ORIGIN
	_house_back.modulate.a = 0.0
	_house_back.z_index = -6
	add_child(_house_back)

	_house_front = Sprite2D.new()
	_house_front.name = "HouseFront"
	_house_front.texture = HOUSE_FRONT_TEXTURE
	_house_front.centered = false
	_house_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_house_front.scale = WORKSHOP_SCALE
	_house_front.position = WORKSHOP_ORIGIN
	_house_front.z_index = 12
	add_child(_house_front)

func _set_house_inside(inside: bool) -> void:
	_house_front.modulate.a = 0.0 if inside else 1.0
	_house_back.modulate.a = 1.0 if inside else 0.0

# 保证可解性：从正确状态开始随机移动N次
func _solvable_shuffle() -> void:
	current_layout = CORRECT_LAYOUT.duplicate()
	var gap: int = current_layout.find(0)
	var last_move: int = -1
	for _i in range(100):
		var neighbors = _get_neighbors(gap)
		if neighbors.is_empty(): break
		var filtered: PackedInt32Array = []
		for n in neighbors:
			if n != last_move: filtered.append(n)
		if filtered.is_empty(): filtered = neighbors
		var pick: int = filtered[randi() % filtered.size()]
		current_layout[gap] = current_layout[pick]
		current_layout[pick] = 0
		last_move = gap
		gap = pick
	if _is_correct():
		var n2 := _get_neighbors(gap)
		if n2.size() > 0:
			var p: int = n2[0]
			current_layout[gap] = current_layout[p]
			current_layout[p] = 0

func _is_correct() -> bool:
	for i in range(9):
		if current_layout[i] != CORRECT_LAYOUT[i]:
			return false
	return true

# ── 安全检查：确保布局中有且仅有一个 0（空格）──
func _validate_layout() -> void:
	var zero_count := 0
	for v in current_layout:
		if v == 0:
			zero_count += 1
	if zero_count != 1:
		# 布局损坏，从正确答案重新生成可解布局
		current_layout = CORRECT_LAYOUT.duplicate()
		_solvable_shuffle()
		zero_count = 0
		for v in current_layout:
			if v == 0:
				zero_count += 1
		if zero_count != 1:
			# 极端情况：直接用正确答案，但保证有一个空格
			current_layout = CORRECT_LAYOUT.duplicate()
		_make_tile_visuals()

func _get_neighbors(idx: int) -> PackedInt32Array:
	var result: PackedInt32Array = []
	var r: int = idx / 3
	var c: int = idx % 3
	if r < 2: result.append(idx + 3)
	if r > 0: result.append(idx - 3)
	if c < 2: result.append(idx + 1)
	if c > 0: result.append(idx - 1)
	return result

func _make_grid() -> void:
	grid_container = Node2D.new()
	grid_container.name = "GridContainer"
	grid_container.position = Vector2(0, -60)
	add_child(grid_container)

	var bs := CELL_SIZE * 3 + 12
	var back := ColorRect.new()
	back.position = Vector2(-bs / 2.0, -bs / 2.0)
	back.size = Vector2(bs, bs)
	back.color = Color("#1a1820")
	back.z_index = -2
	grid_container.add_child(back)

	var border := ColorRect.new()
	border.position = Vector2(-bs / 2.0 - 3, -bs / 2.0 - 3)
	border.size = Vector2(bs + 6, bs + 6)
	border.color = Color("#5a506a")
	border.z_index = -3
	grid_container.add_child(border)

	for idx in range(9):
		var gx: int = idx % 3
		var gy: int = idx / 3
		var bg := ColorRect.new()
		bg.position = Vector2(gx * CELL_SIZE - CELL_SIZE - CELL_SIZE/2.0, gy * CELL_SIZE - CELL_SIZE - CELL_SIZE/2.0)
		bg.size = Vector2(CELL_SIZE, CELL_SIZE)
		bg.color = Color("#141218")
		bg.z_index = -1
		grid_container.add_child(bg)

	_make_tile_visuals()

	var title := Label.new()
	title.text = "[ 石台拼图 ]"
	title.position = Vector2(-60, -120)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#8ab4d8"))
	add_child(title)

# ═══════════════════════════════════════════════════════
#  全屏密码展示层（仅抑郁模式使用）
# ═══════════════════════════════════════════════════════
func _make_fullscreen_overlay() -> void:
	fullscreen_overlay = CanvasLayer.new()
	fullscreen_overlay.name = "FullscreenPassword"
	fullscreen_overlay.layer = 100
	fullscreen_overlay.visible = false
	add_child(fullscreen_overlay)
	fullscreen_root = Control.new()
	fullscreen_root.name = "AnswerRoot"
	fullscreen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	fullscreen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	fullscreen_overlay.add_child(fullscreen_root)

	var fade_bg := ColorRect.new()
	fade_bg.name = "FadeBG"
	fade_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_bg.color = Color(0, 0, 0, 0.88)
	fullscreen_root.add_child(fade_bg)
	
	# 标题
	fullscreen_title = Label.new()
	fullscreen_title.text = "记住这个排列"
	fullscreen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fullscreen_title.add_theme_font_size_override("font_size", 36)
	fullscreen_title.add_theme_color_override("font_color", Color("#ffd760"))
	fullscreen_root.add_child(fullscreen_title)
	
	# 背景框
	fullscreen_grid_bg = ColorRect.new()
	fullscreen_grid_bg.color = Color("#2a2220")
	fullscreen_root.add_child(fullscreen_grid_bg)
	
	for idx in range(9):
		var tile_num: int = CORRECT_LAYOUT[idx]
		var cell: Control
		if tile_num == 0:
			var empty_bg := ColorRect.new()
			empty_bg.color = Color("#12101a")
			cell = empty_bg
		else:
			var tile_rect := TextureRect.new()
			tile_rect.texture = TILE_TEXTURES[tile_num]
			tile_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tile_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cell = tile_rect
		cell.set_meta("grid_index", idx)
		fullscreen_root.add_child(cell)
		fullscreen_cells.append(cell)
		
		# 位置编号
		var pos_label := Label.new()
		pos_label.name = "PositionLabel"
		pos_label.text = str(idx + 1)
		pos_label.add_theme_font_size_override("font_size", 14)
		pos_label.add_theme_color_override("font_color", Color("#7777aa", 0.6))
		pos_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(pos_label)
	
	# 底部提示（静态说明）
	fullscreen_hint = Label.new()
	fullscreen_hint.text = "记忆一段时间后会消失，稍后再次出现"
	fullscreen_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fullscreen_hint.add_theme_font_size_override("font_size", 18)
	fullscreen_hint.add_theme_color_override("font_color", Color("#9999bb"))
	fullscreen_root.add_child(fullscreen_hint)

	# 驱散成功提示（初始隐藏）
	_dismiss_hint_label = Label.new()
	_dismiss_hint_label.text = "✦ 挥手让负面回忆驱散 ✦"
	_dismiss_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dismiss_hint_label.position = Vector2(240, 600)
	_dismiss_hint_label.size = Vector2(800, 40)
	_dismiss_hint_label.add_theme_font_size_override("font_size", 28)
	_dismiss_hint_label.add_theme_color_override("font_color", Color("#a8d8ff"))
	_dismiss_hint_label.modulate.a = 0.0
	fullscreen_root.add_child(_dismiss_hint_label)
	_layout_fullscreen_overlay()
	get_viewport().size_changed.connect(_layout_fullscreen_overlay)

func _layout_fullscreen_overlay() -> void:
	if fullscreen_root == null:
		return
	var viewport_size := get_viewport_rect().size
	var grid_size := minf(viewport_size.x * 0.72, viewport_size.y * 0.75)
	var cell_step := grid_size / 3.0
	var gap := clampf(cell_step * 0.045, 6.0, 14.0)
	var grid_origin := Vector2((viewport_size.x - grid_size) * 0.5, (viewport_size.y - grid_size) * 0.5)
	fullscreen_grid_bg.position = grid_origin - Vector2(gap, gap)
	fullscreen_grid_bg.size = Vector2(grid_size, grid_size) + Vector2(gap, gap) * 2.0
	fullscreen_title.position = Vector2(0.0, maxf(8.0, grid_origin.y - 56.0))
	fullscreen_title.size = Vector2(viewport_size.x, 46.0)
	for index in range(fullscreen_cells.size()):
		var cell := fullscreen_cells[index]
		var gx := index % 3
		var gy := index / 3
		cell.position = grid_origin + Vector2(gx * cell_step + gap, gy * cell_step + gap)
		cell.size = Vector2(cell_step - gap * 2.0, cell_step - gap * 2.0)
		var position_label := cell.get_node_or_null("PositionLabel") as Label
		if position_label != null:
			position_label.position = Vector2(5.0, 2.0)
	fullscreen_hint.position = Vector2(0.0, minf(viewport_size.y - 34.0, grid_origin.y + grid_size + 12.0))
	fullscreen_hint.size = Vector2(viewport_size.x, 28.0)
	_dismiss_hint_label.position = Vector2(0.0, maxf(8.0, grid_origin.y - 94.0))
	_dismiss_hint_label.size = Vector2(viewport_size.x, 36.0)

func _make_tile_visuals() -> void:
	# 立即删除旧节点（free，而非queue_free，避免同帧出现"鬼影"复制）
	for ch in grid_container.get_children():
		var n: String = ch.name
		if n.begins_with("TileSprite_") or n.begins_with("EmptySlot_") \
				or n.begins_with("EmptyMark_"):
			ch.free()
	tile_nodes.clear()

	for idx in range(9):
		var tile_num: int = current_layout[idx]
		var gx: int = idx % 3
		var gy: int = idx / 3
		var cx: float = gx * CELL_SIZE - CELL_SIZE
		var cy: float = gy * CELL_SIZE - CELL_SIZE

		if tile_num == 0:
			# ── 空位：醒目深黑底 + 亮蓝边框（4条线，比其他格子明显不同）──
			var ev := ColorRect.new()
			ev.name = "EmptySlot_%d" % idx
			ev.position = Vector2(cx - CELL_SIZE / 2.0 + 3, cy - CELL_SIZE / 2.0 + 3)
			ev.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
			ev.color = Color("#04040a")   # 比周围格子明显更暗
			ev.z_index = 1
			grid_container.add_child(ev)
			# 4条高亮边框线（EmptyMark_ 前缀，清除逻辑统一回收）
			for line_data in [
				["EmptyMark_%d_top" % idx, Vector2(cx - CELL_SIZE/2.0, cy - CELL_SIZE/2.0),         Vector2(CELL_SIZE, 3)],
				["EmptyMark_%d_bot" % idx, Vector2(cx - CELL_SIZE/2.0, cy + CELL_SIZE/2.0 - 3),     Vector2(CELL_SIZE, 3)],
				["EmptyMark_%d_l"   % idx, Vector2(cx - CELL_SIZE/2.0, cy - CELL_SIZE/2.0),          Vector2(3, CELL_SIZE)],
				["EmptyMark_%d_r"   % idx, Vector2(cx + CELL_SIZE/2.0 - 3, cy - CELL_SIZE/2.0),     Vector2(3, CELL_SIZE)],
			]:
				var ln := ColorRect.new()
				ln.name     = line_data[0]
				ln.position = line_data[1]
				ln.size     = line_data[2]
				ln.color    = Color("#5ab4ff", 0.9)  # 明亮蓝色边框
				ln.z_index  = 2
				grid_container.add_child(ln)
			tile_nodes.append(ev)
			continue

		# 有图块 — Sprite2D 显示切片纹理
		var tile := Sprite2D.new()
		tile.texture = TILE_TEXTURES[tile_num]
		tile.centered = true
		tile.position = Vector2(cx, cy)
		var tex_w := float(TILE_TEXTURES[tile_num].get_width())
		var tex_h := float(TILE_TEXTURES[tile_num].get_height())
		var sc := (CELL_SIZE - 4) / maxf(tex_w, tex_h)
		tile.scale = Vector2(sc, sc)
		tile.z_index = 2
		tile.name = "TileSprite_%d" % idx
		tile.texture_filter = TEXTURE_FILTER_NEAREST  # pixel-perfect
		grid_container.add_child(tile)
		tile_nodes.append(tile)

func _make_hint() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-90, 85)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "按 [E] 启动拼图"
	hint_label.visible = false
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_set_house_inside(true)
		room_toggled.emit(true)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_set_house_inside(false)
		room_toggled.emit(false)

# ═══════════════════════════════════════════════════════
#  输入处理：鼠标点击滑动方块
# ═══════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	# ── 抑郁模式：同时按住四个及以上不同键驱散正确答案 ──
	if depression_fullscreen_visible and event is InputEventKey:
		var kcode: int = event.keycode
		# 忽略修饰键本身
		if kcode not in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			if event.pressed and not event.echo:
				_keys_held[kcode] = true
			elif not event.pressed:
				_keys_held.erase(kcode)
			# 严格超过三个键（四键及以上）时驱散。
			if should_dismiss_for_key_count(_keys_held.size()):
				_dismiss_overlay_with_animation()
				get_viewport().set_input_as_handled()
				return

	if not player_in_range or is_completed:
		return

	# 启动拼图（E 键）
	if event.is_action_pressed("interact"):
		if not challenge_active:
			_start_challenge()
		get_viewport().set_input_as_handled()
		return

	if not challenge_active:
		return

	# ── 鼠标点击滑动方块 ──
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_mouse_click(event.position)
		get_viewport().set_input_as_handled()


## 驱散动画：淡出 overlay 并显示"挥手让负面回忆驱散"
func _dismiss_overlay_with_animation() -> void:
	depression_fullscreen_visible = false
	# 重置间隔计时到隐藏周期（让下次出现等够 HIDE_DURATION）
	depression_timer = 0.0
	_keys_held.clear()
	_flash_timer = 0.0

	# 显示驱散提示
	if _dismiss_hint_label != null and is_instance_valid(_dismiss_hint_label):
		_dismiss_hint_label.modulate.a = 1.0

	# 用 tween 做淡出效果
	var tween := create_tween()
	tween.tween_property(fullscreen_root, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		fullscreen_overlay.visible = false
		fullscreen_root.modulate.a = 1.0
	)

	# 提示文字显示 2 秒后淡出
	if _dismiss_hint_label != null and is_instance_valid(_dismiss_hint_label):
		var tween2 := create_tween()
		tween2.tween_interval(2.0)
		tween2.tween_property(_dismiss_hint_label, "modulate:a", 0.0, 0.8)

func _handle_mouse_click(screen_pos: Vector2) -> void:
	if grid_container == null:
		return
	
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	
	# 将屏幕坐标转为世界坐标
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = camera.zoom
	var center: Vector2 = camera.get_screen_center_position()
	var world_pos: Vector2 = center + (screen_pos - vs / 2.0) * zoom
	var local_pos := grid_container.to_local(world_pos)
	
	var bs := CELL_SIZE * 3 + 12
	var half := bs / 2.0
	if local_pos.x < -half or local_pos.x > half or local_pos.y < -half or local_pos.y > half:
		return
	
	var gx := int((local_pos.x + half) / CELL_SIZE)
	var gy := int((local_pos.y + half) / CELL_SIZE)
	gx = clampi(gx, 0, 2)
	gy = clampi(gy, 0, 2)
	var clicked_idx := gy * 3 + gx
	
	var gap_idx := current_layout.find(0)
	var neighbors := _get_neighbors(gap_idx)
	if neighbors.has(clicked_idx) and current_layout[clicked_idx] != 0:
		_slide(clicked_idx)

func _start_challenge() -> void:
	challenge_active = true
	hint_label.text = "点击方块滑动到空位"
	hint_updated.emit("拼图启动！点击方块，把它们滑到正确位置。")

func _slide(from_idx: int) -> void:
	var gap := current_layout.find(0)
	if gap == -1:
		_validate_layout()  # 布局损坏，修复
		gap = current_layout.find(0)
		if gap == -1:
			return  # 无法修复，放弃
	current_layout[gap] = current_layout[from_idx]
	current_layout[from_idx] = 0
	_validate_layout()  # 滑动后再次检查
	_make_tile_visuals()
	AudioManager.play_tone(440.0 + from_idx * 35, 0.1)
	AudioManager.play_sfx("grid_slide")
	if _is_correct():
		_complete()

func _complete() -> void:
	is_completed = true
	challenge_active = false
	# 完成后永久关闭 overlay，不再出现
	fullscreen_overlay.visible = false
	fullscreen_root.modulate.a = 1.0
	depression_fullscreen_visible = false
	depression_timer = 0.0
	hint_label.text = "✨ 获得激光装置2！"
	hint_updated.emit("✨ 拼图完成！获得激光装置2！")
	puzzle_completed.emit("laser_device_2")

# ═══════════════════════════════════════════════════════
#  抑郁模式：全屏密码间隔展示
# ═══════════════════════════════════════════════════════
func _process(delta: float) -> void:
	var in_depression: bool = (_get_view() == "depression")
	var modal_open := _is_blocking_modal_open()
	if not should_show_depression_answer(is_completed, _get_view(), modal_open):
		if fullscreen_overlay.visible:
			fullscreen_overlay.visible = false
			fullscreen_root.modulate.a = 1.0
		depression_fullscreen_visible = false
		_keys_held.clear()
		_was_in_depression = in_depression
		return

	# 九宫格完成前，刚切入抑郁视角便立即出现，不要求先启动谜题。
	if in_depression and not _was_in_depression and not depression_fullscreen_visible:
		fullscreen_overlay.visible = true
		fullscreen_root.modulate.a = 1.0
		depression_fullscreen_visible = true
		depression_timer = 0.0
		_flash_timer = 0.0
	_was_in_depression = in_depression

	if in_depression:
		depression_timer += delta

		if depression_fullscreen_visible:
			# ── 闪动效果：overlay可见时每 FLASH_PERIOD 切换一次透明度 ──
			_flash_timer += delta
			if _flash_timer >= FLASH_PERIOD:
				_flash_timer = 0.0
				if fullscreen_root.modulate.a >= 1.0:
					fullscreen_root.modulate.a = 0.35
				else:
					fullscreen_root.modulate.a = 1.0

			# 等够展示时间后隐藏
			if depression_timer >= DEPRESSION_SHOW_DURATION:
				fullscreen_overlay.visible = false
				fullscreen_root.modulate.a = 1.0
				_flash_timer = 0.0
				depression_fullscreen_visible = false
				depression_timer = 0.0
				_keys_held.clear()
		else:
			# 隐藏中，等够间隔后再次展示
			if depression_timer >= DEPRESSION_HIDE_DURATION:
				fullscreen_overlay.visible = true
				fullscreen_root.modulate.a = 1.0
				_flash_timer = 0.0
				depression_fullscreen_visible = true
				depression_timer = 0.0
				_keys_held.clear()

func _is_blocking_modal_open() -> bool:
	if get_tree().paused:
		return true
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return false
	var active_dialogue: Variant = main.get("dialogue")
	if is_live_canvas_item(active_dialogue) and (active_dialogue as CanvasItem).visible:
		return true
	for property_name in ["pause_root", "wheel_root", "menu_root"]:
		var modal: Variant = main.get(property_name)
		if is_live_canvas_item(modal):
			return true
	return false

func _get_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"

func is_solved() -> bool:
	return is_completed
