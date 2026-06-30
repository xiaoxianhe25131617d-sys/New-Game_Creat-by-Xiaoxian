extends Area2D
class_name PuzzleNineGrid
# ════════════════════════════════════════════════════════════
#  九宫格滑动拼图 (3×3 Sliding Tile Puzzle)
#  位置：水坝区域石台上
#  规则：
#    3×3 网格，8 块 + 1 空位
#    每块有不同的图案/颜色
#    玩家踩到空位相邻的块 → 滑动到空位
#    抑郁模式：每 10 秒闪烁一次正确排列
#  产出：激光装置2
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false

# 正确排列（0=空位在右下角，1-8 = 第1-8个块）
const CORRECT_LAYOUT: Array = [1, 2, 3, 4, 5, 6, 7, 8, 0]
# 当前块排列（索引 = 网格位置，值 = 块编号，0 = 空）
var current_layout: Array = []

# 每个块的图案/颜色
const TILE_COLORS: Array = [
	Color.MAGENTA,        # unused (idx 0)
	Color("#ff6b6b"),     # 块1：红
	Color("#ffa94d"),     # 块2：橙
	Color("#ffd43b"),     # 块3：黄
	Color("#69db7c"),     # 块4：绿
	Color("#4dabf7"),     # 块5：蓝
	Color("#748ffc"),     # 块6：靛
	Color("#9775fa"),     # 块7：紫
	Color("#da77f2"),     # 块8：粉
]

const TILE_PATTERNS: Array = [
	"",                   # idx 0
	"★", "◆", "●",       # 1-3
	"▲", "■", "♥",       # 4-6
	"♦", "♣",             # 7-8
]

const TILE_SYMBOLS: Array = [
	"", "星", "菱", "圆", "角", "方", "心", "钻", "草",
]

# 网格大小
const GRID_COLS := 3
const GRID_ROWS := 3
const CELL_SIZE := 36
const GAP_INDEX: int = 8  # 空位初始在右下角

# 抑郁模式闪烁
var depression_flash_timer: float = 0.0
var is_flashing: bool = false

# 玩家踩格冷却
var step_cooldown: float = 0.0

# 视觉元素
var grid_container: Node2D
var tile_nodes: Array = []
var bg_rects: Array = []
var hint_label: Label

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_shuffle_layout()
	_make_grid()
	_make_hint()

func _shuffle_layout() -> void:
	# 创建可解的打乱：从正确排列出发做随机滑动
	current_layout = CORRECT_LAYOUT.duplicate()
	var gap: int = current_layout.find(0)
	
	var moves = 30
	for _i in range(moves):
		var neighbors = _get_neighbors(gap)
		var pick: int = neighbors[randi() % neighbors.size()]
		current_layout[gap] = current_layout[pick]
		current_layout[pick] = 0
		gap = pick

func _get_neighbors(idx: int) -> PackedInt32Array:
	var result: PackedInt32Array = []
	var r: int = idx / GRID_COLS
	var c: int = idx % GRID_COLS
	if r > 0: result.append(idx - GRID_COLS)
	if r < GRID_ROWS - 1: result.append(idx + GRID_COLS)
	if c > 0: result.append(idx - 1)
	if c < GRID_COLS - 1: result.append(idx + 1)
	return result

func _make_grid() -> void:
	grid_container = Node2D.new()
	grid_container.name = "GridContainer"
	grid_container.position = Vector2(0, -30)
	add_child(grid_container)

	# 底板
	var back := ColorRect.new()
	var board_size: int = CELL_SIZE * GRID_COLS + 12
	back.position = Vector2(-board_size / 2.0, -board_size / 2.0)
	back.size = Vector2(board_size, board_size)
	back.color = Color("#3a3040")
	back.z_index = -2
	grid_container.add_child(back)

	# 外框
	var border := ColorRect.new()
	border.position = Vector2(-board_size / 2.0 - 3, -board_size / 2.0 - 3)
	border.size = Vector2(board_size + 6, board_size + 6)
	border.color = Color("#8a7060")
	border.z_index = -3
	grid_container.add_child(border)

	# 创建 9 个格子
	for idx in range(GRID_ROWS * GRID_COLS):
		var gx: int = idx % GRID_COLS
		var gy: int = idx / GRID_COLS
		var cell_pos: Vector2 = Vector2(
			gx * CELL_SIZE - CELL_SIZE * (GRID_COLS - 1) / 2.0,
			gy * CELL_SIZE - CELL_SIZE * (GRID_ROWS - 1) / 2.0
		)

		# 格子背景
		var cell_bg := ColorRect.new()
		cell_bg.position = cell_pos - Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
		cell_bg.size = Vector2(CELL_SIZE, CELL_SIZE)
		cell_bg.color = Color("#2a2830")
		grid_container.add_child(cell_bg)
		bg_rects.append(cell_bg)

		# 块（如果不是空位）
		var tile_num: int = current_layout[idx]
		_make_tile_visual(idx, tile_num)

	# 标题
	var title := Label.new()
	title.text = "[ 石台拼图 ]"
	title.position = Vector2(-35, -95)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#d4c4a4"))
	add_child(title)

func _make_tile_visual(grid_idx: int, tile_num: int) -> void:
	var gx: int = grid_idx % GRID_COLS
	var gy: int = grid_idx / GRID_COLS
	var cell_pos: Vector2 = Vector2(
		gx * CELL_SIZE - CELL_SIZE * (GRID_COLS - 1) / 2.0,
		gy * CELL_SIZE - CELL_SIZE * (GRID_ROWS - 1) / 2.0
	)

	if tile_num == 0:
		# 空位：深色
		var empty_vis := Polygon2D.new()
		empty_vis.polygon = PackedVector2Array([
			Vector2(-CELL_SIZE / 2.0 + 2, -CELL_SIZE / 2.0 + 2),
			Vector2(CELL_SIZE / 2.0 - 2, -CELL_SIZE / 2.0 + 2),
			Vector2(CELL_SIZE / 2.0 - 2, CELL_SIZE / 2.0 - 2),
			Vector2(-CELL_SIZE / 2.0 + 2, CELL_SIZE / 2.0 - 2),
		])
		empty_vis.color = Color("#1a1820")
		empty_vis.position = cell_pos
		empty_vis.z_index = 1
		empty_vis.name = "Tile_%d" % grid_idx
		grid_container.add_child(empty_vis)
		tile_nodes.append(empty_vis)
		return

	# 块：有颜色的方块
	var tile := Polygon2D.new()
	tile.polygon = PackedVector2Array([
		Vector2(-CELL_SIZE / 2.0 + 3, -CELL_SIZE / 2.0 + 3),
		Vector2(CELL_SIZE / 2.0 - 3, -CELL_SIZE / 2.0 + 3),
		Vector2(CELL_SIZE / 2.0 - 3, CELL_SIZE / 2.0 - 3),
		Vector2(-CELL_SIZE / 2.0 + 3, CELL_SIZE / 2.0 - 3),
	])
	tile.color = TILE_COLORS[tile_num]
	tile.position = cell_pos
	tile.z_index = 2
	tile.name = "Tile_%d" % grid_idx
	grid_container.add_child(tile)

	# 小块图案
	var symbol := Label.new()
	symbol.text = TILE_PATTERNS[tile_num]
	symbol.position = cell_pos + Vector2(-6, -10)
	symbol.add_theme_font_size_override("font_size", 14)
	symbol.add_theme_color_override("font_color", Color.BLACK)
	symbol.z_index = 3
	grid_container.add_child(symbol)

	# 编号
	var num := Label.new()
	num.text = str(tile_num)
	num.position = cell_pos + Vector2(-CELL_SIZE / 2.0 + 4, -CELL_SIZE / 2.0 + 2)
	num.add_theme_font_size_override("font_size", 9)
	num.add_theme_color_override("font_color", Color("#ffffff"))
	num.z_index = 3
	grid_container.add_child(num)

	tile_nodes.append(tile)

func _make_hint() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-70, 55)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "踩相邻块滑动拼图"
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if not is_completed:
			hint_label.text = "踩到与空位相邻的块来滑动！"

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _process(delta: float) -> void:
	if is_completed:
		return

	# 抑郁模式闪烁逻辑
	_depression_flash(delta)

	# 检测玩家踩格
	step_cooldown = maxf(0.0, step_cooldown - delta)
	if step_cooldown > 0.0:
		return

	var player: Node2D = _get_player()
	if player == null:
		return

	var gap_idx: int = current_layout.find(0)
	var gap_cell_pos: Vector2 = _cell_world_pos(gap_idx)

	for idx in range(current_layout.size()):
		if idx == gap_idx or current_layout[idx] == 0:
			continue
		var cell_pos: Vector2 = _cell_world_pos(idx)
		var dist: float = player.global_position.distance_to(cell_pos)
		if dist < CELL_SIZE / 2.0 + 10:
			# 检查是否与空位相邻
			var neighbors = _get_neighbors(idx)
			if gap_idx in neighbors:
				_try_slide(idx)
				step_cooldown = 0.5
				break

func _cell_world_pos(idx: int) -> Vector2:
	var gx: int = idx % GRID_COLS
	var gy: int = idx / GRID_COLS
	return global_position + Vector2(
		gx * CELL_SIZE - CELL_SIZE * (GRID_COLS - 1) / 2.0,
		gy * CELL_SIZE - CELL_SIZE * (GRID_ROWS - 1) / 2.0
	) - Vector2(0, 30)

func _depression_flash(delta: float) -> void:
	var view: String = _get_current_view()
	if view != "depression":
		depression_flash_timer = 0.0
		return

	depression_flash_timer += delta
	if depression_flash_timer >= 10.0:
		depression_flash_timer = 0.0
		_flash_correct_pattern()

func _flash_correct_pattern() -> void:
	# 短暂闪烁所有正确的格子位置
	for idx in range(CORRECT_LAYOUT.size()):
		if CORRECT_LAYOUT[idx] == 0:
			continue
		if current_layout[idx] == CORRECT_LAYOUT[idx]:
			continue  # 已经正确的不用闪
		var bg: ColorRect = bg_rects[idx] as ColorRect
		if bg:
			var tween := create_tween()
			tween.tween_property(bg, "color", Color("#80ff80"), 0.2)
			tween.tween_property(bg, "color", Color("#2a2830"), 0.5)
	hint_updated.emit("忧郁视角：正确图案位置闪烁了！")

func _try_slide(idx: int) -> void:
	var gap_idx: int = current_layout.find(0)
	current_layout[gap_idx] = current_layout[idx]
	current_layout[idx] = 0
	_rebuild_visuals()
	_play_slide_sound()

	if _is_solved():
		_complete()

func _rebuild_visuals() -> void:
	# 清理旧视觉
	for n in tile_nodes:
		if is_instance_valid(n):
			n.queue_free()
	tile_nodes.clear()

	for idx in range(current_layout.size()):
		var tile_num: int = current_layout[idx]
		_make_tile_visual(idx, tile_num)

func _play_slide_sound() -> void:
	AudioManager.play_tone(523.0 + current_layout.find(0) * 30.0, 0.15)

func _is_solved() -> bool:
	for i in range(CORRECT_LAYOUT.size()):
		if current_layout[i] != CORRECT_LAYOUT[i]:
			return false
	return true

func _complete() -> void:
	is_completed = true
	hint_label.text = "✨ 获得激光装置2！"
	hint_updated.emit("✨ 拼图完成！你获得了激光装置2！")
	puzzle_completed.emit("laser_device_2")

	# 庆祝动画
	for n in tile_nodes:
		if is_instance_valid(n) and n is Polygon2D:
			var tween := create_tween()
			tween.tween_property(n as Polygon2D, "color", Color("#ffd700"), 0.3)

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
