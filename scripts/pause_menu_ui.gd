extends Control
class_name PauseMenuUI

signal resume_requested
signal album_requested
signal notes_requested
signal debug_requested
signal save_exit_requested

const ACTIONS := [
	{"id": "resume", "title": "继续旅途", "detail": "返回眼前的世界"},
	{"id": "album", "title": "纪念相册", "detail": "回看旅途中收集的记忆"},
	{"id": "notes", "title": "纸条日志", "detail": "整理已经发现的线索与文字"},
	{"id": "debug", "title": "后期测试工具", "detail": "仅调试版本可用"},
	{"id": "save_exit", "title": "保存并返回", "detail": "保存当前进度并回到主菜单"},
]

var _show_debug := false


func configure(show_debug: bool) -> void:
	_show_debug = show_debug


func _ready() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_backdrop()
	_build_frame()


func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color("#090b0d9c")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)


func _build_frame() -> void:
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 20.0
	center.offset_right = -24.0
	center.offset_bottom = -20.0
	add_child(center)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2(580.0, 0.0)
	frame.add_theme_stylebox_override("panel", _frame_style())
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	frame.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	_build_header(layout)
	_build_actions(layout)
	_build_footer(layout)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)

	var title := Label.new()
	title.name = "MenuTitle"
	title.text = "◇  旅途暂停"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#f1d39a"))
	header.add_child(title)

	var code := Label.new()
	code.text = "PAUSE / SYSTEM"
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 11)
	code.add_theme_color_override("font_color", Color("#a9855f"))
	header.add_child(code)

	var subtitle := Label.new()
	subtitle.text = "整理记忆，然后继续向前"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#bdb3a5"))
	parent.add_child(subtitle)

	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", _separator_style())
	parent.add_child(separator)

	var status := Label.new()
	status.text = "系统状态  /  游戏已暂停"
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("#d7bd8f"))
	parent.add_child(status)


func _build_actions(parent: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.name = "ActionList"
	list.add_theme_constant_override("separation", 6)
	parent.add_child(list)

	var visible_index := 0
	var first_button: Button = null
	for action_variant in ACTIONS:
		var action: Dictionary = action_variant
		if action["id"] == "debug" and not _show_debug:
			continue
		visible_index += 1
		var button := _build_action_button(action, visible_index)
		list.add_child(button)
		if first_button == null:
			first_button = button
	if first_button != null:
		first_button.call_deferred("grab_focus")


func _build_action_button(action: Dictionary, index: int) -> Button:
	var action_id := str(action["id"])
	var accent := _action_accent(action_id)
	var button := Button.new()
	button.name = "Action_%s" % action_id
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s：%s" % [action["title"], action["detail"]]
	button.add_theme_stylebox_override("normal", _action_style(accent, action_id == "resume", false))
	button.add_theme_stylebox_override("hover", _action_style(accent, true, true))
	button.add_theme_stylebox_override("pressed", _action_style(accent, true, true))
	button.add_theme_stylebox_override("focus", _focus_style(accent))
	button.pressed.connect(func(): _emit_action(action_id))

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14.0
	content.offset_right = -14.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	button.add_child(content)

	var number := Label.new()
	number.text = "%02d" % index
	number.custom_minimum_size.x = 26.0
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 12)
	number.add_theme_color_override("font_color", accent)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(number)

	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	text_stack.add_theme_constant_override("separation", 0)
	text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text_stack)

	var action_title := Label.new()
	action_title.text = str(action["title"])
	action_title.add_theme_font_size_override("font_size", 16)
	action_title.add_theme_color_override("font_color", Color("#f1ece4"))
	action_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(action_title)

	var detail := Label.new()
	detail.name = "Detail_%s" % action_id
	detail.text = str(action["detail"])
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", Color("#aaa197"))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(detail)

	var cue := Label.new()
	cue.text = "返回" if action_id == "resume" else "打开"
	if action_id == "save_exit":
		cue.text = "保存"
	cue.custom_minimum_size.x = 42.0
	cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cue.add_theme_font_size_override("font_size", 11)
	cue.add_theme_color_override("font_color", accent)
	cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cue)
	return button


func _build_footer(parent: VBoxContainer) -> void:
	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", _separator_style())
	parent.add_child(separator)
	var hint := Label.new()
	hint.text = "↑↓ 选择  ·  Enter 确认"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("#948b80"))
	parent.add_child(hint)


func _emit_action(action_id: String) -> void:
	match action_id:
		"resume": resume_requested.emit()
		"album": album_requested.emit()
		"notes": notes_requested.emit()
		"debug": debug_requested.emit()
		"save_exit": save_exit_requested.emit()


func _action_accent(action_id: String) -> Color:
	match action_id:
		"resume": return Color("#f1d39a")
		"debug": return Color("#8dcbd0")
		"save_exit": return Color("#cf8a65")
		_: return Color("#b7a98f")


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#17191bf2")
	style.border_color = Color("#9a6840")
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_color = Color("#00000099")
	style.shadow_size = 10
	return style


func _action_style(accent: Color, emphasized: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#302d27f2") if emphasized else Color("#202225e8")
	if hovered:
		style.bg_color = Color("#39342ced")
	style.border_color = accent if emphasized or hovered else Color("#49443d")
	style.border_width_left = 3 if emphasized else 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(2)
	return style


func _focus_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#00000000")
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	return style


func _separator_style() -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = Color("#6f5137")
	style.thickness = 1
	return style
