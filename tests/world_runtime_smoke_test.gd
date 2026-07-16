extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var packed := load("res://map/MainWorld.tscn") as PackedScene
	if packed == null:
		push_error("world_runtime_smoke_test: MainWorld.tscn failed to load")
		get_tree().quit(1)
		return
	var world := packed.instantiate() as MindscapeWorld
	add_child(world)
	world.build(GameData.default_state())
	_expect(world.is_in_group("world"), "world registers its runtime group")
	_expect(world.get_node_or_null("Markers/monsters/distractor_park") == null, "distractor marker is removed from the authored world")
	_expect(world.get_node_or_null("MonsterCanvas/Monster_distractor_park") == null, "distractor is not created at runtime")
	_expect(world.get_node_or_null("MonsterCanvas/Monster_mouth_station") == null, "silent mouth is not created at runtime")
	_expect(world.get_node_or_null("MonsterCanvas/Monster_shadow_forest") == null, "depression shadow polygon is not created at runtime")
	_expect(world.get_node_or_null("MonsterCanvas/Monster_noise_lighthouse") == null, "information noise ball is not created at runtime")
	for monster_node in get_tree().get_nodes_in_group("monster"):
		var monster := monster_node as MindscapeMonster
		_expect(monster == null or monster.monster_type != "silent_mouth", "no silent mouth monster remains in the world")
		_expect(monster == null or monster.monster_type != "shadow", "no shadow polygon remains in depression view")
		_expect(monster == null or monster.monster_type != "noise", "no information noise ball remains in blind view")
	_test_inactive_monster_visuals_hide_immediately()
	_expect(not world.collectible_nodes.has("collectible_05"), "left banquet hall collectible is not created at runtime")
	_expect(not world.collectible_nodes.has("collectible_06"), "right banquet hall collectible is not created at runtime")
	for anchor in world.anchor_nodes:
		_expect(str(anchor.get_meta("id", "")) != "dam", "banquet hall memory bench is not created at runtime")
	_expect(world.interactables.size() > GameData.NPCS.size(), "runtime interactables are created")
	_expect(world.get_node_or_null("NPC_guide_old_man") != null, "NPCs are created from markers")
	_expect(world.get_node_or_null("NPC_npc_cipher_1") == null, "underground entrance guard is not created at runtime")
	_expect(world.get_node_or_null("UndergroundPortal") != null, "underground portal is created from its marker")
	var tree_line := world.get_node_or_null("Visuals/Decorations/TownTreeLineParallax") as Node2D
	_expect(tree_line != null, "authored town tree line exists")
	if tree_line != null:
		var tree_parallax_factor := -1.0
		for layer_data in world.parallax_layers:
			if layer_data.get("node") == tree_line:
				tree_parallax_factor = float(layer_data.get("factor", -1.0))
				break
		_expect(tree_parallax_factor > 0.0 and tree_parallax_factor < 1.0, "town tree line uses background parallax")
		var tree_sprites: Array[Sprite2D] = []
		for child in tree_line.get_children():
			if child is Sprite2D:
				tree_sprites.append(child as Sprite2D)
		tree_sprites.sort_custom(func(a: Sprite2D, b: Sprite2D): return a.position.x < b.position.x)
		for index in range(1, tree_sprites.size()):
			var previous := tree_sprites[index - 1]
			var visible_width := previous.texture.get_image().get_used_rect().size.x * absf(previous.scale.x)
			var repeat_step := tree_sprites[index].position.x - previous.position.x
			_expect(repeat_step <= visible_width, "town tree clusters overlap without a visible gap")
	var portal := world.get_node_or_null("UndergroundPortal") as Area2D
	if portal != null:
		var entrance_back := portal.get_node_or_null("EntranceBack") as Sprite2D
		var entrance_front := portal.get_node_or_null("EntranceFront") as Sprite2D
		var entry_shape: CollisionShape2D = null
		for child in portal.get_children():
			if child is CollisionShape2D:
				entry_shape = child as CollisionShape2D
				break
		var entry_rect := entry_shape.shape as RectangleShape2D if entry_shape != null else null
		var expected_scale := Vector2.ONE * (0.34 * 2.0 / 3.0)
		_expect(entrance_back != null and entrance_back.scale.is_equal_approx(expected_scale), "underground entrance back is two thirds of its previous size")
		_expect(entrance_front != null and entrance_front.scale.is_equal_approx(expected_scale), "underground entrance front is two thirds of its previous size")
		_expect(entry_rect != null and entry_rect.size.is_equal_approx(Vector2(100, 60)), "underground entrance interaction area shrinks to two thirds")
		_expect(entry_shape != null and entry_shape.position.is_equal_approx(Vector2(0, -28)), "underground entrance interaction area remains grounded")
		var visible_bottom := maxf(_opaque_bottom_y(entrance_back), _opaque_bottom_y(entrance_front))
		_expect(absf(visible_bottom) <= 1.0, "underground portal visible bottom touches its ground marker (bottom %.2f)" % visible_bottom)
	_expect(world.puzzle_nodes.has("texture_wall"), "puzzles are created from markers")
	var guide := world.get_node_or_null("NPC_guide_old_man") as Node2D
	if guide != null:
		_expect(guide.global_position.is_equal_approx(world.get_marker_position(&"npcs", &"guide_old_man")), "NPC position matches its authored marker")
	_finish()


func _test_inactive_monster_visuals_hide_immediately() -> void:
	var monster := MindscapeMonster.new()
	monster.setup("test_noise", "noise", Vector2.ZERO)
	add_child(monster)
	monster.current_alpha = 1.0
	monster.body_node.modulate.a = 1.0
	monster.label_node.modulate.a = 1.0
	monster.on_view_changed("depression")
	_expect(is_zero_approx(monster.current_alpha), "inactive monster alpha clears immediately after switching views")
	_expect(is_zero_approx(monster.body_node.modulate.a), "inactive monster polygon does not linger in depression view")
	_expect(is_zero_approx(monster.label_node.modulate.a), "inactive monster label does not linger in depression view")
	monster.free()


func _opaque_bottom_y(sprite: Sprite2D) -> float:
	if sprite == null or sprite.texture == null:
		return -INF
	var image := sprite.texture.get_image()
	for y in range(image.get_height() - 1, -1, -1):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.8:
				return sprite.position.y + (float(y) - float(image.get_height()) * 0.5) * sprite.scale.y
	return -INF


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("world_runtime_smoke_test: PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("world_runtime_smoke_test: %s" % failure)
	get_tree().quit(1)
