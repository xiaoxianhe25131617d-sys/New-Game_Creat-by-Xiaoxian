extends Node

const GAME_DATA := preload("res://scripts/game_data.gd")

var failures: Array[String] = []


func _ready() -> void:
	var view_wheel_script := load("res://scripts/view_wheel_ui.gd") as GDScript
	if view_wheel_script == null:
		_fail("View wheel UI script must load")
		_finish()
		return

	var wheel := view_wheel_script.new() as Control
	wheel.call("configure", ["depression", "blind", "normal", "autism", "adhd"], "blind")
	add_child(wheel)
	await get_tree().process_frame

	_expect(wheel.anchor_right == 1.0 and wheel.anchor_bottom == 1.0, "View wheel must cover the viewport at every supported resolution")
	var panel := wheel.get_node_or_null("Center/Frame") as PanelContainer
	_expect(panel != null, "View wheel must render a centered frame")
	if panel != null:
		_expect(panel.custom_minimum_size.x <= 620.0, "View wheel frame must stay compact enough for the 1280x720 viewport")

	var buttons := wheel.find_children("View_*", "Button", true, false)
	_expect(buttons.size() == GAME_DATA.VIEWS.size(), "Every unlocked view must have one keyboard-focusable button")
	for index in buttons.size():
		_expect(buttons[index].name == "View_%s" % GAME_DATA.VIEWS[index], "View buttons must keep the canonical gameplay order")
	for button in buttons:
		_expect((button as Button).focus_mode == Control.FOCUS_ALL, "View buttons must support keyboard focus")

	var current_badge := wheel.find_child("CurrentView", true, false) as Label
	_expect(current_badge != null and current_badge.text.contains("盲人视角"), "Current view must be communicated with text, not color alone")
	var blind_button := wheel.find_child("View_blind", true, false) as Button
	var blind_title := blind_button.find_child("Title", true, false) as Label
	var blind_detail := blind_button.find_child("Detail", true, false) as Label
	_expect(blind_title != null and blind_title.text == "盲人视角", "Each view must have a concise title")
	_expect(blind_detail != null and blind_detail.text.contains("听觉"), "Each view must separate its effect into supporting text")
	var selected_views: Array[String] = []
	wheel.connect("view_selected", func(view: String): selected_views.append(view))
	blind_button.pressed.emit()
	_expect(selected_views == ["blind"], "Pressing a view button must emit the selected gameplay view")
	var close_requests: Array[bool] = []
	wheel.connect("close_requested", func(): close_requests.append(true))
	var close_button := wheel.find_child("CloseButton", true, false) as Button
	close_button.pressed.emit()
	_expect(close_requests.size() == 1, "The return button must use the shared close path")

	wheel.queue_free()
	await get_tree().process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: view wheel visual structure check")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
