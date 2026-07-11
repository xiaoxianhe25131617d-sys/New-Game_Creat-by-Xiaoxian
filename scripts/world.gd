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
var sky_background: TextureRect
var view_tint_canvas: CanvasLayer
var palette_overlay: ColorRect
var blind_vision: ColorRect
var blind_vision_material: ShaderMaterial
var view_overlay_canvas: CanvasLayer
var monster_canvas: CanvasLayer

var current_palette_view: String = "normal"
var view_pulse_time: float = 0.0
var _spike_canvas: CanvasLayer

const BLIND_VISION_WORLD_RADIUS: float = 80.0
const BLIND_VISION_FEATHER: float = 16.0
const BLIND_VISION_SHADER := preload("res://shaders/blind_vision.gdshader")

var _drop_through_tiles: Array[Vector2i] = []  # 可穿透地板位置列表
var _ladder_zones: Array[Area2D] = []  # 梯子列表（玩家可爬）

func is_drop_through_tile(tile_pos: Vector2i) -> bool:
	for dt in _drop_through_tiles:
		if dt == tile_pos:
			return true
	return false

func is_drop_through_at(point: Vector2) -> bool:
	var tile_pos := Vector2i(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))
	return is_drop_through_tile(tile_pos) or is_drop_through_tile(tile_pos + Vector2i(0, 1))

func get_ladder_at_point(_p: Vector2) -> Area2D:
	return null

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
const GROUND_Y_PX := GROUND_ROW * TILE_SIZE
const WORLD_TILE_W := 700
const WORLD_TILE_H := 226

# 预加载 TileSet 资源（确保 iOS 导出时正确打包）
const TILESET_MAIN := preload("res://map/tileset.tres")
const TILESET_DROP := preload("res://map/tileset_drop.tres")
const SKY_TEXTURE := preload("res://assets/sky_user.png")
const MEMORY_BENCH_TEXTURE_PATH := "res://assets/environment/generated/memory_bench.png"

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
const T_BRIDGE_H := Vector2i(4, 1)
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
	{"x0": 263, "x1": 327, "row": GROUND_ROW, "tag": "floor_mid1"},
	{"x0": 328, "x1": 395, "row": GROUND_ROW, "tag": "floor_dam"},
	{"x0": 396, "x1": 450, "row": GROUND_ROW, "tag": "floor_station"},
	{"x0": 451, "x1": 520, "row": GROUND_ROW, "tag": "floor_park"},
	{"x0": 521, "x1": WORLD_TILE_W - 1, "row": GROUND_ROW, "tag": "floor_obs"},
]

var _texture_wall_body: StaticBody2D
var _memory_bench_alignment_cached := false
var _memory_bench_visual_position := Vector2.ZERO

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
	_make_wind_vanes()

# ══════════════════════════════════════════════════════════════
#  BACKGROUND CANVAS + VIEW TINT
# ══════════════════════════════════════════════════════════════
func _make_background_canvas() -> void:
	# Run after normal gameplay nodes so the mask uses the latest camera canvas transform.
	process_priority = 1000
	# 固定在视口后的像素天空背景。
	bg_canvas = CanvasLayer.new()
	bg_canvas.name = "BackgroundCanvas"
	bg_canvas.layer = -100
	bg_canvas.follow_viewport_enabled = false
	add_child(bg_canvas)

	sky_background = TextureRect.new()
	sky_background.name = "Sky"
	sky_background.position = Vector2.ZERO
	sky_background.texture = SKY_TEXTURE
	sky_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sky_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_canvas.add_child(sky_background)
	_resize_sky_background()
	get_viewport().size_changed.connect(_resize_sky_background)

	# View tint (layer 500)
	view_tint_canvas = CanvasLayer.new()
	view_tint_canvas.name = "ViewTintCanvas"
	view_tint_canvas.layer = 500
	view_tint_canvas.follow_viewport_enabled = false
	add_child(view_tint_canvas)

	palette_overlay = ColorRect.new()
	palette_overlay.name = "ViewTint"
	palette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_overlay.color = Color(1.0, 0.9, 0.75, 0.08)
	view_tint_canvas.add_child(palette_overlay)

	# Blind vision mask. The shader samples the already-rendered scene and
	# replaces it with grayscale only inside the player's dynamic radius.
	blind_vision = ColorRect.new()
	blind_vision.name = "BlindVision"
	blind_vision.set_anchors_preset(Control.PRESET_FULL_RECT)
	blind_vision.color = Color.WHITE
	blind_vision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_vision.visible = false
	blind_vision.z_index = 127
	blind_vision_material = ShaderMaterial.new()
	blind_vision_material.shader = BLIND_VISION_SHADER
	blind_vision_material.set_shader_parameter("player_screen_uv", Vector2(0.5, 0.5))
	blind_vision_material.set_shader_parameter("radius_px", BLIND_VISION_WORLD_RADIUS)
	blind_vision_material.set_shader_parameter("feather_px", BLIND_VISION_FEATHER)
	blind_vision.material = blind_vision_material
	view_tint_canvas.add_child(blind_vision)

	view_overlay_canvas = CanvasLayer.new()
	view_overlay_canvas.name = "ViewOverlayCanvas"
	view_overlay_canvas.layer = 10000
	view_overlay_canvas.follow_viewport_enabled = false
	add_child(view_overlay_canvas)

	monster_canvas = CanvasLayer.new()
	monster_canvas.name = "MonsterCanvas"
	monster_canvas.layer = 450
	monster_canvas.follow_viewport_enabled = true
	add_child(monster_canvas)

func _resize_sky_background() -> void:
	if is_instance_valid(sky_background):
		sky_background.size = get_viewport_rect().size

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
	# 水坝
	_draw_dam(Vector2(6200, 3000), container)
	# 许愿堂
	_draw_observatory(Vector2(9800, 2950), container)

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
	_paint_texture_wall_blocker()
	_paint_decorations()

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
	# 顶层只画草坪，下面只画泥土，避免草边纹理在地层中重复成条纹。
	for x in range(x0, x1 + 1):
		var tile := T_GRASS_TM
		if x == x0: tile = T_GRASS_TL
		elif x == x1: tile = T_GRASS_TR
		_ground_layer.set_cell(Vector2i(x, top_row), 0, tile)

	for y in range(1, WORLD_TILE_H - top_row):
		var yi := top_row + y
		for x in range(x0, x1 + 1):
			var tile := T_GRASS_FILL_ALT if (x + y) % 9 == 0 else T_GRASS_FILL
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

func _paint_texture_wall_blocker() -> void:
	_texture_wall_body = StaticBody2D.new()
	_texture_wall_body.name = "TextureWallBlocker"
	_texture_wall_body.position = Vector2(4208, GROUND_Y_PX - 150)
	_texture_wall_body.collision_layer = 1
	_texture_wall_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 300)
	shape.shape = rect
	_texture_wall_body.add_child(shape)
	add_child(_texture_wall_body)

func remove_texture_wall_blocker() -> void:
	if is_instance_valid(_texture_wall_body):
		_texture_wall_body.queue_free()
	_texture_wall_body = null
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
#  REGIONS & LABELS
# ══════════════════════════════════════════════════════════════
func _make_regions_on_tilemap() -> void:
	var gy := GROUND_Y_PX
	_label_region("中央广场", Vector2(3300, 2960), Color("#b5a05e"))
	_label_region("森林", Vector2(5000, 2950), Color("#5f8b5f"))
	_label_region("灯塔", Vector2(5500, 2950), Color("#6eb8db"))
	_label_region("水坝", Vector2(6200, 2950), Color("#7b9088"))
	_label_region("旧车站", Vector2(6900, 2950), Color("#878792"))
	_label_region("游乐园", Vector2(7900, 2950), Color("#e7a84c"))
	_label_region("许愿堂", Vector2(9800, 2950), Color("#8fa9d7"))

	_add_zone_marker(Vector2(5000, gy), "关卡2\n找不同", Color("#c080d0"))
	_add_zone_marker(Vector2(5800, 3100), "关卡3\n油画舞步", Color("#d060a0"))
	_add_zone_marker(Vector2(6600, gy), "关卡4\n石台拼图", Color("#78d0b8"))
	_add_zone_marker(Vector2(7800, 3140), "关卡5\n灯板", Color("#ffaa30"))
	_add_zone_marker(Vector2(9800, gy), "关卡6\n密码台", Color("#a080f0"))

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
		for pp in puzzle_positions:
			var delta_x: float = npc.position.x - pp.x
			if absf(delta_x) < MIN_PUZZLE_GAP:
				var push_dir := -1.0 if delta_x <= 0.0 else 1.0
				npc.position.x += push_dir * (MIN_PUZZLE_GAP - absf(delta_x) + 40.0)
		npc.position.y = npc.spawn_pos.y
		npc.spawn_pos = npc.position

func _separate_npcs(npcs: Array[Node2D]) -> void:
	const MIN_GAP: float = 130.0  # NPC间距 (碰撞半径48*2=96 + 余量)
	for iteration in range(8):
		var moved := false
		for i in range(npcs.size()):
			for j in range(i + 1, npcs.size()):
				var delta_x: float = npcs[j].position.x - npcs[i].position.x
				var dist := absf(delta_x)
				if dist < MIN_GAP:
					var direction := -1.0 if delta_x < 0.0 else 1.0
					var push := (MIN_GAP - dist) * 0.5
					npcs[i].position.x -= direction * push
					npcs[j].position.x += direction * push
					npcs[i].position.y = npcs[i].spawn_pos.y
					npcs[j].position.y = npcs[j].spawn_pos.y
					moved = true
		if not moved:
			break
	for npc in npcs:
		npc.spawn_pos = npc.position

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
	]
	for p in placements:
		var i: int = p["i"]
		var id := "collectible_%02d" % i
		if collected.has(id): continue
		var area := _add_collectible_marker(p["pos"], Color("#f9d978"))
		area.set_meta("kind", "collectible")
		area.set_meta("id", id)
		collectible_nodes[id] = area
		interactables.append(area)

func _make_memory_anchors() -> void:
	var positions := {
		"plaza": Vector2(3400, GROUND_Y_PX), "forest": Vector2(4800, GROUND_Y_PX),
		"lighthouse": Vector2(4900, GROUND_Y_PX), "dam": Vector2(6200, GROUND_Y_PX),
		"station": Vector2(6900, GROUND_Y_PX), "park": Vector2(7900, GROUND_Y_PX),
		"observatory": Vector2(9800, GROUND_Y_PX),
	}
	for key in GameData.REGIONS.keys():
		if key == "spawn": continue
		var pos: Vector2 = positions.get(key, Vector2(4500, GROUND_Y_PX))
		var area := _add_memory_bench(pos)
		area.set_meta("kind", "anchor")
		area.set_meta("id", key)
		anchor_nodes.append(area)
		interactables.append(area)

func _add_memory_bench(pos: Vector2) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	add_child(area)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 68)
	shape.shape = rect
	shape.position = Vector2(0, -34)
	area.add_child(shape)

	var texture := load(MEMORY_BENCH_TEXTURE_PATH) as Texture2D
	var bench := Sprite2D.new()
	bench.name = "BenchTexture"
	bench.texture = texture
	bench.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bench.z_index = 4
	if texture != null:
		var texture_size := texture.get_size()
		var scale_factor := minf(132.0 / texture_size.x, 76.0 / texture_size.y)
		bench.scale = Vector2(scale_factor, scale_factor)
		if _memory_bench_alignment_cached:
			bench.position = _memory_bench_visual_position
		else:
			_align_grounded_sprite(bench, texture.get_image())
			_memory_bench_visual_position = bench.position
			_memory_bench_alignment_cached = true
	area.add_child(bench)

	var label := Label.new()
	label.text = "记忆长椅"
	label.position = Vector2(-60, -88)
	label.size = Vector2(120, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#e8f4f0"))
	area.add_child(label)
	area.add_to_group("interactable")
	return area

func _align_grounded_sprite(sprite: Sprite2D, image: Image) -> void:
	var min_x := image.get_width()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.8:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_y < 0:
		return
	var center := Vector2(image.get_width(), image.get_height()) * 0.5
	sprite.position.x = -(((min_x + max_x) * 0.5) - center.x) * sprite.scale.x
	sprite.position.y = -(max_y - center.y) * sprite.scale.y

func _add_collectible_marker(pos: Vector2, color: Color) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	add_child(area)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26
	shape.shape = circle
	area.add_child(shape)

	var root := Node2D.new()
	root.name = "PixelCollectible"
	root.scale = Vector2(2.0, 2.0)
	root.z_index = 8
	area.add_child(root)
	_add_pixel_rect(root, Rect2(-3, -12, 6, 2), color.lightened(0.35))
	_add_pixel_rect(root, Rect2(-5, -10, 10, 4), color)
	_add_pixel_rect(root, Rect2(-4, -6, 8, 5), color.darkened(0.18))
	_add_pixel_rect(root, Rect2(-2, -4, 4, 3), color.lightened(0.18))
	_add_pixel_rect(root, Rect2(-1, -15, 2, 3), Color("#fff3b0"))

	var label := Label.new()
	label.text = "纪念物"
	label.position = Vector2(-28, -48)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("#fff1a8"))
	area.add_child(label)
	area.add_to_group("interactable")
	return area

func _add_pixel_rect(parent: Node2D, rect: Rect2, color: Color) -> void:
	var px := ColorRect.new()
	px.position = rect.position
	px.size = rect.size
	px.color = color
	parent.add_child(px)

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
		if node is PuzzleTextureWall or node is PuzzleFindDifference or node is PuzzleBanquetPainting or node is PuzzleAmusementLights or node is PuzzleNPCPassword or node is PuzzleNineGrid:
			priority = 4
		match node.get_meta("kind", ""):
			"puzzle": priority = 4
			"npc": priority = 3
			"anchor": priority = 2
			"collectible": priority = 1
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
	if current_palette_view == "blind" and is_instance_valid(blind_vision_material):
		_update_blind_vision()

func set_view_palette(view: String) -> void:
	if not is_instance_valid(palette_overlay): return
	current_palette_view = view
	view_pulse_time = 0.0
	palette_overlay.material = null

	match view:
		"blind":
			palette_overlay.color = Color(1, 1, 1, 0)
			blind_vision.visible = true
			_update_blind_vision()
		"adhd":
			palette_overlay.color = Color(1.0, 0.92, 0.4, 0.12)
			blind_vision.visible = false
		"autism":
			palette_overlay.color = Color(0.6, 0.75, 1.0, 0.2)
			blind_vision.visible = false
		"depression":
			palette_overlay.color = Color(0.12, 0.18, 0.28, 0.5)
			blind_vision.visible = false
		_:
			palette_overlay.color = Color(1.0, 0.9, 0.75, 0.06)
			blind_vision.visible = false

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

func _update_blind_vision() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var screen_position := _get_player_screen_position()
	var player_screen_uv := Vector2(
		screen_position.x / viewport_size.x,
		screen_position.y / viewport_size.y
	)
	var camera := get_viewport().get_camera_2d()
	var zoom_scale := 1.0
	if camera != null:
		zoom_scale = maxf(absf(camera.zoom.x), 0.001)
	blind_vision_material.set_shader_parameter("player_screen_uv", player_screen_uv)
	blind_vision_material.set_shader_parameter("radius_px", BLIND_VISION_WORLD_RADIUS * zoom_scale)
	blind_vision_material.set_shader_parameter("feather_px", BLIND_VISION_FEATHER * zoom_scale)

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
	ring.position = _get_player_screen_position() - Vector2(start_sz, start_sz) / 2.0
	view_overlay_canvas.add_child(ring)
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_echo_ring_step.bind(ring, start_sz, end_sz), 0.0, 1.0, 0.55)
	tween.tween_callback(_echo_ring_done.bind(ring))

func _echo_ring_step(val: float, ring: Panel, start_sz: float, end_sz: float) -> void:
	if not is_instance_valid(ring): return
	var sz := lerpf(start_sz, end_sz, val)
	ring.size = Vector2(sz, sz)
	ring.position = _get_player_screen_position() - Vector2(sz, sz) / 2.0
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

func _get_player_screen_position() -> Vector2:
	var player := _get_player()
	if player == null:
		return get_viewport_rect().size * 0.5
	return player.get_global_transform_with_canvas().origin

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
