extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_world_uses_sky_texture()
	_test_platforms_have_no_ground_seams()
	_test_wall_has_one_textured_visual()
	_test_room_has_textured_exterior()
	_test_memory_anchors_use_benches()
	_test_lighthouse_geometry_is_removed()
	_test_npc_shoes_define_the_ground_line()
	if failures.is_empty():
		print("PASS: world art cleanup regression checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_world_uses_sky_texture() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_background_canvas()
	var sky := world.bg_canvas.get_node_or_null("Sky") as TextureRect
	if sky == null or sky.texture == null:
		failures.append("World background must have a sky texture")
	elif sky.texture.resource_path != "res://assets/sky_user.png":
		failures.append("World background must use sky_user.png")
	elif sky.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		failures.append("Sky texture must preserve its aspect ratio while covering the viewport")
	elif sky.size.x <= 0.0 or sky.size.y <= 0.0:
		failures.append("Sky texture must be sized to the viewport")
	if world.bg_canvas.follow_viewport_enabled:
		failures.append("Sky background canvas must remain fixed to the screen")
	world.free()

func _test_platforms_have_no_ground_seams() -> void:
	var covered_columns: Dictionary = {}
	for platform in MindscapeWorld.PLATFORMS:
		for x in range(platform["x0"], platform["x1"] + 1):
			if covered_columns.has(x):
				failures.append("Ground column %d is painted by multiple platforms" % x)
			covered_columns[x] = true
	for x in range(MindscapeWorld.WORLD_TILE_W):
		if not covered_columns.has(x):
			failures.append("Ground seam remains at tile column %d" % x)

func _test_wall_has_one_textured_visual() -> void:
	var wall := PuzzleTextureWall.new()
	add_child(wall)
	var textures := wall.find_children("WallTexture", "Sprite2D", true, false)
	if textures.size() != 1:
		failures.append("Stone wall must have exactly one textured visual")
	wall.free()
	var world := MindscapeWorld.new()
	world._paint_texture_wall_blocker()
	if world._texture_wall_body == null:
		failures.append("Stone wall has no physical blocker")
	else:
		for child in world._texture_wall_body.get_children():
			if child is Sprite2D or child is Polygon2D or child is ColorRect or child is Label:
				failures.append("Stone wall physical blocker must stay invisible")
	world.free()

func _test_room_has_textured_exterior() -> void:
	var room := PuzzleFindDifference.new()
	add_child(room)
	if room.find_child("ExteriorTexture", true, false) == null:
		failures.append("Find-difference room must use a textured exterior")
	room.free()

func _test_memory_anchors_use_benches() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world._make_memory_anchors()
	for anchor in world.anchor_nodes:
		var bench := anchor.find_child("BenchTexture", true, false) as Sprite2D
		if bench == null or bench.texture == null:
			failures.append("Memory anchor %s has no bench texture" % anchor.get_meta("id", "unknown"))
	world.free()

func _test_lighthouse_geometry_is_removed() -> void:
	var world := MindscapeWorld.new()
	var container := Node2D.new()
	world.add_child(container)
	world._draw_buildings_bg(container)
	for child in container.get_children():
		if child is ColorRect and (child as ColorRect).position.x > 4800.0 and (child as ColorRect).position.x < 5000.0:
			failures.append("Procedural lighthouse ColorRect still exists")
		if child is Polygon2D:
			for point in (child as Polygon2D).polygon:
				if point.x > 4800.0 and point.x < 5000.0:
					failures.append("Procedural lighthouse Polygon2D still exists")
					break
	world.free()

func _test_npc_shoes_define_the_ground_line() -> void:
	for data in GameData.NPCS:
		if absf((data["pos"] as Vector2).y - MindscapeWorld.GROUND_Y_PX) > 0.1:
			failures.append("NPC %s spawn is not on the ground baseline" % data["id"])
		var npc := MindscapeNPC.new()
		npc.setup(data)
		var sprite := npc.character_sprite
		if sprite == null or not sprite.texture is AtlasTexture:
			npc.free()
			continue
		var frame := sprite.texture as AtlasTexture
		var image := frame.atlas.get_image()
		var region := frame.region
		var x0 := int(region.size.x * 0.32)
		var x1 := int(region.size.x * 0.68)
		var shoe_bottom := -1
		for y in range(int(region.size.y)):
			for x in range(x0, x1):
				if image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a > 0.8:
					shoe_bottom = maxi(shoe_bottom, y)
		var frame_center_y := (region.size.y - 1.0) * 0.5
		var visual_shoe_y := sprite.position.y + (shoe_bottom - frame_center_y) * sprite.scale.y
		if absf(visual_shoe_y - MindscapeNPC.NPC_FOOT_Y) > 0.6:
			failures.append("NPC %s shoes are %.1fpx away from the ground line" % [data["id"], visual_shoe_y - MindscapeNPC.NPC_FOOT_Y])
		npc.free()
