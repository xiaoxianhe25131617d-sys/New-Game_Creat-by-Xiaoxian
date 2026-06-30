extends Area2D
class_name PuzzleNineGrid
# ════════════════════════════════════════════════════════════
#  石台拼图 (3x3 Sliding Puzzle)
#  方向键滑动方块到空位
#  抑郁模式：直接显示正确答案覆盖
#  保证可解性：随机移动从正确状态出发
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false
var challenge_active: bool = false

const CORRECT_LAYOUT: Array = [1, 2, 3, 4, 5, 6, 7, 8, 0]
var current_layout: Array = []

const TILE_COLORS: Array = [
	Color.MAGENTA,
	Color("#4a6c8f"), Color("#5b7da0"), Color("#4a7199"),
	Color("#6b8eac"), Color("#5080a8"), Color("#3d6588"),
	Color("#5a80a8"), Color("#406c94"),
]

const TILE_SYMBOLS: Array = [
	"", "☁", "🌧", "💧", "⏳", "🍂", "🖤", "🌑", "🔗",
]

const CELL_SIZE := 36
var grid_container: Node2D
var tile_nodes: Array = []
var hint_label: Label
var answer_overlay: Control

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160, 180)
	shape.shape = rect
	shape.position = Vector2(0, -20)
	add_child(shape)
	_solvable_shuffle()
	_make_grid()
	_make_hint()

# 保证可解性：从正确状态开始随机移动N次
func _solvable_shuffle() -> void:
	current_layout = CORRECT_LAYOUT.duplicate()
	var gap: int = current_layout.find(0)
	var last_move: int = -1
	for _i in range(100):
		var neighbors = _get_neighbors(gap)
		if neighbors.is_empty(): break
		# 尽量避免来回移动
		var filtered: PackedInt32Array = []
		for n in neighbors:
			if n != last_move: filtered.append(n)
		if filtered.is_empty(): filtered = neighbors
		var pick: int = filtered[randi() % filtered.size()]
		current_layout[gap] = current_layout[pick]
		current_layout[pick] = 0
		last_move = gap
		gap = pick
	# 确保不等于正确答案
	if _is_correct():
		# 再移一次
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
	if r < 2: result.append(idx + 3)  # 下
	if r > 0: result.append(idx - 3)  # 上
	if c < 2: result.append(idx + 1)  # 右
	if c > 0: result.append(idx - 1)  # 左
	return result

func _make_grid() -> void:
	grid_container = Node2D.new()
	grid_container.name = "GridContainer"
	grid_container.position = Vector2(0, -40)
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
		bg.color = Color("#242028")
		bg.z_index = -1
		grid_container.add_child(bg)

	_make_tile_visuals()
	_answer_overlay_make()

	var title := Label.new()
	title.text = "[ 石台拼图 ]"
	title.position = Vector2(-40, -105)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#8ab4d8"))
	add_child(title)

func _answer_overlay_make() -> void:
	answer_overlay = Control.new()
	answer_overlay.visible = false
	answer_overlay.z_index = 100
	grid_container.add_child(answer_overlay)
	var bs := CELL_SIZE * 3 + 12
	var w := bs / 2.0
	answer_overlay.position = Vector2(-w, -w)
	answer_overlay.size = Vector2(bs, bs)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.45, 0.3, 0.55)
	answer_overlay.add_child(bg)

	for idx in range(9):
		var tile_num: int = CORRECT_LAYOUT[idx]
		if tile_num == 0: continue
		var gx: int = idx % 3
		var gy: int = idx / 3
		var tile := ColorRect.new()
		tile.position = Vector2(gx * CELL_SIZE - CELL_SIZE/2.0 + 3, gy * CELL_SIZE - CELL_SIZE/2.0 + 3)
		tile.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
		tile.color = TILE_COLORS[tile_num]
		answer_overlay.add_child(tile)
		var sym := Label.new()
		sym.text = TILE_SYMBOLS[tile_num]
		sym.position = Vector2(gx * CELL_SIZE - 4, gy * CELL_SIZE - 6)
		sym.add_theme_font_size_override("font_size", 14)
		sym.add_theme_color_override("font_color", Color.BLACK)
		answer_overlay.add_child(sym)

	var al := Label.new()
	al.text = "← 正确答案"
	al.position = Vector2(8, 4)
	al.add_theme_font_size_override("font_size", 10)
	al.add_theme_color_override("font_color", Color.WHITE)
	answer_overlay.add_child(al)

func _make_tile_visuals() -> void:
	# 清除旧的可视
	for ch in grid_container.get_children():
		if ch is Polygon2D and ch.z_index >= 1 and ch.z_index <= 3:
			ch.queue_free()
		elif ch is Label and ch.z_index == 3:
			ch.queue_free()
	tile_nodes.clear()

	for idx in range(9):
		var tile_num: int = current_layout[idx]
		var gx: int = idx % 3
		var gy: int = idx / 3
		var cx: float = gx * CELL_SIZE - CELL_SIZE
		var cy: float = gy * CELL_SIZE - CELL_SIZE

		if tile_num == 0:
			var ev := Polygon2D.new()
			ev.polygon = PackedVector2Array([
				Vector2(-CELL_SIZE/2.0+2, -CELL_SIZE/2.0+2),
				Vector2(CELL_SIZE/2.0-2, -CELL_SIZE/2.0+2),
				Vector2(CELL_SIZE/2.0-2, CELL_SIZE/2.0-2),
				Vector2(-CELL_SIZE/2.0+2, CELL_SIZE/2.0-2),
			])
			ev.color = Color("#121016")
			ev.position = Vector2(cx, cy)
			ev.z_index = 1
			grid_container.add_child(ev)
			tile_nodes.append(ev)
			continue

		var tile := Polygon2D.new()
		tile.polygon = PackedVector2Array([
			Vector2(-CELL_SIZE/2.0+3, -CELL_SIZE/2.0+3),
			Vector2(CELL_SIZE/2.0-3, -CELL_SIZE/2.0+3),
			Vector2(CELL_SIZE/2.0-3, CELL_SIZE/2.0-3),
			Vector2(-CELL_SIZE/2.0+3, CELL_SIZE/2.0-3),
		])
		tile.color = TILE_COLORS[tile_num]
		tile.position = Vector2(cx, cy)
		tile.z_index = 2
		grid_container.add_child(tile)
		tile_nodes.append(tile)

		var sym := Label.new()
		sym.text = TILE_SYMBOLS[tile_num]
		sym.position = Vector2(cx - 6, cy - 8)
		sym.add_theme_font_size_override("font_size", 14)
		sym.add_theme_color_override("font_color", Color.WHITE)
		sym.z_index = 3
		grid_container.add_child(sym)

func _make_hint() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-75, 65)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "按 [E] 启动，方向键滑动"
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed: return
	if event.is_action_pressed("interact"):
		if not challenge_active:
			_start_challenge()
		return
	if not challenge_active: return
	if event is InputEventKey and event.pressed:
		var gap_idx: int = current_layout.find(0)
		var gr: int = gap_idx / 3
		var gc: int = gap_idx % 3
		var target_idx: int = -1
		match event.keycode:
			KEY_UP, KEY_W:    if gr < 2: target_idx = gap_idx + 3
			KEY_DOWN, KEY_S:  if gr > 0: target_idx = gap_idx - 3
			KEY_LEFT, KEY_A:  if gc < 2: target_idx = gap_idx + 1
			KEY_RIGHT, KEY_D: if gc > 0: target_idx = gap_idx - 1
		if target_idx >= 0 and current_layout[target_idx] != 0:
			_slide(target_idx)

func _start_challenge() -> void:
	challenge_active = true
	hint_label.text = "↑↓←→ 滑动方块"
	hint_updated.emit("拼图启动！方向键将块滑入空位。抑郁模式看正确答案。")
	_update_overlay()

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
	hint_label.text = "✨ 获得激光装置2！"
	hint_updated.emit("✨ 拼图完成！获得激光装置2！")
	answer_overlay.visible = false
	puzzle_completed.emit("laser_device_2")

func _process(_delta: float) -> void:
	if is_completed or not challenge_active: return
	_update_overlay()

func _update_overlay() -> void:
	answer_overlay.visible = (_get_view() == "depression")

func update_on_view_change(_view: String) -> void:
	_update_overlay()

func _get_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"

func is_solved() -> bool:
	return is_completed
