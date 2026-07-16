extends Node

const EPSILON := 0.55

var failures: Array[String] = []

func _ready() -> void:
	_test_npc_targets_stay_on_spawn_y()
	_test_npc_motion_stays_on_spawn_y()
	_test_npc_idle_duration_is_extended_and_randomized()
	_test_all_npcs_have_distinct_atlas_regions()
	_test_all_characters_render_in_world_foreground()
	_test_player_sprite_feet_match_collision_bottom()
	if failures.is_empty():
		print("PASS: character presentation regression checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_npc_targets_stay_on_spawn_y() -> void:
	var npc := MindscapeNPC.new()
	npc.setup({"id": "test", "name": "Test", "pos": Vector2(100.0, 200.0)})
	for _attempt in range(20):
		npc._pick_new_walk_target()
		_expect_close(npc.walk_target.y, npc.spawn_pos.y, "NPC walk target changed its Y coordinate")
	npc.free()

func _test_npc_idle_duration_is_extended_and_randomized() -> void:
	var npc := MindscapeNPC.new()
	npc.setup({"id": "test", "name": "Test", "pos": Vector2(100.0, 200.0)})
	for _attempt in range(20):
		npc._begin_idle()
		if npc.walk_timer < MindscapeNPC.IDLE_DURATION_MIN or npc.walk_timer > MindscapeNPC.IDLE_DURATION_MAX:
			failures.append("NPC idle duration fell outside the configured random range")
	npc.free()

func _test_npc_motion_stays_on_spawn_y() -> void:
	var npc := MindscapeNPC.new()
	npc.setup({"id": "test", "name": "Test", "pos": Vector2(100.0, 200.0)})
	add_child(npc)
	npc.walk_target = Vector2(160.0, 230.0)
	npc.is_walking = true
	npc._process(0.5)
	_expect_close(npc.position.y, npc.spawn_pos.y, "NPC movement changed its Y coordinate")
	npc.free()

func _test_all_npcs_have_distinct_atlas_regions() -> void:
	var regions: Dictionary = {}
	for data in GameData.NPCS:
		var npc := MindscapeNPC.new()
		npc.setup(data)
		var sprite := npc.character_sprite
		if sprite == null or not sprite.texture is AtlasTexture:
			failures.append("NPC %s did not load an atlas texture" % data["id"])
			npc.free()
			continue
		var region := (sprite.texture as AtlasTexture).region
		regions[str(region)] = true
		_expect_close(float(sprite.get_meta("visual_foot_y", -1.0)), MindscapeNPC.NPC_FOOT_Y, "NPC visual foot baseline is incorrect")
		npc.free()
	if regions.size() != GameData.NPCS.size():
		failures.append("Expected %d distinct NPC atlas regions, got %d" % [GameData.NPCS.size(), regions.size()])

func _test_all_characters_render_in_world_foreground() -> void:
	var npc := MindscapeNPC.new()
	npc.setup({"id": "test", "name": "Test", "pos": Vector2.ZERO})
	var player := MindscapePlayer.create()
	if npc.z_index < 100:
		failures.append("NPC root must render in the world foreground")
	if player.z_index < 100:
		failures.append("Player root must render in the world foreground")
	npc.free()
	player.free()

func _test_player_sprite_feet_match_collision_bottom() -> void:
	var player := MindscapePlayer.create()
	var sprite := player.get_node("CharacterTexture") as AnimatedSprite2D
	var shape := player.get_node("CollisionShape2D") as CollisionShape2D
	var rect := shape.shape as RectangleShape2D
	var frame := sprite.sprite_frames.get_frame_texture(&"idle", 0) as AtlasTexture
	var image := frame.atlas.get_image()
	var region := frame.region
	var opaque_bottom := -1
	for y in range(int(region.size.y)):
		for x in range(int(region.size.x)):
			if image.get_pixel(int(region.position.x) + x, int(region.position.y) + y).a > 0.1:
				opaque_bottom = maxi(opaque_bottom, y)
	var frame_center_y := (region.size.y - 1.0) * 0.5
	var visual_foot_y := sprite.position.y + (opaque_bottom - frame_center_y) * sprite.scale.y
	var collision_bottom_y := rect.size.y * 0.5
	_expect_close(visual_foot_y, collision_bottom_y, "Player sprite feet do not match collision bottom")
	player.free()

func _expect_close(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) > EPSILON:
		failures.append("%s: expected %.2f, got %.2f" % [message, expected, actual])
