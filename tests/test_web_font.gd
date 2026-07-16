extends Node

const EXPECTED_FONT_PATH := "res://assets/fonts/MindscapeWebFont.tres"
const BRAILLE_FONT_PATH := "res://assets/fonts/NotoSansSymbols2-Regular.ttf"
const REQUIRED_GLYPHS := ["心", "灵", "视", "界", "旅", "行", "者"]
const REQUIRED_UI_SYMBOLS := "◈"
const REQUIRED_BRAILLE := "⠕⠄⠝⠼⠂⠞⠡⠁⠙⠖⠆⠌⠅⠾⠢⠋⠔⠟⠥⠉⠺⠱⠣"

func _ready() -> void:
	var configured_path := str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	if configured_path != EXPECTED_FONT_PATH:
		_fail("Project custom font must point to the bundled composite web font")
		return
	if not ResourceLoader.exists(EXPECTED_FONT_PATH):
		_fail("Bundled composite web font resource is missing")
		return
	var font := load(EXPECTED_FONT_PATH) as Font
	if font == null:
		_fail("Bundled composite web font must load as a Font resource")
		return
	for glyph in REQUIRED_GLYPHS:
		if not font.has_char(glyph.unicode_at(0)):
			_fail("Bundled font is missing required glyph: %s" % glyph)
			return
	for glyph in REQUIRED_UI_SYMBOLS:
		if not font.has_char(glyph.unicode_at(0)):
			_fail("Bundled font is missing required UI symbol: %s" % glyph)
			return
	if not ResourceLoader.exists(BRAILLE_FONT_PATH):
		_fail("Bundled Braille font resource is missing")
		return
	var braille_font := load(BRAILLE_FONT_PATH) as Font
	if braille_font == null:
		_fail("Bundled Braille font must load as a Font resource")
		return
	for glyph in REQUIRED_BRAILLE:
		if not braille_font.has_char(glyph.unicode_at(0)):
			_fail("Bundled Braille font is missing required glyph: %s" % glyph)
			return
	var popup := PuzzleNotePopup.new()
	add_child(popup)
	popup.open_note({"text": "Web font check", "braille": REQUIRED_BRAILLE}, "normal")
	var popup_braille_font := popup._braille.get_theme_font("font")
	for glyph in REQUIRED_BRAILLE:
		if not popup_braille_font.has_char(glyph.unicode_at(0)):
			_fail("Puzzle note popup does not render required Braille glyph: %s" % glyph)
			return
	popup.free()
	var view_wheel := ViewWheelUI.new()
	view_wheel.configure(["normal"], "normal")
	add_child(view_wheel)
	var marker_label: Label = null
	for child in view_wheel.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null and label.text.begins_with(REQUIRED_UI_SYMBOLS):
			marker_label = label
			break
	if marker_label == null:
		_fail("View wheel marker label is missing")
		return
	if not marker_label.get_theme_font("font").has_char(REQUIRED_UI_SYMBOLS.unicode_at(0)):
		_fail("View wheel marker does not render required UI symbol: %s" % REQUIRED_UI_SYMBOLS)
		return
	view_wheel.free()
	print("PASS: bundled web fonts cover required Chinese, Braille, and UI symbols")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
