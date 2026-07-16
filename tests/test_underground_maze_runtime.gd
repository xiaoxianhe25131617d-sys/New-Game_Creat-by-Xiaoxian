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
	await _test_wind_trigger_audio(locked_maze)
	if locked_maze.get_node_or_null("HiddenDoorCollision") == null:
		failures.append("Locked maze must create a physical hidden-door collision")
	if locked_maze.compass_button == null or not locked_maze.compass_button.disabled:
		failures.append("Locked maze must show the compass as unavailable")
	_test_key_marker_interaction(locked_maze)
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

func _test_wind_trigger_audio(maze: UndergroundMaze) -> void:
	var wind_line := maze.get_node_or_null("WindTriggerLine")
	if wind_line == null:
		failures.append("Runtime maze must include WindTriggerLine")
		return
	var wind_audio := wind_line.get_node_or_null("WindAudio") as AudioStreamPlayer
	if wind_audio == null:
		failures.append("WindTriggerLine must own a wind audio player")
		return
	if wind_audio.playing:
		failures.append("Wind audio must be silent before the player touches the line")
	maze._update_route_feedback(0.1)
	if maze.route_audio != null and maze.route_audio.playing:
		failures.append("The old hard-coded route must not play correct wind audio away from the line")
	wind_line.set("fade_duration", 0.01)
	maze.runtime_player.set_view("normal")
	wind_line.call("_on_body_entered", maze.runtime_player)
	await get_tree().create_timer(0.03).timeout
	if not bool(wind_line.call("is_player_touching")):
		failures.append("WindTriggerLine must retain physical contact in every view")
	if wind_audio.playing:
		failures.append("Non-blind views must not hear wind while touching WindTriggerLine")
	maze.runtime_player.set_view("blind")
	wind_line.call("_process", 0.01)
	await get_tree().create_timer(0.03).timeout
	if not wind_audio.playing:
		failures.append("Blind view must fade in wind while touching WindTriggerLine")
	if wind_audio.stream == null or wind_audio.stream.resource_path != "res://assets/audio/黑色迷宫正确声音.MP3":
		failures.append("WindTriggerLine must use the black-maze correct wind sound")
	maze.runtime_player.set_view("normal")
	wind_line.call("_process", 0.01)
	await get_tree().create_timer(0.03).timeout
	if wind_audio.playing:
		failures.append("Leaving blind view while still touching the line must fade out the wind")
	wind_line.call("_on_body_exited", maze.runtime_player)
	await get_tree().create_timer(0.03).timeout
	if bool(wind_line.call("is_player_touching")) or wind_audio.playing:
		failures.append("Leaving WindTriggerLine must fade out and stop the wind audio")

func _test_spawn_return_interaction(maze: UndergroundMaze) -> void:
	maze.runtime_player.global_position = maze.player_spawn.global_position
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

func _test_key_marker_interaction(maze: UndergroundMaze) -> void:
	var key_marker := maze.get_node_or_null("Markers/Key") as Marker2D
	var exit_marker := maze.get_node_or_null("Markers/PortalExit") as Marker2D
	if key_marker == null:
		failures.append("The maze key needs an authored Key marker")
		return
	if maze.maze_key_sprite == null or maze.maze_key_sprite.global_position.distance_to(key_marker.global_position) > 1.0:
		failures.append("The maze key visual must be anchored to the Key marker")
	if exit_marker != null:
		maze.runtime_player.global_position = exit_marker.global_position
		maze._update_maze_key_prompt()
		if (maze.maze_state.get("collected_keys", []) as Array).has("maze_key"):
			failures.append("Reaching the maze exit must not collect the key automatically")
	maze.runtime_player.global_position = key_marker.global_position
	var interact_event := InputEventAction.new()
	interact_event.action = "interact"
	interact_event.pressed = true
	maze._unhandled_input(interact_event)
	if not (maze.maze_state.get("collected_keys", []) as Array).has("maze_key"):
		failures.append("Pressing E beside the Key marker must collect the maze key")
	if maze.maze_key_sprite != null and maze.maze_key_sprite.visible:
		failures.append("The maze key visual must disappear after collection")

func _finish() -> void:
	if failures.is_empty():
		print("PASS: underground maze runtime checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
