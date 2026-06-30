extends Node2D
class_name MindscapeWorld

signal interactable_changed(node: Node)
signal hint_updated(text: String)  # 全局提示消息（显示在HUD）

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
	_make_land()
	_make_regions()
	_make_decorations()
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

# ─── LAND / TERRAIN ───────────────────────────────
# 基于设计文档的完整地图布局（匹配tilemap参考图）：
#   [左侧森林] → [出生点/中央广场] → [灯塔] → [水坝] → [车站] → [游乐园] → [天文台]
#   [地下迷宫] 在地下层 (y > 4200)
#
# 地面高度统一为 Y=3200，地下为 Y=4300
const GROUND_Y: float = 3200.0
const UG_GROUND_Y: float = 4300.0
const PLAT_Y: float = 3125.0

func _make_land() -> void:
	var GROUND_H := 750.0
	var UG_H := 350.0

	# ══════ 地面层地形（从左到右）═══════
	# ── 区域1：左侧森林（纹理墙+找不同+宴会场）──
	_add_terrain_segment(0.0,    GROUND_Y, 800.0,  GROUND_H, Color("#4a6838"), Color("#385028"))   # 纹理墙区域
	_add_terrain_segment(800.0,  GROUND_Y, 800.0,  GROUND_H, Color("#527840"), Color("#406030"))   # 找不同密室区域
	_add_terrain_segment(1600.0, GROUND_Y, 800.0,  GROUND_H, Color("#5c8a4f"), Color("#4a703e"))   # 宴会厅油画区域

	# ── 区域2：出生点 / 中央广场（安全出生区 X:2500-4000）──
	_add_terrain_segment(2400.0, GROUND_Y, 1800.0, GROUND_H, Color("#8a8860"), Color("#6a6848"))   # 中央广场

	# ── 区域3：湖泊灯塔 ──
	_add_terrain_segment(4200.0, GROUND_Y, 1200.0, GROUND_H, Color("#6a9890"), Color("#4a7870"))   # 灯塔湖岸

	# ── 区域4：水坝工业区 ──
	_add_terrain_segment(5400.0, GROUND_Y, 1200.0, GROUND_H, Color("#788068"), Color("#586048"))   # 水坝

	# ── 区域5：旧车站 ──
	_add_terrain_segment(6600.0, GROUND_Y, 1600.0, GROUND_H, Color("#8a8880"), Color("#6a6860"))   # 车站区

	# ── 区域6：游乐园（灯板在此）──
	_add_terrain_segment(8200.0, GROUND_Y, 1400.0, GROUND_H, Color("#c8a858"), Color("#a08840"))   # 游乐园

	# ── 区域7：天文台（NPC密码台在最右侧）──
	_add_terrain_segment(9600.0, GROUND_Y, 1400.0, GROUND_H, Color("#7a88a8"), Color("#5a6888"))   # 天文台

	# ═════ 可行走高台平台 ═════
	# 森林小路平台
	_add_platform(Rect2(500,  PLAT_Y, 280, 28), Color("#6a9848"), true, true)
	_add_platform(Rect2(1100, PLAT_Y, 280, 28), Color("#78a858"), true, true)

	# 广场两侧平台（避开出生缓冲区X:3100-3700）
	_add_platform(Rect2(2550, PLAT_Y, 300, 28), Color("#9a9858"), true, true)
	_add_platform(Rect2(3800, PLAT_Y, 300, 28), Color("#9a9858"), true, true)

	# 灯塔栈桥平台
	_add_platform(Rect2(4450, PLAT_Y, 550, 28), Color("#7aaab8"), true, true)

	# 水坝操作平台
	_add_platform(Rect2(5650, PLAT_Y, 550, 28), Color("#8a9080"), true, true)

	# 车站站台
	_add_platform(Rect2(6950, PLAT_Y, 750, 28), Color("#9a9890"), true, true)

	# 游乐园主平台
	_add_platform(Rect2(8550, PLAT_Y, 550, 28), Color("#e0b868"), true, true)

	# 天文台观景台
	_add_platform(Rect2(9950, PLAT_Y, 550, 28), Color("#8a98c0"), true, true)

	# ══════ 地下层地形（地下迷宫）═══════
	# 入口在瀑布附近(X:5200)，向左延伸到钥匙A，向右延伸到宝箱
	_add_terrain_segment(4800.0, UG_GROUND_Y, 1800.0, UG_H, Color("#30384a"), Color("#202838"))

	# 地下平台
	_add_platform(Rect2(4950, UG_GROUND_Y - 85, 280, 28), Color("#485868"), true, true)   # 靠近入口
	_add_platform(Rect2(5450, UG_GROUND_Y - 85, 220, 28), Color("#485868"), true, true)   # 中转
	_add_platform(Rect2(4950, UG_GROUND_Y - 85, 200, 28), Color("#586878"), true, true)   # 钥匙3附近
	_add_platform(Rect2(5450, UG_GROUND_Y - 85, 200, 28), Color("#604030"), true, true)   # 宝箱附近

	# ── 地下入口传送门（在地面上）──
	var maze_entry := _add_marker(Vector2(5200, GROUND_Y - 25), "↓ 黑暗迷宫入口 ↓", Color("#8040a0"), 52)
	maze_entry.set_meta("kind", "teleport")
	maze_entry.set_meta("target", Vector2(5200, UG_GROUND_Y - 90))
	maze_entry.set_meta("requires_view", "blind")  # 需要盲人模式才能进入
	interactables.append(maze_entry)

	# ── 从迷宫返回地面的出口 ──
	var maze_exit := _add_marker(Vector2(5200, UG_GROUND_Y - 90), "↑ 返回地面 ↑", Color("#a0ffc0"), 44)
	maze_exit.set_meta("kind", "teleport")
	maze_exit.set_meta("target", Vector2(5200, GROUND_Y - 25))
	interactables.append(maze_exit)

	# ── 台阶连接（视觉引导）──
	for px in [500.0, 1100.0, 2550.0, 4450.0, 5650.0, 6950.0, 8550.0, 9950.0]:
		_add_step_block(px - 30.0, GROUND_Y - 55, 26.0, 30.0, false)
		_add_step_block(px + 250.0, GROUND_Y - 55, 26.0, 30.0, false)

func _add_terrain_segment(x: float, y: float, w: float, h: float, top_color: Color, bottom_color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x + w / 2.0, y + h / 2.0)
	add_child(body)
	
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(w, h)
	shape.shape = box
	body.add_child(shape)
	
	# Terrain visual with grass top
	var terrain := ColorRect.new()
	terrain.position = Vector2(-w / 2.0, -h / 2.0)
	terrain.size = Vector2(w, h)
	terrain.color = bottom_color
	body.add_child(terrain)
	
	# Grass layer on top
	var grass := ColorRect.new()
	grass.position = Vector2(-w / 2.0, -h / 2.0)
	grass.size = Vector2(w, 24.0)
	grass.color = top_color
	body.add_child(grass)
	
	# Dirt/stone texture lines
	for i in range(int(h / 80.0)):
		var line := ColorRect.new()
		line.position = Vector2(-w / 2.0, -h / 2.0 + 30.0 + i * 80.0)
		line.size = Vector2(w, 3.0)
		line.color = bottom_color.darkened(0.15)
		line.modulate.a = 0.3
		body.add_child(line)

func _add_step_block(x: float, y: float, w: float, h: float, collidable: bool = true) -> void:
	# Small block for connecting levels. Ground-level connectors are visual-only (no collision).
	if collidable:
		var body := StaticBody2D.new()
		body.position = Vector2(x + w / 2.0, y + h / 2.0)
		add_child(body)
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(w, h)
		shape.shape = box
		body.add_child(shape)
		var visual := ColorRect.new()
		visual.position = Vector2(-w / 2.0, -h / 2.0)
		visual.size = Vector2(w, h)
		visual.color = Color("#6b5b45")
		body.add_child(visual)
		var top := ColorRect.new()
		top.position = Vector2(-w / 2.0, -h / 2.0)
		top.size = Vector2(w, 5.0)
		top.color = Color("#8a7a60")
		body.add_child(top)
	else:
		# Visual-only step (no collision, just eye candy between ground segments)
		var visual := ColorRect.new()
		visual.position = Vector2(x, y)
		visual.size = Vector2(w, h)
		visual.color = Color("#6b5b45")
		add_child(visual)
		var top := ColorRect.new()
		top.position = Vector2(x, y)
		top.size = Vector2(w, 4.0)
		top.color = Color("#8a7a60")
		add_child(top)

func _add_platform(rect: Rect2, color: Color, has_grass: bool = true, walkable: bool = false) -> void:
	# Platform visual + optional collision for walkable surfaces
	var container := Node2D.new()
	container.position = rect.position + rect.size / 2.0
	add_child(container)
	
	var visual := ColorRect.new()
	visual.position = -rect.size / 2.0
	visual.size = rect.size
	visual.color = color
	container.add_child(visual)
	
	if has_grass:
		var grass := ColorRect.new()
		grass.position = Vector2(-rect.size.x / 2.0, -rect.size.y / 2.0)
		grass.size = Vector2(rect.size.x, 8.0)
		grass.color = color.lightened(0.15)
		container.add_child(grass)
	
	if walkable:
		# Thin collision (6px) at platform TOP only — player walks underneath freely
		var body := StaticBody2D.new()
		body.name = "PlatformCollision"
		body.position = Vector2(0, -rect.size.y / 2.0 + 3.0)
		container.add_child(body)
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(rect.size.x, 6.0)
		shape.shape = box
		body.add_child(shape)

# ─── DECORATIONS ────────────────────────────────────
func _make_decorations() -> void:
	# Flowers scattered around
	for i in range(40):
		var flower := Polygon2D.new()
		var fx: float = 200.0 + (i * 283.0)
		var fy: float = 3220.0
		var fp := PackedVector2Array()
		for j in range(6):
			var a: float = TAU * j / 6.0
			fp.append(Vector2(cos(a) * 6.0, sin(a) * 6.0 - 10.0))
		flower.polygon = fp
		flower.position = Vector2(fx, fy)
		var flower_colors := [Color("#ff8a9e"), Color("#ffe066"), Color("#ffb3c6"), Color("#fff0a0"), Color("#c4a0ff")]
		flower.color = flower_colors[i % flower_colors.size()]
		flower.z_index = -5
		add_child(flower)
	
	# Grass tufts
	for i in range(30):
		var tuft := Polygon2D.new()
		var gx: float = 150.0 + i * 390.0
		var gy: float = 3225.0
		var gp := PackedVector2Array([
			Vector2(0, 0),
			Vector2(-4, -16),
			Vector2(-2, -22),
			Vector2(0, -14),
			Vector2(3, -24),
			Vector2(5, -18),
			Vector2(8, -12),
			Vector2(6, 0),
		])
		tuft.polygon = gp
		tuft.position = Vector2(gx, gy)
		tuft.color = Color("#4a7a3a") if i % 2 == 0 else Color("#5a8a4a")
		tuft.z_index = -4
		add_child(tuft)
	
	# Rocks
	for i in range(15):
		var rock := Polygon2D.new()
		var rx: float = 350.0 + i * 780.0
		var ry: float = 3228.0
		var rp := PackedVector2Array()
		for j in range(10):
			var a: float = TAU * j / 10.0
			var rr: float = 10.0 + sin(j * 2.5) * 5.0
			rp.append(Vector2(cos(a) * rr, sin(a) * rr - 6.0))
		rock.polygon = rp
		rock.position = Vector2(rx, ry)
		rock.color = Color("#8a8a82") if i % 3 == 0 else Color("#9a9a92")
		rock.z_index = -3
		add_child(rock)
	
	# Underground: glowing crystals
	for i in range(8):
		var crystal := Polygon2D.new()
		var cx: float = 4650.0 + i * 380.0
		var cy: float = 4170.0 - (i % 3) * 40.0
		var cp := PackedVector2Array([
			Vector2(0, 0),
			Vector2(-4, -18),
			Vector2(-1, -26),
			Vector2(3, -22),
			Vector2(6, -30),
			Vector2(8, -16),
			Vector2(4, 0),
		])
		crystal.polygon = cp
		crystal.position = Vector2(cx, cy)
		crystal.color = Color("#b8e8ff")
		crystal.modulate.a = 0.6
		crystal.z_index = -2
		add_child(crystal)

# ─── REGIONS / BUILDINGS ───────────────────────────
# 基于设计文档的区域标注（从左到右）
func _make_regions() -> void:
	# 区域标签（在地图上方显示）
	_label_region("左侧森林", Vector2(700, 2950), Color("#5f8b5f"))
	_label_region("中央广场", Vector2(3300, 2960), Color("#b5a05e"))
	_label_region("湖泊灯塔", Vector2(4750, 2950), Color("#6eb8db"))
	_label_region("水坝工业区", Vector2(5950, 2950), Color("#7b9088"))
	_label_region("旧车站",   Vector2(7300, 2950), Color("#878792"))
	_label_region("游乐园",   Vector2(8850, 2950), Color("#e7a84c"))
	_label_region("天文台",   Vector2(10150, 2950), Color("#8fa9d7"))
	_label_region("地下迷宫", Vector2(5200, 4080), Color("#645880"))

	# ═════ 建筑物/地标 ═════
	
	# ── 关卡1：纹理墙（左侧森林入口）──
	_add_building_detail(Vector2(400, 3100), Vector2(60, 140), Color("#6a5545"), "纹理墙")
	_add_zone_marker(Vector2(400, 3170), "关卡1\n纹理墙", Color("#e0a050"))

	# ── 关卡2：找不同密室（森林中部小楼）──
	_add_building_detail(Vector2(1200, 3080), Vector2(100, 130), Color("#8a7060"), "密室")
	_add_zone_marker(Vector2(1200, 3170), "关卡2\n找不同", Color("#c080d0"))

	# ── 关卡3：宴会厅油画（森林深处）──
	_add_building_detail(Vector2(2000, 3050), Vector2(160, 150), Color("#9a8068"), "宴会厅")
	_add_zone_marker(Vector2(2000, 3100), "关卡3\n油画舞步", Color("#d060a0"))

	# ── 出生点/中央广场 ──
	_add_building_detail(Vector2(3400, 3080), Vector2(220, 100), Color("#d3ae76"), "中央广场")

	# ── 灯塔 ──
	_add_building_detail(Vector2(4800, 2950), Vector2(80, 320), Color("#d7dee7"), "灯塔")
	var glow := Polygon2D.new()
	var gp := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * i / 16.0
		gp.append(Vector2(cos(a) * 28.0, sin(a) * 28.0))
	glow.polygon = gp
	glow.position = Vector2(4800, 2770)
	glow.color = Color("#ffe8a0")
	glow.modulate.a = 0.5
	glow.z_index = -1
	add_child(glow)

	# ── 水坝 ──
	_add_building_detail(Vector2(6000, 3080), Vector2(240, 170), Color("#8ea7b1"), "水坝")

	# ── 车站 ──
	_add_building_detail(Vector2(7500, 3080), Vector2(550, 140), Color("#9b9080"), "旧车站")

	# ── 游乐园：摩天轮 + 灯板区域 ──
	_draw_wheel(Vector2(9000, 3040))
	_add_zone_marker(Vector2(8800, 3170), "关卡4\n灯板谜题", Color("#ffaa30"))

	# ── 天文台 + NPC密码台 ──
	_add_building_detail(Vector2(10200, 3080), Vector2(240, 150), Color("#b7c8e8"), "天文台")
	var dome := Polygon2D.new()
	var dp := PackedVector2Array()
	for i in range(32):
		var a: float = PI * i / 31.0
		dp.append(Vector2(cos(a) * 82.0, sin(a) * 50.0 - 72.0))
	dome.polygon = dp
	dome.position = Vector2(10200, 2900)
	dome.color = Color("#8fa9d7")
	dome.z_index = -1
	add_child(dome)
	_add_zone_marker(Vector2(10500, 3170), "关卡5\nNPC密码台", Color("#a080f0"))

	# ── 地下迷宫入口标识 ──
	_add_zone_marker(Vector2(5200, UG_GROUND_Y - 20), "关卡6\n黑暗迷宫", Color("#8040c0"))

	# ═════ 风向标系统 ═════
	_make_wind_vanes()

	# ═════ 宝藏位置（激光交叉点）═══════
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
