extends Node2D
class_name MindscapeWorld

const LASER_FOCUS_SCRIPT := preload("res://scripts/puzzle_laser_focus.gd")

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
var blind_black: ColorRect
var blind_label: Label
var view_overlay_canvas: CanvasLayer
var monster_canvas: CanvasLayer

var blind_cursor: Panel
var cursor_pulse_time: float = 0.0
var current_palette_view: String = "normal"
var view_pulse_time: float = 0.0
var _spike_canvas: CanvasLayer

var _drop_through_tiles: Array[Vector2i] = []  # 可穿透地板位置列表
var _ladder_zones: Array[Area2D] = []  # 梯子列表（玩家可爬）
var _laser_focus_puzzle: Area2D  # 出生点激光聚焦关卡引用

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

# 激光联动（风向标视觉已移除，保留放置区和激光系统）
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

const DISTANT_MOUNTAIN_TEX := preload("res://assets/mountain_bg.png")  # 远山原图平铺
const CLOUD_BG_TEX := preload("res://assets/cloud_bg.png")
const TREE_BG_TEX := preload("res://assets/tree_bg.png")

# ── 动物帧路径（运行时 load，避免 preload 需要 import 缓存）──
# 狗帧：新6帧spritesheet切割结果
# 帧1-3（行1）= 走路动作；帧4=站立；帧5=嗅地；帧6=卧趴（休息）
const DOG_FRAME_PATHS: Array[String] = [
	"res://assets/characters/animals/dog_new_1.png",
	"res://assets/characters/animals/dog_new_2.png",
	"res://assets/characters/animals/dog_new_3.png",
	"res://assets/characters/animals/dog_new_4.png",
	"res://assets/characters/animals/dog_new_5.png",
	"res://assets/characters/animals/dog_new_6.png",
]
# 猫帧：新6帧spritesheet切割结果
# 帧1-3（行1）= 走路动作；帧4=坐下；帧5=趴着（休息）；帧6=回头坐
const CAT_FRAME_PATHS: Array[String] = [
	"res://assets/characters/animals/cat_new_1.png",
	"res://assets/characters/animals/cat_new_2.png",
	"res://assets/characters/animals/cat_new_3.png",
	"res://assets/characters/animals/cat_new_4.png",
	"res://assets/characters/animals/cat_new_5.png",
	"res://assets/characters/animals/cat_new_6.png",
]
# 运行时加载的纹理缓存
var _dog_frames: Array[Texture2D] = []
var _cat_frames: Array[Texture2D] = []

const ANIMAL_COUNT: int = 6
const ANIMAL_MIN_SPEED: float = 18.0
const ANIMAL_MAX_SPEED: float = 42.0
const ANIMAL_BARK_INTERVAL_MIN: float = 6.0
const ANIMAL_BARK_INTERVAL_MAX: float = 14.0
const ANIMAL_HEAR_RADIUS: float = 380.0
const ANIMAL_SPAWN_MIN_X: float = 600.0
const ANIMAL_SPAWN_MAX_X: float = 10500.0

const BOOKSHELF_TEX := preload("res://assets/bookshelf.png")
const STONE_CHEST_TEX := preload("res://assets/stone_chest.png")
const HOUSE_TEX := preload("res://assets/house_user.png")  # 用户觉得好看的房子
const WISHPLACE_HOUSE_EXTERIOR_TEX := preload("res://assets/house_user_alpha.png")  # 许愿堂外观（带透明，已导入）
# 内部背景用 load（新文件，编辑器首次打开时自动导入）
const WISHPLACE_HOUSE_INTERIOR_PATH := "res://assets/wishplace_house_interior.png"

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

var _parallax_initialized: bool = false
var _last_cam_pos: Vector2 = Vector2.ZERO
var parallax_orig_positions: Dictionary = {}  # 每层原始位置

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
	_make_laser_zones()  # 激光放置区（无风向标视觉）
	_make_laser_focus_puzzle(state)  # 出生点激光聚焦台
	_make_right_world_boundary()  # 右边界隐形墙 + 远处道路景观
	_make_flying_birds()  # 随机空中飞鸟（6帧精灵图）
	_make_animals()       # 地面狗猫（各3只）
	_make_hidden_color_clues()   # 草丛隐藏颜色线索（舞蹈按钮答案）

# ══════════════════════════════════════════════════════════════
#  BACKGROUND CANVAS + VIEW TINT
# ══════════════════════════════════════════════════════════════
func _make_background_canvas() -> void:
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
#  PARALLAX BACKGROUNDS
#  远山：放在独立 CanvasLayer（固定像素大小，不随 camera zoom 缩放）
#  其他层：仍然在世界空间用 Node2D，每帧用视差公式移动
# ══════════════════════════════════════════════════════════════

# 远山 CanvasLayer 引用（用于每帧更新 offset）
var _mountain_canvas: CanvasLayer = null
var _mountain_strip: Node2D = null   # 存放平铺 Sprite2D 的容器

# 云层 CanvasLayer（最远，极慢漂移）
var _cloud_canvas: CanvasLayer = null
var _cloud_strip: Node2D = null

# 树层 CanvasLayer（比山近，速度稍快）
var _tree_canvas: CanvasLayer = null
var _tree_strip: Node2D = null

func _make_parallax_backgrounds() -> void:
	# ── 三层贴图 CanvasLayer（从远到近：云 → 山 → 树）──
	_make_bg_canvas_layer(CLOUD_BG_TEX,    -95, 120.0, 0.006, "_cloud")
	_make_mountain_canvas_layer()
	_make_bg_canvas_layer(TREE_BG_TEX,     -85, 330.0, 0.025, "_tree")
	# ── 代码生成的中景层（建筑/水坝等固定元素）──
	_add_parallax_layer(0.35, _draw_buildings_bg)


## 通用贴图背景 CanvasLayer 工厂
## tex: 贴图  layer_z: CanvasLayer层级  screen_y: 屏幕Y位置  factor: 视差系数
func _make_bg_canvas_layer(tex: Texture2D, layer_z: int, screen_y: float, factor: float, tag: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "BgCanvas" + tag
	canvas.layer = layer_z
	canvas.follow_viewport_enabled = false
	add_child(canvas)

	var strip := Node2D.new()
	strip.name = "Strip" + tag
	canvas.add_child(strip)

	var tile_w: float = float(tex.get_width())
	var num_tiles: int = 4
	for i in range(num_tiles):
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.centered = false
		s.position = Vector2((i - 1) * tile_w, 0.0)
		strip.add_child(s)
	strip.position = Vector2(0.0, screen_y)

	# 注册到视差更新字典
	_bg_strips[tag] = {"strip": strip, "tile_w": tile_w, "factor": factor}


var _bg_strips: Dictionary = {}  # tag → {strip, tile_w, factor}

func _make_mountain_canvas_layer() -> void:
	_mountain_canvas = CanvasLayer.new()
	_mountain_canvas.name = "MountainParallax"
	_mountain_canvas.layer = -90          # 在天空背景(-100)上面，其他层下面
	_mountain_canvas.follow_viewport_enabled = false
	add_child(_mountain_canvas)

	_mountain_strip = Node2D.new()
	_mountain_strip.name = "MountainStrip"
	_mountain_canvas.add_child(_mountain_strip)

	var tile_w: float = float(DISTANT_MOUNTAIN_TEX.get_width())
	var tile_h: float = float(DISTANT_MOUNTAIN_TEX.get_height())
	# 覆盖约3个屏幕宽度（1280×3）使平铺不会露白
	var num_tiles: int = 4
	for i in range(num_tiles):
		var s := Sprite2D.new()
		s.texture = DISTANT_MOUNTAIN_TEX
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 保持像素精度
		s.centered = false
		# x: 从 -tile_w 开始铺，保证向左偏移时不露边
		s.position = Vector2((i - 1) * tile_w, 0.0)
		s.modulate = Color(1.0, 1.0, 1.0, 0.92)
		_mountain_strip.add_child(s)

	# 初始Y位置：屏幕下半区，让山顶可见（在 _update_parallax 首帧设置）
	_mountain_strip.position = Vector2(0.0, 380.0)  # 380≈720*0.53，山位于屏幕偏下位置

func _add_parallax_layer(parallax_factor: float, draw_func: Callable) -> void:
	var container := Node2D.new()
	container.name = "Parallax_%.2f" % parallax_factor
	container.z_index = int(-80 + parallax_factor * 30) if parallax_factor < 0.30 else 10
	add_child(container)
	draw_func.call(container)
	parallax_layers.append({"node": container, "factor": parallax_factor})
	parallax_orig_positions[container] = container.position

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
	# 水坝（放在视差层，可以缓动）
	_draw_dam(Vector2(6200, 3000), container)
	# 许愿堂：直接加到世界根节点（不随视差移动，位置固定准确）
	_spawn_wishplace_decor(self, Vector2(WISHPLACE_X, GROUND_Y_PX))

# ══════════════════════════════════════════════════════════════
#  视差背景跟随相机（每帧调用）
# ══════════════════════════════════════════════════════════════
func _update_parallax() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cam_pos: Vector2 = cam.global_position
	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	# ── 远山 CanvasLayer（mountain_bg）视差 ──
	if _mountain_strip != null and is_instance_valid(_mountain_strip):
		var tile_w: float = float(DISTANT_MOUNTAIN_TEX.get_width())
		var raw_x: float = -cam_pos.x * 0.018
		var offset_x: float = fmod(raw_x, tile_w)
		if offset_x < 0.0:
			offset_x += tile_w
		_mountain_strip.position = Vector2(offset_x - tile_w, _mountain_strip.position.y)

	# ── 云 / 树 等贴图 CanvasLayer 视差 ──
	for tag in _bg_strips:
		var data: Dictionary = _bg_strips[tag]
		var strip: Node2D = data["strip"]
		if not is_instance_valid(strip):
			continue
		var tile_w: float = data["tile_w"]
		var factor: float = data["factor"]
		var raw_x: float = -cam_pos.x * factor
		var offset_x: float = fmod(raw_x, tile_w)
		if offset_x < 0.0:
			offset_x += tile_w
		strip.position = Vector2(offset_x - tile_w, strip.position.y)

	# ── 其他世界空间视差层 ──
	if not _parallax_initialized:
		_last_cam_pos = cam_pos
		_parallax_initialized = true
		for layer_data in parallax_layers:
			var node: Node2D = layer_data["node"] as Node2D
			var factor: float = layer_data["factor"]
			if is_instance_valid(node) and parallax_orig_positions.has(node):
				var orig: Vector2 = parallax_orig_positions[node]
				node.position = Vector2(orig.x - cam_pos.x * factor, orig.y)
		return
	for layer_data in parallax_layers:
		var node: Node2D = layer_data["node"] as Node2D
		var factor: float = layer_data["factor"]
		if is_instance_valid(node) and parallax_orig_positions.has(node):
			var orig: Vector2 = parallax_orig_positions[node]
			node.position = Vector2(orig.x - cam_pos.x * factor, orig.y)
	_last_cam_pos = cam_pos

# 在指定位置放置小房子（RGBA透明底，底部贴地）
# pos 是房子底边中点（地面位置），height_px 是房子在世界中显示的可见高度
func _spawn_house_sprite(container: Node2D, pos: Vector2, height_px: float) -> void:
	var s := Sprite2D.new()
	s.texture = HOUSE_TEX
	s.centered = false
	s.texture_filter = TEXTURE_FILTER_LINEAR
	s.z_index = 2

	# 自动检测内容包围盒（避免每帧扫像素，这里用预算值：house_user.png 大约 23.8%..76.2% 水平，15%..72% 垂直）
	const HOUSE_CONTENT_LEFT := 244
	const HOUSE_CONTENT_TOP := 154
	const HOUSE_CONTENT_RIGHT := 779
	const HOUSE_CONTENT_BOTTOM := 737
	var content_w: float = float(HOUSE_CONTENT_RIGHT - HOUSE_CONTENT_LEFT)
	var content_h: float = float(HOUSE_CONTENT_BOTTOM - HOUSE_CONTENT_TOP)
	s.region_enabled = true
	s.region_rect = Rect2(float(HOUSE_CONTENT_LEFT), float(HOUSE_CONTENT_TOP), content_w, content_h)

	var aspect: float = content_w / content_h
	var width_px: float = height_px * aspect
	var scale_x: float = width_px / content_w
	var scale_y: float = height_px / content_h
	s.scale = Vector2(scale_x, scale_y)
	s.position = Vector2(pos.x - width_px * 0.5, pos.y - height_px)
	s.modulate = Color(1.02, 0.95, 0.85, 1.0)
	container.add_child(s)

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
	# 许愿堂：先画房子内部背景，再放书架/宝箱，最后加外观前板
	_spawn_wishplace_decor(container, Vector2(WISHPLACE_X, GROUND_Y_PX))

# 许愿堂装饰：内部背景 + 左侧书架 + 右侧石台宝箱 + 外观前板（走近淡出）
func _spawn_wishplace_decor(container: Node2D, pos: Vector2) -> void:
	# ── 计算房子显示区域 ──
	var cw: float = float(WISHPLACE_CONTENT_RIGHT - WISHPLACE_CONTENT_LEFT)
	var ch: float = float(WISHPLACE_CONTENT_BOTTOM - WISHPLACE_CONTENT_TOP)
	var aspect: float = cw / ch
	var house_w: float = WISHPLACE_DISPLAY_H * aspect
	var house_left: float = pos.x - house_w * 0.5   # 房子左边 X
	var house_top: float  = pos.y - WISHPLACE_DISPLAY_H  # 房子顶部 Y

	# ── 内部背景（暖色木屋内景，始终可见，z_index 低于书架/宝箱）──
	var interior := Sprite2D.new()
	interior.texture = load(WISHPLACE_HOUSE_INTERIOR_PATH) as Texture2D
	interior.centered = false
	interior.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	interior.region_enabled = true
	interior.region_rect = Rect2(WISHPLACE_CONTENT_LEFT, WISHPLACE_CONTENT_TOP, cw, ch)
	interior.scale = Vector2(house_w / cw, WISHPLACE_DISPLAY_H / ch)
	interior.position = Vector2(house_left, house_top)
	interior.z_index = 1
	container.add_child(interior)

	# ── 书架精灵（内部左侧，z_index=2 在内部背景前）──
	var shelf := Sprite2D.new()
	shelf.texture = BOOKSHELF_TEX
	shelf.centered = false
	shelf.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 书架底边贴地，靠左放（房子内部偏左1/3）
	var shelf_x: float = house_left + house_w * 0.18
	shelf.position = Vector2(shelf_x, pos.y - float(BOOKSHELF_TEX.get_height()))
	shelf.z_index = 2
	shelf.modulate = Color(1.02, 0.96, 0.85, 1.0)
	container.add_child(shelf)

	# ── 石台+宝箱精灵（内部右侧，z_index=2）──
	var chest_sprite := Sprite2D.new()
	chest_sprite.texture = STONE_CHEST_TEX
	chest_sprite.centered = false
	chest_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 宝箱靠右放（房子内部偏右1/2）
	var chest_x: float = house_left + house_w * 0.55
	chest_sprite.position = Vector2(chest_x, pos.y - float(STONE_CHEST_TEX.get_height()))
	chest_sprite.z_index = 2
	chest_sprite.modulate = Color(1.02, 0.95, 0.84, 1.0)
	container.add_child(chest_sprite)

	# ── 外观前板（房子正面，z_index=3 遮住书架/宝箱，走近后淡出）──
	var front := Sprite2D.new()
	front.texture = WISHPLACE_HOUSE_EXTERIOR_TEX
	front.centered = false
	front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	front.region_enabled = true
	front.region_rect = Rect2(WISHPLACE_CONTENT_LEFT, WISHPLACE_CONTENT_TOP, cw, ch)
	front.scale = Vector2(house_w / cw, WISHPLACE_DISPLAY_H / ch)
	front.position = Vector2(house_left, house_top)
	front.z_index = 3
	front.modulate.a = 1.0  # 初始完全可见
	container.add_child(front)
	_wishplace_front = front  # 保存引用，用于每帧更新透明度

	# ── 书架交互区域（按E出现密码本） ──
	var shelf_zone := Area2D.new()
	shelf_zone.name = "BookshelfZone"
	shelf_zone.position = Vector2(shelf_x + BOOKSHELF_TEX.get_width() * 0.5, pos.y - BOOKSHELF_TEX.get_height() * 0.5)
	shelf_zone.set_meta("kind", "bookshelf")
	var shelf_shape := CollisionShape2D.new()
	var shelf_rect := RectangleShape2D.new()
	shelf_rect.size = Vector2(BOOKSHELF_TEX.get_width() + 20, BOOKSHELF_TEX.get_height() + 20)
	shelf_shape.shape = shelf_rect
	shelf_zone.add_child(shelf_shape)
	add_child(shelf_zone)
	interactables.append(shelf_zone)

	# ── 宝箱交互区域（按E出现密码锁） ──
	var chest_zone := Area2D.new()
	chest_zone.name = "ChestPasswordZone"
	chest_zone.position = Vector2(chest_x + STONE_CHEST_TEX.get_width() * 0.5, pos.y - STONE_CHEST_TEX.get_height() * 0.5)
	chest_zone.set_meta("kind", "chest_password")
	var chest_shape := CollisionShape2D.new()
	var chest_rect := RectangleShape2D.new()
	chest_rect.size = Vector2(STONE_CHEST_TEX.get_width() + 20, STONE_CHEST_TEX.get_height() + 20)
	chest_shape.shape = chest_rect
	chest_zone.add_child(chest_shape)
	add_child(chest_zone)
	interactables.append(chest_zone)

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
	# 车站小房子已移除（用户不需要）
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
	# 前景树（在玩家前方，z_index高，制造近景遮挡感）
	_draw_foreground_trees()

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

func _draw_foreground_trees() -> void:
	# 前景树：z_index高（玩家面前），比背景树大，位置靠近地面，颜色更深
	var fg_tree_colors := [Color("#1e4a18"), Color("#266022"), Color("#1a3d14"), Color("#2d6b26")]
	# 在地图多处散布，特别是森林区域密集
	var positions: Array[float] = [
		800, 1400, 2100, 2900, 3800, 4200, 4700, 5100, 5500,
		5900, 6400, 7200, 7600, 8300, 8900, 9300, 9900, 10300
	]
	for i in range(positions.size()):
		var tx: float = positions[i]
		_draw_fg_tree(Vector2(tx, GROUND_Y_PX), fg_tree_colors[i % fg_tree_colors.size()], i)

func _draw_fg_tree(pos: Vector2, color: Color, seed_i: int) -> void:
	var h: float = 130.0 + fmod(seed_i * 31.7, 1.0) * 70.0  # 130-200px高
	var trunk_w: float = 7.0 + fmod(seed_i * 7.3, 1.0) * 4.0
	# 树干（棕色）
	var trunk := Polygon2D.new()
	trunk.polygon = PackedVector2Array([
		Vector2(pos.x - trunk_w, pos.y),
		Vector2(pos.x + trunk_w, pos.y),
		Vector2(pos.x + trunk_w * 0.6, pos.y - h * 0.38),
		Vector2(pos.x - trunk_w * 0.6, pos.y - h * 0.38),
	])
	trunk.color = Color("#4a2e12")
	trunk.z_index = 80
	add_child(trunk)
	# 树冠（3层叠加，半透明增加层次）
	var canopy_colors := [color, color.lightened(0.1), color.darkened(0.15)]
	for layer in range(3):
		var cp := Polygon2D.new()
		var pts := PackedVector2Array()
		var r: float = (50.0 - layer * 10.0) + fmod(seed_i * 2.3, 1.0) * 20.0
		var cy_off: float = h * 0.32 + layer * h * 0.15
		var cx_off: float = fmod(layer * 17.3 + seed_i * 3.1, 1.0) * 18.0 - 9.0
		for j in range(12):
			var a := TAU * j / 12.0
			pts.append(Vector2(pos.x + cx_off + cos(a) * r, pos.y - cy_off + sin(a) * r * 0.75))
		cp.polygon = pts
		cp.color = canopy_colors[layer]
		cp.modulate.a = 0.88
		cp.z_index = 80 + layer
		add_child(cp)

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

	# 灯板位置房子前/后层
	_make_lights_house_layers()

# ══════════════════════════════════════════════════════════════
#  灯板位置：仓库前/后分层
#  - 背板（内景）：z_index 低于灯板平台，始终可见
#  - 表面层（外景砖墙）：玩家走入触发范围时才淡入显示，叠在灯板上方；
#    玩家走进内部时淡出消失，呈现内部背板
# ══════════════════════════════════════════════════════════════
const LIGHTS_HOUSE_FRONT_TEX := preload("res://assets/lights_house_front.png")
const LIGHTS_HOUSE_BACK_TEX  := preload("res://assets/lights_house_back.png")

const LIGHTS_HOUSE_X := 7800.0
const LIGHTS_HOUSE_Y := 3200.0         # 图片底边对齐地面
# 显示高度：大于灯板总高（灯板3行间距105px×2+平台高=约350px），这里设 520px 确保完整包住
const LIGHTS_HOUSE_DISPLAY_H := 520.0
# 触发距离：走到灯板感应区边缘（820/2=410）时表面层开始淡入
const LIGHTS_HOUSE_SHOW_DIST := 420.0   # 超过此距离 → 表面层不可见
const LIGHTS_HOUSE_HIDE_DIST := 160.0   # 低于此距离 → 表面层消失（看内部）

var _lights_house_front: Sprite2D
var _lights_house_back: Sprite2D

# 许愿堂房子前后板
const WISHPLACE_X := 9800.0
const WISHPLACE_DISPLAY_H := 400.0          # 房子显示高度（像素）
const WISHPLACE_HIDE_DIST := 180.0          # 进入此距离后前板淡出，露出书架/宝箱
# 内容区域（house_user_alpha.png 实际内容边界）
const WISHPLACE_CONTENT_LEFT   := 244
const WISHPLACE_CONTENT_TOP    := 156
const WISHPLACE_CONTENT_RIGHT  := 776
const WISHPLACE_CONTENT_BOTTOM := 736
var _wishplace_front: Sprite2D = null  # 外观前板（遮住书架的那一层）

func _make_lights_house_layers() -> void:
	# 用 front（外观）的宽高比决定统一显示宽度，back（内景）强制对齐到同样的矩形
	var front_w_orig: float = float(LIGHTS_HOUSE_FRONT_TEX.get_width())
	var front_h_orig: float = float(LIGHTS_HOUSE_FRONT_TEX.get_height())
	var shared_w: float = LIGHTS_HOUSE_DISPLAY_H * (front_w_orig / front_h_orig)
	var anchor_x: float = LIGHTS_HOUSE_X - shared_w * 0.5
	var anchor_y: float = LIGHTS_HOUSE_Y - LIGHTS_HOUSE_DISPLAY_H

	# ── 背板（仓库内景，始终可见，在灯板平台后方）──
	_lights_house_back = Sprite2D.new()
	_lights_house_back.texture = LIGHTS_HOUSE_BACK_TEX
	_lights_house_back.centered = false
	_lights_house_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_lights_house_back.z_index = -2
	var back_w_orig: float = float(LIGHTS_HOUSE_BACK_TEX.get_width())
	var back_h_orig: float = float(LIGHTS_HOUSE_BACK_TEX.get_height())
	# 强制与 front 完全相同的屏幕矩形（拉伸适配）
	_lights_house_back.scale = Vector2(shared_w / back_w_orig, LIGHTS_HOUSE_DISPLAY_H / back_h_orig)
	_lights_house_back.position = Vector2(anchor_x, anchor_y)
	add_child(_lights_house_back)

	# ── 表面层（外观，远处始终可见，进入内部后淡出）──
	_lights_house_front = Sprite2D.new()
	_lights_house_front.texture = LIGHTS_HOUSE_FRONT_TEX
	_lights_house_front.centered = false
	_lights_house_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_lights_house_front.z_index = 9
	_lights_house_front.modulate.a = 1.0  # 初始可见（远处应始终显示外观）
	_lights_house_front.scale = Vector2(shared_w / front_w_orig, LIGHTS_HOUSE_DISPLAY_H / front_h_orig)
	_lights_house_front.position = Vector2(anchor_x, anchor_y)
	add_child(_lights_house_front)

func _update_lights_house_visibility() -> void:
	if _lights_house_front == null or not is_instance_valid(_lights_house_front):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# 用玩家X范围判断是否进入仓库内部（比距离判断更准确）
	# 仓库X范围：LIGHTS_HOUSE_X ± shared_w/2（用DISPLAY_H和宽高比估算）
	var front_w_orig: float = float(LIGHTS_HOUSE_FRONT_TEX.get_width())
	var front_h_orig: float = float(LIGHTS_HOUSE_FRONT_TEX.get_height())
	var shared_w: float = LIGHTS_HOUSE_DISPLAY_H * (front_w_orig / front_h_orig)
	var house_left: float = LIGHTS_HOUSE_X - shared_w * 0.5
	var house_right: float = LIGHTS_HOUSE_X + shared_w * 0.5
	var px: float = player.global_position.x
	# 进入仓库X范围内 → 外墙淡出；超出范围 → 外墙显示
	var margin: float = 60.0  # 进入边缘后60px内完成淡出
	var alpha: float
	if px < house_left - margin or px > house_right + margin:
		alpha = 1.0  # 外部：完全显示外墙
	elif px >= house_left and px <= house_right:
		alpha = 0.0  # 内部：完全隐藏外墙
	else:
		# 过渡区：线性淡出
		var edge_dist: float = minf(px - (house_left - margin), (house_right + margin) - px)
		alpha = clampf(edge_dist / margin, 0.0, 1.0)
	_lights_house_front.modulate.a = alpha

## 许愿堂外观前板可见性：远处显示正面，走进屋内后淡出露出书架/宝箱
func _update_wishplace_visibility() -> void:
	if _wishplace_front == null or not is_instance_valid(_wishplace_front):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# 用X范围判断（同灯板仓库）
	var cw: float = float(WISHPLACE_CONTENT_RIGHT - WISHPLACE_CONTENT_LEFT)
	var ch: float = float(WISHPLACE_CONTENT_BOTTOM - WISHPLACE_CONTENT_TOP)
	var house_w: float = WISHPLACE_DISPLAY_H * (cw / ch)
	var house_left: float = WISHPLACE_X - house_w * 0.5
	var house_right: float = WISHPLACE_X + house_w * 0.5
	var px: float = player.global_position.x
	var margin: float = 60.0
	var alpha: float
	if px < house_left - margin or px > house_right + margin:
		alpha = 1.0
	elif px >= house_left and px <= house_right:
		alpha = 0.0
	else:
		var edge_dist: float = minf(px - (house_left - margin), (house_right + margin) - px)
		alpha = clampf(edge_dist / margin, 0.0, 1.0)
	_wishplace_front.modulate.a = alpha

func _create_puzzle_instance(type: String, id: String, data: Dictionary) -> Node2D:
	match type:
		"texture_wall":    return PuzzleTextureWall.new()
		"find_diff":       return PuzzleFindDifference.new()
		"dance_sequence":  return PuzzleBanquetPainting.new()
		"light_board":     return PuzzleAmusementLights.new()
		"npc_cipher":      return PuzzleNPCPassword.new()
		"nine_grid":       return PuzzleNineGrid.new()
		"laser_focus":     return LASER_FOCUS_SCRIPT.new() as Node2D
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

func _add_collectible_marker(pos: Vector2, _color: Color) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	add_child(area)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26
	shape.shape = circle
	area.add_child(shape)
	# 仅保留一个小标签，不放任何像素艺术装饰（避免地面蓝色异物）
	var label := Label.new()
	label.text = "✦"
	label.position = Vector2(-8, -30)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#ffe8a0", 0.7))
	label.z_index = 5
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
	if current_palette_view == "blind" and blind_cursor.visible:
		_update_blind_cursor(delta)
	# 灯板房子前/后层可见性更新
	_update_lights_house_visibility()
	# 许愿堂外观前板可见性更新
	_update_wishplace_visibility()
	# 飞鸟更新
	_update_birds(delta)
	# 地面动物更新
	_update_animals(delta)
	# 视差背景跟随相机（慢速移动产生远景深度感）
	_update_parallax()

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
#  激光放置区（风向标视觉已移除）
# ══════════════════════════════════════════════════════════════

func _make_laser_zones() -> void:
	var data: Dictionary = GameData.LASER_SYSTEM
	var vane1_pos: Vector2 = data["wind_vane_1"]["pos"] as Vector2
	var vane2_pos: Vector2 = data["wind_vane_2"]["pos"] as Vector2
	var treasure: Vector2 = data["treasure_pos"] as Vector2
	
	# 计算正确角度
	_correct_angle_1 = (treasure - vane1_pos).angle()
	_correct_angle_2 = (treasure - vane2_pos).angle()
	
	# 只创建放置区域（无风向标视觉）
	_make_placement_zone(vane1_pos, 1)
	_make_placement_zone(vane2_pos, 2)
	_make_treasure_spot(treasure)

func _make_placement_zone(pos: Vector2, vane_idx: int) -> void:
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
	
	# 微弱标记（小光点替代风向标）
	var marker := Polygon2D.new()
	marker.name = "GlowRing"
	var gp := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		gp.append(Vector2(cos(a) * 14, sin(a) * 14))
	marker.polygon = gp
	marker.color = Color("#ff6644", 0.0)
	zone.add_child(marker)

# ══════════════════════════════════════════════════════════════
#  出生点激光聚焦台
# ══════════════════════════════════════════════════════════════

func _make_laser_focus_puzzle(state: Dictionary) -> void:
	# 如果已完成则不创建
	if state.get("completed_levels", []).has("laser_focus"):
		return
	_laser_focus_puzzle = LASER_FOCUS_SCRIPT.new() as Area2D
	_laser_focus_puzzle.call("restore_installation_state", state)
	_laser_focus_puzzle.position = Vector2(3900, 3168)  # 出生点右侧空地，避开广场和记忆长椅
	_laser_focus_puzzle.set_meta("kind", "puzzle")
	_laser_focus_puzzle.set_meta("id", "laser_focus")
	add_child(_laser_focus_puzzle)
	if _laser_focus_puzzle.has_signal("puzzle_completed"):
		_laser_focus_puzzle.puzzle_completed.connect(func(reward: String): _on_puzzle_completed("laser_focus", reward))
	if _laser_focus_puzzle.has_signal("hint_updated"):
		_laser_focus_puzzle.hint_updated.connect(func(txt: String): hint_updated.emit(txt))
	interactables.append(_laser_focus_puzzle)
	puzzle_nodes["laser_focus"] = _laser_focus_puzzle

# ══════════════════════════════════════════════════════════════
#  右边界：隐形墙 + 远处道路景观
#  - 玩家在 x > RIGHT_BOUNDARY_X 时被推开
#  - 远处贴一段 distant_road.png 让人觉得远方有路
# ══════════════════════════════════════════════════════════════
const RIGHT_BOUNDARY_X: float = GameData.WORLD_SIZE.x - 40.0
const DISTANT_ROAD_TEX := preload("res://assets/environment/generated/distant_road.png")

func _make_right_world_boundary() -> void:
	# ── 1. 隐形墙：阻止玩家向右走出地图 ──
	var wall := StaticBody2D.new()
	wall.name = "RightBoundary"
	wall.position = Vector2(RIGHT_BOUNDARY_X, GROUND_Y_PX - 200)
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cshape := CollisionShape2D.new()
	var crect := RectangleShape2D.new()
	crect.size = Vector2(40.0, 800.0)  # 厚度40px，足够高的墙
	cshape.shape = crect
	wall.add_child(cshape)
	add_child(wall)

	# 右边界不再贴 distant_road，避免右侧出现多余贴图

# ══════════════════════════════════════════════════════════════
#  随机空中飞鸟
#  鸟的帧索引说明（来自 spritesheet 切图）：
#   BIRD_FLY_FRAMES  = [0,1,2]  ss_fly_a, ss_fly_b, ss_flap（飞行三帧）
#   BIRD_REST_FRAMES = [3,4,5]  ss_stand, ss_eat, ss_squat（休息三帧）
#  飞行方向：确定后不反复切换，仅靠 flip_h 镜像
#  拉屎：每只鸟随机20-40秒掉落一次白色水滴，命中玩家则眩晕0.5秒
# ══════════════════════════════════════════════════════════════

# 飞行帧：4帧翅膀扇动动画，均朝右，向左飞时 flip_h=true
const BIRD_FLY_PATHS: Array[String] = [
	"res://assets/characters/birds/bird_new_fly_1.png",
	"res://assets/characters/birds/bird_new_fly_2.png",
	"res://assets/characters/birds/bird_new_fly_3.png",
	"res://assets/characters/birds/bird_new_fly_4.png",
]
# 休息帧：站立 + 低头啄食（均朝右，flip_h向左）
const BIRD_REST_PATHS: Array[String] = [
	"res://assets/characters/birds/bird_new_stand.png",
	"res://assets/characters/birds/bird_new_eat.png",
]
const BIRD_COUNT: int = 5
const BIRD_SIZE: float = 32.0
const BIRD_FLY_SPEED_MIN: float = 65.0
const BIRD_FLY_SPEED_MAX: float = 125.0
const BIRD_FLAP_FPS: float = 7.0
const BIRD_REST_CHANCE: float = 0.18       # 每秒进入休息的概率
const BIRD_REST_DURATION_MIN: float = 3.0
const BIRD_REST_DURATION_MAX: float = 9.0
const BIRD_POOP_INTERVAL_MIN: float = 20.0  # 拉屎最短间隔（秒）
const BIRD_POOP_INTERVAL_MAX: float = 40.0

var _birds: Array = []
var _bird_fly_tex: Array[Texture2D] = []
var animals: Array = []  # 狗猫：{node, sprite, is_dog, frames, state, dir, speed, ...}
var _bird_rest_tex: Array[Texture2D] = []
var _bird_poop_tex: Texture2D = null       # 鸟屎水滴贴图
# 活跃鸟屎：{sprite, vy}
var _poops: Array = []

func _make_flying_birds() -> void:
	# 预加载飞行帧
	for path in BIRD_FLY_PATHS:
		var tex := load(path) as Texture2D
		if tex != null:
			_bird_fly_tex.append(tex)
		else:
			push_warning("无法加载鸟飞行帧: %s" % path)
	# 预加载休息帧
	for path in BIRD_REST_PATHS:
		var tex := load(path) as Texture2D
		if tex != null:
			_bird_rest_tex.append(tex)
		else:
			push_warning("无法加载鸟休息帧: %s" % path)
	# 预加载鸟屎贴图
	_bird_poop_tex = load("res://assets/characters/birds/bird_poop.png") as Texture2D

	if _bird_fly_tex.size() < 2 or _bird_rest_tex.size() < 2:
		push_warning("鸟帧不足，跳过生成")
		return

	for i in range(BIRD_COUNT):
		var bird := _create_bird()
		var sx: float = randf_range(600.0, 10200.0)
		var sy: float = randf_range(2680.0, 3080.0)
		bird["sprite"].position = Vector2(sx, sy)
		# 随机初始飞行方向（确定后不再随机切换）
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		bird["vx"] = dir * randf_range(BIRD_FLY_SPEED_MIN, BIRD_FLY_SPEED_MAX)
		bird["state"] = "flying"
		bird["fly_frame"] = 0
		bird["anim_timer"] = 0.0
		bird["rest_timer"] = 0.0
		bird["poop_timer"] = randf_range(BIRD_POOP_INTERVAL_MIN, BIRD_POOP_INTERVAL_MAX)
		bird["phase"] = randf_range(0.0, TAU)
		_bird_set_fly_frame(bird, 0)
		_bird_apply_dir(bird)
		add_child(bird["sprite"])
		_birds.append(bird)

func _create_bird() -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = _bird_fly_tex[0]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 7
	sprite.scale = Vector2.ONE * (BIRD_SIZE / float(_bird_fly_tex[0].get_height()))
	sprite.centered = true

	# 为每只鸟创建一个 Area2D 交互感应圈（仅在 resting 时激活）
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 0  # 不与 tilemap/player 碰撞，只用于距离检测
	area.set_meta("kind", "bird")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 60.0
	shape.shape = circle
	area.add_child(shape)
	add_child(area)

	return {
		"sprite": sprite, "state": "flying",
		"vx": 0.0, "fly_frame": 0,
		"anim_timer": 0.0, "rest_timer": 0.0,
		"poop_timer": 25.0, "phase": 0.0,
		"area": area,
	}

## 仅根据 vx 设置 flip_h，不改变 vx 本身（保持方向固定）
## 所有帧（fly/rest）原始朝右 → vx<0（向左）时 flip_h=true
func _bird_apply_dir(bird: Dictionary) -> void:
	var s: Sprite2D = bird["sprite"]
	s.flip_h = (bird["vx"] < 0.0)

func _bird_set_fly_frame(bird: Dictionary, idx: int) -> void:
	bird["fly_frame"] = idx
	var s := bird["sprite"] as Sprite2D
	if idx < _bird_fly_tex.size():
		s.texture = _bird_fly_tex[idx]
	# 每次换帧后重新应用方向镜像，防止纹理切换重置 flip_h
	s.flip_h = (bird["vx"] < 0.0)

func _bird_set_rest_frame(bird: Dictionary, idx: int) -> void:
	var s := bird["sprite"] as Sprite2D
	if idx < _bird_rest_tex.size():
		s.texture = _bird_rest_tex[idx]
	# 休息帧也跟飞行方向一致（vx 决定朝向，不随机翻转）
	s.flip_h = (bird["vx"] < 0.0)

func _update_birds(delta: float) -> void:
	# 更新鸟
	for bird in _birds:
		match bird["state"]:
			"flying":  _update_bird_flying(bird, delta)
			"resting": _update_bird_resting(bird, delta)
		# 同步 Area2D 位置跟 sprite
		if bird.has("area") and is_instance_valid(bird["area"]):
			(bird["area"] as Area2D).global_position = (bird["sprite"] as Sprite2D).global_position
			# 只有停歇时才开放交互感应
			(bird["area"] as Area2D).monitoring = (bird["state"] == "resting")
	# 更新活跃鸟屎
	_update_poops(delta)

## 返回玩家附近最近的正在休息的鸟（用于交互提示）
func nearest_resting_bird(point: Vector2, max_dist: float = 90.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = max_dist
	for bird in _birds:
		if bird["state"] != "resting":
			continue
		var d: float = (bird["sprite"] as Sprite2D).global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = bird
	return best

## 按世界坐标点击小鸟（鼠标点击）：在指定位置附近找到任意状态的鸟吓飞它
func scare_bird_at_world_pos(world_pos: Vector2, max_dist: float = 70.0) -> bool:
	var best: Dictionary = {}
	var best_d: float = max_dist
	for bird in _birds:
		var d: float = (bird["sprite"] as Sprite2D).global_position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = bird
	if best.is_empty():
		return false
	if best["state"] == "flying":
		return false  # 飞行中的不需要处理
	AudioManager.play_sfx("bird_chirp")
	best["state"] = "flying"
	var s: Sprite2D = best["sprite"]
	s.position.y -= 50.0
	var player := _get_player_node()
	if player != null:
		best["vx"] = -sign(player.global_position.x - s.position.x) * randf_range(BIRD_FLY_SPEED_MIN, BIRD_FLY_SPEED_MAX)
	best["fly_frame"] = 0
	best["anim_timer"] = 0.0
	_bird_set_fly_frame(best, 0)
	_bird_apply_dir(best)
	return true

## 按E吓飞最近的休息鸟：播放鸟叫 + 立即飞走
func scare_nearest_bird(point: Vector2) -> bool:
	var bird: Dictionary = nearest_resting_bird(point)
	if bird.is_empty():
		return false
	AudioManager.play_sfx("bird_chirp")
	# 立即进入飞行状态，飞离玩家方向
	bird["state"] = "flying"
	var s: Sprite2D = bird["sprite"]
	s.position.y -= 50.0
	# 飞行方向：远离玩家
	var player := _get_player_node()
	if player != null:
		bird["vx"] = -sign(player.global_position.x - s.position.x) * randf_range(BIRD_FLY_SPEED_MIN, BIRD_FLY_SPEED_MAX)
	bird["fly_frame"] = 0
	bird["anim_timer"] = 0.0
	_bird_set_fly_frame(bird, 0)
	_bird_apply_dir(bird)
	return true

func _update_bird_flying(bird: Dictionary, delta: float) -> void:
	var s: Sprite2D = bird["sprite"]
	# 水平移动（方向固定，不反转）
	s.position.x += bird["vx"] * delta
	# 轻微垂直正弦起伏（相位固定，避免左右晃动感）
	bird["phase"] += delta * 1.8
	s.position.y += sin(bird["phase"]) * 0.4

	# 出界：回绕到另一侧（不调头，保持同方向）
	if s.position.x < 100.0:
		s.position.x = 10700.0
	elif s.position.x > 10800.0:
		s.position.x = 200.0

	# 翅膀拍动动画
	bird["anim_timer"] += delta
	if bird["anim_timer"] >= 1.0 / BIRD_FLAP_FPS:
		bird["anim_timer"] = 0.0
		_bird_set_fly_frame(bird, (bird["fly_frame"] + 1) % _bird_fly_tex.size())

	# 拉屎计时（只在飞行时）
	bird["poop_timer"] -= delta
	if bird["poop_timer"] <= 0.0:
		bird["poop_timer"] = randf_range(BIRD_POOP_INTERVAL_MIN, BIRD_POOP_INTERVAL_MAX)
		_spawn_poop(s.position)

	# 随机进入休息
	if randf() < BIRD_REST_CHANCE * delta:
		_enter_rest(bird)

func _enter_rest(bird: Dictionary) -> void:
	bird["state"] = "resting"
	bird["rest_timer"] = randf_range(BIRD_REST_DURATION_MIN, BIRD_REST_DURATION_MAX)
	bird["anim_timer"] = 0.0
	var s: Sprite2D = bird["sprite"]
	s.position.y = GameData.PLAYER_START.y - 18.0
	# 随机选休息帧（站立/吃东西/蹲伏）
	var ridx: int = randi() % _bird_rest_tex.size()
	_bird_set_rest_frame(bird, ridx)
	# 朝向与飞行方向一致（vx 决定），不随机

func _update_bird_resting(bird: Dictionary, delta: float) -> void:
	bird["rest_timer"] -= delta
	# 换帧：每2秒换一次休息姿势（吃东西/站立/蹲伏循环）
	bird["anim_timer"] += delta
	if bird["anim_timer"] >= 2.0:
		bird["anim_timer"] = 0.0
		var ridx: int = randi() % _bird_rest_tex.size()
		_bird_set_rest_frame(bird, ridx)

	if bird["rest_timer"] <= 0.0:
		# 飞起来，保持原 vx 方向
		bird["state"] = "flying"
		var s: Sprite2D = bird["sprite"]
		s.position.y -= 45.0
		bird["fly_frame"] = 0
		bird["anim_timer"] = 0.0
		_bird_set_fly_frame(bird, 0)
		_bird_apply_dir(bird)

# ──────────────────────────────────────────────
#  鸟拉屎系统
# ──────────────────────────────────────────────
func _spawn_poop(from_pos: Vector2) -> void:
	if _bird_poop_tex == null:
		return
	var ps := Sprite2D.new()
	ps.texture = _bird_poop_tex
	ps.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ps.z_index = 8
	ps.scale = Vector2.ONE * 2.0
	ps.centered = true
	ps.position = from_pos + Vector2(0, 10)
	add_child(ps)
	_poops.append({"sprite": ps, "vy": 80.0})

func _update_poops(delta: float) -> void:
	var to_remove: Array = []
	for poop in _poops:
		var ps: Sprite2D = poop["sprite"]
		poop["vy"] = minf(poop["vy"] + 300.0 * delta, 500.0)  # 加速落下
		ps.position.y += poop["vy"] * delta

		# 检测命中玩家
		var player_node := _get_player_node()
		if player_node != null:
			var dist: float = ps.position.distance_to(player_node.global_position)
			if dist < 28.0:
				to_remove.append(poop)
				_on_poop_hit_player(player_node, ps.position)
				continue

		# 落到地面以下则销毁
		if ps.position.y > GROUND_Y_PX + 40.0:
			to_remove.append(poop)

	for poop in to_remove:
		if poop in _poops:
			_poops.erase(poop)
		var ps: Sprite2D = poop["sprite"]
		if is_instance_valid(ps):
			ps.queue_free()

func _get_player_node() -> CharacterBody2D:
	# 从场景树中找到玩家节点
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as CharacterBody2D
	return null

func _on_poop_hit_player(player: CharacterBody2D, hit_pos: Vector2) -> void:
	# 通知 main.gd 处理眩晕效果
	var main_node := get_tree().get_first_node_in_group("main")
	if main_node != null and main_node.has_method("trigger_poop_stun"):
		main_node.trigger_poop_stun(player)



# ══════════════════════════════════════════════════════════════
#  草丛隐藏颜色线索（舞蹈谜题答案：自闭模式+E才能拨开/收回）
#
#  设计：
#  · 7个草丛按地图从左到右散布，玩家后方（z_index低）
#  · 正常模式：只是背景灌木，无法交互
#  · 自闭模式：靠近时显示"按E拨开"提示；再按E收回
#  · 拨开后：草丛分成左右两半散开，露出后面彩色方块
#  · 颜色顺序：从左到右第i号草丛 → DANCE_ANSWER_SEQ[i] 对应颜色
#  · 每个草丛各自独立开/关，互不影响
# ══════════════════════════════════════════════════════════════
const DANCE_BTN_COLORS: Array = [
	Color("#ff7755"),  # 0: 向前走 (橙红)
	Color("#55cc55"),  # 1: 向前跳 (绿)
	Color("#5588ff"),  # 2: 向后跳 (蓝)
	Color("#aacc44"),  # 3: 向后走 (黄绿)
	Color("#ffaa22"),  # 4: 向前大跳 (橙黄)
	Color("#aa44ff"),  # 5: 向后大跳 (紫)
]
# 正确答案序列（7步）→ 对应颜色索引
const DANCE_ANSWER_SEQ: Array[int] = [0, 1, 4, 2, 1, 3, 5]

# 7个草丛的 X 坐标（从左到右散布，选前面无遮挡的开阔地带，避开前景树和建筑）
# 前景树位置：800,1400,2100,2900,3800,4200,4700,5100,5500,5900,6400,7200,7600,8300,8900,9300...
# 建筑/谜题区：~3400(广场喷泉),5000(找不同),5800(油画),7800(灯板),9800(天文台)
const BUSH_CLUE_X_POSITIONS: Array[float] = [
	1800.0,   # 草丛1（避开1400前景树阴影，移到更空旷处）
	2600.0,   # 草丛2（避开2100树遮挡，颜色更清晰）
	3560.0,   # 草丛3（略右移，避开喷泉与前景树重叠）
	4480.0,   # 草丛4（向右移，减少前景遮挡）
	5360.0,   # 草丛5（微调到空档）
	6760.0,   # 草丛6（避开6400/7200两棵前景树中心区）
	8680.0,   # 草丛7（避开游乐园右侧密集前景树）
]

# 草丛数据：{area, bush_left, bush_right, color_block, opened: bool}
var _bush_clues: Array[Dictionary] = []

func _make_hidden_color_clues() -> void:
	_bush_clues.clear()
	var ground_y: float = float(GROUND_Y_PX)

	for i in range(DANCE_ANSWER_SEQ.size()):
		var cx: float = BUSH_CLUE_X_POSITIONS[i]
		var cy: float = ground_y

		var color_idx: int = DANCE_ANSWER_SEQ[i]
		var clue_color: Color = DANCE_BTN_COLORS[color_idx]

		# ── 颜色方块（默认隐藏，在草丛后方）──
		var block := ColorRect.new()
		block.position = Vector2(cx - 16.0, cy - 38.0)
		block.size = Vector2(32.0, 36.0)
		block.color = clue_color
		block.z_index = 2   # 在草丛后面
		block.visible = false
		add_child(block)

		# 序号标签（在颜色块上方）
		var num_lbl := Label.new()
		num_lbl.text = str(i + 1)
		num_lbl.position = Vector2(cx - 8.0, cy - 54.0)
		num_lbl.add_theme_font_size_override("font_size", 13)
		num_lbl.add_theme_color_override("font_color", clue_color.lightened(0.25))
		num_lbl.z_index = 3
		num_lbl.visible = false
		add_child(num_lbl)

		# ── 草丛左半（闭合时与右半合并覆盖颜色块）──
		var bl := _make_bush_half(cx, cy, -1)
		add_child(bl)

		# ── 草丛右半 ──
		var br := _make_bush_half(cx, cy, 1)
		add_child(br)

		# ── 交互感应区（Area2D，kind = "bush_clue"）──
		var area := Area2D.new()
		area.name = "BushClue_%d" % i
		area.position = Vector2(cx, cy - 20.0)
		area.collision_layer = 0
		area.collision_mask = 1
		area.set_meta("kind", "bush_clue")
		area.set_meta("bush_idx", i)
		var ashape := CollisionShape2D.new()
		var arect := RectangleShape2D.new()
		arect.size = Vector2(70.0, 50.0)
		ashape.shape = arect
		area.add_child(ashape)
		add_child(area)
		interactables.append(area)

		_bush_clues.append({
			"area": area,
			"bush_left": bl,
			"bush_right": br,
			"color_block": block,
			"num_label": num_lbl,
			"opened": false,
			"cx": cx,
			"cy": cy,
		})

## 生成草丛半边 Polygon2D（放置于世界坐标 cx,cy；side=-1左半，side=1右半）
## 顶点使用绝对世界坐标（poly.position 保持 Vector2.ZERO）
func _make_bush_half(cx: float, cy: float, side: int) -> Polygon2D:
	var poly := Polygon2D.new()
	# 使用相对于 (cx,cy) 的局部坐标，poly 本身 position=ZERO（顶点包含绝对坐标）
	# 草丛宽 ~36px（单侧），高 ~32px
	var bw := 36.0
	var bh := 32.0
	var pts := PackedVector2Array()

	# 底部中心
	pts.append(Vector2(cx, cy))

	# 向上绕半圆（每个半边 = 半圆）
	var steps := 10
	for j in range(steps + 1):
		var t: float = float(j) / float(steps)  # 0.0 ~ 1.0
		# side=-1：从 cx 到 cx-bw（左半圆，t从0到1对应角度0到PI）
		# side= 1：从 cx 到 cx+bw（右半圆，t从1到0对应角度PI到0）
		var ang: float
		if side == -1:
			ang = PI * t          # 0 → PI（顶点从右边跑到左边，形成左半圆）
		else:
			ang = PI * (1.0 - t)  # PI → 0（顶点从左边跑到右边，形成右半圆）
		var bump: float = 1.0 + 0.15 * sin(j * 1.9)  # 轮廓凸起扰动
		var px: float = cx + cos(ang) * bw
		var py: float = cy - abs(sin(ang)) * bh * bump
		pts.append(Vector2(px, py))

	# 底部中心（闭合）
	pts.append(Vector2(cx, cy))

	poly.polygon = pts
	poly.color = Color("#3a7828") if side == -1 else Color("#4a9034")
	poly.z_index = 6
	return poly

## 拨开/收回第 idx 号草丛（由 main.gd 调用）
func toggle_bush_clue(idx: int) -> void:
	if idx < 0 or idx >= _bush_clues.size():
		return
	var d: Dictionary = _bush_clues[idx]
	d["opened"] = not d["opened"]
	_apply_bush_state(d)

## 应用草丛开/关状态
func _apply_bush_state(d: Dictionary) -> void:
	var opened: bool = d["opened"]
	var bl: Polygon2D = d["bush_left"]
	var br: Polygon2D = d["bush_right"]
	var block: ColorRect = d["color_block"]
	var num_lbl: Label = d["num_label"]

	if opened:
		# 左半向左移20px，右半向右移20px → 呈现"拨开"效果
		bl.position = Vector2(-22.0, 0.0)
		br.position = Vector2(22.0, 0.0)
		block.visible = true
		num_lbl.visible = true
	else:
		bl.position = Vector2.ZERO
		br.position = Vector2.ZERO
		block.visible = false
		num_lbl.visible = false

## 兼容旧接口（reveal_hidden_clues 批量切换已废弃，保留存根避免调用报错）
func reveal_hidden_clues(_visible_flag: bool) -> void:
	pass  # 草丛现在各自独立，不再批量切换

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
	
	# 更新放置区发光
	_update_vane_glow(vane_idx)
	_update_laser_beam(vane_idx)
	AudioManager.play_sfx("laser_place")
	
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
	AudioManager.play_sfx("laser_rotate")
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
			AudioManager.play_sfx("laser_fire")
		# 命中提示音（叠加短音高），确保每次交汇都有反馈
		AudioManager.play_tone(660.0, 0.08)
		AudioManager.play_tone(880.0, 0.08)
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

# ── 更新放置区发光 ──
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

# ══════════════════════════════════════════════════════════════
#  地面动物（狗 & 猫）系统
#  各 3 只，在地面上来回走动，靠近玩家时播放叫声
# ══════════════════════════════════════════════════════════════
func _make_animals() -> void:
	# 运行时加载动物帧（.import 由 Godot 在首次打开项目时自动生成）
	_dog_frames.clear()
	_cat_frames.clear()
	for p in DOG_FRAME_PATHS:
		var t := load(p) as Texture2D
		if t != null:
			_dog_frames.append(t)
		else:
			push_warning("world.gd: 无法加载狗帧: " + p)
	for p in CAT_FRAME_PATHS:
		var t := load(p) as Texture2D
		if t != null:
			_cat_frames.append(t)
		else:
			push_warning("world.gd: 无法加载猫帧: " + p)
	if _dog_frames.size() < 6 or _cat_frames.size() < 6:
		push_warning("world.gd: 动物帧不足，跳过动物生成（请在 Godot 编辑器中打开项目以重新导入图片）")
		return
	animals.clear()
	for i in range(ANIMAL_COUNT):
		var is_dog: bool = (i % 2) == 0
		animals.append(_create_animal(is_dog, i))

func _create_animal(is_dog: bool, seed_idx: int) -> Dictionary:
	var frames: Array[Texture2D] = _dog_frames if is_dog else _cat_frames
	var root := Node2D.new()
	root.name = "Dog_%d" % seed_idx if is_dog else "Cat_%d" % seed_idx
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_idx * 7919 + 31
	var x: float = rng.randf_range(ANIMAL_SPAWN_MIN_X, ANIMAL_SPAWN_MAX_X)
	# 用 GROUND_Y_PX=3200 作为地面基准，与 NPC 一致（NPC 脚底也对齐 y=3200）
	var ground_y: float = float(GROUND_Y_PX)
	# 小动物整体降低贴地高度，防止显得过高
	root.position = Vector2(x, ground_y - 6.0)
	root.z_index = 50
	add_child(root)
	var sprite := Sprite2D.new()
	sprite.texture = frames[0]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	# 目标显示高度：约60px
	var target_height: float = 60.0
	var sc: float = target_height / float(frames[0].get_height())
	sprite.scale = Vector2(sc, sc)
	# centered=true：精灵中心在 position
	# 动物贴图脚底通常在纹理高度约85%处（有透明边距），
	# 所以往下推：让中心在 -target_height*(1 - 0.85) = -target_height*0.15 处
	# 即底部对齐地面：center_y = -(target_height - target_height*0.85) + target_height*0.5 * (1-0.15)
	# 简化：position.y = -(target_height * 0.82) 让底部在世界 ground_y
	# 让脚底更贴地：从0.82调整为0.86
	sprite.position = Vector2(0.0, -target_height * 0.86)
	root.add_child(sprite)
	var dir: int = [-1, 1][rng.randi() % 2]
	sprite.flip_h = (dir < 0)
	var speed: float = rng.randf_range(ANIMAL_MIN_SPEED, ANIMAL_MAX_SPEED)

	# ── 交互感应区（玩家靠近时显示提示，按E触发跟随）──
	var area := Area2D.new()
	area.name = "AnimalInteract"
	area.collision_layer = 0
	area.collision_mask = 1
	var ashape := CollisionShape2D.new()
	var acircle := CircleShape2D.new()
	acircle.radius = 55.0
	ashape.shape = acircle
	area.add_child(ashape)
	area.set_meta("kind", "animal")
	root.add_child(area)

	return {
		"node": root, "sprite": sprite, "is_dog": is_dog, "frames": frames,
		"state": "walking", "dir": dir, "speed": speed,
		"anim_t": 0.0, "anim_idx": 0,
		"bark_cd": rng.randf_range(2.0, ANIMAL_BARK_INTERVAL_MAX),
		"rest_t": 0.0, "rest_dur": 0.0, "rng": rng,
		"follow_timer": 0.0,   # >0 表示正在跟随玩家
		"area": area,          # 交互感应区引用
	}

func _update_animals(delta: float) -> void:
	if animals.size() == 0:
		return
	var player := _get_player()
	var player_pos: Vector2 = player.global_position if player else Vector2(-99999.0, 0.0)
	for a in animals:
		if not is_instance_valid(a["node"]):
			continue
		# ── 跟随倒计时 ──
		if a.get("follow_timer", 0.0) > 0.0:
			a["follow_timer"] -= delta
			_update_animal_following(a, delta, player_pos)
			if a["follow_timer"] <= 0.0:
				a["follow_timer"] = 0.0
				a["state"] = "walking"
			continue
		match a["state"]:
			"walking":  _update_animal_walking(a, delta, player_pos)
			"barking":  _update_animal_barking(a, delta, player_pos)
			"resting":  _update_animal_resting(a, delta, player_pos)

func _update_animal_walking(a: Dictionary, delta: float, player_pos: Vector2) -> void:
	var node: Node2D = a["node"]
	var sprite: Sprite2D = a["sprite"]
	node.position.x += a["dir"] * a["speed"] * delta
	# 碰到边界就转身
	if node.position.x < ANIMAL_SPAWN_MIN_X - 200:
		a["dir"] = 1; sprite.flip_h = false
	elif node.position.x > ANIMAL_SPAWN_MAX_X + 200:
		a["dir"] = -1; sprite.flip_h = true
	# 走路动画：循环帧 0-2（新6帧中前3帧是走路）
	a["anim_t"] += delta
	var walk_spd: float = 0.14
	while a["anim_t"] >= walk_spd:
		a["anim_t"] -= walk_spd
		a["anim_idx"] = (a["anim_idx"] + 1) % 3  # 只循环帧0/1/2（走路）
		sprite.texture = a["frames"][a["anim_idx"]]
	# 计时：到时间决定叫或休息
	a["bark_cd"] -= delta
	if a["bark_cd"] <= 0.0:
		var rng: RandomNumberGenerator = a["rng"]
		var frames: Array[Texture2D] = a["frames"]
		if rng.randf() < 0.35 and frames.size() >= 4:
			# 进入叫声状态，切到帧3（站立/坐 → 叫声姿势）
			a["state"] = "barking"
			a["anim_t"] = 0.0
			a["anim_idx"] = 3
			sprite.texture = frames[3]
			a["bark_cd"] = rng.randf_range(ANIMAL_BARK_INTERVAL_MIN, ANIMAL_BARK_INTERVAL_MAX)
		elif frames.size() >= 5:
			# 进入休息状态，切到帧4（嗅地/趴下）
			a["state"] = "resting"
			a["anim_t"] = 0.0
			a["anim_idx"] = 4
			sprite.texture = frames[4]
			a["rest_dur"] = rng.randf_range(1.5, 4.0)
			a["rest_t"] = 0.0
		else:
			a["bark_cd"] = rng.randf_range(ANIMAL_BARK_INTERVAL_MIN, ANIMAL_BARK_INTERVAL_MAX)

func _update_animal_barking(a: Dictionary, delta: float, player_pos: Vector2) -> void:
	# 第一帧：播放叫声音效（靠近玩家才能听见）
	if not a.get("_bark_played", false):
		var dist: float = a["node"].position.distance_to(player_pos)
		if dist < ANIMAL_HEAR_RADIUS:
			if a["is_dog"]:
				AudioManager.play_sfx("dog_bark")
			else:
				AudioManager.play_sfx("cat_meow")
		a["_bark_played"] = true
	# 叫声动画：帧3（站立/坐 → 叫声姿势）持续约0.7秒后回到走路
	a["anim_t"] += delta
	if a["anim_t"] >= 0.7:
		a["state"] = "walking"
		a["anim_t"] = 0.0
		a["anim_idx"] = 0
		a["sprite"].texture = a["frames"][0]
		a["_bark_played"] = false
		a["bark_cd"] = a["rng"].randf_range(ANIMAL_BARK_INTERVAL_MIN, ANIMAL_BARK_INTERVAL_MAX)

func _update_animal_resting(a: Dictionary, delta: float, _player_pos: Vector2) -> void:
	a["rest_t"] += delta
	var frames: Array[Texture2D] = a["frames"]
	# 0.8秒后切到帧5（卧趴/回头坐），如果有的话
	if a["rest_t"] > 0.8 and a["anim_idx"] == 4 and frames.size() >= 6:
		a["anim_idx"] = 5
		a["sprite"].texture = frames[5]
	if a["rest_t"] >= a["rest_dur"]:
		var rng: RandomNumberGenerator = a["rng"]
		if rng.randf() < 0.3:
			a["dir"] = -a["dir"]
			a["sprite"].flip_h = (a["dir"] < 0)
		a["state"] = "walking"
		a["rest_t"] = 0.0
		a["anim_t"] = 0.0
		a["anim_idx"] = 0
		a["sprite"].texture = frames[0]


# ═══════════════════════════════════════════════════════
#  动物跟随玩家（按E触发，持续10秒）
# ═══════════════════════════════════════════════════════

## 跟随时每帧更新（仅在地面上移动，跟随速度=普通速度*1.5）
func _update_animal_following(a: Dictionary, delta: float, player_pos: Vector2) -> void:
	var node: Node2D = a["node"]
	var sprite: Sprite2D = a["sprite"]
	var ground_y: float = float(GROUND_Y_PX)

	# 保持在地面（Y固定）
	node.position.y = ground_y

	var dx: float = player_pos.x - node.position.x
	var follow_speed: float = a["speed"] * 1.5

	# 靠近玩家时（距离<40）停下
	if absf(dx) < 40.0:
		# 播放走路帧0
		sprite.texture = a["frames"][0]
		return

	var move_dir: int = 1 if dx > 0 else -1
	node.position.x += move_dir * follow_speed * delta
	sprite.flip_h = (move_dir < 0)

	# 走路动画
	a["anim_t"] += delta
	while a["anim_t"] >= 0.12:
		a["anim_t"] -= 0.12
		a["anim_idx"] = (a["anim_idx"] + 1) % 3
		sprite.texture = a["frames"][a["anim_idx"]]


## 外部调用：玩家按E与动物互动（播放音效+显示爱心+启动跟随）
func interact_animal(a: Dictionary) -> void:
	if a.get("follow_timer", 0.0) > 0.0:
		# 已在跟随，延长时间
		a["follow_timer"] = 10.0
		return
	a["follow_timer"] = 10.0
	a["state"] = "following"

	# 播放触发音效
	if a["is_dog"]:
		AudioManager.play_sfx("dog_triggered")
	else:
		AudioManager.play_sfx("cat_triggered")

	# 显示爱心（漂浮消失动画）
	var heart := Label.new()
	heart.text = "❤"
	heart.add_theme_font_size_override("font_size", 28)
	heart.add_theme_color_override("font_color", Color("#ff6688"))
	heart.position = Vector2(-10, -80)
	a["node"].add_child(heart)
	var tw := create_tween()
	tw.tween_property(heart, "position:y", -120.0, 0.8)
	tw.parallel().tween_property(heart, "modulate:a", 0.0, 0.8)
	tw.tween_callback(heart.queue_free)


## 找最近的可交互动物（供 main.gd 调用）
func get_nearest_animal(world_pos: Vector2, max_dist: float = 60.0) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = max_dist
	for a in animals:
		if not is_instance_valid(a.get("node")):
			continue
		var d: float = (a["node"].global_position - world_pos).length()
		if d < best_dist:
			best_dist = d
			best = a
	return best
