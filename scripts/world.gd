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

# 预加载 TileSet 资源（确保 iOS 导出时正确打包）
const TILESET_MAIN := preload("res://map/tileset.tres")
const TILESET_DROP := preload("res://map/tileset_drop.tres")
const SKY_MOUNTAINS_TEX := preload("res://assets/sky_user.png")
const HOUSE_TEX := preload("res://assets/house_user.png")
const SLAB_TEX := preload("res://assets/slab.png")
const DIRT_GRAD_TEX := preload("res://assets/dirt_gradient.png")
const VINE_WALL_TEX := preload("res://assets/vine_wall.png")
const MOUNTAIN_BG_TEX := preload("res://assets/mountain_bg.png")
const TREE_BG_TEX := preload("res://assets/tree_bg.png")
const TREE_NEAR_TEX := preload("res://assets/tree_near.png")
const CLOUD_BG_TEX := preload("res://assets/cloud_bg.png")

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
var _drop_tileset: TileSet     # _drop_layer 专用 tileset，物理层号为2

# 平台
const PLATFORMS: Array = [
	{"x0": 0,   "x1": 262, "row": GROUND_ROW, "tag": "floor_left"},
	{"x0": 264, "x1": 300, "row": GROUND_ROW, "tag": "floor_mid1"},
	# 台阶入口在 x:301-319, 6 级台阶 + 38-tile 自由落体段
	# 自由落体段 x:320-327, floor_dam 从 x=328 开始（紧贴 + 1-tile 间隙）
	{"x0": 328, "x1": 395, "row": GROUND_ROW, "tag": "floor_dam"},
	{"x0": 397, "x1": 450, "row": GROUND_ROW, "tag": "floor_station"},
	{"x0": 452, "x1": 520, "row": GROUND_ROW, "tag": "floor_park"},
	{"x0": 522, "x1": 700, "row": GROUND_ROW, "tag": "floor_obs"},
	{"x0": 260, "x1": 440, "row": UG_GROUND_ROW, "tag": "ug_floor"},
]

var _texture_wall_blocks: Array[Vector2i] = []
var _texture_wall_visual: Sprite2D = null

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
	_add_parallax_layer(0.01, _draw_sky_mountains_tile)
	_add_parallax_layer(0.03, _draw_distant_mountains)
	_add_parallax_layer(0.08, _draw_clouds)
	_add_parallax_layer(0.12, _draw_mid_hills)
	_add_parallax_layer(0.22, _draw_trees_far)
	_add_parallax_layer(0.30, _draw_trees_near)
	_add_parallax_layer(0.35, _draw_buildings_bg)

func _add_parallax_layer(parallax_factor: float, draw_func: Callable) -> void:
	var container := Node2D.new()
	container.name = "Parallax_%.2f" % parallax_factor
	container.z_index = int(-80 + parallax_factor * 30)
	add_child(container)
	draw_func.call(container)
	parallax_layers.append({"node": container, "factor": parallax_factor})

func _spawn_sky_tile(container: Node2D, region: Rect2, pos_x: float, pos_y: float, flip: bool) -> void:
	var s := Sprite2D.new()
	s.texture = SKY_MOUNTAINS_TEX
	s.centered = false
	s.region_enabled = true
	s.region_rect = region
	s.position = Vector2(pos_x, pos_y)
	s.flip_h = flip
	s.texture_filter = TEXTURE_FILTER_LINEAR
	container.add_child(s)

func _draw_sky_mountains_tile(container: Node2D) -> void:
	# 天空+远山背景层(最远层),用用户原图,永不镂空
	# 原图 1080x720, 上半 40%(0~288) 是天空渐变可无限纵向平铺
	# 下半 60%(288~720) 是远山+山脚,只在底部一层
	var sky_h := 288.0
	var mtn_h := 432.0
	var mtn_top_y := 3200.0 - mtn_h
	var sky_bottom_y := mtn_top_y
	var sky_top_y := 1000.0
	var world_w := float(WORLD_TILE_W) * TILE_SIZE
	var start_x := float(floor(-1080.0 * 2.0))
	var end_x := float(world_w + 1080.0 * 2.0)

	# 远山层:只一行,底部贴地(2768~3200)
	var even := true
	var x := start_x
	while x < end_x:
		_spawn_sky_tile(container, Rect2(0, 288, 1080, 432), x, mtn_top_y, not even)
		x += 1080.0
		even = not even

	# 天空层:纵向重复从山顶往上铺到 sky_top_y
	var sky_y := sky_bottom_y - sky_h
	while sky_y >= sky_top_y:
		x = start_x
		while x < end_x:
			_spawn_sky_tile(container, Rect2(0, 0, 1080, 288), x, sky_y, not even)
			x += 1080.0
			even = not even
		sky_y -= sky_h
		even = not even

func _draw_distant_mountains(container: Node2D) -> void:
	# 使用透明底PNG山脉精灵替代Polgyon2D
	var mw := float(MOUNTAIN_BG_TEX.get_width())
	var mh := float(MOUNTAIN_BG_TEX.get_height())
	var base_y := 3380.0
	for i in range(12):
		var s := Sprite2D.new()
		s.texture = MOUNTAIN_BG_TEX
		s.centered = true
		var x := i * 1300.0 - 200.0
		s.position = Vector2(x + mw * 0.5, base_y + 10 - fmod(i * 1.7, 1.0) * 40)
		s.scale = Vector2(1.0 + fmod(i * 0.3, 1.0) * 0.4, 0.9 + fmod(i * 0.5, 1.0) * 0.3)
		s.modulate.a = 0.45
		s.texture_filter = TEXTURE_FILTER_LINEAR
		container.add_child(s)

func _draw_mid_hills(container: Node2D) -> void:
	# 远景山丘 — 用柔和的大地色系替代原来的绿色方块
	var colors := [Color("#b0a890"), Color("#a89880"), Color("#b8a888"), Color("#a09078")]
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
		hill.modulate.a = 0.4
		container.add_child(hill)

func _draw_clouds(container: Node2D) -> void:
	var cw := float(CLOUD_BG_TEX.get_width())
	var ch := float(CLOUD_BG_TEX.get_height())
	for i in range(18):
		var s := Sprite2D.new()
		s.texture = CLOUD_BG_TEX
		s.centered = true
		s.position = Vector2(i * 750.0 + sin(i * 1.3) * 250.0, 260.0 + cos(i * 1.7) * 150.0)
		s.scale = Vector2(0.8 + fmod(i * 0.3, 1.0) * 0.5, 0.7 + fmod(i * 0.4, 1.0) * 0.4)
		s.modulate.a = 0.25 + fmod(i * 0.3, 1.0) * 0.2
		s.texture_filter = TEXTURE_FILTER_LINEAR
		container.add_child(s)

func _draw_trees_far(container: Node2D) -> void:
	# 使用透明底PNG树木精灵替换Polgyon2D
	var tw := float(TREE_BG_TEX.get_width())
	var th := float(TREE_BG_TEX.get_height())
	for i in range(25):
		var s := Sprite2D.new()
		s.texture = TREE_BG_TEX
		s.centered = true
		var tx := i * 500.0 + fmod(i * 3.7, 1.0) * 200.0
		s.position = Vector2(tx, 3280.0 - fmod(i * 1.1, 1.0) * 40)
		s.scale = Vector2(0.25 + fmod(i * 0.4, 1.0) * 0.15, 0.25 + fmod(i * 0.3, 1.0) * 0.15)
		s.modulate.a = 0.75
		s.texture_filter = TEXTURE_FILTER_LINEAR
		container.add_child(s)

func _draw_trees_near(container: Node2D) -> void:
	# 近景树木 — 使用单独的大树PNG精灵
	var nw := float(TREE_NEAR_TEX.get_width())
	var nh := float(TREE_NEAR_TEX.get_height())
	for i in range(18):
		var s := Sprite2D.new()
		s.texture = TREE_NEAR_TEX
		s.centered = true
		var tx := i * 780.0 + fmod(i * 5.1, 1.0) * 300.0 - 200.0
		s.position = Vector2(tx, 3220.0 - fmod(i * 1.7, 1.0) * 40)
		s.scale = Vector2(0.8 + fmod(i * 0.5, 1.0) * 0.5, 0.8 + fmod(i * 0.4, 1.0) * 0.5)
		s.modulate.a = 0.85
		s.texture_filter = TEXTURE_FILTER_LINEAR
		container.add_child(s)

func _draw_buildings_bg(container: Node2D) -> void:
	var bld_colors := [Color("#8a7060"), Color("#9a8070"), Color("#7a6050"), Color("#a09080")]
	# 灯塔位置 — 用用户的房子图替换原来的灯塔
	_spawn_house_sprite(container, Vector2(4900, 2900), 360.0)
	# 水坝
	_draw_dam(Vector2(6200, 3000), container)
	# 许愿堂位置 — 用用户的房子图替换原来的许愿堂
	_spawn_house_sprite(container, Vector2(9800, 2900), 360.0)

# 在指定位置放置用户提供的房子图（透明底）
# pos 是房子底边中点（地面位置），height_px 是房子在世界中显示的高度
func _spawn_house_sprite(container: Node2D, pos: Vector2, height_px: float) -> void:
	var s := Sprite2D.new()
	s.texture = HOUSE_TEX
	s.centered = false
	# 原图 1024x1024 → 等比例缩放到指定高度
	var aspect: float = float(HOUSE_TEX.get_width()) / float(HOUSE_TEX.get_height())
	var width_px: float = height_px * aspect
	s.position = Vector2(pos.x - width_px * 0.5, pos.y - height_px)
	s.scale = Vector2(width_px / float(HOUSE_TEX.get_width()), height_px / float(HOUSE_TEX.get_height()))
	s.texture_filter = TEXTURE_FILTER_LINEAR
	s.z_index = -3  # 在前景石板之下，但在远景之上
	container.add_child(s)

func _draw_lighthouse(_pos: Vector2, _container: Node2D) -> void:
	# 灯塔已替换为用户房子图（见 _spawn_house_sprite）
	pass

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

func _draw_observatory(_pos: Vector2, _container: Node2D) -> void:
	# 许愿堂已替换为用户房子图（见 _spawn_house_sprite）
	pass

# ══════════════════════════════════════════════════════════════
#  TILEMAP WORLD
# ══════════════════════════════════════════════════════════════
func _make_tilemap_world() -> void:
	# 校验预加载的 TileSet 资源（iOS 导出时资源必须正确打包）
	if TILESET_MAIN == null:
		push_error("world.gd: TILESET_MAIN (res://map/tileset.tres) failed to preload! Tiles will be invisible on some platforms.")
	if TILESET_DROP == null:
		push_error("world.gd: TILESET_DROP (res://map/tileset_drop.tres) failed to preload! Drop-through floors will not work.")

	_ground_layer = _create_layer("Ground", true, -30)
	_water_layer = _create_layer("Water", true, -28)
	_bridge_layer = _create_layer("Bridge", false, -27)
	_deco_layer = _create_layer("Deco", false, -26)
	_pickup_layer = _create_layer("Pickups", false, -25)
	_block_layer = _create_layer("Blocks", true, -24)
	_bg_layer = _create_layer("Background", false, -32)
	# _drop_layer 使用专用 tileset（物理层 2，让 player 的 mask 位 2 单独控制穿透）
	_drop_tileset = TILESET_DROP
	_drop_layer = _create_layer_with_set("DropThrough", true, -23, _drop_tileset)   # 可穿透地板层（碰撞层2）

	_paint_background_bg()
	_paint_all_platforms()
	_paint_water_features()
	_paint_underground_solid()
	_paint_underground_maze_walls()
	_paint_texture_wall_blocker()
	_paint_decorations()
	_draw_ground_foreground()

func _create_layer(name: String, with_collision: bool, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = TILESET_MAIN
	layer.collision_enabled = with_collision
	layer.z_index = z
	add_child(layer)
	return layer

# 使用指定 TileSet 创建 TileMapLayer（用于 _drop_layer 物理层2）
func _create_layer_with_set(name: String, with_collision: bool, z: int, tile_set: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = tile_set
	layer.collision_enabled = with_collision
	layer.z_index = z
	add_child(layer)
	return layer

func _paint_background_bg() -> void:
	pass  # 天空小点已清除

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
	#  地下区域 — 已封死成普通连续平路
	#
	#  之前这里是复杂的多层迷宫（主层/下层/穿透点/梯子/夹层）。
	#  现在：把整个 x:260..440, y:200..280 区域填成实心石板平路，
	#  玩家在地表走过去是连续路面，不会掉到地下。
	#  ── 取消：穿透点、梯子、夹层、墙壁、空气通道
	# ════════════════════════════════════════════════════════════════

	const MAZE_X0 := 260
	const MAZE_X1 := 440
	const TOP_Y := 200
	const FLOOR_Y := 280
	const WR := T_GRASS_MID

	var _G := _ground_layer
	var _B := _block_layer
	var _D := _drop_layer
	_drop_through_tiles.clear()
	_maze_main_to_upper_ladders = []  # 没有任何梯子

	# 1. 先清空所有 _G / _B / _D / deco tile
	for y in range(TOP_Y, FLOOR_Y + 1):
		for x in range(MAZE_X0, MAZE_X1 + 1):
			_G.set_cell(Vector2i(x, y), -1)
			_B.set_cell(Vector2i(x, y), -1)
			_D.set_cell(Vector2i(x, y), -1)
			_deco_layer.set_cell(Vector2i(x, y), -1)

	# 2. 全部用石板路瓦片填实（用 T_GRASS_FILL 作为通用实心 tile）
	for y in range(TOP_Y, FLOOR_Y + 1):
		for x in range(MAZE_X0, MAZE_X1 + 1):
			var tile := T_GRASS_FILL
			if (x + y) % 5 == 0: tile = T_GRASS_FILL_ALT
			_G.set_cell(Vector2i(x, y), 0, tile)

	# 3. 地表 y=200（= GROUND_ROW）那一行用 _B 加碰撞（让玩家能踩）
	for x in range(MAZE_X0, MAZE_X1 + 1):
		_B.set_cell(Vector2i(x, GROUND_ROW), 0, WR)

# ════════════════════════════════════════════════════════════════
#  地下剖面前景 — 石板路 → 泥土 → 深色渐变
#  覆盖所有裸露地面，让地下看起来更自然，无可见接缝
# ════════════════════════════════════════════════════════════════
func _draw_ground_foreground() -> void:
	var fg := Node2D.new()
	fg.name = "GroundForeground"
	fg.z_index = -27
	fg.z_as_relative = false
	add_child(fg)

	var world_w := float(WORLD_TILE_W * TILE_SIZE)         # 11200 px
	var surface_y := GROUND_Y_PX                            # 3200
	var bottom_y := float(WORLD_TILE_H * TILE_SIZE)         # 4496

	const SLAB_H  := 56.0   # 石板表层高度
	const MUD_H   := 80.0   # 泥土层高度（大幅缩短）
	var slab_y := surface_y + 4.0
	var mud_y  := slab_y + SLAB_H
	var grad_y := mud_y + MUD_H
	var grad_h := bottom_y - grad_y

	# ── 1. 石板路表层 ──
	var slab_tex_w := float(SLAB_TEX.get_width())
	var slab_tex_h := float(SLAB_TEX.get_height())
	var slab_tile_w := SLAB_H
	var slab_n := int(ceil(world_w / slab_tile_w)) + 2
	for i in range(maxi(0, slab_n)):
		var s := Sprite2D.new()
		s.texture = SLAB_TEX
		s.centered = false
		s.position = Vector2(i * slab_tile_w - slab_tile_w, slab_y)
		s.scale = Vector2(slab_tile_w / slab_tex_w, SLAB_H / slab_tex_h)
		s.texture_filter = TEXTURE_FILTER_LINEAR
		fg.add_child(s)

	# ── 2. 泥土层 — 统一底色 + 少量深色条纹 ──
	var base_mud := ColorRect.new()
	base_mud.position = Vector2(-100, mud_y)
	base_mud.size = Vector2(world_w + 200, MUD_H)
	base_mud.color = Color("#8a5e38", 0.95)
	fg.add_child(base_mud)

	# 只有少数几条深色条纹，不是大面积色块
	for i in range(5):
		var stripe_x := i * 2600.0 + 400.0
		var stripe := ColorRect.new()
		stripe.position = Vector2(stripe_x, mud_y)
		stripe.size = Vector2(180.0, MUD_H)
		stripe.color = Color("#6d4520", 0.45)
		fg.add_child(stripe)

	# ── 3. 大段渐变（泥土→深棕→黑），占据剩余全部空间 ──
	var grad_tex_w := float(DIRT_GRAD_TEX.get_width())
	var grad_tex_h := float(DIRT_GRAD_TEX.get_height())
	var grad_n := int(ceil(world_w / grad_tex_w)) + 2
	for i in range(maxi(0, grad_n)):
		var g := Sprite2D.new()
		g.texture = DIRT_GRAD_TEX
		g.centered = false
		g.position = Vector2(i * grad_tex_w - grad_tex_w, grad_y)
		g.scale = Vector2(1.0, grad_h / grad_tex_h)
		g.texture_filter = TEXTURE_FILTER_LINEAR
		fg.add_child(g)


func _paint_texture_wall_blocker() -> void:
	var wall_col := 263
	var wall_top := GROUND_ROW - 18
	var wall_bot := GROUND_ROW
	for y in range(wall_top, wall_bot + 1):
		for dx in [-1, 0, 1]:
			_block_layer.set_cell(Vector2i(wall_col + dx, y), 0, T_GRASS_MID)
			_texture_wall_blocks.append(Vector2i(wall_col + dx, y))

	# ── 藤蔓纹理墙视觉 ──
	var wall_sprite := Sprite2D.new()
	wall_sprite.name = "TexWallVine"
	wall_sprite.texture = VINE_WALL_TEX
	wall_sprite.centered = true
	wall_sprite.position = Vector2(wall_col * TILE_SIZE + 24, GROUND_Y_PX - 20)
	wall_sprite.scale = Vector2(0.42, 0.42)
	wall_sprite.z_index = 3
	wall_sprite.texture_filter = TEXTURE_FILTER_LINEAR
	add_child(wall_sprite)
	_texture_wall_visual = wall_sprite

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
	# 移除藤蔓墙视觉
	if _texture_wall_visual != null:
		_texture_wall_visual.queue_free()
		_texture_wall_visual = null
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
	# 迷宫入口改为门洞 — 玩家走到这里按 E 进入
	_maze_main_to_upper_ladders = []
	
	var gate_x := 288 * TILE_SIZE   # 4608 px
	var gate_y := GROUND_Y_PX       # 3200 px
	
	# ── 门框（石拱） ──
	var left_pillar := Polygon2D.new()
	left_pillar.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(14, 0), Vector2(14, -64), Vector2(0, -64)
	])
	left_pillar.position = Vector2(gate_x - 40, gate_y)
	left_pillar.color = Color("#5a4a3a")
	left_pillar.z_index = 6
	add_child(left_pillar)
	
	var right_pillar := Polygon2D.new()
	right_pillar.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(14, 0), Vector2(14, -64), Vector2(0, -64)
	])
	right_pillar.position = Vector2(gate_x + 26, gate_y)
	right_pillar.color = Color("#5a4a3a")
	right_pillar.z_index = 6
	add_child(right_pillar)
	
	var arch := Polygon2D.new()
	arch.polygon = PackedVector2Array([
		Vector2(-6, 0), Vector2(54, 0), Vector2(54, 14), 
		Vector2(44, -20), Vector2(4, -20), Vector2(-6, 14),
	])
	arch.position = Vector2(gate_x - 40, gate_y - 64)
	arch.color = Color("#6a5a4a")
	arch.z_index = 6
	add_child(arch)
	
	# ── 入口门板（带颜色提示是交互门） ──
	var door := ColorRect.new()
	door.position = Vector2(gate_x - 36, gate_y - 60)
	door.size = Vector2(68, 60)
	door.color = Color("#3a3020", 0.85)
	door.z_index = 5
	add_child(door)
	
	var door_label := Label.new()
	door_label.text = "[E] 进入"
	door_label.position = Vector2(gate_x - 30, gate_y - 42)
	door_label.add_theme_font_size_override("font_size", 12)
	door_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	door_label.z_index = 7
	add_child(door_label)
	
	# ── 可交互区域 ──
	var gate_zone := Area2D.new()
	gate_zone.name = "MazeGate"
	gate_zone.position = Vector2(gate_x, gate_y - 20)
	gate_zone.set_meta("kind", "maze_gate")
	var gshape := CollisionShape2D.new()
	var grect := RectangleShape2D.new()
	grect.size = Vector2(100, 80)
	gshape.shape = grect
	gate_zone.add_child(gshape)
	interactables.append(gate_zone)
	add_child(gate_zone)
	
	# ── 门板隐藏引用（用于后续打开动画） ──
	door.name = "MazeDoor"
	door_label.name = "MazeDoorLabel"

# ═══════════════════════════════════════════════════════
#  梯子：玩家在 Area2D 内按 W/↑ 持续上移，按 S/↓ 持续下移
#  kind="ladder" 让 main.gd 知道这是梯子
# ═══════════════════════════════════════════════════════
func _make_ladder(x_tile0: int, y_tile0: int, x_tile1: int, y_tile1: int, ladder_name: String) -> void:
	# 梯子范围（tile 坐标）— 支持 y0 > y1（让玩家能从下方爬上地表）
	var x0_px: float = x_tile0 * TILE_SIZE
	var y0_px: float = y_tile0 * TILE_SIZE
	var x1_px: float = (x_tile1 + 1) * TILE_SIZE
	var y1_px: float = (y_tile1 + 1) * TILE_SIZE
	# ── 修复：归一化 top/bottom ──
	var top_y_px: float = minf(y0_px, y1_px)
	var bot_y_px: float = maxf(y0_px, y1_px)

	var ladder := Area2D.new()
	ladder.name = ladder_name
	ladder.position = Vector2((x0_px + x1_px) * 0.5, (top_y_px + bot_y_px) * 0.5)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(x1_px - x0_px, bot_y_px - top_y_px)
	shape.shape = rect
	ladder.add_child(shape)
	ladder.set_meta("kind", "ladder")
	# top_y = 玩家站立位置的上边界（y 小 = 屏幕上方 = 较小像素）
	# 这里用"实际梯子小端"作为 top_y
	ladder.set_meta("ladder_top_y", top_y_px)
	ladder.set_meta("ladder_bottom_y", bot_y_px)
	ladder.set_meta("ladder_x", (x0_px + x1_px) * 0.5)

	# 梯子视觉：用 2 列竖线模拟（每行 1 个矩形）
	# ── 修复：y_tile0 > y_tile1 时也能画（用 normalize 后的范围）──
	var y_draw_start: int = mini(y_tile0, y_tile1)
	var y_draw_end: int = maxi(y_tile0, y_tile1)
	var ladder_vis := Node2D.new()
	ladder_vis.z_index = 4
	# 左竖
	for ty in range(y_draw_start, y_draw_end + 1):
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
	for ty in range(y_draw_start, y_draw_end + 1):
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
				# 用 lambda 捕获 level_id，避免 bind 参数顺序问题
				puzzle_instance.puzzle_completed.connect(func(reward: String): _on_puzzle_completed(level_id, reward))
			if puzzle_instance.has_signal("room_toggled"):
				puzzle_instance.room_toggled.connect(_on_puzzle_room_toggle)
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

func _on_puzzle_room_toggle(_open: bool) -> void:
	pass  # player.controls_enabled 由 puzzle 直接设置

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
		"observatory": Vector2(10600, 3170), "underground": Vector2(5350, UG_GROUND_Y_PX - 25),
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
