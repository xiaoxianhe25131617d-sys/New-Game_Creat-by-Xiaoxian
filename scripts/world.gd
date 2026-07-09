extends Node2D
class_name MindscapeWorld

signal interactable_changed(node: Node)
signal hint_updated(text: String)
signal puzzle_completed(level_id: String, reward: String)

var interactables: Array[Node2D] = []
var puzzle_nodes: Dictionary = {}
var anchor_nodes: Array = []
var collectible_nodes: Dictionary = {}
var parallax_layers: Array = []
var world_shift: Vector2 = Vector2.ZERO

var bg_canvas: CanvasLayer
var view_tint_canvas: CanvasLayer
var palette_overlay: ColorRect
var blind_black: ColorRect
var blind_label: Label
var view_overlay_canvas: CanvasLayer
var monster_canvas: CanvasLayer

var blind_cursor: Panel
var cursor_pulse_time: float = 0.0
var current_palette_view: String = "normal"
var view_pulse_time: float = 0.0
var _spike_canvas: CanvasLayer

# 地下迷宫相关
var _maze_wall_rects: Array[ColorRect] = []
var _drop_through_tiles: Array[Vector2i] = []  # 可穿透地板位置列表
var _maze_fork_a_zone: Area2D
var _maze_fork_b_zone: Area2D
var _ladder_zones: Array[Area2D] = []  # 梯子列表（玩家可爬）
var _one_way_doors: Array[StaticBody2D] = []  # 单行道门
var _key_chest_zones: Array[Area2D] = []  # 钥匙宝箱
var _maze_main_to_upper_ladders: Array = []  # 主层→上层梯子定义

func is_drop_through_tile(tile_pos: Vector2i) -> bool:
	for dt in _drop_through_tiles:
		if dt == tile_pos:
			return true
	return false

# 风向标 + 激光联动
var _wind_vane_nodes: Array[Node2D] = []
var _vane_placement_zones: Array[Area2D] = []
var _placed_lasers: Dictionary = {}  # {1: {node, beam}, 2: {node, beam}}
var _treasure_marker: Area2D
var _laser_angles: Dictionary = {1: 0.0, 2: 0.0}
const LASER_BEAM_LENGTH: float = 2000.0
const LASER_ANGLE_STEP: float = 0.03  # 滚轮旋转步长(rad)
const ANGLE_TOLERANCE: float = 0.1    # 角度容差(rad)
# 正确角度（从风向标指向treasure_pos）
var _correct_angle_1: float = 0.0
var _correct_angle_2: float = 0.0

# ════════════════════════════════════════════════════════════
#  TILEMAP CONSTANTS
# ════════════════════════════════════════════════════════════
const TILE_SIZE := 16
const GROUND_ROW := 200
const UG_GROUND_ROW := 269
const GROUND_Y_PX := GROUND_ROW * TILE_SIZE
const UG_GROUND_Y_PX := UG_GROUND_ROW * TILE_SIZE
const WORLD_TILE_W := 700
const WORLD_TILE_H := 281

const T_GRASS_TL := Vector2i(4, 0)
const T_GRASS_TR := Vector2i(5, 0)
const T_GRASS_TM := Vector2i(6, 0)
const T_GRASS_MID_L := Vector2i(3, 0)
const T_GRASS_MID_R := Vector2i(2, 0)
const T_GRASS_MID := Vector2i(2, 0)
const T_GRASS_FILL := Vector2i(0, 0)
const T_GRASS_FILL_ALT := Vector2i(1, 0)
const T_DEC_TREE := Vector2i(6, 2)
const T_DEC_BUSH := Vector2i(7, 2)
const T_WATER_TOP := Vector2i(0, 1)
const T_WATER_BODY := Vector2i(1, 1)
const T_BRIDGE_H := Vector2i(4, 0)
const T_BG_MOUNTAIN := Vector2i(2, 3)
const T_BG_CLOUD := Vector2i(3, 2)

var _ground_layer: TileMapLayer
var _water_layer: TileMapLayer
var _bridge_layer: TileMapLayer
var _bg_layer: TileMapLayer
var _block_layer: TileMapLayer
var _pickup_layer: TileMapLayer
var _deco_layer: TileMapLayer
var _drop_layer: TileMapLayer  # 可穿透地板（按下键穿过）

# 平台
const PLATFORMS: Array = [
	{"x0": 0,   "x1": 262, "row": GROUND_ROW, "tag": "floor_left"},
	{"x0": 264, "x1": 300, "row": GROUND_ROW, "tag": "floor_mid1"},
	# 台阶入口在 x:301-304，floor_dam 紧贴台阶右侧开始（小间隙即可跳跃）
	{"x0": 306, "x1": 395, "row": GROUND_ROW, "tag": "floor_dam"},
	{"x0": 397, "x1": 450, "row": GROUND_ROW, "tag": "floor_station"},
	{"x0": 452, "x1": 520, "row": GROUND_ROW, "tag": "floor_park"},
	{"x0": 522, "x1": 700, "row": GROUND_ROW, "tag": "floor_obs"},
	{"x0": 260, "x1": 440, "row": UG_GROUND_ROW, "tag": "ug_floor"},
]

var _texture_wall_blocks: Array[Vector2i] = []

func build(state: Dictionary) -> void:
	add_to_group("world")
	_make_background_canvas()
	_make_depression_spikes()
	_make_parallax_backgrounds()
	_make_tilemap_world()
	_make_beautiful_decor()
	_make_regions_on_tilemap()
	_make_npcs()
	_make_puzzles(state)
	_make_collectibles(state)
	_make_monsters(state)
	_make_memory_anchors()
	_make_underground_maze_entrance()
	_make_wind_vanes()

# ══════════════════════════════════════════════════════════════
#  BACKGROUND CANVAS + VIEW TINT
# ══════════════════════════════════════════════════════════════
func _make_background_canvas() -> void:
	# 天空背景渐变
	bg_canvas = CanvasLayer.new()
	bg_canvas.name = "BackgroundCanvas"
	bg_canvas.layer = -100
	bg_canvas.follow_viewport_enabled = true
	add_child(bg_canvas)

	var sky_grad := GradientTexture2D.new()
	sky_grad.gradient = Gradient.new()
	sky_grad.gradient.set_color(0, Color("#87ceeb"))
	sky_grad.gradient.set_color(1, Color("#e8f4f8"))
	sky_grad.width = 2
	sky_grad.height = 1080

	var sky_rect := TextureRect.new()
	sky_rect.name = "Sky"
	sky_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky_rect.texture = sky_grad
	sky_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_canvas.add_child(sky_rect)

	# View tint (layer 500)
	view_tint_canvas = CanvasLayer.new()
	view_tint_canvas.name = "ViewTintCanvas"
	view_tint_canvas.layer = 500
	view_tint_canvas.follow_viewport_enabled = true
	add_child(view_tint_canvas)

	palette_overlay = ColorRect.new()
	palette_overlay.name = "ViewTint"
	palette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_overlay.color = Color(1.0, 0.9, 0.75, 0.08)
	view_tint_canvas.add_child(palette_overlay)

	# 盲人全黑覆盖层（最高优先级）
	blind_black = ColorRect.new()
	blind_black.name = "BlindBlack"
	blind_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	blind_black.color = Color(0, 0, 0, 1)
	blind_black.mouse_filter = Control.MOUSE_FILTER_PASS
	blind_black.visible = false
	blind_black.z_index = 127
	view_tint_canvas.add_child(blind_black)

	blind_label = Label.new()
	blind_label.name = "BlindLabel"
	blind_label.text = "盲人模式 - 按F键回声定位"
	blind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blind_label.position = Vector2(300, 500)
	blind_label.size = Vector2(680, 60)
	blind_label.add_theme_font_size_override("font_size", 28)
	blind_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	blind_label.visible = false
	blind_label.z_index = 127
	view_tint_canvas.add_child(blind_label)

	# Blind cursor (layer 1000, above blind_black)
	view_overlay_canvas = CanvasLayer.new()
	view_overlay_canvas.name = "ViewOverlayCanvas"
	view_overlay_canvas.layer = 10000
	view_overlay_canvas.follow_viewport_enabled = true
	add_child(view_overlay_canvas)

	blind_cursor = Panel.new()
	blind_cursor.name = "BlindCursor"
	blind_cursor.size = Vector2(14, 14)
	blind_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_cursor.visible = false
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color.WHITE
	cs.set_corner_radius_all(7)
	blind_cursor.add_theme_stylebox_override("panel", cs)
	view_overlay_canvas.add_child(blind_cursor)

	monster_canvas = CanvasLayer.new()
	monster_canvas.name = "MonsterCanvas"
	monster_canvas.layer = 9000
	monster_canvas.follow_viewport_enabled = true
	add_child(monster_canvas)

func _make_depression_spikes() -> void:
	_spike_canvas = CanvasLayer.new()
	_spike_canvas.name = "DepressionSpikes"
	_spike_canvas.layer = 400
	_spike_canvas.follow_viewport_enabled = true
	_spike_canvas.visible = false
	add_child(_spike_canvas)

	for x_tile in range(0, WORLD_TILE_W, 4):
		var sx := x_tile * TILE_SIZE
		var spike := Polygon2D.new()
		var h: float = 8.0 + fmod(sx * 0.13, 6.0)
		spike.polygon = PackedVector2Array([
			Vector2(-3, h), Vector2(3, h), Vector2(0, -3)
		])
		spike.position = Vector2(sx, GROUND_Y_PX)
		spike.color = Color("#ff3333")
		spike.modulate.a = 0.7
		spike.z_index = 10
		_spike_canvas.add_child(spike)

	var label := Label.new()
	label.text = "地面布满尖刺..."
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#ff6666"))
	_spike_canvas.add_child(label)

# ══════════════════════════════════════════════════════════════
#  PARALLAX BACKGROUNDS - 美化版
# ══════════════════════════════════════════════════════════════
func _make_parallax_backgrounds() -> void:
	_add_parallax_layer(0.03, _draw_distant_mountains)
	_add_parallax_layer(0.08, _draw_clouds)
	_add_parallax_layer(0.12, _draw_mid_hills)
	_add_parallax_layer(0.22, _draw_trees_far)
	_add_parallax_layer(0.35, _draw_buildings_bg)

func _add_parallax_layer(parallax_factor: float, draw_func: Callable) -> void:
	var container := Node2D.new()
	container.name = "Parallax_%.2f" % parallax_factor
	container.z_index = int(-80 + parallax_factor * 30)
	add_child(container)
	draw_func.call(container)
	parallax_layers.append({"node": container, "factor": parallax_factor})

func _draw_distant_mountains(container: Node2D) -> void:
	var colors: Array = [Color("#8899bb"), Color("#99aacc"), Color("#7788aa"), Color("#aabbdd")]
	for i in range(12):
		var mountain := Polygon2D.new()
		var x: float = i * 1300.0 - 300.0
		var h: float = 300.0 + fmod(i * 1.7, 1.0) * 250.0
		var w: float = 1100.0 + fmod(i + 3, 1.0) * 500.0
		mountain.polygon = PackedVector2Array([
			Vector2(x, 3400.0), Vector2(x + w * 0.25, 3400.0 - h * 0.55),
			Vector2(x + w * 0.5, 3400.0 - h), Vector2(x + w * 0.75, 3400.0 - h * 0.5),
			Vector2(x + w, 3400.0),
		])
		mountain.color = colors[i % colors.size()]
		mountain.modulate.a = 0.4
		container.add_child(mountain)
	# 雪顶
	for i in range(8):
		var snow := Polygon2D.new()
		var x := i * 1900.0 + 200.0
		snow.polygon = PackedVector2Array([
			Vector2(x - 120, 3400 - 400), Vector2(x + 120, 3400 - 400),
			Vector2(x - 40, 3400 - 460), Vector2(x + 40, 3400 - 460),
		])
		snow.color = Color(1, 1, 1, 0.5)
		container.add_child(snow)

func _draw_mid_hills(container: Node2D) -> void:
	var colors := [Color("#7da86b"), Color("#8db878"), Color("#6d985b"), Color("#9dc888")]
	for i in range(14):
		var hill := Polygon2D.new()
		var x := i * 1200.0 - 200.0
		var w := 900.0 + fmod(i * 3.1, 1.0) * 400.0
		var cx := x + w * 0.5
		hill.polygon = PackedVector2Array([
			Vector2(x, 3400.0),
			Vector2(cx - w * 0.2, 3300.0 - fmod(i * 0.7, 1.0) * 120),
			Vector2(cx, 3260.0 - fmod(i * 0.3, 1.0) * 100),
			Vector2(cx + w * 0.2, 3290.0 - fmod(i * 0.5, 1.0) * 90),
			Vector2(x + w, 3400.0),
		])
		hill.color = colors[i % colors.size()]
		hill.modulate.a = 0.5
		container.add_child(hill)

func _draw_clouds(container: Node2D) -> void:
	for i in range(20):
		var cloud := Polygon2D.new()
		var cx := i * 750.0 + sin(i * 1.3) * 250.0
		var cy := 300.0 + cos(i * 1.7) * 180.0
		var pts := PackedVector2Array()
		for j in range(24):
			var a := TAU * j / 24.0
			var rx := 60.0 + sin(j * 3.0) * 20.0
			var ry := 22.0 + cos(j * 2.0) * 8.0
			pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
		cloud.polygon = pts
		cloud.color = Color(1, 1, 1, 0.25 + fmod(i * 0.3, 1.0) * 0.2)
		container.add_child(cloud)

func _draw_trees_far(container: Node2D) -> void:
	var tree_colors := [Color("#3a6b30"), Color("#4a7b3e"), Color("#2d5a24"), Color("#558a45")]
	for i in range(35):
		var tx := i * 480.0 + fmod(i * 3.7, 1.0) * 150.0
		var ty := 3280.0 - fmod(i * 2.3, 1.0) * 60.0
		var th := 100.0 + fmod(i * 1.1, 1.0) * 80.0
		# 树干
		var trunk := Polygon2D.new()
		trunk.polygon = PackedVector2Array([
			Vector2(tx - 4, ty), Vector2(tx + 4, ty),
			Vector2(tx + 3, ty - th * 0.35), Vector2(tx - 3, ty - th * 0.35),
		])
		trunk.color = Color("#5a3a28")
		container.add_child(trunk)
		# 树冠（多层）
		for layer in range(3):
			var canopy := Polygon2D.new()
			var cp := PackedVector2Array()
			var cx_off := fmod(layer * 1.3, 1.0) * 12 - 6
			var cy_off := th * 0.3 + layer * th * 0.18
			var r := 35.0 - layer * 8.0
			for j in range(14):
				var a := TAU * j / 14.0
				cp.append(Vector2(tx + cx_off + cos(a) * r, ty - cy_off + sin(a) * r * 0.7))
			canopy.polygon = cp
			canopy.color = tree_colors[(i + layer) % tree_colors.size()]
			canopy.modulate.a = 0.8
			container.add_child(canopy)

func _draw_buildings_bg(container: Node2D) -> void:
	var bld_colors := [Color("#8a7060"), Color("#9a8070"), Color("#7a6050"), Color("#a09080")]
	# 灯塔
	_draw_lighthouse(Vector2(4900, 2900), container)
	# 水坝
	_draw_dam(Vector2(6200, 3000), container)
	# 许愿堂
	_draw_observatory(Vector2(9800, 2950), container)

func _draw_lighthouse(pos: Vector2, container: Node2D) -> void:
	var x := pos.x; var y := pos.y
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(x - 20, y + 200), Vector2(x + 20, y + 200),
		Vector2(x + 12, y), Vector2(x - 12, y),
	])
	body.color = Color("#d0d8e0")
	container.add_child(body)
	# 灯塔条纹
	for si in range(6):
		var stripe := ColorRect.new()
		stripe.position = Vector2(x - 18 + si * 6, y + 10 + si * 30)
		stripe.size = Vector2(12 + si, 8)
		stripe.color = Color("#e04040") if si % 2 == 0 else Color("#ffffff")
		container.add_child(stripe)
	# 灯室
	var light_room := Polygon2D.new()
	light_room.polygon = PackedVector2Array([
		Vector2(x - 10, y - 10), Vector2(x + 10, y - 10),
		Vector2(x + 14, y), Vector2(x - 14, y),
	])
	light_room.color = Color("#ffe8a0", 0.8)
	container.add_child(light_room)

func _draw_dam(pos: Vector2, container: Node2D) -> void:
	var x := pos.x; var y := pos.y
	for row in range(5):
		var block := ColorRect.new()
		block.position = Vector2(x + row * 40, y + row * 8)
		block.size = Vector2(36, 22)
		block.color = Color("#889098")
		container.add_child(block)
	var wall := ColorRect.new()
	wall.position = Vector2(x + 40, y - 80)
	wall.size = Vector2(160, 120)
	wall.color = Color("#788890", 0.5)
	container.add_child(wall)

func _draw_observatory(pos: Vector2, container: Node2D) -> void:
	var x := pos.x; var y := pos.y
	# 基座
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(x - 50, y + 80), Vector2(x + 50, y + 80),
		Vector2(x + 30, y + 30), Vector2(x - 30, y + 30),
	])
	base.color = Color("#706868")
	container.add_child(base)
	# 穹顶
	var dome := Polygon2D.new()
	var dp := PackedVector2Array()
	for i in range(18):
		var a := PI + TAU * i / 34.0
		dp.append(Vector2(x + cos(a) * 40, y + 30 + sin(a) * 35))
	dome.polygon = dp
	dome.color = Color("#90a0b0")
	container.add_child(dome)
	# 望远镜
	var scope := ColorRect.new()
	scope.position = Vector2(x - 3, y)
	scope.size = Vector2(6, 50)
	scope.color = Color("#c0c0c0")
	container.add_child(scope)

# ══════════════════════════════════════════════════════════════
#  TILEMAP WORLD
# ══════════════════════════════════════════════════════════════
func _make_tilemap_world() -> void:
	_ground_layer = _create_layer("Ground", true, -30)
	_water_layer = _create_layer("Water", true, -28)
	_bridge_layer = _create_layer("Bridge", false, -27)
	_deco_layer = _create_layer("Deco", false, -26)
	_pickup_layer = _create_layer("Pickups", false, -25)
	_block_layer = _create_layer("Blocks", true, -24)
	_bg_layer = _create_layer("Background", false, -32)
	_drop_layer = _create_layer("DropThrough", true, -23)   # 可穿透地板层
	_drop_layer.collision_layer = 2                         # 碰撞层2（玩家mask也含这层）

	_paint_background_bg()
	_paint_all_platforms()
	_paint_water_features()
	_paint_underground_solid()
	_paint_underground_maze_walls()
	_paint_texture_wall_blocker()
	_paint_decorations()

func _create_layer(name: String, with_collision: bool, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = load("res://map/tileset.tres") as TileSet
	layer.collision_enabled = with_collision
	layer.z_index = z
	add_child(layer)
	return layer

func _paint_background_bg() -> void:
	for y in range(0, GROUND_ROW, 12):
		for x in range(WORLD_TILE_W):
			if (x + y) % 29 == 0:
				_bg_layer.set_cell(Vector2i(x, y), 0, T_BG_CLOUD)
	for x in range(WORLD_TILE_W):
		_bg_layer.set_cell(Vector2i(x, 4), 0, T_BG_MOUNTAIN)

func _paint_all_platforms() -> void:
	for p in PLATFORMS:
		_paint_platform(p["x0"], p["x1"], p["row"])

func _paint_platform(x0: int, x1: int, top_row: int) -> void:
	# 顶层草坪 —— 用不同色块交替
	for x in range(x0, x1 + 1):
		var tile := T_GRASS_TM
		if x == x0: tile = T_GRASS_TL
		elif x == x1: tile = T_GRASS_TR
		elif (x % 7) == 0: tile = T_GRASS_FILL_ALT
		_ground_layer.set_cell(Vector2i(x, top_row), 0, tile)

	var body_depth: int = 20 if top_row == UG_GROUND_ROW else 12
	for y in range(1, body_depth + 1):
		var yi := top_row + y
		for x in range(x0, x1 + 1):
			var tile := T_GRASS_MID
			if (x + y) % 5 == 0: tile = T_GRASS_FILL_ALT
			elif (x + y) % 7 == 0: tile = T_GRASS_MID_L
			elif y == body_depth: tile = T_GRASS_FILL
			_ground_layer.set_cell(Vector2i(x, yi), 0, tile)

func _paint_water_features() -> void:
	# 灯塔旁边的湖
	for x in range(290, 305):
		for y in range(GROUND_ROW, GROUND_ROW + 30):
			_water_layer.set_cell(Vector2i(x, y), 0, T_WATER_BODY)
		_water_layer.set_cell(Vector2i(x, GROUND_ROW), 0, T_WATER_TOP)
	# 桥上
	_bridge_layer.set_cell(Vector2i(297, GROUND_ROW), 0, T_BRIDGE_H)
	_bridge_layer.set_cell(Vector2i(298, GROUND_ROW), 0, T_BRIDGE_H)
	_bridge_layer.set_cell(Vector2i(299, GROUND_ROW), 0, T_BRIDGE_H)
	# 水坝下游水
	for x in range(420, 435):
		for y in range(GROUND_ROW, GROUND_ROW + 24):
			_water_layer.set_cell(Vector2i(x, y), 0, T_WATER_BODY)
	# 游乐园小湖
	for x in range(490, 500):
		for y in range(GROUND_ROW, GROUND_ROW + 18):
			_water_layer.set_cell(Vector2i(x, y), 0, T_WATER_BODY)

func _paint_underground_solid() -> void:
	# 只填非迷宫区域的地下（迷宫由 _paint_underground_maze_walls 自己处理）
	var left_col := 260
	var right_col := 440
	var maze_left := 265
	var maze_right := 440
	for y in range(UG_GROUND_ROW, WORLD_TILE_H):
		for x in range(left_col, right_col + 1):
			# 跳过迷宫区域（x:265-440, y>=269），迷宫函数会自己填充
			if x >= maze_left and x <= maze_right:
				continue
			var tile := T_GRASS_MID
			if (x + y) % 4 == 0: tile = T_GRASS_FILL
			elif (x + y) % 7 == 0: tile = T_GRASS_FILL_ALT
			_ground_layer.set_cell(Vector2i(x, y), 0, tile)

func _paint_underground_maze_walls() -> void:
	# ════════════════════════════════════════════════════════════════
	#  真正复杂的地下迷宫 — 3 层交错，多弯道，多死胡同
	#  设计参考 MAZE_DESIGN.txt
	#  玩家从台阶下来 (x=368) → 必须穿过迷宫到 (x=418) 出口
	#  路径：入口→用梯子/穿透地板绕多层→出口
	# ════════════════════════════════════════════════════════════════
	
	# ── 层级定义 ──
	const UPPER_Y := 261   # 上层走廊地板
	const MID_Y   := 267   # 中层/主层（台阶入口层）
	const LOWER_Y := 273   # 下层走廊地板
	const MAZE_TOP := 256
	const BOT_FILL := 281
	const WR := T_GRASS_MID
	
	var _G := _ground_layer
	var _B := _block_layer
	var _D := _drop_layer
	_drop_through_tiles.clear()
	
	# ════════════════════════════════════════════════════════════════
	#  步骤1：画台阶（地表→主层）
	# ════════════════════════════════════════════════════════════════
	var stair_w := 4
	var stair_x0 := 301
	var stair_dx := 1
	var stair_rows := MID_Y - GROUND_ROW
	
	for y in range(GROUND_ROW + 1, GROUND_ROW + 13):
		for x in range(264, 302):
			_G.set_cell(Vector2i(x, y), -1)
	
	var stair_bot_x: int = stair_x0 + (stair_rows - 1) * stair_dx
	
	for step in range(stair_rows):
		var sy := GROUND_ROW + step
		var sx := stair_x0 + step * stair_dx
		for dx in range(stair_w):
			_G.set_cell(Vector2i(sx + dx, sy), 0, WR)
	
	for step in range(stair_rows):
		var swy := GROUND_ROW + 1 + step
		var swx := stair_x0 - 1 + step * stair_dx
		_G.set_cell(Vector2i(swx, swy), 0, WR)
	
	# ════════════════════════════════════════════════════════════════
	#  步骤2：清空地下区域 + 实心填充
	# ════════════════════════════════════════════════════════════════
	for x in range(265, 441):
		for y in range(MAZE_TOP, BOT_FILL + 1):
			_G.set_cell(Vector2i(x, y), -1)
			_B.set_cell(Vector2i(x, y), -1)
			_D.set_cell(Vector2i(x, y), -1)
	
	for x in range(265, 441):
		for y in range(MAZE_TOP, BOT_FILL + 1):
			_G.set_cell(Vector2i(x, y), 0, WR)
	
	# ════════════════════════════════════════════════════════════════
	#  步骤3：挖空 3 条连续长走廊（每层 1 条）
	#  走廊净高：5 tile（4格空气+1格地板）— 玩家62px高需要至少4格空气
	# ════════════════════════════════════════════════════════════════
	# 上层长走廊
	for x in range(266, 441):
		for y in range(UPPER_Y - 4, UPPER_Y):
			_G.set_cell(Vector2i(x, y), -1)
		_B.set_cell(Vector2i(x, UPPER_Y), 0, WR)
	
	# 主层长走廊
	for x in range(266, 441):
		for y in range(MID_Y - 4, MID_Y):
			_G.set_cell(Vector2i(x, y), -1)
		_B.set_cell(Vector2i(x, MID_Y), 0, WR)
	
	# 下层长走廊
	for x in range(266, 441):
		for y in range(LOWER_Y - 4, LOWER_Y):
			_G.set_cell(Vector2i(x, y), -1)
		_B.set_cell(Vector2i(x, LOWER_Y), 0, WR)
	
	# ════════════════════════════════════════════════════════════════
	#  步骤4：绘制隔断墙柱（关键：制造真正的迷宫！）
	#
	#  设计思路：
	#  - 每层都是一条连续长走廊
	#  - 用"全高墙柱"（占 y=261-267）切断主层走廊
	#  - 玩家不能直接走过全高墙，必须爬梯子到上层/下层绕过
	#  - 用"半高墙柱"（只占 y=264-266）做视觉迷宫感（玩家可跳）
	#  - 死路：在走廊端点放全高墙，玩家必须折返
	#  
	#  全高墙位置（x 坐标）: 282, 318, 358, 398, 425
	#  玩家必须从对应上层/下层绕过这些墙
	#  对应上层/下层该位置是"通道"（挖空）
	# ════════════════════════════════════════════════════════════════
	
	# ── 全高墙柱（关键：必须能挡住跳跃的玩家）──
	# 玩家跳跃能力 105px (normal)，depression 63px
	# 墙顶 y_top 必须满足：y_top*16 ≤ 玩家跳跃最低脚底 y (4167)
	# 即 y_top ≤ 260
	# 实际用 y=260-267 (8 tile) — 玩家跳跃到 y=4136 中心时脚底 y=4167 > 墙顶 y=4160
	# 玩家撞墙！✓
	var full_walls: Array = [
		# 格式: [x, y_top, y_bot]
		[282, 260, 267],   # FW1 主层西侧分隔 (8 tile)
		[318, 260, 267],   # FW2 主层中部分隔
		[358, 260, 267],   # FW3 主层中央分隔（入口x=365 的左侧）
		[398, 260, 267],   # FW4 主层中央分隔（入口x=365 的右侧）
		[425, 260, 267],   # FW5 主层东侧分隔
	]
	
	# ── 半高墙柱（y=264-266, 玩家可跳）──
	# 这些墙柱不阻挡玩家跳跃，但视觉上是隔断
	# 注意：避开梯子位置（x=275, 290, 308, 310, 325, 345, 375, 388, 390, 410, 415, 420, 430）
	var half_walls: Array = [
		# 主层半高墙（避开所有梯子位置）
		[300, 264, 266],   # HW1 主层视觉隔断
		[330, 264, 266],   # HW2
		[368, 264, 266],   # HW3 入口区视觉隔断
		# x=415 改到 405 (避开 x=410 梯子)
		[405, 264, 266],   # HW4 出口区视觉隔断
		
		# 上层半高墙
		[270, 258, 260],   # UHW1
		[315, 258, 260],   # UHW2
		[355, 258, 260],   # UHW3
		[395, 258, 260],   # UHW4
		# 避开 x=430 梯子
		[437, 258, 260],   # UHW5 上层东端
		
		# 下层半高墙
		[280, 270, 272],   # LHW1
		[300, 270, 272],   # LHW2
		[320, 270, 272],   # LHW3
		# 避开 x=346 梯子
		[375, 270, 272],   # LHW4
		[420, 270, 272],   # LHW5
	]
	
	# ── 上层全高墙（让玩家从上层走也需要绕）──
	# 玩家在上层 y=261 站位，跳跃后中心 y=4080, 脚底 y=4111
	# 墙顶 y_top 必须满足 y_top*16 ≤ 4111，即 y_top ≤ 257
	# 实际用 y=257-261 (5 tile, 80px) — y_top=257*16=4112 > 4111，玩家撞墙！✓
	# 但要避开 x=398 (D-E关键路径)
	var upper_full_walls: Array = [
		# 上层全高墙（y=257-261）— 避开 x=398
		[282, 257, 261],   # UFW1 A-B分隔
		[318, 257, 261],   # UFW2 B-C分隔
		[358, 257, 261],   # UFW3 C-D分隔
		# x=398 故意不放墙 — 玩家从 D 上方走到 E 上方
		[425, 257, 261],   # UFW5 E-F分隔
		# 边界
		[265, 257, 261],   # 边界
		[440, 257, 261],   # 边界
	]

	# ── 下层全高墙（让玩家从下层走也需要绕）──
	# 玩家在下层 y=273 站位，跳跃后中心 y=4337-105=4232, 脚底 y=4263
	# 墙顶 y_top 必须满足 y_top*16 ≤ 4263，即 y_top ≤ 266
	# 实际用 y=266-273 (8 tile, 128px) — y_top=266*16=4256 < 4263，玩家撞墙！✓
	# 但要避开穿透点位置 (x=308-310, 346-348, 388-390, 415-417)
	var lower_full_walls: Array = [
		# 下层全高墙（y=266-273）
		[275, 266, 273],   # LFW1 下层西端
		[330, 266, 273],   # LFW2 下层中
		[370, 266, 273],   # LFW3 下层中
		# x=400 位置需要避开穿透点x=388-390下方
		# 玩家从穿透点x=388-390下来后必须能向东走
		# 让下层x=388-417之间没有全高墙
		[435, 266, 273],   # LFW4 下层东端
	]
	
	# ════════════════════════════════════════════════════════════════
	#  步骤5：绘制所有墙柱
	# ════════════════════════════════════════════════════════════════
	for wall in full_walls:
		var wx: int = wall[0]
		var wy0: int = wall[1]
		var wy1: int = wall[2]
		for y in range(wy0, wy1 + 1):
			_G.set_cell(Vector2i(wx, y), 0, WR)
	
	for wall in half_walls:
		var wx: int = wall[0]
		var wy0: int = wall[1]
		var wy1: int = wall[2]
		for y in range(wy0, wy1 + 1):
			_G.set_cell(Vector2i(wx, y), 0, WR)
	
	for wall in upper_full_walls:
		var wx: int = wall[0]
		var wy0: int = wall[1]
		var wy1: int = wall[2]
		for y in range(wy0, wy1 + 1):
			_G.set_cell(Vector2i(wx, y), 0, WR)
	
	for wall in lower_full_walls:
		var wx: int = wall[0]
		var wy0: int = wall[1]
		var wy1: int = wall[2]
		for y in range(wy0, wy1 + 1):
			_G.set_cell(Vector2i(wx, y), 0, WR)
	
	# ════════════════════════════════════════════════════════════════
	#  步骤6：清理楼梯穿过的区域
	# ════════════════════════════════════════════════════════════════
	for step in range(stair_rows):
		var sy2 := GROUND_ROW + step
		var sx2 := stair_x0 + step * stair_dx
		for dx in range(-1, stair_w + 1):
			_G.set_cell(Vector2i(sx2 + dx, sy2), -1)
			_B.set_cell(Vector2i(sx2 + dx, sy2), -1)
	
	for dy in range(-1, 2):
		for dx in range(stair_w):
			_G.set_cell(Vector2i(stair_bot_x + dx, MID_Y + dy), -1)
			_B.set_cell(Vector2i(stair_bot_x + dx, MID_Y + dy), -1)
	
	# ════════════════════════════════════════════════════════════════
	#  步骤7：穿透地板（按 ↓ 键从主层掉到下层）
	#  多个穿透点让玩家有多种选择
	#  
	#  关键：穿透点位置 y=267 是 _B 地板，y=268 是空气（挖空）
	#  玩家从 y=267 穿透后会掉到 y=268, 269, 270... 直到撞到下层地板 y=273
	# ════════════════════════════════════════════════════════════════
	# 穿透点 1：x=308..310（主→下，FW2 墙东侧）
	for x in range(308, 311):
		_D.set_cell(Vector2i(x, MID_Y), 0, WR)
		_drop_through_tiles.append(Vector2i(x, MID_Y))
		_B.set_cell(Vector2i(x, MID_Y), 0, WR)
		# 挖空 y=268 让玩家能掉下去
		_G.set_cell(Vector2i(x, 268), -1)
	
	# 穿透点 2：x=346..348（主→下，FW3 墙西侧，钥匙宝箱上方）
	for x in range(346, 349):
		_D.set_cell(Vector2i(x, MID_Y), 0, WR)
		_drop_through_tiles.append(Vector2i(x, MID_Y))
		_B.set_cell(Vector2i(x, MID_Y), 0, WR)
		_G.set_cell(Vector2i(x, 268), -1)
	
	# 穿透点 3：x=388..390（主→下，FW4 墙东侧）
	for x in range(388, 391):
		_D.set_cell(Vector2i(x, MID_Y), 0, WR)
		_drop_through_tiles.append(Vector2i(x, MID_Y))
		_B.set_cell(Vector2i(x, MID_Y), 0, WR)
		_G.set_cell(Vector2i(x, 268), -1)
	
	# 穿透点 4：x=415..417（主→下，出口前）
	for x in range(415, 418):
		_D.set_cell(Vector2i(x, MID_Y), 0, WR)
		_drop_through_tiles.append(Vector2i(x, MID_Y))
		_B.set_cell(Vector2i(x, MID_Y), 0, WR)
		_G.set_cell(Vector2i(x, 268), -1)
	
	# ════════════════════════════════════════════════════════════════
	#  步骤8：定义梯子位置（供 _make_underground_maze_entrance 使用）
	#  
	#  关键设计：
	#  1. 每个"全高墙"必须有梯子让玩家绕过
	#  2. 主层 → 上层 的梯子（y范围 261-267）
	#  3. 下层 → 主层 的梯子（y范围 267-273）— 玩家从穿透点掉到下层后能爬回主层
	# ════════════════════════════════════════════════════════════════
	var all_ladders: Array = [
		# [x, y_top, y_bot]  梯子范围
		# 玩家站在 y_bot，向上爬到 y_top
		# y_top 必须等于该层地板 y 值，y_bot 必须等于该层地板 y 值
		
		# ═══ 主层 → 上层 梯子（每个全高墙需要 2 个：左房间1个爬上去，右房间1个下来）═══
		# 墙 x=282：A房间[266-281] 和 B房间[283-317]
		[275, UPPER_Y, MID_Y],   # 梯子1 A内（爬到上层）
		[290, UPPER_Y, MID_Y],   # 梯子2 B内（从上层下来）
		# 墙 x=318：B房间[283-317] 和 C房间[319-357]
		[310, UPPER_Y, MID_Y],   # 梯子3 B内
		[325, UPPER_Y, MID_Y],   # 梯子4 C内
		# 墙 x=358：C房间[319-357] 和 D房间[359-397]
		[345, UPPER_Y, MID_Y],   # 梯子5 C内
		[375, UPPER_Y, MID_Y],   # 梯子6 D内（入口附近）
		# 墙 x=398：D房间[359-397] 和 E房间[399-424]
		[390, UPPER_Y, MID_Y],   # 梯子7 D内
		[410, UPPER_Y, MID_Y],   # 梯子8 E内（出口梯子位置）
		# 墙 x=425：E房间[399-424] 和 F房间[426-440]
		[420, UPPER_Y, MID_Y],   # 梯子9 E内
		[430, UPPER_Y, MID_Y],   # 梯子10 F内
		# 出口长梯（地表→主层E房间x=418位置）
		[418, 201, MID_Y],       # 梯子11 出口长梯
		
		# ═══ 下层 → 主层 梯子（让玩家从穿透点掉到下层后能爬回主层）═══
		# 玩家穿透到下层后，需要梯子爬回主层
		# 位置：在每个穿透点附近放梯子
		# 穿透点 1：x=308-310 → 梯子 x=308 (y=267-273)
		[308, MID_Y, LOWER_Y],   # 梯子12 主层B内（从下层上来）
		# 穿透点 2：x=346-348 → 梯子 x=346
		[346, MID_Y, LOWER_Y],   # 梯子13 主层C内（钥匙区上来）
		# 穿透点 3：x=388-390 → 梯子 x=388
		[388, MID_Y, LOWER_Y],   # 梯子14 主层D内
		# 穿透点 4：x=415-417 → 梯子 x=415
		[415, MID_Y, LOWER_Y],   # 梯子15 主层E内
		# 额外：下层深处的探索区也放梯子
		[285, MID_Y, LOWER_Y],   # 梯子16 下层左死路返回
		[365, MID_Y, LOWER_Y],   # 梯子17 下层中返回
		[400, MID_Y, LOWER_Y],   # 梯子18 下层右中返回
		[425, MID_Y, LOWER_Y],   # 梯子19 下层右死路返回
	]
	
	# 存到全局变量供后续使用
	_maze_main_to_upper_ladders = all_ladders

# ── 迷宫砖墙绘制辅助方法 ──
func _mf_rect(layer: TileMapLayer, x0: int, y0: int, x1: int, y1: int, tile: Vector2i) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			layer.set_cell(Vector2i(x, y), 0, tile)

func _mf_row(layer: TileMapLayer, x0: int, x1: int, y: int, tile: Vector2i) -> void:
	for x in range(x0, x1 + 1):
		layer.set_cell(Vector2i(x, y), 0, tile)

func _mf_col(layer: TileMapLayer, y0: int, y1: int, x: int, tile: Vector2i) -> void:
	for y in range(y0, y1 + 1):
		layer.set_cell(Vector2i(x, y), 0, tile)

# ════════════════════════════════════════════════════════════
#  平滑斜坡碰撞体 — 替代 tile 台阶，玩家可自然行走
# ════════════════════════════════════════════════════════════
func _build_ramp_tunnel(x0_t: int, y0_t: int, x1_t: int, y1_t: int, w_t: int, add_walls: bool = true) -> void:
	var px0: float = x0_t * TILE_SIZE       # 斜坡顶端 X
	var py0: float = y0_t * TILE_SIZE       # 斜坡顶端 Y
	var px1: float = x1_t * TILE_SIZE       # 斜坡底端 X
	var py1: float = y1_t * TILE_SIZE       # 斜坡底端 Y
	var fw: float = w_t * TILE_SIZE         # 地板宽度(px)
	var ww: float = 2.0 * TILE_SIZE         # 墙壁厚度(px)
	var wh: float = 6.0 * TILE_SIZE         # 墙壁超出高度(px)
	
	# 地板梯形（保留方向：顶端→底端，支持斜向左/斜向右）
	var tl: Vector2 = Vector2(px0, py0)           # top-left
	var tr: Vector2 = Vector2(px0 + fw, py0)      # top-right
	var br: Vector2 = Vector2(px1 + fw, py1)      # bottom-right
	var bl: Vector2 = Vector2(px1, py1)           # bottom-left
	
	var body := StaticBody2D.new()
	body.name = "RampTunnel_%d_%d" % [x0_t, y0_t]
	body.collision_layer = 1
	body.collision_mask = 0
	body.z_index = -27
	
	var fc := CollisionPolygon2D.new()
	fc.polygon = PackedVector2Array([tl, tr, br, bl])
	body.add_child(fc)
	
	# ── 可选：左右墙壁（主入口需要）──
	if add_walls:
		# 左墙：沿 ram 左侧边 (tl→bl) 向外偏移
		var lw := CollisionPolygon2D.new()
		lw.polygon = PackedVector2Array([
			tl + Vector2(-ww, -wh),
			tl + Vector2(0, -wh),
			bl + Vector2(0, wh),
			bl + Vector2(-ww, wh),
		])
		body.add_child(lw)
		
		# 右墙：沿 ram 右侧边 (tr→br) 向外偏移
		var rw := CollisionPolygon2D.new()
		rw.polygon = PackedVector2Array([
			tr + Vector2(0, -wh),
			tr + Vector2(ww, -wh),
			br + Vector2(ww, wh),
			br + Vector2(0, wh),
		])
		body.add_child(rw)
	
	add_child(body)
	
	# ── 地板视觉 ──
	var fv := Polygon2D.new()
	fv.polygon = PackedVector2Array([tl, tr, br, bl])
	fv.color = Color("#4a3530") if add_walls else Color("#3a2a22")
	fv.z_index = -29
	add_child(fv)
	
	# ── 墙壁视觉 ──
	if add_walls:
		var lwv := Polygon2D.new()
		lwv.polygon = PackedVector2Array([
			tl + Vector2(-ww, -wh),
			tl + Vector2(0, -wh),
			bl + Vector2(0, wh),
			bl + Vector2(-ww, wh),
		])
		lwv.color = Color("#2a1f1a")
		lwv.z_index = -28
		add_child(lwv)
		
		var rwv := Polygon2D.new()
		rwv.polygon = PackedVector2Array([
			tr + Vector2(0, -wh),
			tr + Vector2(ww, -wh),
			br + Vector2(ww, wh),
			br + Vector2(0, wh),
		])
		rwv.color = Color("#2a1f1a")
		rwv.z_index = -28
		add_child(rwv)

func _paint_texture_wall_blocker() -> void:
	var wall_col := 263
	var wall_top := GROUND_ROW - 18
	var wall_bot := GROUND_ROW
	for y in range(wall_top, wall_bot + 1):
		for dx in [-1, 0, 1]:
			_block_layer.set_cell(Vector2i(wall_col + dx, y), 0, T_GRASS_MID)
			_texture_wall_blocks.append(Vector2i(wall_col + dx, y))

	var label := Label.new()
	label.text = "══ 石墙 ══\n需要盲人模式触摸"
	label.position = Vector2(wall_col * TILE_SIZE - 45, GROUND_Y_PX - 310)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#ffaa44"))
	label.z_index = 10
	add_child(label)

func remove_texture_wall_blocker() -> void:
	for pos in _texture_wall_blocks:
		_block_layer.set_cell(pos, -1)
	_texture_wall_blocks.clear()
	hint_updated.emit("石门打开了！后面的区域现已可通行。")

func _paint_decorations() -> void:
	# 树和灌木
	for p in PLATFORMS:
		if p["row"] != GROUND_ROW: continue
		var x0: int = p["x0"]; var x1: int = p["x1"]
		for i in range((x1 - x0) / 30):
			var tx := x0 + 5 + i * 30
			if tx < x1 - 3:
				_deco_layer.set_cell(Vector2i(tx, GROUND_ROW - 1), 0, T_DEC_TREE)
		for i in range((x1 - x0) / 40):
			var bx := x0 + 10 + i * 40
			if bx < x1 - 3:
				_deco_layer.set_cell(Vector2i(bx, GROUND_ROW - 1), 0, T_DEC_BUSH)

# ══════════════════════════════════════════════════════════════
#  手绘装饰 — 各区域特色建筑
# ══════════════════════════════════════════════════════════════
func _make_beautiful_decor() -> void:
	# 中央广场喷泉
	_draw_fountain(Vector2(3400, GROUND_Y_PX - 20))
	# 森林小屋
	_draw_cabin(Vector2(4600, GROUND_Y_PX - 30))
	# 车站
	_draw_station(Vector2(6900, GROUND_Y_PX - 30))
	# 游乐园摩天轮
	_draw_ferris_wheel(Vector2(8100, GROUND_Y_PX - 60))
	# 花朵
	for i in range(60):
		var fx := 500 + i * 160 + fmod(i * 2.7, 1.0) * 80
		if fx < 11000:
			_draw_flower(Vector2(fx, GROUND_Y_PX - 5), [Color("#ff9999"), Color("#ffcc66"), Color("#ff6699"), Color("#99ccff")][i % 4])
	# 石头
	for i in range(40):
		var rx := 300 + i * 280 + fmod(i * 1.3, 1.0) * 120
		if rx < 11000:
			_draw_rock(Vector2(rx, GROUND_Y_PX - 2), [Color("#888888"), Color("#999999"), Color("#777777")][i % 3])

func _draw_fountain(pos: Vector2) -> void:
	var p := Polygon2D.new()
	var base := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		base.append(Vector2(pos.x + cos(a) * 30, pos.y + sin(a) * 30))
	p.polygon = base
	p.color = Color("#808890")
	p.z_index = -5
	add_child(p)
	var water := Polygon2D.new()
	var wp := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		wp.append(Vector2(pos.x + cos(a) * 18, pos.y + sin(a) * 18))
	water.polygon = wp
	water.color = Color("#5599cc", 0.6)
	add_child(water)

func _draw_cabin(pos: Vector2) -> void:
	for row in range(4):
		for col in range(3):
			var log := ColorRect.new()
			log.position = Vector2(pos.x - 24 + col * 16, pos.y - 60 + row * 15)
			log.size = Vector2(14, 13)
			log.color = Color("#8b6914") if (row + col) % 2 == 0 else Color("#7a5a10")
			add_child(log)
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(pos.x - 32, pos.y - 60), Vector2(pos.x + 28, pos.y - 60),
		Vector2(pos.x, pos.y - 85)
	])
	roof.color = Color("#a04030")
	roof.z_index = -5
	add_child(roof)

func _draw_station(pos: Vector2) -> void:
	var back := ColorRect.new()
	back.position = Vector2(pos.x - 60, pos.y - 50)
	back.size = Vector2(120, 70)
	back.color = Color("#b0a090")
	back.z_index = -20
	add_child(back)
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(pos.x - 70, pos.y - 50), Vector2(pos.x + 70, pos.y - 50),
		Vector2(pos.x, pos.y - 75)
	])
	roof.color = Color("#d04030")
	roof.z_index = -5
	add_child(roof)

func _draw_ferris_wheel(pos: Vector2) -> void:
	var cx := pos.x; var cy := pos.y
	for i in range(8):
		var a := TAU * i / 8.0
		var gondola := Polygon2D.new()
		gondola.polygon = PackedVector2Array([
			Vector2(cos(a) * 45 - 5, sin(a) * 45 - 3 + cy),
			Vector2(cos(a) * 45 + 5, sin(a) * 45 - 3 + cy),
			Vector2(cos(a) * 45 + 4, sin(a) * 45 + 5 + cy),
			Vector2(cos(a) * 45 - 4, sin(a) * 45 + 5 + cy),
		])
		gondola.position = Vector2(cx, cy)
		gondola.color = Color("#ff8855") if i % 2 == 0 else Color("#55aaff")
		add_child(gondola)
	var center := Polygon2D.new()
	var cp := PackedVector2Array()
	for i in range(12):
		var a := TAU * i / 12.0
		cp.append(Vector2(cx + cos(a) * 8, cy + sin(a) * 8))
	center.polygon = cp
	center.color = Color("#ffd700")
	add_child(center)

func _draw_flower(pos: Vector2, color: Color) -> void:
	for i in range(6):
		var a := TAU * i / 6.0
		var petal := Polygon2D.new()
		petal.polygon = PackedVector2Array([
			Vector2(pos.x, pos.y),
			Vector2(pos.x + cos(a - 0.2) * 6, pos.y + sin(a - 0.2) * 6),
			Vector2(pos.x + cos(a) * 5, pos.y + sin(a) * 5),
			Vector2(pos.x + cos(a + 0.2) * 6, pos.y + sin(a + 0.2) * 6),
		])
		petal.color = color
		petal.z_index = -3
		add_child(petal)

func _draw_rock(pos: Vector2, color: Color) -> void:
	var rock := Polygon2D.new()
	var sz := 6.0 + fmod(pos.x * 0.1, 1.0) * 8.0
	rock.polygon = PackedVector2Array([
		Vector2(pos.x - sz, pos.y),
		Vector2(pos.x - sz * 0.3, pos.y - sz * 0.7),
		Vector2(pos.x + sz * 0.5, pos.y - sz),
		Vector2(pos.x + sz, pos.y),
	])
	rock.color = color
	rock.z_index = -4
	add_child(rock)

# ══════════════════════════════════════════════════════════════
#  地下迷宫入口 — 真正可走的石头台阶
# ══════════════════════════════════════════════════════════════
func _make_underground_maze_entrance() -> void:
	# ── 地面门框（石拱门，立在入口上方的草地上）──
	# 台阶起点在 tile x=288（像素 4608），门框架在左边
	var gate_tx := 285          # tile坐标，门框左边
	var gate_x := gate_tx * TILE_SIZE  # 4560 px
	var gate_y := GROUND_Y_PX          # 门柱底端贴地
	
	# 左门柱
	var pillar_l := Polygon2D.new()
	pillar_l.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(12, 0), Vector2(12, -48), Vector2(0, -48)
	])
	pillar_l.position = Vector2(gate_x, gate_y)
	pillar_l.color = Color("#4a3a3a")
	pillar_l.z_index = 6
	add_child(pillar_l)
	
	# 右门柱
	var pillar_r := Polygon2D.new()
	pillar_r.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(12, 0), Vector2(12, -48), Vector2(0, -48)
	])
	pillar_r.position = Vector2(gate_x + 44, gate_y)
	pillar_r.color = Color("#4a3a3a")
	pillar_r.z_index = 6
	add_child(pillar_r)
	
	# 门楣（架在两根门柱之上）
	var lintel := Polygon2D.new()
	lintel.polygon = PackedVector2Array([
		Vector2(-4, 0), Vector2(60, 0), Vector2(60, 10), Vector2(-4, 10)
	])
	lintel.position = Vector2(gate_x, gate_y - 48)
	lintel.color = Color("#5a4a4a")
	lintel.z_index = 6
	add_child(lintel)
	
	# ── 入口标签 ──
	var entry_tag := Label.new()
	entry_tag.text = "▼ 地下迷宫 ▼"
	entry_tag.position = Vector2(gate_x - 24, gate_y - 72)
	entry_tag.add_theme_font_size_override("font_size", 14)
	entry_tag.add_theme_color_override("font_color", Color("#c0b0ff"))
	entry_tag.z_index = 7
	add_child(entry_tag)
	
	# ── 发光脉冲 ──
	var entry_glow := ColorRect.new()
	entry_glow.name = "MazeEntryGlow"
	entry_glow.position = Vector2(gate_x - 6, gate_y - 54)
	entry_glow.size = Vector2(68, 60)
	entry_glow.color = Color("#c0b0ff", 0.0)
	entry_glow.z_index = 2
	add_child(entry_glow)
	var glow_tween := create_tween().set_loops()
	glow_tween.tween_property(entry_glow, "color", Color("#c0b0ff", 0.2), 1.0)
	glow_tween.tween_property(entry_glow, "color", Color("#c0b0ff", 0.03), 1.0)

	# 岔路A终点 — 下层左探索区
	_maze_fork_a_zone = Area2D.new()
	_maze_fork_a_zone.name = "MazeForkA"
	_maze_fork_a_zone.position = Vector2(292 * TILE_SIZE, 274 * TILE_SIZE - 10)
	var ash := CollisionShape2D.new()
	var ar := RectangleShape2D.new()
	ar.size = Vector2(100, 50)
	ash.shape = ar
	_maze_fork_a_zone.add_child(ash)
	var al := Label.new()
	al.text = "死路..."
	al.position = Vector2(-18, -6)
	al.add_theme_font_size_override("font_size", 10)
	al.add_theme_color_override("font_color", Color("#888888"))
	_maze_fork_a_zone.add_child(al)
	_maze_fork_a_zone.set_meta("kind", "maze_fork_a")
	interactables.append(_maze_fork_a_zone)

	# 岔路B终点 — 上层出口区宝箱提示
	_maze_fork_b_zone = Area2D.new()
	_maze_fork_b_zone.name = "MazeForkB"
	_maze_fork_b_zone.position = Vector2(422 * TILE_SIZE, 261 * TILE_SIZE - 8)
	var bsh := CollisionShape2D.new()
	var br := RectangleShape2D.new()
	br.size = Vector2(100, 50)
	bsh.shape = br
	_maze_fork_b_zone.add_child(bsh)
	var bl := Label.new()
	bl.text = "宝箱(需4钥匙)"
	bl.position = Vector2(-24, -8)
	bl.add_theme_font_size_override("font_size", 10)
	bl.add_theme_color_override("font_color", Color("#ffd700"))
	_maze_fork_b_zone.add_child(bl)
	_maze_fork_b_zone.set_meta("kind", "maze_fork_b")
	interactables.append(_maze_fork_b_zone)

	# ═══════════════════════════════════════════════════════
	#  梯子系统（使用 _maze_main_to_upper_ladders 中定义的位置）
	#  格式：_make_ladder(x, y_top, y_bot)
	# ═══════════════════════════════════════════════════════
	for i in range(_maze_main_to_upper_ladders.size()):
		var lad = _maze_main_to_upper_ladders[i]
		var lx: int = lad[0]
		var ly0: int = lad[1]
		var ly1: int = lad[2]
		_make_ladder(lx, ly0, lx, ly1, "ladder_%d" % i)

	# ═══════════════════════════════════════════════════════
	#  钥匙宝箱 — 下层中右区（通过穿透地板 x=346-348 到达下层）
	# ═══════════════════════════════════════════════════════
	_make_key_chest(370, 272, "key_3")

	# ═══════════════════════════════════════════════════════
	#  出口单行道 — 梯子顶端右侧，只能出不能进
	# ═══════════════════════════════════════════════════════
	_make_one_way_door(420, 199, 420, 202, "open: -x")

# ═══════════════════════════════════════════════════════
#  梯子：玩家在 Area2D 内按 W/↑ 持续上移，按 S/↓ 持续下移
#  kind="ladder" 让 main.gd 知道这是梯子
# ═══════════════════════════════════════════════════════
func _make_ladder(x_tile0: int, y_tile0: int, x_tile1: int, y_tile1: int, ladder_name: String) -> void:
	# 梯子范围（tile 坐标）
	var x0_px: float = x_tile0 * TILE_SIZE
	var y0_px: float = y_tile0 * TILE_SIZE
	var x1_px: float = (x_tile1 + 1) * TILE_SIZE
	var y1_px: float = (y_tile1 + 1) * TILE_SIZE

	var ladder := Area2D.new()
	ladder.name = ladder_name
	ladder.position = Vector2((x0_px + x1_px) * 0.5, (y0_px + y1_px) * 0.5)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(x1_px - x0_px, y1_px - y0_px)
	shape.shape = rect
	ladder.add_child(shape)
	ladder.set_meta("kind", "ladder")
	ladder.set_meta("ladder_top_y", y0_px)
	ladder.set_meta("ladder_bottom_y", y1_px)
	ladder.set_meta("ladder_x", (x0_px + x1_px) * 0.5)

	# 梯子视觉：用 2 列竖线模拟（每行 1 个矩形）
	var ladder_vis := Node2D.new()
	ladder_vis.z_index = 4
	# 左竖
	for ty in range(y_tile0, y_tile1 + 1):
		var rail_l := ColorRect.new()
		rail_l.position = Vector2(x0_px - ladder.position.x + 2, ty * TILE_SIZE - ladder.position.y)
		rail_l.size = Vector2(2, TILE_SIZE)
		rail_l.color = Color("#a07050")
		ladder_vis.add_child(rail_l)
		# 横档
		var rung := ColorRect.new()
		rung.position = Vector2(x0_px - ladder.position.x + 2, ty * TILE_SIZE - ladder.position.y + TILE_SIZE / 2 - 2)
		rung.size = Vector2(TILE_SIZE - 4, 3)
		rung.color = Color("#b88060")
		ladder_vis.add_child(rung)
	# 右竖
	for ty in range(y_tile0, y_tile1 + 1):
		var rail_r := ColorRect.new()
		rail_r.position = Vector2(x1_px - ladder.position.x - 4, ty * TILE_SIZE - ladder.position.y)
		rail_r.size = Vector2(2, TILE_SIZE)
		rail_r.color = Color("#a07050")
		ladder_vis.add_child(rail_r)
	ladder.add_child(ladder_vis)

	add_child(ladder)
	# 梯子不加入 interactables（持续检测不是按 E 触发）
	# 但加到 _ladder_zones 供 main.gd 查询
	_ladder_zones.append(ladder)

# ── 玩家所在位置是否在某个梯子内 ──
func get_ladder_at_point(p: Vector2) -> Area2D:
	for ladder in _ladder_zones:
		if not is_instance_valid(ladder): continue
		var top: float = ladder.get_meta("ladder_top_y", -1.0)
		var bot: float = ladder.get_meta("ladder_bottom_y", -1.0)
		var lx: float = ladder.get_meta("ladder_x", 0.0)
		# 玩家碰撞体 34 宽，居中 — 给点余量
		if p.y >= top - 8.0 and p.y <= bot + 8.0 and absf(p.x - lx) < TILE_SIZE * 0.8:
			return ladder
	return null

# ═══════════════════════════════════════════════════════
#  钥匙宝箱（kind="key_chest"）— 玩家按 E 拾取 key_id
# ═══════════════════════════════════════════════════════
func _make_key_chest(x_tile: int, y_tile: int, key_id: String) -> void:
	var chest := Area2D.new()
	chest.name = "KeyChest_%s" % key_id
	chest.position = Vector2(x_tile * TILE_SIZE + 8, y_tile * TILE_SIZE + 8)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 28)
	shape.shape = rect
	chest.add_child(shape)

	# 视觉：金色小箱子
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-12, 4), Vector2(12, 4), Vector2(12, -8), Vector2(-12, -8)
	])
	body.color = Color("#a07028")
	chest.add_child(body)
	var lid := Polygon2D.new()
	lid.polygon = PackedVector2Array([
		Vector2(-14, -8), Vector2(14, -8), Vector2(14, -14), Vector2(-14, -14)
	])
	lid.color = Color("#c89038")
	chest.add_child(lid)
	var lockc := ColorRect.new()
	lockc.position = Vector2(-2, -8)
	lockc.size = Vector2(4, 6)
	lockc.color = Color("#ffd700")
	chest.add_child(lockc)

	var lbl := Label.new()
	lbl.text = "🔑 钥匙箱"
	lbl.position = Vector2(-22, -36)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#ffd700"))
	chest.add_child(lbl)

	chest.set_meta("kind", "key_chest")
	chest.set_meta("key_id", key_id)
	add_child(chest)
	interactables.append(chest)
	_key_chest_zones.append(chest)

# ═══════════════════════════════════════════════════════
#  单行道门（kind="one_way_door"）— 玩家只能从指定方向通过
#  实现：把"门"做成两个 Area2D：
#    - inner: 玩家在内部（梯子上）触发
#    - outer_block: 静态墙（阻止从外侧进入）
#  这里简化：只放一个静态墙 + Area2D 提示
# ═══════════════════════════════════════════════════════
var _one_way_doors_local: Array = []

func _make_one_way_door(x_tile0: int, y_tile0: int, x_tile1: int, y_tile1: int, dir: String) -> void:
	# 单行道门：从地下往上爬时能过，从地面进不来
	# 在 x_tile0..x_tile1, y_tile0..y_tile1 范围内放一个 StaticBody2D
	# 但只在 y > y_tile1（即地面）方向挡，玩家从 y < y_tile0（地下）方向不挡
	# 简化：用 _B 层画一面墙，标记为单行道
	var body := StaticBody2D.new()
	body.name = "OneWayDoor_%d_%d" % [x_tile0, y_tile0]
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2((x_tile1 - x_tile0 + 1) * TILE_SIZE, (y_tile1 - y_tile0 + 1) * TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(
		(x_tile0 + x_tile1 + 1) * 0.5 * TILE_SIZE,
		(y_tile0 + y_tile1 + 1) * 0.5 * TILE_SIZE
	)
	add_child(body)

	# 视觉：紫色光幕（表示不可见但存在）
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-rect.size.x * 0.5, -rect.size.y * 0.5),
		Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
		Vector2(rect.size.x * 0.5, rect.size.y * 0.5),
		Vector2(-rect.size.x * 0.5, rect.size.y * 0.5)
	])
	vis.color = Color("#8060c0", 0.3)
	vis.z_index = 5
	body.add_child(vis)

	# 标签（出口标记）
	var lbl := Label.new()
	lbl.text = "出口（单向）"
	lbl.position = Vector2(-30, -16)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#c0a0ff"))
	body.add_child(lbl)

	# 重要：用 _B 层在这个范围也画 tile 保持视觉一致
	# （不影响碰撞，因为 _B 也带碰撞 — 玩家从任何方向都会撞）
	# 真正实现单行道需要更复杂的逻辑（监控玩家位置）
	# — 简化版：先在 _B 层画墙，玩家想从地面进入时会撞墙
	# — 玩家从梯子上来时梯子在墙的左边（x_tile0=420 左边的 x=415）
	# — 梯子顶端 y_tile0=201 — 玩家爬到 y=201 之后会撞墙 199-202
	# — 等等我把墙画在 y:199-202 玩家从梯子上来（y=269 → y=201）会被挡
	# — 修正：单行道墙在 y:199-202, x:420, 玩家从梯子顶 x:415 走到 x:416 就能继续 — 但墙 x:420 挡
	# — 需要把墙挪到 x:421, 玩家从 x:415 走到 x:420 时是单行道 — 出口在右边
	# — 实际：这个"出口"的设计需要更多思考，先占位不做硬阻挡
	body.set_meta("kind", "one_way_door")
	body.set_meta("dir", dir)
	_one_way_doors_local.append(body)

# ══════════════════════════════════════════════════════════════
#  REGIONS & LABELS
# ══════════════════════════════════════════════════════════════
func _make_regions_on_tilemap() -> void:
	var gy := GROUND_Y_PX
	_label_region("中央广场", Vector2(3300, 2960), Color("#b5a05e"))
	_label_region("← 石墙", Vector2(4100, 2960), Color("#ff8040"))
	_label_region("森林", Vector2(5000, 2950), Color("#5f8b5f"))
	_label_region("灯塔", Vector2(5500, 2950), Color("#6eb8db"))
	_label_region("水坝", Vector2(6200, 2950), Color("#7b9088"))
	_label_region("旧车站", Vector2(6900, 2950), Color("#878792"))
	_label_region("游乐园", Vector2(7900, 2950), Color("#e7a84c"))
	_label_region("许愿堂", Vector2(9800, 2950), Color("#8fa9d7"))
	_label_region("地下迷宫", Vector2(5300, 4050), Color("#645880"))

	_add_zone_marker(Vector2(4200, gy), "关卡1\n石墙", Color("#ff8040"))
	_add_zone_marker(Vector2(5000, gy), "关卡2\n找不同", Color("#c080d0"))
	_add_zone_marker(Vector2(5800, 3100), "关卡3\n油画舞步", Color("#d060a0"))
	_add_zone_marker(Vector2(6600, gy), "关卡4\n石台拼图", Color("#78d0b8"))
	_add_zone_marker(Vector2(5400, 4220), "关卡5\n迷宫", Color("#645880"))
	_add_zone_marker(Vector2(7800, 3140), "关卡6\n灯板", Color("#ffaa30"))
	_add_zone_marker(Vector2(9800, gy), "关卡7\n密码台", Color("#a080f0"))

func _label_region(text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.modulate = color.darkened(0.2)
	label.add_theme_font_size_override("font_size", 38)
	label.z_index = -7
	add_child(label)

func _add_zone_marker(pos: Vector2, text: String, color: Color) -> void:
	var marker := Area2D.new()
	marker.position = pos
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28
	shape.shape = circle
	marker.add_child(shape)
	var orb := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(10):
		var a := TAU * i / 10.0
		pts.append(Vector2(cos(a) * 18, sin(a) * 18))
	orb.polygon = pts
	orb.color = color
	marker.add_child(orb)
	var label := Label.new()
	label.text = text
	label.position = Vector2(-36, -48)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color.lightened(0.2))
	marker.add_child(label)
	marker.set_meta("kind", "zone_indicator")

# ══════════════════════════════════════════════════════════════
#  NPCs / PUZZLES / COLLECTIBLES
# ══════════════════════════════════════════════════════════════
func _make_npcs() -> void:
	var spawned: Array[Node2D] = []
	for data in GameData.NPCS:
		var npc := MindscapeNPC.new()
		npc.setup(data)
		add_child(npc)
		interactables.append(npc)
		spawned.append(npc)
	# 反堆叠：推开重叠的NPC
	_separate_npcs(spawned)
	# 把NPC从谜题位置推开
	_push_npcs_away_from_puzzles(spawned)

func _push_npcs_away_from_puzzles(npcs: Array[Node2D]) -> void:
	# 收集所有谜题位置
	var puzzle_positions: Array[Vector2] = []
	for level in GameData.LEVELS:
		puzzle_positions.append(level["pos"] as Vector2)
	
	const MIN_PUZZLE_GAP: float = 200.0
	for npc in npcs:
		var np: Vector2 = npc.position
		for pp in puzzle_positions:
			var dist := np.distance_to(pp)
			if dist < MIN_PUZZLE_GAP and dist > 0.01:
				var push_dir := (np - pp).normalized()
				var push_dist := MIN_PUZZLE_GAP - dist + 40
				npc.position += push_dir * push_dist
				npc.spawn_pos = npc.position  # 更新spawn_pos

func _separate_npcs(npcs: Array[Node2D]) -> void:
	const MIN_GAP: float = 130.0  # NPC间距 (碰撞半径48*2=96 + 余量)
	for iteration in range(8):
		var moved := false
		for i in range(npcs.size()):
			for j in range(i + 1, npcs.size()):
				var a := npcs[i].position
				var b := npcs[j].position
				var diff := b - a
				var dist := diff.length()
				if dist < MIN_GAP and dist > 0.01:
					var push := diff.normalized() * (MIN_GAP - dist) * 0.5
					npcs[i].position -= push
					npcs[j].position += push
					moved = true
		if not moved:
			break

func _make_puzzles(state: Dictionary) -> void:
	for level_data in GameData.LEVELS:
		var level_id: String = level_data["id"]
		var level_pos: Vector2 = level_data["pos"]
		var level_type: String = level_data["type"]
		var prereq: String = level_data.get("prereq", "")
		if prereq != "" and not state.get("completed_levels", []).has(prereq): continue
		if state.get("completed_levels", []).has(level_id): continue
		var puzzle_instance := _create_puzzle_instance(level_type, level_id, level_data)
		if puzzle_instance != null:
			puzzle_instance.position = level_pos
			add_child(puzzle_instance)
			if puzzle_instance.has_signal("puzzle_completed"):
				puzzle_instance.puzzle_completed.connect(_on_puzzle_completed.bind(level_id))
			puzzle_nodes[level_id] = puzzle_instance
			interactables.append(puzzle_instance)

func _create_puzzle_instance(type: String, id: String, data: Dictionary) -> Node2D:
	match type:
		"texture_wall":    return PuzzleTextureWall.new()
		"find_diff":       return PuzzleFindDifference.new()
		"dance_sequence":  return PuzzleBanquetPainting.new()
		"light_board":     return PuzzleAmusementLights.new()
		"npc_cipher":      return PuzzleNPCPassword.new()
		"audio_maze":      return PuzzleDarkMaze.new()
		"nine_grid":       return PuzzleNineGrid.new()
		_:                 return null

func _on_puzzle_completed(level_id: String, reward: String = "") -> void:
	if level_id == "texture_wall":
		remove_texture_wall_blocker()
	puzzle_completed.emit(level_id, reward)

func _make_collectibles(state: Dictionary) -> void:
	var collected: Array = state.get("collectibles", [])
	var placements: Array = [
		{"i": 0, "pos": Vector2(2400, 3170)}, {"i": 1, "pos": Vector2(2800, 3170)},
		{"i": 2, "pos": Vector2(3600, 3170)}, {"i": 3, "pos": Vector2(4400, 3170)},
		{"i": 4, "pos": Vector2(5200, 3170)}, {"i": 5, "pos": Vector2(5600, 3170)},
		{"i": 6, "pos": Vector2(6000, 3170)}, {"i": 7, "pos": Vector2(6600, 3170)},
		{"i": 8, "pos": Vector2(7200, 3170)}, {"i": 9, "pos": Vector2(7600, 3170)},
		{"i": 10, "pos": Vector2(8000, 3170)}, {"i": 11, "pos": Vector2(8400, 3170)},
		{"i": 12, "pos": Vector2(8800, 3170)}, {"i": 13, "pos": Vector2(9200, 3170)},
		{"i": 14, "pos": Vector2(9600, 3170)}, {"i": 15, "pos": Vector2(10000, 3170)},
		{"i": 16, "pos": Vector2(10400, 3170)}, {"i": 17, "pos": Vector2(10800, 3170)},
		{"i": 18, "pos": Vector2(4800, 4150)}, {"i": 19, "pos": Vector2(5200, 4150)},
		{"i": 20, "pos": Vector2(5600, 4150)},
	]
	for p in placements:
		var i: int = p["i"]
		var id := "collectible_%02d" % i
		if collected.has(id): continue
		var area := _add_marker(p["pos"], "★ 纪念物", Color("#f9f4bf"), 28)
		area.set_meta("kind", "collectible")
		area.set_meta("id", id)
		collectible_nodes[id] = area
		interactables.append(area)

func _make_memory_anchors() -> void:
	var positions := {
		"plaza": Vector2(3400, 3170), "forest": Vector2(4800, 3170),
		"lighthouse": Vector2(4900, 3170), "dam": Vector2(6200, 3170),
		"station": Vector2(6900, 3170), "park": Vector2(7900, 3170),
		"observatory": Vector2(9800, 3170), "underground": Vector2(5350, UG_GROUND_Y_PX - 25),
	}
	for key in GameData.REGIONS.keys():
		if key == "spawn": continue
		var pos: Vector2 = positions.get(key, Vector2(4500, 3170))
		var area := _add_marker(pos, "记忆长椅", Color("#bdf7ff"), 44)
		area.set_meta("kind", "anchor")
		area.set_meta("id", key)
		anchor_nodes.append(area)
		interactables.append(area)

func _add_marker(pos: Vector2, label_text: String, color: Color, radius := 36) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	add_child(area)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	area.add_child(shape)
	var orb := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(12):
		var a := TAU * i / 12.0
		pts.append(Vector2(cos(a), sin(a)) * radius * 0.45)
	orb.polygon = pts
	orb.color = color
	area.add_child(orb)
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(-60, -52)
	label.add_theme_font_size_override("font_size", 16)
	area.add_child(label)
	area.add_to_group("interactable")
	return area

func _make_monsters(state: Dictionary) -> void:
	var completed: Array = state.get("completed_regions", [])
	var data: Array = [
		{"id": "noise_lighthouse", "type": "noise", "region": "lighthouse", "pos": Vector2(5300, 3170)},
		{"id": "mouth_station", "type": "silent_mouth", "region": "station", "pos": Vector2(7100, 3170)},
		{"id": "distractor_park", "type": "distractor", "region": "park", "pos": Vector2(8400, 3170)},
		{"id": "shadow_forest", "type": "shadow", "region": "forest", "pos": Vector2(4600, 3170)},
	]
	for item in data:
		if completed.has(item["region"]): continue
		var monster := MindscapeMonster.new()
		monster.setup(item["id"], item["type"], item["pos"])
		monster_canvas.add_child(monster)

# ══════════════════════════════════════════════════════════════
#  INTERACTION
# ══════════════════════════════════════════════════════════════
func nearest_interactable(point: Vector2, max_distance: float = 110.0) -> Node2D:
	var best: Node2D = null
	var best_dist: float = max_distance
	var best_priority: int = -1
	for node in interactables:
		if not is_instance_valid(node): continue
		var dist: float = point.distance_to(node.global_position)
		if dist > best_dist: continue
		var priority: int = 0
		if node is PuzzleTextureWall or node is PuzzleFindDifference or node is PuzzleBanquetPainting or node is PuzzleAmusementLights or node is PuzzleNPCPassword or node is PuzzleDarkMaze or node is PuzzleNineGrid:
			priority = 4
		match node.get_meta("kind", ""):
			"puzzle": priority = 4
			"npc": priority = 3
			"anchor": priority = 2
			"collectible": priority = 1
			"maze_fork_a": priority = 4
			"maze_fork_b": priority = 4
		if dist < best_dist - 5.0 or (abs(dist - best_dist) < 5.0 and priority > best_priority):
			best_dist = dist; best = node; best_priority = priority
	return best

func remove_interactable(node: Node) -> void:
	interactables.erase(node)
	if is_instance_valid(node): node.queue_free()

# ══════════════════════════════════════════════════════════════
#  VIEW PALETTE + EFFECTS
# ══════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	view_pulse_time += delta
	_animate_view_tint()
	if current_palette_view == "blind" and blind_cursor.visible:
		_update_blind_cursor(delta)

func set_view_palette(view: String) -> void:
	if not is_instance_valid(palette_overlay): return
	current_palette_view = view
	view_pulse_time = 0.0
	palette_overlay.material = null

	match view:
		"blind":
			palette_overlay.color = Color(1, 1, 1, 0)
			blind_black.visible = true
			blind_label.visible = true
			blind_cursor.visible = true
			cursor_pulse_time = 0.0
		"adhd":
			palette_overlay.color = Color(1.0, 0.92, 0.4, 0.12)
			blind_black.visible = false; blind_label.visible = false
			blind_cursor.visible = false
		"autism":
			palette_overlay.color = Color(0.6, 0.75, 1.0, 0.2)
			blind_black.visible = false; blind_label.visible = false
			blind_cursor.visible = false
		"depression":
			palette_overlay.color = Color(0.12, 0.18, 0.28, 0.5)
			blind_black.visible = false; blind_label.visible = false
			blind_cursor.visible = false
		_:
			palette_overlay.color = Color(1.0, 0.9, 0.75, 0.06)
			blind_black.visible = false; blind_label.visible = false
			blind_cursor.visible = false

	if _spike_canvas: _spike_canvas.visible = (view == "depression")
	_notify_monsters_view_changed(view)

func get_current_view() -> String: return current_palette_view

func _animate_view_tint() -> void:
	if not is_instance_valid(palette_overlay) or current_palette_view == "blind": return
	var base := palette_overlay.color
	match current_palette_view:
		"adhd":
			var p := 1.0 + 0.04 * sin(view_pulse_time * 8.0)
			palette_overlay.color = Color(base.r, base.g, base.b, clampf(0.12 * p, 0.08, 0.18))
		"autism":
			var p := 1.0 + 0.02 * sin(view_pulse_time * 2.5)
			palette_overlay.color = Color(base.r, base.g, base.b, clampf(0.2 * p, 0.17, 0.25))
		"depression":
			var br := 1.0 + 0.04 * sin(view_pulse_time * 0.6)
			palette_overlay.color = Color(base.r, base.g, base.b, clampf(0.5 * br, 0.44, 0.56))
		_: pass

func _update_blind_cursor(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null: return
	var player := _get_player()
	if player == null: return
	var vs := get_viewport().get_visible_rect().size
	var cam_pos := camera.global_position
	var p_pos := player.global_position
	var zoom := camera.zoom
	var screen_pos := (p_pos - cam_pos) / zoom + vs / 2.0
	blind_cursor.position = screen_pos - blind_cursor.size / 2.0
	cursor_pulse_time += delta
	var alpha: float = 0.8 + 0.2 * sin(cursor_pulse_time * 3.0)
	var st := blind_cursor.get_theme_stylebox("panel") as StyleBoxFlat
	if st != null: st.bg_color = Color(1.0, 1.0, 1.0, alpha)

func trigger_echo_pulse(_center: Vector2) -> void:
	if current_palette_view != "blind" or not is_instance_valid(view_overlay_canvas): return
	var ss := get_viewport().get_visible_rect().size
	var start_sz: float = 14.0
	var end_sz: float = minf(ss.x, ss.y) * 1.5
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color.TRANSPARENT
	rs.border_width_left = 3; rs.border_width_right = 3
	rs.border_width_top = 3; rs.border_width_bottom = 3
	rs.border_color = Color(1.0, 1.0, 1.0, 0.9)
	ring.add_theme_stylebox_override("panel", rs)
	ring.size = Vector2(start_sz, start_sz)
	ring.position = Vector2(ss.x * 0.5 - start_sz / 2.0, ss.y * 0.5 - start_sz / 2.0)
	view_overlay_canvas.add_child(ring)
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_echo_ring_step.bind(ring, start_sz, end_sz), 0.0, 1.0, 0.55)
	tween.tween_callback(_echo_ring_done.bind(ring))

func _echo_ring_step(val: float, ring: Panel, start_sz: float, end_sz: float) -> void:
	if not is_instance_valid(ring): return
	var sz := lerpf(start_sz, end_sz, val)
	ring.size = Vector2(sz, sz)
	var vs := get_viewport().get_visible_rect().size
	ring.position = Vector2(vs.x / 2.0 - sz / 2.0, vs.y / 2.0 - sz / 2.0)
	var st := ring.get_theme_stylebox("panel") as StyleBoxFlat
	if st != null:
		st.set_corner_radius_all(int(sz / 2.0))
		st.border_color = Color(1.0, 1.0, 1.0, lerpf(0.9, 0.0, val))

func _echo_ring_done(ring: Panel) -> void:
	if is_instance_valid(ring): ring.queue_free()

func _notify_monsters_view_changed(view: String) -> void:
	for node in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(node) and node.has_method("on_view_changed"):
			node.on_view_changed(view)

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"): return node
	return null

# ══════════════════════════════════════════════════════════════
#  风向标 + 激光联动系统
# ══════════════════════════════════════════════════════════════

func _make_wind_vanes() -> void:
	var data: Dictionary = GameData.LASER_SYSTEM
	var vane1_pos: Vector2 = data["wind_vane_1"]["pos"] as Vector2
	var vane2_pos: Vector2 = data["wind_vane_2"]["pos"] as Vector2
	var treasure: Vector2 = data["treasure_pos"] as Vector2
	
	# 计算正确角度
	_correct_angle_1 = (treasure - vane1_pos).angle()
	_correct_angle_2 = (treasure - vane2_pos).angle()
	
	_make_single_vane(vane1_pos, 1, _correct_angle_1)
	_make_single_vane(vane2_pos, 2, _correct_angle_2)
	_make_treasure_spot(treasure)

func _make_single_vane(pos: Vector2, vane_idx: int, hint_angle: float) -> void:
	var vane := Node2D.new()
	vane.name = "WindVane_%d" % vane_idx
	vane.position = pos
	vane.z_index = 10
	add_child(vane)
	_wind_vane_nodes.append(vane)
	
	# 基座
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-16, -4), Vector2(16, -4), Vector2(12, 8), Vector2(-12, 8)
	])
	base.color = Color("#6a5a4a")
	vane.add_child(base)
	
	# 柱子
	var pole := ColorRect.new()
	pole.position = Vector2(-3, -64)
	pole.size = Vector2(6, 60)
	pole.color = Color("#8a7a6a")
	vane.add_child(pole)
	
	# 风向标头部（箭头，指向hint_angle方向）
	var arrow := Polygon2D.new()
	var arr_len: float = 30.0
	var arr_w: float = 8.0
	arrow.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(-arr_len * 0.6, -arr_w),
		Vector2(-arr_len * 0.6, -arr_w * 0.3),
		Vector2(-arr_len, -arr_w * 0.3),
		Vector2(-arr_len, arr_w * 0.3),
		Vector2(-arr_len * 0.6, arr_w * 0.3),
		Vector2(-arr_len * 0.6, arr_w),
	])
	arrow.position = Vector2(0, -68)
	arrow.rotation = hint_angle  # 指向treasure的初始方向
	arrow.color = Color("#ff6644")
	arrow.name = "Arrow"
	vane.add_child(arrow)
	
	# 标签
	var label := Label.new()
	label.text = "风向标%d" % vane_idx
	label.position = Vector2(-30, -96)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#ffe8a0"))
	vane.add_child(label)
	
	# 放置区域（更大的碰撞区，用于拖放检测）
	var zone := Area2D.new()
	zone.name = "VanePlacement_%d" % vane_idx
	zone.position = pos
	var zshape := CollisionShape2D.new()
	var zcircle := CircleShape2D.new()
	zcircle.radius = 70.0
	zshape.shape = zcircle
	zone.add_child(zshape)
	zone.set_meta("kind", "wind_vane_placement")
	zone.set_meta("vane_idx", vane_idx)
	add_child(zone)
	_vane_placement_zones.append(zone)
	
	# 高亮环（呼吸效果，仅当装置已获得但未放置时可见）
	var glow := Polygon2D.new()
	glow.name = "GlowRing"
	var gp := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		gp.append(Vector2(cos(a) * 50, sin(a) * 50))
	glow.polygon = gp
	glow.color = Color("#ff6644", 0.0)
	zone.add_child(glow)

func _make_treasure_spot(pos: Vector2) -> void:
	_treasure_marker = Area2D.new()
	_treasure_marker.name = "TreasureSpot"
	_treasure_marker.position = pos
	var tshape := CollisionShape2D.new()
	var tcircle := CircleShape2D.new()
	tcircle.radius = 40.0
	tshape.shape = tcircle
	_treasure_marker.add_child(tshape)
	
	# 宝箱标记（初始不可见）
	var mark := Label.new()
	mark.name = "TreasureLabel"
	mark.text = "✨ 宝藏 ✨"
	mark.position = Vector2(-40, -12)
	mark.add_theme_font_size_override("font_size", 20)
	mark.add_theme_color_override("font_color", Color("#ffd700", 0.0))
	mark.modulate.a = 0.0
	_treasure_marker.add_child(mark)
	_treasure_marker.set_meta("kind", "treasure_spot")
	add_child(_treasure_marker)
	interactables.append(_treasure_marker)

# ── 放置激光装置（由main.gd拖放调用）──
func place_laser_device(device_id: String, vane_idx: int) -> bool:
	var data: Dictionary = GameData.LASER_SYSTEM
	var vane_key := "wind_vane_%d" % vane_idx
	if not data.has(vane_key):
		return false
	var vane_pos: Vector2 = data[vane_key]["pos"] as Vector2
	
	if _placed_lasers.has(vane_idx):
		return false  # 已经有装置了
	
	# 创建激光装置节点（世界空间）
	var device := Node2D.new()
	device.name = device_id
	device.position = vane_pos + Vector2(0, -80)
	device.z_index = 20
	
	var body := Polygon2D.new()
	# 菱形装置
	var sz := 12.0
	body.polygon = PackedVector2Array([
		Vector2(0, -sz), Vector2(sz, 0), Vector2(0, sz), Vector2(-sz, 0)
	])
	var dev_color := Color("#ff4444") if vane_idx == 1 else Color("#44aaff")
	body.color = dev_color
	device.add_child(body)
	
	var dev_label := Label.new()
	dev_label.text = "装置%d" % vane_idx
	dev_label.position = Vector2(-18, -24)
	dev_label.add_theme_font_size_override("font_size", 11)
	dev_label.add_theme_color_override("font_color", dev_color.lightened(0.3))
	device.add_child(dev_label)
	
	# 激光束（初始水平）
	var beam := Line2D.new()
	beam.name = "LaserBeam"
	beam.width = 4.0
	beam.default_color = Color(dev_color.r, dev_color.g, dev_color.b, 0.7)
	beam.z_index = 15
	beam.add_point(Vector2.ZERO)
	beam.add_point(Vector2.ZERO)
	device.add_child(beam)
	
	add_child(device)
	_placed_lasers[vane_idx] = {"node": device, "beam": beam}
	_laser_angles[vane_idx] = 0.0
	
	# 更新风向标发光
	_update_vane_glow(vane_idx)
	_update_laser_beam(vane_idx)
	
	return true

func _update_laser_beam(vane_idx: int) -> void:
	if not _placed_lasers.has(vane_idx):
		return
	var beam: Line2D = _placed_lasers[vane_idx]["beam"]
	var angle: float = _laser_angles.get(vane_idx, 0.0)
	var end := Vector2(cos(angle), sin(angle)) * LASER_BEAM_LENGTH
	beam.set_point_position(0, Vector2.ZERO)
	beam.set_point_position(1, end)

# ── 旋转激光装置 ──
func rotate_placed_laser(vane_idx: int, delta_angle: float) -> void:
	if not _placed_lasers.has(vane_idx):
		return
	_laser_angles[vane_idx] += delta_angle
	_update_laser_beam(vane_idx)
	_check_treasure_alignment()

# ── 设置激光角度（由拖放等直接设定）──
func set_laser_angle(vane_idx: int, angle: float) -> void:
	if not _placed_lasers.has(vane_idx):
		return
	_laser_angles[vane_idx] = angle
	_update_laser_beam(vane_idx)
	_check_treasure_alignment()

func get_laser_angle(vane_idx: int) -> float:
	return _laser_angles.get(vane_idx, 0.0)

func is_laser_placed(vane_idx: int) -> bool:
	return _placed_lasers.has(vane_idx)

# ── 检查双激光是否对齐 ──
func _check_treasure_alignment() -> void:
	if not _placed_lasers.has(1) or not _placed_lasers.has(2):
		return
	
	var vane1_pos: Vector2 = GameData.LASER_SYSTEM["wind_vane_1"]["pos"] as Vector2
	var vane2_pos: Vector2 = GameData.LASER_SYSTEM["wind_vane_2"]["pos"] as Vector2
	var treasure: Vector2 = GameData.LASER_SYSTEM["treasure_pos"] as Vector2
	
	# 检查每条光束是否穿过 treasure_pos 附近
	var a1: float = _laser_angles[1]
	var a2: float = _laser_angles[2]
	
	# 光束1: vane1_pos + t*(cos(a1), sin(a1)) 是否经过treasure
	var hit1 := _point_on_ray(vane1_pos, a1, treasure, 80.0)
	var hit2 := _point_on_ray(vane2_pos, a2, treasure, 80.0)
	
	var mark: Label = _treasure_marker.get_node_or_null("TreasureLabel") as Label
	if mark == null:
		return
	
	if hit1 and hit2:
		mark.modulate.a = 1.0
		mark.add_theme_color_override("font_color", Color("#ffd700", 1.0))
		if not _treasure_marker.has_meta("solved"):
			_treasure_marker.set_meta("solved", true)
			hint_updated.emit("✨ 两束激光在宝藏位置交汇！去那里看看吧！")
	else:
		# 距离越近，标记越亮
		var d1 := _ray_point_dist(vane1_pos, a1, treasure)
		var d2 := _ray_point_dist(vane2_pos, a2, treasure)
		var max_d := maxf(d1, d2)
		var alpha := clampf(1.0 - max_d / 300.0, 0.0, 0.4)
		mark.modulate.a = alpha
		mark.add_theme_color_override("font_color", Color("#ffd700", alpha * 0.6))

func _point_on_ray(origin: Vector2, angle: float, point: Vector2, tolerance: float) -> bool:
	return _ray_point_dist(origin, angle, point) < tolerance

func _ray_point_dist(origin: Vector2, angle: float, point: Vector2) -> float:
	var dir := Vector2(cos(angle), sin(angle))
	var to_point := point - origin
	var proj := to_point.dot(dir)
	if proj < 0:
		return 1e9  # point behind ray
	var closest := origin + dir * proj
	return closest.distance_to(point)

# ── 更新风向标发光 ──
func _update_vane_glow(vane_idx: int) -> void:
	if vane_idx < 1 or vane_idx > _vane_placement_zones.size():
		return
	var zone := _vane_placement_zones[vane_idx - 1]
	var glow: Polygon2D = zone.get_node_or_null("GlowRing") as Polygon2D
	if glow == null:
		return
	if _placed_lasers.has(vane_idx):
		# 已放置 → 绿色呼吸
		var t := create_tween().set_loops()
		t.tween_property(glow, "color", Color("#44ff44", 0.3), 1.0)
		t.tween_property(glow, "color", Color("#44ff44", 0.08), 1.0)
	else:
		# 未放置 → 橙色呼吸
		var t := create_tween().set_loops()
		t.tween_property(glow, "color", Color("#ff6644", 0.35), 1.0)
		t.tween_property(glow, "color", Color("#ff6644", 0.05), 1.0)

# 设置装置可放置状态（由main根据是否有装置决定是否高亮）
func set_vane_highlight(vane_idx: int, active: bool) -> void:
	if vane_idx < 1 or vane_idx > _vane_placement_zones.size():
		return
	var zone := _vane_placement_zones[vane_idx - 1]
	var glow: Polygon2D = zone.get_node_or_null("GlowRing") as Polygon2D
	if glow == null:
		return
	if active:
		_update_vane_glow(vane_idx)
	else:
		glow.color = Color("#ff6644", 0.0)

# ── 获取风向标放置区域的世界位置 ──
func get_vane_placement_pos(vane_idx: int) -> Vector2:
	var data: Dictionary = GameData.LASER_SYSTEM
	var key := "wind_vane_%d" % vane_idx
	if data.has(key):
		return data[key]["pos"] as Vector2
	return Vector2.ZERO

# ── 检测世界坐标是否在风向标放置区域内 ──
func get_nearest_vane_at(pos: Vector2, max_dist: float = 90.0) -> int:
	for i in range(_vane_placement_zones.size()):
		var zone := _vane_placement_zones[i]
		var dist := pos.distance_to(zone.position)
		if dist <= max_dist:
			return i + 1  # vane index (1-based)
	return -1

func update_treasure_key_count(collected_keys: Array) -> void:
	pass
