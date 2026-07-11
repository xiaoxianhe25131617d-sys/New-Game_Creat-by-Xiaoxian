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
	_test_ladders(maze)
	_test_navigation_features_are_clear(maze)
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

func _test_ladders(maze: Node) -> void:
	var ladders := maze.get_node("Ladders").get_children()
	if ladders.size() != 11:
		failures.append("Maze must contain all 11 vertical ladders")
	for ladder in ladders:
		if not ladder is Area2D or ladder.get_node_or_null("CollisionShape2D") == null:
			failures.append("Every ladder must be an editable Area2D with a CollisionShape2D")

func _test_navigation_features_are_clear(maze: Node) -> void:
	var walls := maze.get_node("Walls") as TileMapLayer
	for ladder in maze.get_node("Ladders").get_children():
		for wall_cell in walls.get_used_cells():
			var wall_center := walls.to_global(walls.map_to_local(wall_cell))
			if bool(ladder.call("contains_world_point", wall_center)):
				failures.append("Solid wall tile overlaps %s at %s" % [ladder.name, wall_cell])
				break

	var stairs := maze.get_node("OneWayStairs") as TileMapLayer
	for stair_cell in stairs.get_used_cells():
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				if walls.get_cell_source_id(stair_cell + Vector2i(offset_x, offset_y)) >= 0:
					failures.append("Solid wall tile overlaps one-way stairs near %s" % stair_cell)
					return

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
