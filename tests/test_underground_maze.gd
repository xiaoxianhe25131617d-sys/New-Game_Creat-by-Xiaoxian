extends Node

const MAZE_SCENE_PATH := "res://maze/UndergroundMaze.tscn"
const EXPECTED_MAP_SIZE := Vector2(3096, 1758)
const EXPECTED_MARKERS := [&"PlayerSpawn", &"HiddenDoor", &"Chest", &"Key", &"PortalExit"]

var failures: Array[String] = []

func _ready() -> void:
	var packed := load(MAZE_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("UndergroundMaze.tscn must exist and load")
		_finish()
		return

	var maze := packed.instantiate()
	add_child(maze)
	_test_scene_contract(maze)
	_test_markers(maze)
	_test_spawn_return_exit(maze)
	_test_ladders(maze)
	_test_wind_trigger_line(maze)
	_test_navigation_features_are_clear(maze)
	_test_ordered_route_guidance()
	_test_navigation_feedback_strength()
	_test_compass_cardinal_directions()
	_test_exit_trigger_is_forgiving(maze)
	_test_dark_visual_material_only(maze)
	_test_runtime_player(maze)
	maze.free()
	_finish()

func _test_scene_contract(maze: Node) -> void:
	if maze.get("map_size") != EXPECTED_MAP_SIZE:
		failures.append("Maze map_size must be 3096x1758")
	for path in ["ReferenceImage", "Walls", "OneWayStairs", "Ladders", "Markers", "Bounds"]:
		if maze.get_node_or_null(path) == null:
			failures.append("Maze scene is missing %s" % path)
	if not maze.is_in_group("world"):
		failures.append("Maze root must provide the world interface")
	if not maze.has_method("get_ladder_at_point") or not maze.has_method("is_drop_through_tile"):
		failures.append("Maze root must expose ladder and drop-through queries")
	var reference := maze.get_node_or_null("ReferenceImage") as Sprite2D
	if reference != null and reference.visible:
		failures.append("Reference image must be hidden at runtime")
	var walls := maze.get_node_or_null("Walls") as TileMapLayer
	if walls != null and walls.get_used_cells().size() < 1000:
		failures.append("Walls TileMap must contain the traced gray layout")
	var stairs := maze.get_node_or_null("OneWayStairs") as TileMapLayer
	if stairs != null and stairs.get_used_cells().size() < 50:
		failures.append("OneWayStairs must contain all traced diagonal stair runs")
	elif stairs != null:
		var stair_point := stairs.to_global(stairs.map_to_local(stairs.get_used_cells()[0]))
		if not bool(maze.call("is_drop_through_at", stair_point)):
			failures.append("One-way stair cells must be discoverable through the world interface")
	var spawn := maze.get_node_or_null("Markers/PlayerSpawn") as Marker2D
	if walls != null and spawn != null and walls.get_cell_source_id(walls.local_to_map(walls.to_local(spawn.global_position))) >= 0:
		failures.append("PlayerSpawn must remain in a white walkable area")

func _test_markers(maze: Node) -> void:
	var ids: Dictionary = {}
	for marker_name in EXPECTED_MARKERS:
		var marker := maze.get_node_or_null("Markers/%s" % marker_name) as Marker2D
		if marker == null:
			failures.append("Missing marker %s" % marker_name)
			continue
		var persistent_id := str(marker.get_meta("persistent_id", ""))
		if persistent_id.is_empty() or ids.has(persistent_id):
			failures.append("Marker %s needs a unique persistent_id" % marker_name)
		ids[persistent_id] = true

func _test_spawn_return_exit(maze: Node) -> void:
	var spawn := maze.get_node_or_null("Markers/PlayerSpawn") as Marker2D
	var exit_visual := maze.get_node_or_null("SpawnReturnExit") as Node2D
	var prompt := maze.get_node_or_null("SpawnReturnPrompt") as Label
	if spawn == null or exit_visual == null:
		failures.append("Maze spawn must have a visible return exit")
	elif exit_visual.global_position.distance_to(spawn.global_position) > 1.0:
		failures.append("Spawn return exit must stay anchored to PlayerSpawn")
	if prompt == null or "[E]" not in prompt.text or "返回地面" not in prompt.text:
		failures.append("Spawn return exit must explain that E returns to the surface")

func _test_ladders(maze: Node) -> void:
	var ladders := maze.get_node("Ladders").get_children()
	if ladders.size() != 11:
		failures.append("Maze must contain all 11 vertical ladders")
	for ladder in ladders:
		if not ladder is Area2D or ladder.get_node_or_null("CollisionShape2D") == null:
			failures.append("Every ladder must be an editable Area2D with a CollisionShape2D")

func _test_wind_trigger_line(maze: Node) -> void:
	var wind_line := maze.get_node_or_null("WindTriggerLine") as Path2D
	if wind_line == null:
		failures.append("Maze must contain an editable WindTriggerLine Path2D")
		return
	if wind_line.curve == null or wind_line.curve.point_count < 2:
		failures.append("WindTriggerLine needs at least two editable curve points")
	var trigger_area := wind_line.get_node_or_null("TriggerArea") as Area2D
	if trigger_area == null:
		failures.append("WindTriggerLine must build a player overlap Area2D")
	elif trigger_area.collision_mask != 1:
		failures.append("WindTriggerLine must detect the player's collision layer")
	elif trigger_area.get_child_count() == 0:
		failures.append("WindTriggerLine must turn its curve into collision segments")
	var preview := wind_line.get_node_or_null("EditorPreview") as Line2D
	if preview == null or preview.visible:
		failures.append("WindTriggerLine preview must be hidden in the running game")
	if not wind_line.has_method("is_player_touching"):
		failures.append("WindTriggerLine must expose its contact state for runtime verification")

func _test_navigation_features_are_clear(maze: Node) -> void:
	var walls := maze.get_node("Walls") as TileMapLayer
	for waypoint in UndergroundMaze.COMPASS_ROUTE:
		var cell := walls.local_to_map(walls.to_local(waypoint))
		if walls.get_cell_source_id(cell) >= 0:
			failures.append("Compass waypoint %s falls inside solid maze terrain" % waypoint)

func _test_ordered_route_guidance() -> void:
	var route := UndergroundMaze.EXIT_GUIDANCE_ROUTE
	var current_sample := UndergroundMaze.sample_active_route_segment(Vector2(1350, 795), route, 0)
	if float(current_sample.get("distance", INF)) > 1.0:
		failures.append("Ordered guidance must recognize the active route segment")
	var later_route_sample := UndergroundMaze.sample_active_route_segment(Vector2(2350, 440), route, 0)
	if float(later_route_sample.get("distance", 0.0)) <= UndergroundMaze.ROUTE_WRONG_DISTANCE:
		failures.append("A later route segment across the maze must not count as the current correct path")
	var next_index := UndergroundMaze.advance_ordered_route(Vector2(1180, 795), route, 0, 64.0)
	if next_index != 1:
		failures.append("Ordered guidance must advance only after reaching the active segment endpoint")

func _test_navigation_feedback_strength() -> void:
	if UndergroundMaze.route_volume_db(0.0) < -6.11:
		failures.append("Route guidance must be clearly audible from the maze entrance")
	if UndergroundMaze.route_volume_db(1.0) < 5.99:
		failures.append("Route guidance must reach +6 dB near the exit")
	if UndergroundMaze.route_interval(0.0) > 0.201 or UndergroundMaze.route_interval(1.0) > 0.076:
		failures.append("Route guidance cadence must accelerate from 0.20s to about 0.075s")

func _test_compass_cardinal_directions() -> void:
	var cases := {
		Vector2(120, 10): "向右",
		Vector2(-120, 10): "向左",
		Vector2(10, 120): "向下",
		Vector2(10, -120): "向上",
		Vector2(4, 3): "继续前进",
	}
	for offset in cases:
		if UndergroundMaze.cardinal_direction_text(offset) != cases[offset]:
			failures.append("Compass direction for %s should be %s" % [offset, cases[offset]])

func _test_exit_trigger_is_forgiving(_maze: Node) -> void:
	if UndergroundMaze.EXIT_TRIGGER_RADIUS < 120.0:
		failures.append("Invisible maze exit needs a forgiving automatic trigger radius")

func _test_dark_visual_material_only(maze: Node) -> void:
	var background := maze.get_node_or_null("PrototypeBackground") as ColorRect
	if background == null or background.color.get_luminance() > 0.18:
		failures.append("Maze background should be a low-contrast dark stone tone")

func _test_runtime_player(maze: Node) -> void:
	var player := maze.get_node_or_null("RuntimePlayer") as MindscapePlayer
	var spawn := maze.get_node_or_null("Markers/PlayerSpawn") as Marker2D
	if player == null or spawn == null:
		failures.append("Standalone maze must create the doctor at PlayerSpawn")
		return
	if player.global_position.distance_to(spawn.global_position) > 1.0:
		failures.append("Runtime player must start at PlayerSpawn (player=%s spawn=%s)" % [player.global_position, spawn.global_position])
	var camera := player.get_node_or_null("MazeCamera") as Camera2D
	if camera == null:
		failures.append("Standalone maze player needs a bounded camera")
	elif camera.limit_right != int(EXPECTED_MAP_SIZE.x) or camera.limit_bottom != int(EXPECTED_MAP_SIZE.y):
		failures.append("Maze camera limits must match map_size")

func _finish() -> void:
	if failures.is_empty():
		print("PASS: underground maze scene checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
