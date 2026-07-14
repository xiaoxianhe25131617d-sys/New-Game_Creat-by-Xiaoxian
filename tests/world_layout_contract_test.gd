extends SceneTree

const WORLD_SCENE := "res://map/MainWorld.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	_expect(packed != null, "MainWorld.tscn must load")
	if packed == null:
		_finish()
		return

	var world := packed.instantiate()
	root.add_child(world)
	_expect(world.has_method("get_player_spawn"), "world exposes get_player_spawn")
	_expect(world.has_method("get_world_bounds"), "world exposes get_world_bounds")
	_expect(world.has_method("get_region_at"), "world exposes get_region_at")
	_expect(world.has_method("get_marker_position"), "world exposes get_marker_position")
	_expect(world.has_method("validate_layout"), "world exposes validate_layout")

	if world.has_method("get_player_spawn"):
		_expect(world.get_player_spawn().is_equal_approx(Vector2(3400, 3168)), "player spawn preserves the current layout")
	if world.has_method("get_world_bounds"):
		_expect(world.get_world_bounds() == Rect2(0, 0, 11200, 3600), "world bounds preserve the current layout")
	if world.has_method("get_region_at"):
		_expect(world.get_region_at(Vector2(1000, 3168)) == "forest", "forest region is scene-authored")
		_expect(world.get_region_at(Vector2(3500, 3168)) == "spawn", "spawn region is scene-authored")
		_expect(world.get_region_at(Vector2(10000, 3168)) == "observatory", "observatory region is scene-authored")
	if world.has_method("get_marker_position"):
		_expect(world.get_marker_position(&"puzzles", &"texture_wall").is_equal_approx(Vector2(4200, 3168)), "puzzle positions come from scene markers")
		_expect(world.get_marker_position(&"specials", &"underground_portal").is_equal_approx(Vector2(9000, 3200)), "special positions come from scene markers")
	if world.has_method("validate_layout"):
		var errors: PackedStringArray = world.validate_layout()
		_expect(errors.is_empty(), "layout validates without errors: %s" % ", ".join(errors))
	var background := world.get_node_or_null("Visuals/TileMaps/Background") as CanvasItem
	var tree_line := world.get_node_or_null("Visuals/Decorations/TownTreeLineParallax") as CanvasItem
	_expect(background != null and tree_line != null, "authored background and town tree line exist")
	if background != null and tree_line != null:
		_expect(tree_line.z_index < background.z_index, "town tree line renders behind the authored house background")

	world.queue_free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("world_layout_contract_test: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("world_layout_contract_test: %s" % failure)
	quit(1)
