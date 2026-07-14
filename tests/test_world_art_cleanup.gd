extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_world_uses_sky_texture()
	_test_platforms_have_no_ground_seams()
	_test_wall_has_one_textured_visual()
	_test_room_has_textured_exterior()
	_test_memory_anchors_use_benches()
	_test_lighthouse_geometry_is_removed()
	_test_procedural_forest_cabin_is_removed()
	_test_wind_vanes_are_not_spawned()
	_test_npc_shoes_define_the_ground_line()
	_test_required_key_count_matches_available_keys()
	_test_town_foreground_stays_low_and_sparse()
	_test_parallax_is_horizontal_without_follow_tail()
	_test_bush_clues_match_banquet_answer()
	_test_maze_entrance_layers_share_silhouette()
	_test_puzzle_building_pairs_match_exactly()
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

func _test_procedural_forest_cabin_is_removed() -> void:
	var world := MindscapeWorld.new()
	world._make_beautiful_decor()
	for child in world.get_children():
		if child is ColorRect and (child as ColorRect).position.x >= 4550.0 and (child as ColorRect).position.x <= 4650.0:
			failures.append("Legacy brown grid cabin must not be generated near x=4600")
			break
	world.free()

func _test_wind_vanes_are_not_spawned() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world.build(GameData.default_state())
	if world.find_child("WindVane_*", true, false) != null:
		failures.append("Legacy wind-vane artwork must not be spawned")
	if world.find_child("VanePlacement_*", true, false) != null:
		failures.append("Legacy invisible wind-vane drop zones must not remain")
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

func _test_required_key_count_matches_available_keys() -> void:
	var main_script := load("res://scripts/main.gd") as Script
	var constants := main_script.get_script_constant_map()
	var required_key_count := int(constants.get("REQUIRED_KEY_COUNT", -1))
	var overworld_key_count := GameData.KEYS.size() - (1 if GameData.KEYS.has("maze_key") else 0)
	if required_key_count != overworld_key_count:
		failures.append("Required key count must match the three overworld story keys; maze_key is independent")

func _test_town_foreground_stays_low_and_sparse() -> void:
	var world := MindscapeWorld.new()
	world._make_town_art_layers()
	var tree_line := world.get_node_or_null("TownTreeLineParallax") as CanvasItem
	if tree_line == null or tree_line.z_index >= -32:
		failures.append("Town tree line must render behind the authored house background")
	var foreground_count := 0
	for child in world.get_children():
		if child.name.begins_with("TownForegroundTrees_"):
			failures.append("The giant vine-wall foreground must not be spawned")
		if child.name.begins_with("TownForegroundCluster_"):
			foreground_count += 1
			var sprite := child as Sprite2D
			if sprite == null or sprite.texture == null:
				failures.append("Foreground cluster %s has no transparent texture" % child.name)
			elif sprite.texture.get_height() * sprite.scale.y > 245.0:
				failures.append("Foreground cluster %s is tall enough to block the playfield" % child.name)
	if foreground_count < 5:
		failures.append("Town needs several low transparent foreground tree clusters")
	world.free()

func _test_parallax_is_horizontal_without_follow_tail() -> void:
	var world := MindscapeWorld.new()
	if not world.has_method("compute_parallax_offset"):
		failures.append("World has no testable parallax function")
		world.free()
		return
	var base := Vector2(14.0, 37.0)
	var offset: Vector2 = world.compute_parallax_offset(base, Vector2(100.0, 240.0), 0.2, 0.1)
	if not is_equal_approx(offset.x, 94.0):
		failures.append("Parallax X must update directly without a second easing tail")
	if not is_equal_approx(offset.y, base.y):
		failures.append("Parallax Y must remain fixed while the player jumps")
	world.free()

func _test_bush_clues_match_banquet_answer() -> void:
	var clue_colors: Array[Color] = MindscapeWorld.get_bush_clue_colors()
	if clue_colors.size() != PuzzleBanquetPainting.CORRECT_SEQ.size():
		failures.append("World must restore all seven banquet bush clues")
		return
	for index in range(clue_colors.size()):
		var answer_index: int = int(PuzzleBanquetPainting.CORRECT_SEQ[index])
		if not clue_colors[index].is_equal_approx(PuzzleBanquetPainting.MOVE_COLORS[answer_index]):
			failures.append("Bush clue %d does not match the banquet answer" % index)

func _test_maze_entrance_layers_share_silhouette() -> void:
	var front := load("res://assets/environment/generated/maze_entrance_front.png") as Texture2D
	var back := load("res://assets/environment/generated/maze_entrance_back.png") as Texture2D
	if front == null or back == null or front.get_size() != back.get_size():
		failures.append("Maze entrance front/back layers need the same canvas")
		return
	var front_image := front.get_image()
	var back_image := back.get_image()
	for y in range(front_image.get_height()):
		for x in range(front_image.get_width()):
			var front_visible := front_image.get_pixel(x, y).a > 0.02
			var back_visible := back_image.get_pixel(x, y).a > 0.02
			if front_visible != back_visible:
				failures.append("Maze entrance layers must have an identical transparent silhouette")
				return

func _test_puzzle_building_pairs_match_exactly() -> void:
	var puzzle_types: Array = [PuzzleNineGrid, PuzzleBanquetPainting, PuzzleAmusementLights]
	for puzzle_type in puzzle_types:
		var puzzle: Node = puzzle_type.new()
		add_child(puzzle)
		var front := puzzle.find_child("HouseFront", true, false) as Sprite2D
		var back := puzzle.find_child("HouseBackboard", true, false) as Sprite2D
		if front == null or back == null or front.texture == null or back.texture == null:
			failures.append("%s must provide matching front and back building art" % puzzle.get_class())
			puzzle.free()
			continue
		if front.texture.get_size() != back.texture.get_size():
			failures.append("%s building canvases do not match" % puzzle.get_class())
		if not front.position.is_equal_approx(back.position) or not front.scale.is_equal_approx(back.scale):
			failures.append("%s building layers do not share one transform" % puzzle.get_class())
		var front_image := front.texture.get_image()
		var back_image := back.texture.get_image()
		if not _alpha_masks_match(front_image, back_image):
			failures.append("%s building silhouette changes when entering" % puzzle.get_class())
		if puzzle is PuzzleAmusementLights:
			var center_door_alpha := front_image.get_pixel(front_image.get_width() / 2, int(front_image.get_height() * 0.78)).a
			if center_door_alpha < 0.8:
				failures.append("Light-board factory exterior door must be visibly closed")
		puzzle.free()

func _alpha_masks_match(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if absf(a.get_pixel(x, y).a - b.get_pixel(x, y).a) > 0.01:
				return false
	return true
