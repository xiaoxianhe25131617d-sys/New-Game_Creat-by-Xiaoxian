extends Node

const MAZE_SCENE_PATH := "res://maze/UndergroundMaze.tscn"

var failures: Array[String] = []

func _ready() -> void:
	var packed := load(MAZE_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("Underground maze scene must load")
	else:
		var blind_state := GameData.default_state()
		blind_state["current_view"] = "blind"
		ProfileManager.save_state(blind_state)
		var blind_maze := packed.instantiate()
		add_child(blind_maze)
		_test_blind_view(blind_maze)
		blind_maze.free()

		var normal_state := GameData.default_state()
		normal_state["current_view"] = "normal"
		ProfileManager.save_state(normal_state)
		var normal_maze := packed.instantiate()
		add_child(normal_maze)
		_test_non_blind_underground_view(normal_maze)
		normal_maze.free()
	_finish()

func _test_blind_view(maze: Node) -> void:
	var player := maze.get_node_or_null("RuntimePlayer") as MindscapePlayer
	if player == null or player.current_view != "blind":
		failures.append("Maze must preserve a blind view selected before entering")
	var canvas := maze.get_node_or_null("BlindVisionCanvas") as CanvasLayer
	var overlay := maze.get_node_or_null("BlindVisionCanvas/BlindVision") as ColorRect
	if canvas == null or canvas.follow_viewport_enabled:
		failures.append("Maze blind vision canvas must stay fixed to the screen")
	if overlay == null or not overlay.visible:
		failures.append("Maze must show its vision overlay in blind view")
	else:
		var material := overlay.material as ShaderMaterial
		if material == null or material.shader == null or material.shader.resource_path != "res://shaders/blind_vision.gdshader":
			failures.append("Maze blind view must use the shared blind vision shader")

func _test_non_blind_underground_view(maze: Node) -> void:
	var player := maze.get_node_or_null("RuntimePlayer") as MindscapePlayer
	if player == null or player.current_view != "normal":
		failures.append("Maze must preserve a non-blind view selected before entering")
	var overlay := maze.get_node_or_null("BlindVisionCanvas/BlindVision") as ColorRect
	var material := overlay.material as ShaderMaterial if overlay != null else null
	if material == null or material.shader == null or material.shader.resource_path != "res://shaders/underground_darkness.gdshader":
		failures.append("Non-blind underground views must keep the circular darkness shader")

func _finish() -> void:
	if failures.is_empty():
		print("PASS: maze blind view checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
