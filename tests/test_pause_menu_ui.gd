extends Node

var failures: Array[String] = []


func _ready() -> void:
	var pause_menu_script := load("res://scripts/pause_menu_ui.gd") as GDScript
	if pause_menu_script == null:
		_fail("Pause menu UI script must load")
		_finish()
		return

	var menu := pause_menu_script.new() as Control
	menu.call("configure", true)
	add_child(menu)
	await get_tree().process_frame

	_expect(menu.anchor_right == 1.0 and menu.anchor_bottom == 1.0, "Pause menu must cover the viewport at every supported resolution")
	var frame := menu.find_child("Frame", true, false) as PanelContainer
	_expect(frame != null, "Pause menu must render a centered industrial frame")
	if frame != null:
		_expect(frame.custom_minimum_size.x <= 620.0, "Pause menu frame must stay compact inside the 1280x720 viewport")

	var title := menu.find_child("MenuTitle", true, false) as Label
	_expect(title != null and title.text.contains("旅途暂停"), "Pause menu must have a clear title")
	var buttons := menu.find_children("Action_*", "Button", true, false)
	_expect(buttons.size() == 5, "Debug builds must retain all five pause menu actions")
	for button in buttons:
		_expect((button as Button).focus_mode == Control.FOCUS_ALL, "Pause menu actions must support keyboard focus")

	var album_detail := menu.find_child("Detail_album", true, false) as Label
	_expect(album_detail != null and album_detail.text.contains("记忆"), "Pause actions must separate supporting text from their title")
	var emitted_actions: Array[String] = []
	menu.connect("resume_requested", func(): emitted_actions.append("resume"))
	menu.connect("album_requested", func(): emitted_actions.append("album"))
	menu.connect("notes_requested", func(): emitted_actions.append("notes"))
	menu.connect("debug_requested", func(): emitted_actions.append("debug"))
	menu.connect("save_exit_requested", func(): emitted_actions.append("save_exit"))
	for button in buttons:
		(button as Button).pressed.emit()
	_expect(emitted_actions == ["resume", "album", "notes", "debug", "save_exit"], "Pause menu actions must preserve their gameplay callbacks")

	menu.queue_free()
	await get_tree().process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: pause menu visual structure check")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
