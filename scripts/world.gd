extends Node2D
class_name MindscapeWorld

signal interactable_changed(node: Node)
signal hint_updated(text: String)  # 全局提示消息（显示在HUD）
signal puzzle_completed(level_id: String, reward: String)  # 转发自各关卡实例

var interactables: Array[Node2D] = []
var puzzle_nodes: Dictionary = {}
var anchor_nodes: Array = []
var collectible_nodes: Dictionary = {}
var parallax_layers: Array = []
var world_shift: Vector2 = Vector2.ZERO

# ── CanvasLayers (Z-ordering: -100 < 0 < 500 < 1000 < 1001) ──
var bg_canvas: CanvasLayer          # layer -100: sky gradient
var view_tint_canvas: CanvasLayer   # layer  500: view tint ColorRect (no shaders!)
var palette_overlay: ColorRect      # the tint itself, on view_tint_canvas
var view_overlay_canvas: CanvasLayer # layer 1000: blind cursor + echo ring
var monster_canvas: CanvasLayer     # layer 1001: monsters ALWAYS on top

# ── Blind mode state ──
var blind_cursor: Panel             # white dot tracking player
var cursor_pulse_time: float = 0.0
var current_palette_view: String = "normal"
var view_pulse_time: float = 0.0    # for breathing tint animations

func build(state: Dictionary) -> void:
	_make_background_canvas()
	_make_parallax_backgrounds()
	_make_tilemap_world()   # ← TileMapLayer 地形 + 装饰
	_make_regions_on_tilemap()
	_make_npcs()
	_make_puzzles(state)
	_make_collectibles(state)
	_make_monsters(state)
	_make_memory_anchors()

# ─── BACKGROUND CANVAS (fixes Control node jitter in Node2D) ───
# CanvasLayer hierarchy (render order = low → high):
#   -100  bg_canvas              sky gradient
#      0  Node2D children        world terrain, NPCs, interactables
#    500  view_tint_canvas       view tint ColorRect (no shaders, pure ColorRect)
#   1000  view_overlay_canvas   blind cursor + echo ring
#   1001  monster_canvas        monsters always visible on top
func _make_background_canvas() -> void:
	# ── Layer -100: Sky + Gradient ──
	bg_canvas = CanvasLayer.new()
	bg_canvas.name = "BackgroundCanvas"
	bg_canvas.layer = -100
	bg_canvas.follow_viewport_enabled = true
	add_child(bg_canvas)
	
	var sky := ColorRect.new()
	sky.name = "Sky"
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.color = Color("#e8f0f8")
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_canvas.add_child(sky)
	
	var grad := ColorRect.new()
	grad.name = "SkyGradient"
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(0.65, 0.78, 0.95, 1.0);
uniform vec4 bot_color : source_color = vec4(0.98, 0.94, 0.82, 1.0);

void fragment() {
	float t = UV.y;
	COLOR = mix(bot_color, top_color, smoothstep(0.0, 1.0, t));
}
"""
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("top_color", Color("#7baed4"))
	shader_mat.set_shader_parameter("bot_color", Color("#fef5e7"))
	grad.material = shader_mat
	bg_canvas.add_child(grad)
	
	# ── Layer 500: View Tint (replaces ALL shaders — GL Compat safe!) ──
	view_tint_canvas = CanvasLayer.new()
	view_tint_canvas.name = "ViewTintCanvas"
	view_tint_canvas.layer = 500
	view_tint_canvas.follow_viewport_enabled = true
	add_child(view_tint_canvas)
	
	palette_overlay = ColorRect.new()
	palette_overlay.name = "ViewTint"
	palette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_overlay.color = Color(1.0, 0.9, 0.75, 0.08)  # normal warm tint
	view_tint_canvas.add_child(palette_overlay)
	
	# ── Layer 1000: Blind cursor + Echo ring ──
	view_overlay_canvas = CanvasLayer.new()
	view_overlay_canvas.name = "ViewOverlayCanvas"
	view_overlay_canvas.layer = 1000
	view_overlay_canvas.follow_viewport_enabled = true
	add_child(view_overlay_canvas)
	
	# Blind cursor — white dot on view_overlay_canvas (visible only in blind mode)
	blind_cursor = Panel.new()
	blind_cursor.name = "BlindCursor"
	blind_cursor.size = Vector2(12, 12)
	blind_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_cursor.visible = false
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color.WHITE
	cs.set_corner_radius_all(6)
	blind_cursor.add_theme_stylebox_override("panel", cs)
	view_overlay_canvas.add_child(blind_cursor)
	
	# ── Layer 1001: Monsters (always on top of tints) ──
	monster_canvas = CanvasLayer.new()
	monster_canvas.name = "MonsterCanvas"
	monster_canvas.layer = 1001
	monster_canvas.follow_viewport_enabled = true
	add_child(monster_canvas)

# ─── PARALLAX LAYERS ────────────────────────────────
func _make_parallax_backgrounds() -> void:
	# Layer 0: Distant mountains (slowest parallax)
	_add_parallax_layer(0.05, _draw_distant_mountains)
	# Layer 1: Mid-ground hills
	_add_parallax_layer(0.15, _draw_mid_hills)
	# Layer 2: Clouds
	_add_parallax_layer(0.08, _draw_clouds)
	# Layer 3: Trees / foliage silhouettes
	_add_parallax_layer(0.3, _draw_trees)

func _add_parallax_layer(parallax_factor: float, draw_func: Callable) -> void:
	var container := Node2D.new()
	container.name = "Parallax_%.2f" % parallax_factor
	container.z_index = int(-80 + parallax_factor * 30)
	add_child(container)
	draw_func.call(container)
	parallax_layers.append({"node": container, "factor": parallax_factor})

func _draw_distant_mountains(container: Node2D) -> void:
	var colors: Array = [Color("#c8dae8"), Color("#b0c8da"), Color("#a0bcd0"), Color("#8eaec4")]
	for i in range(6):
		var mountain := Polygon2D.new()
		var x: float = i * 2100.0 - 400.0
		var h: float = 450.0 + (i % 3) * 180.0
		var w: float = 1600.0 + (i % 2) * 400.0
		mountain.polygon = PackedVector2Array([
			Vector2(x, 3400.0),
			Vector2(x + w * 0.3, 3400.0 - h * 0.7),
			Vector2(x + w * 0.5, 3400.0 - h),
			Vector2(x + w * 0.7, 3400.0 - h * 0.65),
			Vector2(x + w, 3400.0),
		])
		mountain.color = colors[i % colors.size()]
		mountain.modulate.a = 0.55
		container.add_child(mountain)

func _draw_mid_hills(container: Node2D) -> void:
	for i in range(8):
		var hill := Polygon2D.new()
		var x: float = i * 1500.0 - 300.0
		hill.polygon = PackedVector2Array([
			Vector2(x, 3400.0),
			Vector2(x + 400.0, 3300.0 - (i % 3) * 100.0),
			Vector2(x + 800.0, 3280.0 - (i % 4) * 80.0),
			Vector2(x + 1200.0, 3400.0),
		])
		hill.color = Color("#c4d8a4") if i % 2 == 0 else Color("#b8cc98")
		hill.modulate.a = 0.45
		container.add_child(hill)

func _draw_clouds(container: Node2D) -> void:
	for i in range(12):
		var cloud := Polygon2D.new()
		var cx: float = i * 1050.0 + sin(i * 1.7) * 300.0
		var cy: float = 400.0 + cos(i * 2.1) * 200.0
		var pts := PackedVector2Array()
		for j in range(20):
			var a: float = TAU * j / 20.0
			var rx: float = 80.0 + sin(j * 3.0) * 30.0
			var ry: float = 28.0 + cos(j * 5.0) * 12.0
			pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
		cloud.polygon = pts
		cloud.color = Color.WHITE
		cloud.modulate.a = 0.35 + (i % 3) * 0.1
		container.add_child(cloud)

func _draw_trees(container: Node2D) -> void:
	for i in range(20):
		var tree := Polygon2D.new()
		var tx: float = i * 620.0 + (i % 5) * 80.0
		var ty: float = 3250.0 - (i % 3) * 40.0
		var th: float = 180.0 + (i % 4) * 60.0
		# Tree trunk
		tree.polygon = PackedVector2Array([
			Vector2(tx - 8, ty),
			Vector2(tx + 8, ty),
			Vector2(tx + 6, ty - th * 0.6),
			Vector2(tx - 6, ty - th * 0.6),
		])
		tree.color = Color("#6b4c3b")
		container.add_child(tree)
		# Tree canopy
		var canopy := Polygon2D.new()
		var cp := PackedVector2Array()
		for j in range(16):
			var a: float = TAU * j / 16.0
			cp.append(Vector2(tx + cos(a) * 45.0, ty - th * 0.55 + sin(a) * 55.0))
		canopy.polygon = cp
		canopy.color = Color("#5a8f4a") if i % 3 == 0 else Color("#6d9f58")
		canopy.modulate.a = 0.7
		container.add_child(canopy)

# ════════════════════════════════════════════════════════════
#  MAP SOURCE — 直接加载用户在编辑器里手工搭好的 map/Map.tscn
#  （包含 7 层 TileMapLayer: New_layer_0, Water_1, Bridge_2,
#    Ground_3, Pickups_4, Blocks_5, Background_6）
#  瓦片尺寸 16x16，碰撞层 1，玩家 mask 匹配。
# ════════════════════════════════════════════════════════════
const TILE_SIZE := 16
# 出生点/传送门/区域标签等世界坐标仍按像素单位组织（瓦片×16）
const GROUND_Y_PX := 200 * TILE_SIZE  # 3200，与新瓦片地面行匹配
const UG_GROUND_Y_PX := 269 * TILE_SIZE  # 地下行

var _map_root: Node2D  # 持有加载的 Map.tscn 实例

func _make_tilemap_world() -> void:
	# 加载用户在编辑器里搭好的 Map 场景
	var map_scene: PackedScene = load("res://map/Map.tscn") as PackedScene
	if map_scene == null:
		push_error("Failed to load res://map/Map.tscn")
		return
	_map_root = map_scene.instantiate() as Node2D
	if _map_root == null:
		push_error("Map.tscn root is not a Node2D")
		return
	# Map 整体作为世界的"地形根"放在 z=-30 下
	_map_root.name = "Map"
	_map_root.z_index = -30
	add_child(_map_root)

	# ── 地面行（行 11）和地下行（行 9）的两个传送门 ──
	var maze_entry := _add_marker(Vector2(5200, GROUND_Y_PX - 25), "↓ 黑暗迷宫入口 ↓", Color("#8040a0"), 52)
	maze_entry.set_meta("kind", "teleport")
	maze_entry.set_meta("target", Vector2(5200, UG_GROUND_Y_PX - 90))
	maze_entry.set_meta("requires_view", "blind")
	interactables.append(maze_entry)

	var maze_exit := _add_marker(Vector2(5200, UG_GROUND_Y_PX - 90), "↑ 返回地面 ↑", Color("#a0ffc0"), 44)
	maze_exit.set_meta("kind", "teleport")
	maze_exit.set_meta("target", Vector2(5200, GROUND_Y_PX - 25))
	interactables.append(maze_exit)

# ─── REGIONS / BUILDINGS ───────────────────────────
func _make_regions_on_tilemap() -> void:
	var gy: float = GROUND_Y_PX
	var ugy: float = UG_GROUND_Y_PX

	_label_region("左侧森林",   Vector2(700, 2950), Color("#5f8b5f"))
	_label_region("中央广场",   Vector2(3300, 2960), Color("#b5a05e"))
	_label_region("湖泊灯塔",   Vector2(4750, 2950), Color("#6eb8db"))
	_label_region("水坝工业区", Vector2(5950, 2950), Color("#7b9088"))
	_label_region("旧车站",     Vector2(7300, 2950), Color("#878792"))
	_label_region("游乐园",     Vector2(8850, 2950), Color("#e7a84c"))
	_label_region("天文台",     Vector2(10150, 2950), Color("#8fa9d7"))
	_label_region("地下迷宫",   Vector2(5200, 4080), Color("#645880"))

	# 关卡标记（球体 + 标签）
	_add_zone_marker(Vector2(400, gy),   "关卡1\n纹理墙",    Color("#e0a050"))
	_add_zone_marker(Vector2(1200, gy),  "关卡2\n找不同",    Color("#c080d0"))
	_add_zone_marker(Vector2(2000, 3100),"关卡3\n油画舞步",  Color("#d060a0"))
	_add_zone_marker(Vector2(8800, gy),  "关卡4\n灯板谜题",  Color("#ffaa30"))
	_add_zone_marker(Vector2(10500, gy), "关卡5\nNPC密码台", Color("#a080f0"))
	_add_zone_marker(Vector2(5200, ugy - 20), "关卡6\n黑暗迷宫", Color("#8040c0"))

	# 建筑物视觉（简化 ColorRect）
	_add_building_detail(Vector2(400, 3100),   Vector2(60, 140),  Color("#6a5545"), "纹理墙")
	_add_building_detail(Vector2(1200, 3080),  Vector2(100, 130), Color("#8a7060"), "密室")
	_add_building_detail(Vector2(2000, 3050),  Vector2(160, 150), Color("#9a8068"), "宴会厅")
	_add_building_detail(Vector2(3400, 3080),  Vector2(220, 100), Color("#d3ae76"), "中央广场")
	_add_building_detail(Vector2(4800, 2950),  Vector2(80, 320),  Color("#d7dee7"), "灯塔")
	_add_building_detail(Vector2(6000, 3080),  Vector2(240, 170), Color("#8ea7b1"), "水坝")
	_add_building_detail(Vector2(7500, 3080),  Vector2(550, 140), Color("#9b9080"), "旧车站")
	_add_building_detail(Vector2(10200, 3080), Vector2(240, 150), Color("#b7c8e8"), "天文台")

	# 灯塔光晕
	var glow := Polygon2D.new()
	var gp := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * i / 16.0
		gp.append(Vector2(cos(a) * 28.0, sin(a) * 28.0))
	glow.polygon = gp; glow.position = Vector2(4800, 2770)
	glow.color = Color("#ffe8a0"); glow.modulate.a = 0.5; glow.z_index = -1
	add_child(glow)

	# 天文台穹顶
	var dome := Polygon2D.new()
	var dp := PackedVector2Array()
	for i in range(32):
		var a: float = PI * i / 31.0
		dp.append(Vector2(cos(a) * 82.0, sin(a) * 50.0 - 72.0))
	dome.polygon = dp; dome.position = Vector2(10200, 2900)
	dome.color = Color("#8fa9d7"); dome.z_index = -1
	add_child(dome)

	# 摩天轮
	_draw_wheel(Vector2(9000, 3040))

	# 风向标
	_make_wind_vanes()

	# 宝箱
	_add_treasure_chest(GameData.LASER_SYSTEM["treasure_pos"])

# ── 区域标记（关卡位置指示器）──
func _add_zone_marker(pos: Vector2, text: String, color: Color) -> void:
	var marker := Area2D.new()
	marker.position = pos
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28
	shape.shape = circle
	marker.add_child(shape)
	
	var orb := Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(10):
		var a: float = TAU * i / 10.0
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

func _add_building_detail(pos: Vector2, size: Vector2, color: Color, label_text: String) -> void:
	var rect := ColorRect.new()
	rect.position = pos - size / 2.0
	rect.size = size
	rect.color = color
	rect.z_index = -10
	add_child(rect)
	
	# Roof highlight
	var roof := ColorRect.new()
	roof.position = pos - size / 2.0
	roof.size = Vector2(size.x, 8.0)
	roof.color = color.lightened(0.2)
	roof.z_index = -9
	add_child(roof)
	
	# Windows
	if size.x > 120:
		for w in range(int(size.x / 80.0)):
			var window := ColorRect.new()
			window.position = pos - size / 2.0 + Vector2(30.0 + w * 80.0, size.y * 0.3)
			window.size = Vector2(24, 30)
			window.color = Color("#fff8e8")
			window.modulate.a = 0.7
			window.z_index = -8
			add_child(window)
	
	var label := Label.new()
	label.text = label_text
	label.position = pos + Vector2(-size.x * 0.35, -size.y * 0.68)
	label.add_theme_font_size_override("font_size", 22)
	label.z_index = -7
	add_child(label)

# ─── WIND VANES + LASER SYSTEM ──────────────────
# 风向标1（左侧）+ 风向标2（右侧）
# 放入激光装置后发射光束，交叉点=宝藏位置
func _make_wind_vanes() -> void:
	var vane1 := _make_wind_vane(GameData.LASER_SYSTEM["wind_vane_1"]["pos"], "风向标1")
	vane1.set_meta("vane_id", 1)
	interactables.append(vane1)
	
	var vane2 := _make_wind_vane(GameData.LASER_SYSTEM["wind_vane_2"]["pos"], "风向标2")
	vane2.set_meta("vane_id", 2)
	interactables.append(vane2)

func _make_wind_vane(pos: Vector2, name_label: String) -> Area2D:
	var vane := Area2D.new()
	vane.name = name_label
	vane.position = pos
	
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 60)
	shape.shape = box
	vane.add_child(shape)
	
	var tower := ColorRect.new()
	tower.position = Vector2(-15, -40)
	tower.size = Vector2(30, 60)
	tower.color = Color("#8088a0")
	vane.add_child(tower)
	
	var blade := Polygon2D.new()
	var bp := PackedVector2Array([
		Vector2(0, -55), Vector2(6, -20), Vector2(0, -15),
		Vector2(-6, -20), Vector2(0, -55)
	])
	blade.polygon = bp
	blade.color = Color("#c0d0e0")
	vane.add_child(blade)
	
	var label := Label.new()
	label.text = "[ %s ]" % name_label
	label.position = Vector2(-32, -72)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#b0c0e0"))
	vane.add_child(label)
	
	var status := Label.new()
	status.name = "VaneStatus"
	status.text = "(空)"
	status.position = Vector2(-12, 10)
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color("#888888"))
	vane.add_child(status)
	
	return vane

func _add_treasure_chest(pos: Vector2) -> void:
	var chest := Area2D.new()
	chest.name = "TreasureChest"
	chest.position = pos
	
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(50, 36)
	shape.shape = box
	chest.add_child(shape)
	
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-25, -5), Vector2(25, -5), Vector2(22, 18), Vector2(-22, 18)
	])
	body.color = Color("#a07030")
	chest.add_child(body)
	
	var lid := Polygon2D.new()
	lid.polygon = PackedVector2Array([
		Vector2(-24, -5), Vector2(24, -5), Vector2(20, -16), Vector2(-20, -16)
	])
	lid.color = Color("#c08838")
	chest.add_child(lid)
	
	var lock := ColorRect.new()
	lock.position = Vector2(-6, 2)
	lock.size = Vector2(12, 10)
	lock.color = Color("#ffd700")
	lock.name = "Lock"
	chest.add_child(lock)
	
	var label := Label.new()
	label.text = "★ 时间胶囊宝箱 ★"
	label.position = Vector2(-52, -30)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#ffd700"))
	chest.add_child(label)
	
	var key_count := Label.new()
	key_count.name = "KeyCount"
	key_count.text = "(需要4把钥匙: 0/4)"
	key_count.position = Vector2(-50, 22)
	key_count.add_theme_font_size_override("font_size", 10)
	key_count.add_theme_color_override("font_color", Color("#ccaa66"))
	chest.add_child(key_count)
	
	chest.set_meta("kind", "treasure_chest")
	puzzle_nodes["treasure_chest"] = chest
	interactables.append(chest)

# ─── NPCs ──────────────────────────────────────────
func _make_npcs() -> void:
	for data in GameData.NPCS:
		var npc := MindscapeNPC.new()
		npc.setup(data)
		add_child(npc)
		interactables.append(npc)

# ─── PUZZLES (6大关卡) ──────────────────────────
func _make_puzzles(state: Dictionary) -> void:
	# 遍历设计文档中的6个关卡定义
	for level_data in GameData.LEVELS:
		var level_id: String = level_data["id"]
		var level_pos: Vector2 = level_data["pos"]
		var level_type: String = level_data["type"]
		var prereq: String = level_data.get("prereq", "")
		
		# 检查前置条件
		if prereq != "" and not state.get("completed_levels", []).has(prereq):
			continue
		# 检查是否已完成
		if state.get("completed_levels", []).has(level_id):
			continue
		
		# 根据类型创建对应的谜题实例
		var puzzle_instance := _create_puzzle_instance(level_type, level_id, level_data)
		if puzzle_instance != null:
			puzzle_instance.position = level_pos
			add_child(puzzle_instance)
			
			# 连接完成信号
			if puzzle_instance.has_signal("puzzle_completed"):
				puzzle_instance.puzzle_completed.connect(_on_puzzle_completed.bind(level_id))
			
			puzzle_nodes[level_id] = puzzle_instance
			interactables.append(puzzle_instance)

func _create_puzzle_instance(type: String, id: String, data: Dictionary) -> Node2D:
	match type:
		"texture_wall":
			var p := PuzzleTextureWall.new()
			if data.has("correct_sequence"):
				p.correct_sequence = data["correct_sequence"]
			return p
		"find_diff":
			return PuzzleFindDifference.new()
		"dance_sequence":
			return PuzzleBanquetPainting.new()
		"light_board":
			return PuzzleAmusementLights.new()
		"npc_cipher":
			return PuzzleNPCPassword.new()
		"audio_maze":
			return PuzzleDarkMaze.new()
		_:
			push_warning("Unknown puzzle type: %s" % type)
			return null

func _on_puzzle_completed(level_id: String, reward: String = "") -> void:
	# 记录关卡完成（由 main.gd 的 state 管理）
	print("Puzzle completed: %s (reward: %s)" % [level_id, reward])
	hint_updated.emit("✨ 关卡 '%s' 已完成！" % level_id)
	# 转发给主场景监听
	puzzle_completed.emit(level_id, reward)

# ─── COLLECTIBLES ──────────────────────────────────
func _make_collectibles(state: Dictionary) -> void:
	var collected: Array = state.get("collectibles", [])
	
	# All ground-level Y=3170 (just above surface).
	# IMPORTANT: collectibles are placed in GAPS between walkable platforms so they never appear "under" a platform.
	var placements: Array = []
	
	# Forest — platforms at [900-1280], [1450-1750]
	placements.append_array([
		{"i": 0, "pos": Vector2(300, 3170)},
		{"i": 1, "pos": Vector2(650, 3170)},
		{"i": 2, "pos": Vector2(1350, 3170)},   # gap 1280→1450
		{"i": 3, "pos": Vector2(1850, 3170)},
		{"i": 4, "pos": Vector2(2100, 3170)},
		{"i": 5, "pos": Vector2(2350, 3170)},
	])
	
	# Plaza — platform at [2600-2900], [3700-4000]; spawn buffer 3100-3600 kept clear-ish
	placements.append_array([
		{"i": 6, "pos": Vector2(2480, 3170)},    # gap 2400→2600
		{"i": 7, "pos": Vector2(2560, 3170)},
		{"i": 8, "pos": Vector2(3000, 3170)},    # gap 2900→3700 (left of spawn)
		{"i": 9, "pos": Vector2(3400, 3170)},
		{"i": 10, "pos": Vector2(3600, 3170)},
		{"i": 11, "pos": Vector2(4080, 3170)},    # gap 4000→4400
	])
	
	# Lighthouse — platform at [4700-5300]
	placements.append_array([
		{"i": 12, "pos": Vector2(4450, 3170)},    # gap 4400→4700
		{"i": 13, "pos": Vector2(4600, 3170)},
		{"i": 14, "pos": Vector2(5380, 3170)},    # gap 5300→5600
		{"i": 15, "pos": Vector2(5550, 3170)},
		{"i": 16, "pos": Vector2(5700, 3170)},
		{"i": 17, "pos": Vector2(5800, 3170)},
	])
	
	# Dam — platform at [6050-6650]
	placements.append_array([
		{"i": 18, "pos": Vector2(5750, 3170)},    # gap 5600→6050
		{"i": 19, "pos": Vector2(5900, 3170)},
		{"i": 20, "pos": Vector2(6000, 3170)},
		{"i": 21, "pos": Vector2(6700, 3170)},    # gap 6650→6800
		{"i": 22, "pos": Vector2(6760, 3170)},
	])
	
	# Station — platform at [7300-8100]
	placements.append_array([
		{"i": 23, "pos": Vector2(6900, 3170)},    # gap 6800→7300
		{"i": 24, "pos": Vector2(7050, 3170)},
		{"i": 25, "pos": Vector2(7200, 3170)},
		{"i": 26, "pos": Vector2(8200, 3170)},    # gap 8100→8500
		{"i": 27, "pos": Vector2(8350, 3170)},
		{"i": 28, "pos": Vector2(8460, 3170)},
	])
	
	# Park — platform at [8850-9450]
	placements.append_array([
		{"i": 29, "pos": Vector2(8580, 3170)},    # gap 8500→8850
		{"i": 30, "pos": Vector2(8750, 3170)},
		{"i": 31, "pos": Vector2(9500, 3170)},    # gap 9450→9800
		{"i": 32, "pos": Vector2(9600, 3170)},
		{"i": 33, "pos": Vector2(9700, 3170)},
		{"i": 34, "pos": Vector2(8560, 3170)},    # extra in left gap
	])
	
	# Observatory — platform at [10000-10600]
	placements.append_array([
		{"i": 35, "pos": Vector2(9850, 3170)},    # gap 9800→10000
		{"i": 36, "pos": Vector2(9950, 3170)},
		{"i": 37, "pos": Vector2(10700, 3170)},   # gap 10600→11200
		{"i": 38, "pos": Vector2(10900, 3170)},
	])
	
	# Underground — platforms at [4800-5120], [5400-5700], [5700-5960]
	placements.append_array([
		{"i": 39, "pos": Vector2(4700, 4150)},    # gap 4600→4800
		{"i": 40, "pos": Vector2(5200, 4150)},    # gap 5120→5400
		{"i": 41, "pos": Vector2(5320, 4150)},
		{"i": 42, "pos": Vector2(6100, 4150)},    # gap 5960→7200
		{"i": 43, "pos": Vector2(6350, 4150)},
		{"i": 44, "pos": Vector2(6600, 4150)},
		{"i": 45, "pos": Vector2(6900, 4150)},
	])
	
	for placement in placements:
		var i: int = placement["i"]
		var id := "collectible_%02d" % i
		if collected.has(id):
			continue
		var area := _add_marker(placement["pos"], "★ 纪念物", Color("#f9f4bf"), 28)
		area.set_meta("kind", "collectible")
		area.set_meta("id", id)
		collectible_nodes[id] = area
		interactables.append(area)

# ─── MEMORY ANCHORS ────────────────────────────────
func _make_memory_anchors() -> void:
	# All ground-level, placed in gaps between walkable platforms
	var anchor_positions := {
		"plaza": Vector2(3300, 3170),
		"forest": Vector2(800, 3170),
		"lighthouse": Vector2(4450, 3170),
		"dam": Vector2(5950, 3170),
		"station": Vector2(6950, 3170),
		"park": Vector2(8600, 3170),
		"observatory": Vector2(9850, 3170),
		"underground": Vector2(5350, 4150),
	}
	for key in GameData.REGIONS.keys():
		var pos: Vector2 = anchor_positions.get(key, Vector2(3000, 3170))
		var area := _add_marker(pos, "记忆长椅 休息/切换视角", Color("#bdf7ff"), 44)
		area.set_meta("kind", "anchor")
		area.set_meta("id", key)
		anchor_nodes.append(area)
		interactables.append(area)
	
	# ── Guidance trail: glowing dots from plaza → echo stone ──
	_add_guidance_trail()

# ─── GUIDANCE TRAIL ──────────────────────────────
func _add_guidance_trail() -> void:
	# Small glowing dots from plaza center to the echo stone, guiding new players
	var start_x := 3450.0
	var end_x := 4700.0
	var gy: float = 3170.0  # just above ground surface
	var count := 14
	for i in range(count):
		var t: float = float(i) / float(count - 1)
		var x := lerpf(start_x, end_x, t)
		var dot := Polygon2D.new()
		var dp := PackedVector2Array()
		for j in range(8):
			var a: float = TAU * j / 8.0
			dp.append(Vector2(cos(a), sin(a)) * 5.0)
		dot.polygon = dp
		dot.position = Vector2(x, gy)
		dot.color = Color("#ffe8a0")
		dot.modulate.a = 0.5 + 0.3 * sin(t * PI)
		dot.z_index = 2
		add_child(dot)

# ─── MARKERS ────────────────────────────────────────
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
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(12):
		var a: float = TAU * i / 12.0
		pts.append(Vector2(cos(a), sin(a)) * radius * 0.45)
	orb.polygon = pts
	orb.color = color
	area.add_child(orb)
	var particles := CPUParticles2D.new()
	particles.amount = 10
	particles.lifetime = 1.4
	particles.emitting = true
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.3
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 18.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.color = color
	area.add_child(particles)
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(-70, -58)
	label.add_theme_font_size_override("font_size", 16)
	area.add_child(label)
	area.add_to_group("interactable")
	return area

# ─── MONSTERS ──────────────────────────────────────
func _make_monsters(state: Dictionary) -> void:
	var completed: Array = state.get("completed_regions", [])
	var data: Array = [
		{"id": "noise_lighthouse", "type": "noise", "region": "lighthouse", "pos": Vector2(5350, 3170)},
		{"id": "mouth_station", "type": "silent_mouth", "region": "station", "pos": Vector2(8150, 3170)},
		{"id": "distractor_park", "type": "distractor", "region": "park", "pos": Vector2(9480, 3170)},
		{"id": "shadow_forest", "type": "shadow", "region": "forest", "pos": Vector2(1820, 3170)},
	]
	for item in data:
		if completed.has(item["region"]):
			continue
		var monster := MindscapeMonster.new()
		monster.setup(item["id"], item["type"], item["pos"])
		monster_canvas.add_child(monster)  # on layer 1001 — visible above blind black overlay

# ─── FERRIS WHEEL ──────────────────────────────────
func _draw_wheel(center: Vector2) -> void:
	var line := Line2D.new()
	line.width = 5
	line.default_color = Color("#e96d7c")
	line.z_index = -6
	for i in range(65):
		var a: float = TAU * i / 64.0
		line.add_point(center + Vector2(cos(a), sin(a)) * 185.0)
	add_child(line)
	for i in range(8):
		var spoke := Line2D.new()
		spoke.width = 3
		spoke.default_color = Color("#f1c46d")
		spoke.z_index = -6
		spoke.add_point(center)
		spoke.add_point(center + Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0)) * 185.0)
		add_child(spoke)
	
	# Hub
	var hub := Polygon2D.new()
	var hp := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * i / 16.0
		hp.append(Vector2(cos(a), sin(a)) * 20.0)
	hub.polygon = hp
	hub.position = center
	hub.color = Color("#f5c842")
	hub.z_index = -5
	add_child(hub)

# ─── LABELS ─────────────────────────────────────────
func _label_region(text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.modulate = color.darkened(0.25)
	label.add_theme_font_size_override("font_size", 36)
	label.z_index = -7
	add_child(label)

# ─── INTERACTION ────────────────────────────────────
func nearest_interactable(point: Vector2, max_distance: float = 110.0) -> Node2D:
	var best: Node2D = null
	var best_dist: float = max_distance
	var best_priority: int = -1  # higher = more important
	
	for node in interactables:
		if not is_instance_valid(node):
			continue
		var dist: float = point.distance_to(node.global_position)
		if dist > best_dist:
			continue
		
		var priority: int = 0
		match node.get_meta("kind", ""):
			"puzzle": priority = 4
			"npc": priority = 3
			"anchor": priority = 2
			"teleport": priority = 2
			"collectible": priority = 1
		
		# Prefer closer nodes; if very close (<5px diff), use priority
		if dist < best_dist - 5.0 or (abs(dist - best_dist) < 5.0 and priority > best_priority):
			best_dist = dist
			best = node
			best_priority = priority
	
	return best

func remove_interactable(node: Node) -> void:
	interactables.erase(node)
	if is_instance_valid(node):
		node.queue_free()

# ─── VIEW PALETTE (pure ColorRect tints — NO shaders, GL Compat safe!) ───
# All shader functions below this section are deprecated and will be removed.

func _process(delta: float) -> void:
	view_pulse_time += delta
	# Animate view tint breathing (subtle alpha pulse)
	_animate_view_tint()
	# Blind cursor tracking
	if current_palette_view == "blind" and blind_cursor.visible:
		_update_blind_cursor(delta)

func set_view_palette(view: String) -> void:
	if not is_instance_valid(palette_overlay):
		return
	current_palette_view = view
	view_pulse_time = 0.0
	
	# Clear any old shader material
	palette_overlay.material = null
	
	# ── Apply ColorRect tint per view ──
	match view:
		"blind":
			# PITCH BLACK overlay (at layer 500, world hidden; monsters at 1001 stay visible)
			palette_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
			palette_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
			blind_cursor.visible = true
			cursor_pulse_time = 0.0
		"deaf":
			# Complete desaturation + blue-grey tint + grain visible via vignette
			palette_overlay.color = Color(0.5, 0.65, 0.85, 0.52)
			palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			blind_cursor.visible = false
		"adhd":
			# High contrast bright gold tint + rapid pulse
			palette_overlay.color = Color(1.0, 0.95, 0.55, 0.10)
			palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			blind_cursor.visible = false
		"depression":
			# Heavy blue-grey oppression + dark vignette
			palette_overlay.color = Color(0.15, 0.25, 0.35, 0.48)
			palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			blind_cursor.visible = false
		_:
			# Normal: warm amber glow, almost transparent
			palette_overlay.color = Color(1.0, 0.9, 0.75, 0.08)
			palette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			blind_cursor.visible = false
	
	# Notify all monsters to update visibility for this view
	_notify_monsters_view_changed(view)

func get_current_view() -> String:
	return current_palette_view

# ─── KEY SYSTEM HELPERS ──────────────────────
func update_treasure_key_count(collected_keys: Array) -> void:
	var chest: Node = puzzle_nodes.get("treasure_chest")
	if not is_instance_valid(chest):
		return
	var key_label: Label = chest.get_node_or_null("KeyCount") as Label
	if key_label:
		key_label.text = "(需要4把钥匙: %d/4)" % collected_keys.size()
	var lock: ColorRect = chest.get_node_or_null("Lock") as ColorRect
	if lock:
		if collected_keys.size() >= 4:
			lock.color = Color("#00ff00")
		else:
			lock.color = Color("#ffd700")

func _animate_view_tint() -> void:
	if not is_instance_valid(palette_overlay) or current_palette_view == "blind":
		return
	var base := palette_overlay.color
	match current_palette_view:
		"normal":
			pass  # static warm tint
		"deaf":
			# Slow film-like flicker
			var flick := 1.0 + 0.020 * sin(view_pulse_time * 3.7)
			palette_overlay.color = Color(base.r, base.g, base.b, clampf(0.52 * flick, 0.48, 0.58))
		"adhd":
			# Rapid attention pulse
			var pulse := 1.0 + 0.025 * sin(view_pulse_time * 6.0)
			palette_overlay.color = Color(base.r, base.g, base.b, clampf(0.10 * pulse, 0.07, 0.14))
		"depression":
			# Slow heavy breathing
			var breathe := 1.0 + 0.030 * sin(view_pulse_time * 0.8)
			palette_overlay.color = Color(base.r, base.g, base.b, clampf(0.48 * breathe, 0.43, 0.53))

func _update_blind_cursor(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# Find player in scene
	var player: Node2D = null
	for node in get_tree().get_nodes_in_group("player"):
		player = node
		break
	if player == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var cam_pos := camera.global_position
	var p_pos := player.global_position
	var zoom := camera.zoom
	var screen_pos := (p_pos - cam_pos) / zoom + vs / 2.0
	blind_cursor.position = screen_pos - blind_cursor.size / 2.0
	# Breathing pulse animation
	cursor_pulse_time += delta
	var alpha: float = 0.7 + 0.3 * sin(cursor_pulse_time * 2.5)
	var st := blind_cursor.get_theme_stylebox("panel") as StyleBoxFlat
	if st != null:
		st.bg_color = Color(1.0, 1.0, 1.0, alpha)

func trigger_echo_pulse(_screen_center: Vector2) -> void:
	if current_palette_view != "blind" or not is_instance_valid(view_overlay_canvas):
		return
	
	var screen_size := get_viewport().get_visible_rect().size
	var start_size: float = 12.0
	var end_size: float = minf(screen_size.x, screen_size.y) * 1.5
	
	var ring := Panel.new()
	ring.name = "EchoRing"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color.TRANSPARENT
	ring_style.border_width_left = 3
	ring_style.border_width_right = 3
	ring_style.border_width_top = 3
	ring_style.border_width_bottom = 3
	ring_style.border_color = Color(1.0, 1.0, 1.0, 0.9)
	ring.add_theme_stylebox_override("panel", ring_style)
	ring.size = Vector2(start_size, start_size)
	var cx: float = screen_size.x * 0.5
	var cy: float = screen_size.y * 0.5
	ring.position = Vector2(cx - start_size/2.0, cy - start_size/2.0)
	view_overlay_canvas.add_child(ring)
	
	# Animate expansion using tween — bind captures the ring ref
	var tween := create_tween()
	tween.set_parallel(true)
	
	# bind(ring, start_size, end_size) passes extra args after tween's val
	tween.tween_method(
		_echo_ring_step.bind(ring, start_size, end_size),
		0.0, 1.0, 0.55
	)
	tween.tween_callback(_echo_ring_done.bind(ring))

func _echo_ring_step(val: float, ring: Panel, start_sz: float, end_sz: float) -> void:
	if not is_instance_valid(ring):
		return
	var sz := lerpf(start_sz, end_sz, val)
	ring.size = Vector2(sz, sz)
	var vs := get_viewport().get_visible_rect().size
	ring.position = Vector2(vs.x/2.0 - sz/2.0, vs.y/2.0 - sz/2.0)
	var st := ring.get_theme_stylebox("panel") as StyleBoxFlat
	if st != null:
		st.set_corner_radius_all(int(sz / 2.0))
		st.border_color = Color(1.0, 1.0, 1.0, lerpf(0.9, 0.0, val))

func _echo_ring_done(ring: Panel) -> void:
	if is_instance_valid(ring):
		ring.queue_free()

func _notify_monsters_view_changed(view: String) -> void:
	for node in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(node) and node.has_method("on_view_changed"):
			node.on_view_changed(view)

# No per-frame position update needed - they move naturally with the camera.
