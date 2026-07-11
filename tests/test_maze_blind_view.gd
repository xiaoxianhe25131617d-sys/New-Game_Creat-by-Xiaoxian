extends Node

const MAZE_SCENE_PATH := "res://maze/UndergroundMaze.tscn"

var failures: Array[String] = []

func _ready() -> void:
	var packed := load(MAZE_SCENE_PATH) as PackedScene
	var maze := packed.instantiate() if packed != null else null
	if maze == null:
		failures.append("Underground maze scene must load")
	else:
		add_child(maze)
		_test_default_blind_view(maze)
		maze.free()
	_finish()

func _test_default_blind_view(maze: Node) -> void:
	var player := maze.get_node_or_null("RuntimePlayer") as MindscapePlayer
	if player == null or player.current_view != "blind":
		failures.append("Maze runtime player must start in blind view")
	var canvas := maze.get_node_or_null("BlindVisionCanvas") as CanvasLayer
	var overlay := maze.get_node_or_null("BlindVisionCanvas/BlindVision") as ColorRect
	if canvas == null or canvas.follow_viewport_enabled:
		failures.append("Maze blind vision canvas must stay fixed to the screen")
	if overlay == null or not overlay.visible:
		failures.append("Maze must show the blind vision overlay by default")
	else:
		var material := overlay.material as ShaderMaterial
		if material == null or material.shader == null or material.shader.resource_path != "res://shaders/blind_vision.gdshader":
			failures.append("Maze blind view must use the shared blind vision shader")

func _finish() -> void:
	if failures.is_empty():
		print("PASS: maze blind view checks")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
