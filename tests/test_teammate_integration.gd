extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_world_boundary_preserves_collectibles()
	_test_laser_attempts_include_misses()
	_test_laser_installation_has_one_owner()
	await _test_bird_stun_preserves_control_lock()
	_finish()

func _test_world_boundary_preserves_collectibles() -> void:
	if MindscapeWorld.RIGHT_BOUNDARY_X <= 10800.0:
		failures.append("Right world boundary must not block collectible_17")

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
	main.call("release_lasers_from_focus")
	if not bool(main.call("_can_drag", "laser_device_1")):
		failures.append("Laser device must return to inventory after focus puzzle")
	main.free()

func _test_bird_stun_preserves_control_lock() -> void:
	var main: Node = (load("res://scripts/main.gd") as Script).new()
	var player := MindscapePlayer.create()
	add_child(main)
	main.add_child(player)
	main.set("game_running", true)
	main.set("player", player)
	player.controls_enabled = false
	main.call("trigger_poop_stun", player)
	main.set("game_running", false)
	await get_tree().create_timer(0.6).timeout
	if player.controls_enabled:
		failures.append("Bird stun must not release another system's control lock")
	main.free()

func _finish() -> void:
	if failures.is_empty():
		print("PASS: teammate integration regression checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
