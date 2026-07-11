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

var player_in_range: bool = false
var is_completed: bool = false
var challenge_active: bool = false

const CORRECT_LAYOUT: Array = [1, 2, 3, 4, 5, 6, 7, 8, 0]
var current_layout: Array = []

# ── 预加载切片图片纹理 ──
const TILE_TEXTURES: Array = [
	preload("res://assets/grid_tiles/tile_0.png"),   # 空位
	preload("res://assets/grid_tiles/tile_1.png"),
	preload("res://assets/grid_tiles/tile_2.png"),
	preload("res://assets/grid_tiles/tile_3.png"),
	preload("res://assets/grid_tiles/tile_4.png"),
	preload("res://assets/grid_tiles/tile_5.png"),
	preload("res://assets/grid_tiles/tile_6.png"),
	preload("res://assets/grid_tiles/tile_7.png"),
	preload("res://assets/grid_tiles/tile_8.png"),
]
const FULL_IMAGE := preload("res://assets/grid_tiles/full.png")  # 完整图（抑郁模式展示）

const CELL_SIZE := 50  # 扩大格子以显示清楚图片
var grid_container: Node2D
var tile_nodes: Array = []
var hint_label: Label
var fullscreen_overlay: CanvasLayer  # 抑郁模式全屏密码
var depression_timer: float = 0.0  # 抑郁模式间隔计时

# ── 抑郁模式全屏间隔参数 ──
const DEPRESSION_SHOW_DURATION: float = 5.0   # 展示 5 秒
const DEPRESSION_HIDE_DURATION: float = 10.0  # 隐藏 10 秒
var depression_fullscreen_visible: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(190, 210)  # 配合 CELL_SIZE=50 的放大尺寸
	shape.shape = rect
	shape.position = Vector2(0, -30)
	add_child(shape)
	_solvable_shuffle()
	_make_grid()
	_make_hint()
	_make_fullscreen_overlay()

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
	
	var fade_bg := ColorRect.new()
	fade_bg.name = "FadeBG"
	fade_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_bg.color = Color(0, 0, 0, 0.88)
	fullscreen_overlay.add_child(fade_bg)
	
	# 标题
	var title := Label.new()
	title.text = "记住这个排列"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(290, 20)
	title.size = Vector2(700, 40)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#ffd760"))
	fullscreen_overlay.add_child(title)
	
	# 3x3 大号正确答案 — 使用切片图片纹理
	var big_cell := 150.0
	var big_bs := big_cell * 3 + 20
	var grid_origin := Vector2((1280 - big_bs) / 2.0, (720 - big_bs) / 2.0 - 40)
	
	# 背景框
	var grid_bg := ColorRect.new()
	grid_bg.position = grid_origin - Vector2(6, 6)
	grid_bg.size = Vector2(big_bs + 12, big_bs + 12)
	grid_bg.color = Color("#2a2220")
	fullscreen_overlay.add_child(grid_bg)
	
	for idx in range(9):
		var tile_num: int = CORRECT_LAYOUT[idx]
		var gx: int = idx % 3
		var gy: int = idx / 3
		var px: float = grid_origin.x + gx * big_cell + 6
		var py: float = grid_origin.y + gy * big_cell + 6
		
		if tile_num == 0:
			# 空位
			var empty_bg := ColorRect.new()
			empty_bg.position = Vector2(px, py)
			empty_bg.size = Vector2(big_cell - 12, big_cell - 12)
			empty_bg.color = Color("#12101a")
			fullscreen_overlay.add_child(empty_bg)
		else:
			# 用 TextureRect 显示切片纹理
			var tile_rect := TextureRect.new()
			tile_rect.texture = TILE_TEXTURES[tile_num]
			tile_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tile_rect.stretch_mode = TextureRect.STRETCH_SCALE
			tile_rect.position = Vector2(px, py)
			tile_rect.size = Vector2(big_cell - 12, big_cell - 12)
			fullscreen_overlay.add_child(tile_rect)
		
		# 位置编号
		var pos_label := Label.new()
		pos_label.text = str(idx + 1)
		pos_label.position = Vector2(px + 4, py + 2)
		pos_label.add_theme_font_size_override("font_size", 14)
		pos_label.add_theme_color_override("font_color", Color("#7777aa", 0.6))
		fullscreen_overlay.add_child(pos_label)
	
	# 底部提示
	var hint := Label.new()
	hint.text = "记忆一段时间后会消失，稍后再次出现"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(240, 650)
	hint.size = Vector2(800, 30)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("#9999bb"))
	fullscreen_overlay.add_child(hint)

func _make_tile_visuals() -> void:
	# 清除旧的可视节点（Sprite2D 图块和空位 ColorRect）
	for ch in grid_container.get_children():
		if ch is Sprite2D and ch.name.begins_with("TileSprite_"):
			ch.queue_free()
		elif ch is ColorRect and ch.name.begins_with("EmptySlot_"):
			ch.queue_free()
		elif ch is Label and ch.name.begins_with("EmptyMark_"):
			ch.queue_free()
	tile_nodes.clear()

	for idx in range(9):
		var tile_num: int = current_layout[idx]
		var gx: int = idx % 3
		var gy: int = idx / 3
		var cx: float = gx * CELL_SIZE - CELL_SIZE
		var cy: float = gy * CELL_SIZE - CELL_SIZE

		if tile_num == 0:
			# ── 空位：明显空白（深色底 + 亮色描边 + 大问号）──
			var ev := ColorRect.new()
			ev.name = "EmptySlot_%d" % idx
			ev.position = Vector2(cx - CELL_SIZE/2.0 + 2, cy - CELL_SIZE/2.0 + 2)
			ev.size = Vector2(CELL_SIZE - 4, CELL_SIZE - 4)
			ev.color = Color("#08080f")  # 接近纯黑，明显比图块深
			ev.z_index = 1
			grid_container.add_child(ev)
			# 描边（用第二个 ColorRect 当边框）
			var border := ColorRect.new()
			border.name = "EmptySlotBorder_%d" % idx
			border.position = Vector2(cx - CELL_SIZE/2.0, cy - CELL_SIZE/2.0)
			border.size = Vector2(CELL_SIZE, CELL_SIZE)
			border.color = Color("#4a4a6a", 0.0)  # 透明
			border.z_index = 0
			# 用 StyleBoxFlat 不行（ColorRect 不支持），用4条细线模拟边框
			var top := ColorRect.new()
			top.position = Vector2(cx - CELL_SIZE/2.0, cy - CELL_SIZE/2.0)
			top.size = Vector2(CELL_SIZE, 2)
			top.color = Color("#5a78a0", 0.7)
			top.name = "EmptyMark_%d_top" % idx
			grid_container.add_child(top)
			var bot := ColorRect.new()
			bot.position = Vector2(cx - CELL_SIZE/2.0, cy + CELL_SIZE/2.0 - 2)
			bot.size = Vector2(CELL_SIZE, 2)
			bot.color = Color("#5a78a0", 0.7)
			bot.name = "EmptyMark_%d_bot" % idx
			grid_container.add_child(bot)
			var left := ColorRect.new()
			left.position = Vector2(cx - CELL_SIZE/2.0, cy - CELL_SIZE/2.0)
			left.size = Vector2(2, CELL_SIZE)
			left.color = Color("#5a78a0", 0.7)
			left.name = "EmptyMark_%d_l" % idx
			grid_container.add_child(left)
			var right := ColorRect.new()
			right.position = Vector2(cx + CELL_SIZE/2.0 - 2, cy - CELL_SIZE/2.0)
			right.size = Vector2(2, CELL_SIZE)
			right.color = Color("#5a78a0", 0.7)
			right.name = "EmptyMark_%d_r" % idx
			grid_container.add_child(right)
			# 中央问号
			var q := Label.new()
			q.name = "EmptyMark_%d" % idx
			q.text = "?"
			q.position = Vector2(cx - 8, cy - 14)
			q.size = Vector2(16, 24)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.add_theme_font_size_override("font_size", 22)
			q.add_theme_color_override("font_color", Color("#7a9acf", 0.85))
			q.z_index = 3
			grid_container.add_child(q)
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
		tile.texture_filter = TEXTURE_FILTER_LINEAR
		grid_container.add_child(tile)
		tile_nodes.append(tile)

func _make_hint() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-90, 85)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "按 [E] 启动拼图"
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

# ═══════════════════════════════════════════════════════
#  输入处理：鼠标点击滑动方块
# ═══════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
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
	fullscreen_overlay.visible = false
	depression_timer = 0.0
	depression_fullscreen_visible = false
	hint_label.text = "点击方块滑动到空位"
	hint_updated.emit("拼图启动！点击方块，把它们滑到正确位置。")

func _slide(from_idx: int) -> void:
	var gap := current_layout.find(0)
	current_layout[gap] = current_layout[from_idx]
	current_layout[from_idx] = 0
	_make_tile_visuals()
	AudioManager.play_tone(440.0 + from_idx * 35, 0.1)
	if _is_correct():
		_complete()

func _complete() -> void:
	is_completed = true
	challenge_active = false
	fullscreen_overlay.visible = false
	hint_label.text = "✨ 获得激光装置2！"
	hint_updated.emit("✨ 拼图完成！获得激光装置2！")
	puzzle_completed.emit("laser_device_2")

# ═══════════════════════════════════════════════════════
#  抑郁模式：全屏密码间隔展示
# ═══════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if is_completed or not challenge_active:
		return
	
	if _get_view() == "depression":
		depression_timer += delta
		
		if depression_fullscreen_visible:
			# 正在展示，等够展示时间后隐藏
			if depression_timer >= DEPRESSION_SHOW_DURATION:
				fullscreen_overlay.visible = false
				depression_fullscreen_visible = false
				depression_timer = 0.0
		else:
			# 隐藏中，等够间隔后再次展示
			if depression_timer >= DEPRESSION_HIDE_DURATION:
				fullscreen_overlay.visible = true
				depression_fullscreen_visible = true
				depression_timer = 0.0
	else:
		# 非抑郁模式：确保全屏密码关掉
		if fullscreen_overlay.visible:
			fullscreen_overlay.visible = false
		depression_timer = 0.0
		depression_fullscreen_visible = false

func _get_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"

func is_solved() -> bool:
	return is_completed
