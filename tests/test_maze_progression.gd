extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_new_profile_defaults()
	_test_completed_laser_migrates_unlocks()
	_test_unfinished_profile_stays_locked()
	_test_hidden_door_unlock_is_idempotent()
	_test_compass_requires_ownership()
	_test_compass_route_advances_only_near_waypoints()
	_test_route_distance_and_progress()
	_test_route_feedback_gain_is_obvious()
	_test_hidden_chest_requires_maze_key()
	_test_hidden_chest_completion_is_idempotent()
	_test_interrupted_ending_can_resume()
	_test_finished_profile_keeps_real_completion()
	_finish()

func _test_new_profile_defaults() -> void:
	var state := GameData.default_state()
	for key in ["hidden_door_opened", "maze_compass_owned", "maze_compass_enabled", "hidden_chest_opened", "ending_seen", "ending_pending", "ending_source", "album_piece_positions", "album_puzzles_completed"]:
		if not state.has(key):
			failures.append("Default state is missing %s" % key)
	if bool(state.get("hidden_door_opened", true)) or bool(state.get("maze_compass_owned", true)):
		failures.append("New profiles must start with the hidden door and compass locked")

func _test_completed_laser_migrates_unlocks() -> void:
	var state := {"completed_levels": ["laser_focus"]}
	GameData.migrate_state(state)
	if not bool(state.get("hidden_door_opened", false)):
		failures.append("Completed laser profiles must migrate to an open hidden door")
	if not bool(state.get("maze_compass_owned", false)):
		failures.append("Completed laser profiles must migrate to owning the compass")
	if bool(state.get("maze_compass_enabled", true)):
		failures.append("Migrated compass must default to disabled until the player enables it")

func _test_unfinished_profile_stays_locked() -> void:
	var state := {"completed_levels": []}
	GameData.migrate_state(state)
	if bool(state.get("hidden_door_opened", true)) or bool(state.get("maze_compass_owned", true)):
		failures.append("Unfinished profiles must not receive the hidden-door unlock")

func _test_hidden_door_unlock_is_idempotent() -> void:
	var state := GameData.default_state()
	if not GameData.unlock_hidden_door(state):
		failures.append("First hidden-door unlock must report a new unlock")
	if not bool(state.get("hidden_door_opened", false)) or not bool(state.get("maze_compass_owned", false)):
		failures.append("Hidden-door unlock must grant both door access and compass ownership")
	if GameData.unlock_hidden_door(state):
		failures.append("Repeated hidden-door unlock must not replay first-time rewards")

func _test_compass_requires_ownership() -> void:
	var locked_state := GameData.default_state()
	if GameData.toggle_maze_compass(locked_state):
		failures.append("A locked compass must not be enabled")
	var owned_state := GameData.default_state()
	owned_state["maze_compass_owned"] = true
	if not GameData.toggle_maze_compass(owned_state):
		failures.append("An owned compass must enable on first toggle")
	if GameData.toggle_maze_compass(owned_state):
		failures.append("An enabled compass must disable on second toggle")

func _test_compass_route_advances_only_near_waypoints() -> void:
	var route: Array[Vector2] = [Vector2(100, 100), Vector2(300, 100), Vector2(500, 100)]
	var unchanged := UndergroundMaze.advance_compass_route(Vector2.ZERO, route, 0, 80.0)
	if unchanged != 0:
		failures.append("Compass route must not advance while the player is far from the next waypoint")
	var advanced := UndergroundMaze.advance_compass_route(Vector2(110, 100), route, 0, 80.0)
	if advanced != 1:
		failures.append("Compass route must advance after the player reaches the current waypoint")

func _test_route_distance_and_progress() -> void:
	var route: Array[Vector2] = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100)]
	var sample := UndergroundMaze.sample_route(Vector2(50, 20), route)
	if absf(float(sample.get("distance", 999.0)) - 20.0) > 0.1:
		failures.append("Route sampling must measure perpendicular distance to the polyline")
	if absf(float(sample.get("progress", -1.0)) - 0.25) > 0.01:
		failures.append("Route sampling progress must follow cumulative path length")

func _test_route_feedback_gain_is_obvious() -> void:
	var start_db := UndergroundMaze.route_volume_db(0.0)
	var exit_db := UndergroundMaze.route_volume_db(1.0)
	var linear_gain := db_to_linear(exit_db) / db_to_linear(start_db)
	if linear_gain < 4.0:
		failures.append("Exit route cue must be at least four times the start amplitude")
	if UndergroundMaze.route_interval(1.0) >= UndergroundMaze.route_interval(0.0):
		failures.append("Route cue cadence must accelerate toward the exit")

func _test_hidden_chest_completion_is_idempotent() -> void:
	var state := GameData.default_state()
	state["collected_keys"] = ["maze_key"]
	state["maze_compass_enabled"] = true
	if not GameData.open_hidden_chest(state):
		failures.append("Opening the hidden chest for the first time must start the ending")
	if not bool(state.get("hidden_chest_opened", false)) or not bool(state.get("finished", false)):
		failures.append("Opening the hidden chest must mark both the chest and profile complete")
	if bool(state.get("maze_compass_enabled", true)):
		failures.append("The compass must stop after the hidden chest is opened")
	var album_count: int = (state.get("album", []) as Array).size()
	if GameData.open_hidden_chest(state):
		failures.append("Opening the hidden chest repeatedly must not replay the ending")
	if (state.get("album", []) as Array).size() != album_count:
		failures.append("Repeated hidden-chest interaction must not duplicate album entries")

func _test_hidden_chest_requires_maze_key() -> void:
	var locked_state := GameData.default_state()
	if GameData.open_hidden_chest(locked_state):
		failures.append("The hidden chest must stay locked without the maze key")
	if bool(locked_state.get("hidden_chest_opened", false)) or bool(locked_state.get("ending_pending", false)):
		failures.append("A failed hidden-chest attempt must not mutate story progress")

	var unlocked_state := GameData.default_state()
	unlocked_state["collected_keys"] = ["key_1", "maze_key"]
	if not GameData.open_hidden_chest(unlocked_state):
		failures.append("The maze key must unlock the hidden chest")
	var remaining_keys: Array = unlocked_state.get("collected_keys", []) as Array
	if remaining_keys.has("maze_key") or not remaining_keys.has("key_1"):
		failures.append("Opening the hidden chest must consume only the maze key")

func _test_interrupted_ending_can_resume() -> void:
	var state := GameData.default_state()
	state["collected_keys"] = ["maze_key"]
	GameData.open_hidden_chest(state)
	if not bool(state.get("ending_pending", false)):
		failures.append("Opening the hidden chest must persist a pending ending before playback")
	GameData.migrate_state(state)
	if not GameData.begin_ending(state, "hidden_chest"):
		failures.append("A pending interrupted ending must be resumable")
	GameData.complete_ending(state)
	if bool(state.get("ending_pending", true)) or not bool(state.get("ending_seen", false)):
		failures.append("Completing the ending must clear pending state and mark it seen")

func _test_finished_profile_keeps_real_completion() -> void:
	var state := GameData.default_state()
	state["collected_keys"] = ["maze_key"]
	GameData.open_hidden_chest(state)
	var stats: Dictionary = ProfileManager.compute_stats(state)
	if int(stats.get("completion", 100)) >= 100:
		failures.append("Finishing the story must not force collection completion to 100 percent")

func _finish() -> void:
	if failures.is_empty():
		print("PASS: maze progression state checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
