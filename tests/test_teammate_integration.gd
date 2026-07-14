extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_removed_world_boundary_stays_removed()
	_test_laser_attempts_include_misses()
	_test_laser_installation_has_one_owner()
	_test_player_interaction_lock()
	await _test_laser_unlock_cutscene_runs()
	_finish()

func _test_removed_world_boundary_stays_removed() -> void:
	var world := MindscapeWorld.new()
	add_child(world)
	world.build(GameData.default_state())
	if world.find_child("RightBoundary", true, false) != null:
		failures.append("The removed right-side invisible boundary must not return")
	world.free()

func _test_laser_attempts_include_misses() -> void:
	var puzzle: Node = (load("res://scripts/puzzle_laser_focus.gd") as Script).new()
	puzzle.call("_record_attempt", true)
	puzzle.call("_record_attempt", false)
	if int(puzzle.get("targets_hit")) != 1 or int(puzzle.get("targets_attempted")) != 2:
		failures.append("Laser score must count both hits and timed-out attempts")
	puzzle.free()

func _test_laser_installation_has_one_owner() -> void:
	var main: Node = (load("res://scripts/main.gd") as Script).new()
	main.set("state", GameData.default_state())
	main.set("laser_owned", {"laser_device_1": true, "laser_device_2": true})
	if not bool(main.call("install_laser_in_focus", 1)):
		failures.append("Owned laser device must install in an empty focus slot")
	elif bool(main.call("_can_drag", "laser_device_1")):
		failures.append("Laser device installed in focus puzzle must not remain draggable")
	elif bool(main.call("install_laser_in_focus", 1)):
		failures.append("Laser device must not install in two places at once")
	main.free()

func _test_player_interaction_lock() -> void:
	var player := MindscapePlayer.create()
	player.suspend_for_interaction()
	if player.controls_enabled:
		failures.append("Interaction suspension must keep player controls locked")
	player.resume_after_interaction()
	if not player.controls_enabled:
		failures.append("Interaction resume must restore player controls")
	player.free()

func _test_laser_unlock_cutscene_runs() -> void:
	var main: Node = (load("res://scripts/main.gd") as Script).new()
	add_child(main)
	var player := MindscapePlayer.create()
	main.add_child(player)
	main.set("player", player)
	Engine.time_scale = 20.0
	await main.call("_play_hidden_door_cutscene")
	Engine.time_scale = 1.0
	await get_tree().process_frame
	if player == null or not player.controls_enabled:
		failures.append("Laser unlock cutscene must restore player controls")
	if main.get_node_or_null("LaserUnlockCutscene") != null:
		failures.append("Laser unlock cutscene must clean up its overlay")
	main.free()

func _finish() -> void:
	if failures.is_empty():
		print("PASS: teammate integration regression checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
