extends Control
class_name ViewWheelUI

signal view_selected(view: String)
signal close_requested

const GAME_DATA := preload("res://scripts/game_data.gd")

const VIEW_DETAILS := {
	"normal": "保持清醒 · 感受世界原本的样子",
	"blind": "听觉与触觉 · 在黑暗中感知空间",
	"adhd": "持续前行 · 冲刺与跃动",
	"autism": "聚焦细节 · 识别隐藏模式",
	"depression": "察觉情绪 · 看见未说出口的话",
}

const VIEW_TITLES := {
	"normal": "普通视角",
	"blind": "盲人视角",
	"adhd": "ADHD 视角",
	"autism": "自闭症视角",
	"depression": "抑郁视角",
}

var _unlocked_views: Array = []
var _current_view := "normal"


func configure(unlocked_views: Array, current_view: String) -> void:
	_unlocked_views.clear()
	for view in GAME_DATA.VIEWS:
		if unlocked_views.has(view):
			_unlocked_views.append(view)
	_current_view = current_view


func _ready() -> void:
	name = "ViewWheel"
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
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	_build_header(layout)
	_build_current_view(layout)
	_build_view_list(layout)
	_build_footer(layout)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)

	var marker := Label.new()
	marker.text = "◈  感知校准台"
	marker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	marker.add_theme_font_size_override("font_size", 24)
	marker.add_theme_color_override("font_color", Color("#f1d39a"))
	header.add_child(marker)

	var code := Label.new()
	code.text = "PERSPECTIVE / 05"
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 11)
	code.add_theme_color_override("font_color", Color("#a9855f"))
	header.add_child(code)

	var subtitle := Label.new()
	subtitle.text = "选择一种方式，重新理解眼前的世界"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#bdb3a5"))
	parent.add_child(subtitle)

	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", _separator_style())
	parent.add_child(separator)


func _build_current_view(parent: VBoxContainer) -> void:
	var current := Label.new()
	current.name = "CurrentView"
	current.text = "当前感知  /  %s" % VIEW_TITLES.get(_current_view, _current_view)
	current.add_theme_font_size_override("font_size", 12)
	current.add_theme_color_override("font_color", Color("#d7bd8f"))
	parent.add_child(current)


func _build_view_list(parent: VBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.name = "ViewList"
	list.add_theme_constant_override("separation", 6)
	parent.add_child(list)
	if _unlocked_views.is_empty():
		var empty_state := Label.new()
		empty_state.text = "还没有理解新的视角。\n去灯塔区域触碰回声共鸣石吧。"
		empty_state.custom_minimum_size = Vector2(0.0, 92.0)
		empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_state.add_theme_font_size_override("font_size", 14)
		empty_state.add_theme_color_override("font_color", Color("#bdb3a5"))
		list.add_child(empty_state)
		return

	var first_button: Button = null
	var current_button: Button = null
	for view_variant in _unlocked_views:
		var view := str(view_variant)
		var button := _build_view_button(view, _unlocked_views.find(view_variant) + 1)
		list.add_child(button)
		if first_button == null:
			first_button = button
		if view == _current_view:
			current_button = button

	var focus_target := current_button if current_button != null else first_button
	if focus_target != null:
		focus_target.call_deferred("grab_focus")


func _build_view_button(view: String, index: int) -> Button:
	var accent: Color = GAME_DATA.VIEW_COLORS.get(view, Color("#d5aa72"))
	var is_current := view == _current_view
	var button := Button.new()
	button.name = "View_%s" % view
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s：%s" % [VIEW_TITLES.get(view, view), VIEW_DETAILS.get(view, "")]
	button.add_theme_stylebox_override("normal", _view_style(accent, is_current, false))
	button.add_theme_stylebox_override("hover", _view_style(accent, is_current, true))
	button.add_theme_stylebox_override("pressed", _view_style(accent, true, true))
	button.add_theme_stylebox_override("focus", _focus_style(accent))
	button.pressed.connect(func(): view_selected.emit(view))

	var content := HBoxContainer.new()
	content.name = "Content"
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

	var title := Label.new()
	title.name = "Title"
	title.text = str(VIEW_TITLES.get(view, view))
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#f1ece4"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(title)

	var detail := Label.new()
	detail.name = "Detail"
	detail.text = str(VIEW_DETAILS.get(view, ""))
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", Color("#aaa197"))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.add_child(detail)

	var status := Label.new()
	status.text = "当前" if is_current else "切换"
	status.custom_minimum_size.x = 42.0
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", accent if is_current else Color("#766f67"))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(status)
	return button


func _build_footer(parent: VBoxContainer) -> void:
	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", _separator_style())
	parent.add_child(separator)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	parent.add_child(footer)

	var hint := Label.new()
	hint.text = "↑↓ 选择  ·  Enter 确认"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("#948b80"))
	footer.add_child(hint)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "起身 / 返回"
	close_button.custom_minimum_size = Vector2(120.0, 36.0)
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.add_theme_font_size_override("font_size", 13)
	close_button.add_theme_color_override("font_color", Color("#d9c6a5"))
	close_button.add_theme_stylebox_override("normal", _small_button_style(false))
	close_button.add_theme_stylebox_override("hover", _small_button_style(true))
	close_button.add_theme_stylebox_override("pressed", _small_button_style(true))
	close_button.add_theme_stylebox_override("focus", _focus_style(Color("#cf9458")))
	close_button.pressed.connect(func(): close_requested.emit())
	footer.add_child(close_button)


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#17191bf2")
	style.border_color = Color("#9a6840")
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_color = Color("#00000099")
	style.shadow_size = 10
	return style


func _view_style(accent: Color, selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#292723f2") if selected else Color("#202225e8")
	if hovered:
		style.bg_color = Color("#34312bed")
	style.border_color = accent if selected or hovered else Color("#49443d")
	style.border_width_left = 3 if selected else 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(2)
	return style


func _small_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#3a2d23") if hovered else Color("#28231f")
	style.border_color = Color("#a16a3e") if hovered else Color("#65513f")
	style.set_border_width_all(1)
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
