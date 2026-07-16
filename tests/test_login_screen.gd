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
	ProfileManager.profiles = [{
		"id": "login_test",
		"display_name": "旅行者",
		"avatar": "sun",
		"state": source_state,
		"stats": ProfileManager.compute_stats(source_state),
	}]
	ProfileManager.current_profile_id = "login_test"
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
	var agreement_check := main.menu_root.find_child("AgreementCheckBox", true, false) as CheckBox
	var login_button := main.menu_root.find_child("LoginCurrentButton", true, false) as Button
	var create_button := main.menu_root.find_child("CreateProfileButton", true, false) as Button
	if agreement_check == null or login_button == null or create_button == null:
		_fail("Login screen must expose agreement controls")
		return
	if not login_button.disabled or not create_button.disabled:
		_fail("Profile entry actions must stay locked before agreement")
		return
	agreement_check.button_pressed = true
	agreement_check.toggled.emit(true)
	await get_tree().process_frame
	if login_button.disabled or create_button.disabled:
		_fail("Agreement checkbox must unlock profile entry actions")
		return
	if not main.has_method("show_agreement_document"):
		_fail("Agreement documents must be readable from the login screen")
		return
	main.show_agreement_document("privacy")
	await get_tree().process_frame
	if main.menu_root.find_child("AgreementDocument", true, false) == null:
		_fail("Privacy link must open a readable agreement document")
		return
	print("PASS: login screen startup check")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
