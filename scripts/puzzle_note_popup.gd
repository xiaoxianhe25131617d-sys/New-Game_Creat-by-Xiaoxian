extends CanvasLayer
class_name PuzzleNotePopup

signal closed

const BRAILLE_FONT := preload("res://assets/fonts/NotoSansSymbols2-Regular.ttf")

var _note: Dictionary = {}
var _view := "normal"
var _panel: Panel
var _body: Label
var _braille: Label
var _translation: Label
var _close_hint: Label

func open_note(note: Dictionary, view: String) -> void:
	_note = note
	_view = view
	layer = 1200
	_build()
	_update_content()
	visible = true

func _build() -> void:
	if _panel != null:
		return
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -340
	_panel.offset_top = -245
	_panel.offset_right = 340
	_panel.offset_bottom = 245
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e8d5a8")
	style.border_color = Color("#6e5135")
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var title := Label.new()
	title.text = "孩子留下的小纸条"
	title.position = Vector2(32, 24)
	title.size = Vector2(616, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("#4b3528"))
	_panel.add_child(title)

	_body = Label.new()
	_body.position = Vector2(58, 84)
	_body.size = Vector2(564, 120)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 22)
	_body.add_theme_color_override("font_color", Color("#3d2e28"))
	_panel.add_child(_body)

	_braille = Label.new()
	_braille.position = Vector2(58, 215)
	_braille.size = Vector2(564, 58)
	_braille.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_braille.add_theme_font_override("font", BRAILLE_FONT)
	_braille.add_theme_font_size_override("font_size", 27)
	_braille.add_theme_color_override("font_color", Color("#243f55"))
	_panel.add_child(_braille)

	_translation = Label.new()
	_translation.position = Vector2(58, 284)
	_translation.size = Vector2(564, 52)
	_translation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_translation.add_theme_font_size_override("font_size", 18)
	_translation.add_theme_color_override("font_color", Color("#37536c"))
	_panel.add_child(_translation)

	_close_hint = Label.new()
	_close_hint.position = Vector2(58, 392)
	_close_hint.size = Vector2(564, 30)
	_close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_hint.text = "按 E 继续"
	_close_hint.add_theme_font_size_override("font_size", 18)
	_close_hint.add_theme_color_override("font_color", Color("#76543b"))
	_panel.add_child(_close_hint)

func _update_content() -> void:
	_body.text = str(_note.get("text", ""))
	_braille.text = str(_note.get("braille", ""))
	_translation.text = "盲人视角：%s" % str(_note.get("translation", "")) if _view == "blind" and not str(_note.get("translation", "")).is_empty() else ""
	_braille.visible = not str(_note.get("braille", "")).is_empty()
	_translation.visible = not _translation.text.is_empty()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event is InputEventMouseButton:
		visible = false
		closed.emit()
		get_viewport().set_input_as_handled()
