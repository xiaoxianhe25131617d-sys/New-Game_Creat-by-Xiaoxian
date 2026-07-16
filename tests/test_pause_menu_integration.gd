extends Node

var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main := load("res://scripts/main.gd").new() as Node
	main.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(main)
	await get_tree().process_frame

	var controls := CanvasLayer.new()
	main.add_child(controls)
	main.set("controls_canvas", controls)
	main.call("toggle_pause")
	await get_tree().process_frame

	var pause_menu := main.get("pause_root") as Control
	_expect(get_tree().paused, "Opening the pause menu must pause gameplay")
	_expect(pause_menu != null and pause_menu.get_parent() == controls, "Pause menu must stay on the controls canvas")
	var resume_button := pause_menu.find_child("Action_resume", true, false) as Button
	_expect(resume_button != null, "Pause menu must retain the continue action")
	if resume_button != null:
		resume_button.pressed.emit()
	await get_tree().process_frame
	_expect(not get_tree().paused and main.get("pause_root") == null, "Continue must close the menu and resume gameplay")
	if OS.is_debug_build():
		main.call("toggle_pause")
		await get_tree().process_frame
		pause_menu = main.get("pause_root") as Control
		var debug_button := pause_menu.find_child("Action_debug", true, false) as Button
		_expect(debug_button != null, "Debug builds must retain the test tools entry")
		if debug_button != null:
			debug_button.pressed.emit()
		await get_tree().process_frame
		var debug_panel := main.get("pause_root") as Control
		var debug_labels := debug_panel.find_children("*", "Label", true, false)
		var debug_title := debug_labels[0] as Label if not debug_labels.is_empty() else null
		_expect(debug_panel is Panel and debug_title != null and debug_title.text.contains("后期测试工具"), "Test tools must rebuild their legacy debug panel inside the new pause flow")
		main.call("toggle_pause")
		await get_tree().process_frame

	main.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	get_tree().paused = false
	if failures.is_empty():
		print("PASS: pause menu integration check")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
