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
	_test_underground_audio(locked_maze)
	if locked_maze.get_node_or_null("HiddenDoorCollision") == null:
		failures.append("Locked maze must create a physical hidden-door collision")
	if locked_maze.compass_button == null or not locked_maze.compass_button.disabled:
		failures.append("Locked maze must show the compass as unavailable")
	_test_spawn_return_interaction(locked_maze)
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
	unlocked_maze.runtime_player.global_position = Vector2(1700, 1120)
	unlocked_maze._update_compass(1.0)
	if unlocked_maze.compass_heading_label == null or unlocked_maze.compass_heading_label.text != "偏离路线":
		failures.append("Compass must show a clear warning when the player leaves its walkable route")
	unlocked_maze.queue_free()
	await get_tree().process_frame
	AudioManager.resume_view_bgm()
	if AudioManager.bgm_player == null or not AudioManager.bgm_player.playing:
		failures.append("Leaving the underground maze must allow the saved view BGM to resume")
	AudioManager.stop_bgm()

func _test_underground_audio(maze: UndergroundMaze) -> void:
	var maze_bgm := maze.get_node_or_null("MazeBGM") as AudioStreamPlayer
	if maze_bgm == null:
		failures.append("Underground maze must own its single dedicated BGM player")
	else:
		if maze_bgm.stream == null or maze_bgm.stream.resource_path != "res://assets/audio/地下迷宫音乐.MP3":
			failures.append("Underground maze must use the dedicated maze music and no view BGM")
		if absf(maze_bgm.volume_db - (-27.0)) > 0.01:
			failures.append("Underground maze BGM must stay quiet at -27 dB")
	if AudioManager.bgm_player != null and AudioManager.bgm_player.playing:
		failures.append("Ground view BGM must be stopped while the underground maze is active")
	AudioManager.set_view("adhd")
	if AudioManager.bgm_player != null and AudioManager.bgm_player.playing:
		failures.append("Changing views underground must not restart a ground view BGM")
	if not AudioManager.has_method("stop_bgm") or not AudioManager.has_method("resume_view_bgm"):
		failures.append("AudioManager must expose explicit stop/resume controls for scene transitions")

func _test_spawn_return_interaction(maze: UndergroundMaze) -> void:
	var interact_event := InputEventAction.new()
	interact_event.action = "interact"
	interact_event.pressed = true
	maze._unhandled_input(interact_event)
	var saved_state := ProfileManager.get_current_profile().get("state", {}) as Dictionary
	if not maze._leaving_maze:
		failures.append("Pressing E at the maze spawn must start the return transition")
	if not bool(saved_state.get("return_to_game", false)):
		failures.append("Returning from the maze spawn must resume the ground game")
	var return_position := saved_state.get("position", Vector2.ZERO) as Vector2
	if not return_position.is_equal_approx(UndergroundMaze.MAIN_RETURN_POSITION):
		failures.append("Maze spawn exit must return beside the overworld underground entrance")

func _finish() -> void:
	if failures.is_empty():
		print("PASS: underground maze runtime checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
