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
var _maze_fork_a_zone: Area2D
var _maze_fork_b_zone: Area2D

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

# 平台
const PLATFORMS: Array = [
	{"x0": 0,   "x1": 262, "row": GROUND_ROW, "tag": "floor_left"},
	{"x0": 264, "x1": 300, "row": GROUND_ROW, "tag": "floor_mid1"},
	{"x0": 302, "x1": 340, "row": GROUND_ROW, "tag": "floor_lighthouse"},
	{"x0": 342, "x1": 395, "row": GROUND_ROW, "tag": "floor_dam"},
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
	blind_black.z_index = 9999
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
	blind_label.z_index = 10000
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
	var left_col := 260
	var right_col := 440
	for y in range(UG_GROUND_ROW, WORLD_TILE_H):
		for x in range(left_col, right_col + 1):
			var tile := T_GRASS_MID
			if (x + y) % 4 == 0: tile = T_GRASS_FILL
			elif (x + y) % 7 == 0: tile = T_GRASS_FILL_ALT
			_ground_layer.set_cell(Vector2i(x, y), 0, tile)

func _paint_underground_maze_walls() -> void:
	# ═══════════════════════════════════════════════════════
	#  真正物理走通的地下迷宫 — 多层高低地形
	#  入口(行269) → 中央大厅 → 左下层(钥匙) / 右上(宝箱)
	# ═══════════════════════════════════════════════════════
	var R0 := 269  # 主层/入口层
	var R1 := 263  # 上层（宝箱路径）
	var R2 := 275  # 下层（钥匙路径）
	var BOT := 282  # 底部填充

	var _G := _ground_layer
	var _B := _block_layer
	var WR := T_GRASS_MID  # 墙/地面块(带碰撞)
	var GF := T_GRASS_FILL  # 填充色
	var GA := T_GRASS_FILL_ALT  # 替换色

	# ═══════════════════════════════════════════════════════
	#  地表 → 地下 长阶梯（从行200走到行269）
	#  入口在地面 x=290-304，2:1 斜度下行
	# ═══════════════════════════════════════════════════════
	var stair_x0 := 292
	var stair_x := stair_x0
	var stair_rows := R0 - GROUND_ROW  # 69 行
	for step in range(stair_rows):
		var sy := GROUND_ROW + step
		if step > 0 and step % 2 == 0:
			stair_x += 1  # 每两步右移一格（2:1 斜度）
		# 2 tile 宽的台阶
		_G.set_cell(Vector2i(stair_x, sy), 0, WR)
		_G.set_cell(Vector2i(stair_x + 1, sy), 0, WR)

	# 阶梯两侧墙壁（防止摔下去）
	_mf_col(_B, GROUND_ROW, R0 - 1, stair_x0 - 2, WR)     # 左墙
	var stair_end_x := stair_x0 + (stair_rows / 2) + 1
	for step in range(stair_rows):
		var sy := GROUND_ROW + step
		var sx: int
		if step == 0:
			sx = stair_x0
		elif step % 2 == 1:
			sx = stair_x0 + (step / 2)
		else:
			sx = stair_x0 + (step / 2)
		_B.set_cell(Vector2i(sx + 2, sy), 0, WR)  # 右墙紧跟台阶

	# ── 底部实心大地基 ──
	_mf_rect(_G, 265, R0 + 1, 440, BOT, WR)
	_mf_rect(_G, 265, R0, 440, R0, GA)

	# ── 外围边界墙 ──
	_mf_col(_B, R1 - 1, R0, 265, WR)
	_mf_col(_B, R1 - 1, R0, 440, WR)
	_mf_row(_B, 265, 440, R1 - 1, WR)

	# ── 入口走廊 (x:290-304) — 阶梯从地表到此；墙壁在行269留空让玩家通过 ──
	for step in range(8):
		var sy := R0 + 13 - step
		var sx := 293 + step
		_G.set_cell(Vector2i(sx, sy), 0, WR)
		_G.set_cell(Vector2i(sx + 1, sy), 0, WR)
	for y in range(R1 - 1, R0):
		_G.set_cell(Vector2i(292, y), -1)
		_G.set_cell(Vector2i(293, y), -1)
	_mf_col(_B, R1 - 1, R0 - 1, 290, WR)      # 左墙：不到行269，留空给玩家通过
	_mf_col(_B, R1 - 1, R0 - 1, 304, WR)      # 右墙：不到行269

	# ── 中央大厅 (x:293-350) — 扩展至阶梯着陆点 ──
	for x in range(293, 351):
		for y in range(R1 - 1, R0):
			_G.set_cell(Vector2i(x, y), -1)
	_mf_row(_B, 293, 350, R1, WR)
	# 分界柱 x=345-346
	_mf_col(_B, R1 + 1, R0 - 4, 345, WR)
	_mf_col(_B, R1 + 1, R0 - 4, 346, WR)

	# ── Fork A: 左转下行 → 钥匙 ──
	_mf_col(_B, R1, R0, 280, WR)
	_mf_col(_B, R1, R0, 327, WR)
	# 下行台阶
	for step in range(7):
		var sy := R0 + step
		var sx := 311 + step
		_G.set_cell(Vector2i(sx, sy), 0, WR)
		_G.set_cell(Vector2i(sx + 1, sy), 0, WR)
	_mf_col(_B, R0 + 1, R2 + 2, 308, WR)
	_mf_col(_B, R0 + 1, R2 + 2, 322, WR)
	# 下层区域
	_mf_row(_G, 270, 324, R2, GA)
	for y in range(R2 + 1, BOT + 1):
		_mf_row(_G, 270, 324, y, WR)
	_mf_col(_B, R1, R2 - 1, 270, WR)
	_mf_col(_B, R1, R2, 275, WR)
	_mf_col(_B, R1, R2, 282, WR)
	_mf_row(_B, 271, 281, R1, WR)
	for step in range(3):
		var sy := R2 + step
		var sx := 278 + step
		_G.set_cell(Vector2i(sx, sy), 0, WR)
	_mf_row(_B, 270, 278, R1 - 2, WR)

	# ── Fork B: 右转上行 → 宝箱 ──
	_mf_col(_B, R1 + 1, R0, 365, WR)
	_mf_col(_B, R1 + 1, R0, 400, WR)
	# 上行台阶
	for step in range(7):
		var sy := R0 - step
		var sx := 370 + step
		_G.set_cell(Vector2i(sx, sy), 0, WR)
		_G.set_cell(Vector2i(sx + 1, sy), 0, WR)
	_mf_col(_B, R1, R0, 368, WR)
	_mf_col(_B, R1, R0, 382, WR)
	# 上层区域
	for x in range(365, 439):
		_G.set_cell(Vector2i(x, R1), 0, GA)
		for y in range(R1 + 1, R0):
			_G.set_cell(Vector2i(x, y), 0, WR)
	_mf_row(_B, 365, 438, R1 - 2, WR)
	_mf_col(_B, R1 - 2, R1, 408, WR)
	_mf_col(_B, R1 - 2, R1, 428, WR)
	_mf_row(_B, 425, 438, R1 - 3, WR)

	# ── 大厅到两侧的起步台阶 ──
	for step in range(4):
		var sy := R0 - step
		var sx := 355 + step
		_G.set_cell(Vector2i(sx, sy), 0, WR)
		_G.set_cell(Vector2i(sx + 1, sy), 0, WR)
	for step in range(4):
		var sy := R0 + step
		var sx := 335 - step
		_G.set_cell(Vector2i(sx, sy), 0, WR)

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
#  地下迷宫入口
# ══════════════════════════════════════════════════════════════
func _make_underground_maze_entrance() -> void:
	# ── 地面入口标记（灯塔右侧，玩家走台阶下去）──
	# 大号发光箭头引导
	var arrow_bg := ColorRect.new()
	arrow_bg.position = Vector2(4620, GROUND_Y_PX - 42)
	arrow_bg.size = Vector2(160, 38)
	arrow_bg.color = Color("#3a2a5a", 0.7)
	arrow_bg.z_index = 5
	add_child(arrow_bg)
	
	var entry_tag := Label.new()
	entry_tag.text = "▼ 地下迷宫入口 ▼"
	entry_tag.position = Vector2(4610, GROUND_Y_PX - 38)
	entry_tag.add_theme_font_size_override("font_size", 20)
	entry_tag.add_theme_color_override("font_color", Color("#c0b0ff"))
	entry_tag.z_index = 6
	add_child(entry_tag)
	
	# 发光脉冲提示
	var entry_glow := ColorRect.new()
	entry_glow.name = "MazeEntryGlow"
	entry_glow.position = Vector2(4620, GROUND_Y_PX - 46)
	entry_glow.size = Vector2(160, 46)
	entry_glow.color = Color("#c0b0ff", 0.0)
	entry_glow.z_index = 4
	add_child(entry_glow)
	
	# 入口脉冲动画
	var glow_tween := create_tween().set_loops()
	glow_tween.tween_property(entry_glow, "color", Color("#c0b0ff", 0.25), 0.8)
	glow_tween.tween_property(entry_glow, "color", Color("#c0b0ff", 0.05), 0.8)
	
	# 台阶入口区域 — 同时也是一个 ladder/teleport 让玩家轻松下去
	var stair := Area2D.new()
	stair.name = "MazeStairEntrance"
	stair.position = Vector2(4720, GROUND_Y_PX - 20)
	var mshape := CollisionShape2D.new()
	var mrect := RectangleShape2D.new()
	mrect.size = Vector2(90, 70)
	mshape.shape = mrect
	stair.add_child(mshape)
	var mvis := Polygon2D.new()
	mvis.polygon = PackedVector2Array([
		Vector2(-45, -25), Vector2(45, -25), Vector2(45, 25), Vector2(-45, 25)
	])
	mvis.color = Color("#3a2a4a", 0.5)
	var mlabel := Label.new()
	mlabel.text = "走下去"
	mlabel.position = Vector2(-22, -10)
	mlabel.add_theme_font_size_override("font_size", 13)
	mlabel.add_theme_color_override("font_color", Color("#c0b0ff"))
	mvis.add_child(mlabel)
	stair.add_child(mvis)
	# 改为 teleport 类型，方便玩家快速进入
	stair.set_meta("kind", "teleport")
	stair.set_meta("target_x", 295 * TILE_SIZE)   # 台阶底部着陆点x
	stair.set_meta("target_y", (UG_GROUND_ROW) * TILE_SIZE - 30)  # 迷宫入口层y
	add_child(stair)
	interactables.append(stair)

	# 岔路A终点 — 钥匙触发区（下层左上）
	_maze_fork_a_zone = Area2D.new()
	_maze_fork_a_zone.name = "MazeForkA"
	_maze_fork_a_zone.position = Vector2(275 * TILE_SIZE, (UG_GROUND_ROW + 8) * TILE_SIZE - 10)
	var ash := CollisionShape2D.new()
	var ar := RectangleShape2D.new()
	ar.size = Vector2(120, 60)
	ash.shape = ar
	_maze_fork_a_zone.add_child(ash)
	var al := Label.new()
	al.text = "钥匙"
	al.position = Vector2(-10, -8)
	al.add_theme_font_size_override("font_size", 10)
	al.add_theme_color_override("font_color", Color("#60ff60"))
	_maze_fork_a_zone.add_child(al)
	_maze_fork_a_zone.set_meta("kind", "maze_fork_a")
	interactables.append(_maze_fork_a_zone)

	# 岔路B终点 — 宝箱触发区（上层右侧）
	_maze_fork_b_zone = Area2D.new()
	_maze_fork_b_zone.name = "MazeForkB"
	_maze_fork_b_zone.position = Vector2(430 * TILE_SIZE, (UG_GROUND_ROW - 7) * TILE_SIZE - 8)
	var bsh := CollisionShape2D.new()
	var br := RectangleShape2D.new()
	br.size = Vector2(120, 60)
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

func update_treasure_key_count(collected_keys: Array) -> void:
	pass
