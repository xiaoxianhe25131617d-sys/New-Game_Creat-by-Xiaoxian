extends Node

var failures: Array[String] = []
var maze_scene: PackedScene = preload("res://maze/UndergroundMaze.tscn")

func _ready() -> void:
	await _test_locked_and_unlocked_runtime_states()
	_finish()

func _test_locked_and_unlocked_runtime_states() -> void:
	var locked_state := GameData.default_state()
	ProfileManager.save_state(locked_state)
	var locked_maze := maze_scene.instantiate() as UndergroundMaze
	add_child(locked_maze)
	await get_tree().process_frame
	if locked_maze.get_node_or_null("HiddenDoorCollision") == null:
		failures.append("Locked maze must create a physical hidden-door collision")
	if locked_maze.compass_button == null or not locked_maze.compass_button.disabled:
		failures.append("Locked maze must show the compass as unavailable")
	locked_maze.queue_free()
	await get_tree().process_frame

	var unlocked_state := GameData.default_state()
	GameData.unlock_hidden_door(unlocked_state)
	ProfileManager.save_state(unlocked_state)
	var unlocked_maze := maze_scene.instantiate() as UndergroundMaze
	add_child(unlocked_maze)
	await get_tree().process_frame
	if unlocked_maze.get_node_or_null("HiddenDoorCollision") != null:
		failures.append("Unlocked maze must remove the hidden-door collision")
	if unlocked_maze.compass_button == null or unlocked_maze.compass_button.disabled:
		failures.append("Unlocked maze must allow the compass to be toggled")
	unlocked_maze._toggle_compass()
	if not bool(unlocked_maze.maze_state.get("maze_compass_enabled", false)):
		failures.append("Compass toggle must persist the enabled state in the active profile")
	unlocked_maze.queue_free()
	await get_tree().process_frame

func _finish() -> void:
	if failures.is_empty():
		print("PASS: underground maze runtime checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
