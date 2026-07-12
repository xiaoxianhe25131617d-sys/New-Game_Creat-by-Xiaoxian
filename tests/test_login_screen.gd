extends Node

func _ready() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene must load without script parse errors")
		return
	var main := packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	if main.menu_root == null or not is_instance_valid(main.menu_root):
		_fail("Login screen must be created during startup")
		return
	if main.menu_root.find_children("*", "Label", true, false).is_empty():
		_fail("Login screen must contain visible UI content")
		return
	print("PASS: login screen startup check")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
