extends Node

func _ready() -> void:
	var source_state := GameData.default_state()
	var source_profile := {"id": "real", "display_name": "旅行者", "avatar": "sun", "state": source_state}
	var clone := ProfileManager.make_debug_clone(source_profile, source_state)
	var clone_state := clone.get("state", {}) as Dictionary
	if not bool(clone.get("is_debug_profile", false)) or not bool(clone_state.get("is_debug_profile", false)):
		_fail("Debug tools must create a clearly marked TEST profile")
		return
	clone_state["finished"] = true
	if bool(source_state.get("finished", false)):
		_fail("Debug profile progress must not mutate the real profile state")
		return
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
