extends Node

var failures: Array[String] = []

func _ready() -> void:
	await _test_memory_bench_opens_view_wheel()
	if failures.is_empty():
		print("PASS: memory bench view switch integration check")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_memory_bench_opens_view_wheel() -> void:
	var main := load("res://scripts/main.gd").new() as Node
	add_child(main)
	var state := GameData.default_state().duplicate(true)
	var world := MindscapeWorld.new()
	main.add_child(world)
	world.build(state)
	var player := MindscapePlayer.create()
	player.global_position = GameData.PLAYER_START
	main.add_child(player)
	player.add_to_group("player")
	var dialogue := DialogueBox.new()
	main.add_child(dialogue)
	main.set("state", state)
	main.set("world", world)
	main.set("player", player)
	main.set("dialogue", dialogue)
	main.call("_make_hud")
	if world == null or player == null or world.anchor_nodes.is_empty():
		failures.append("Main game must create a player and memory bench anchors")
		main.free()
		return
	main.call("rest_at_anchor", world.anchor_nodes[0])
	await get_tree().create_timer(0.55).timeout
	var wheel := main.get("wheel_root") as Control
	var controls := main.get("controls_canvas") as CanvasLayer
	if wheel == null:
		failures.append("Pressing E at a memory bench must create the view wheel")
	elif controls == null or wheel.get_parent() != controls:
		failures.append("View wheel must be attached to the controls canvas")
	elif not wheel.visible:
		failures.append("View wheel must remain visible after memory bench interaction")
	main.free()
