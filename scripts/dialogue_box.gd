extends CanvasLayer
class_name DialogueBox

signal closed

var panel: Panel
var name_label: Label
var text_label: Label
# ── Texture portrait (replaces ColorRect blocks when a texture exists) ──
var portrait_tex: TextureRect
# ── Fallback: simple ColorRect portrait when no texture is available ──
var portrait_bg: ColorRect
var portrait_head: ColorRect
var portrait_body: ColorRect
var portrait_face: Label
var active_lines: Array = []
var line_index: int = 0
var current_npc: Dictionary = {}
var current_view: String = "normal"
var subtext_label: Label

# Portrait texture paths, set by main.gd
# Expected per-NPC expression files: "res://assets/portraits/<npc_id>_<expr>.png"
const PORTRAIT_DIR := "res://assets/portraits"


func _ready() -> void:
	layer = 30
	visible = false
	
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = -230
	panel.offset_bottom = -20
	# Semi-transparent dark background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	panel_style.set_corner_radius_all(16)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.5, 0.55, 0.6)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	
	# ── TEXTURE PORTRAIT (primary — shown when image exists) ──
	portrait_tex = TextureRect.new()
	portrait_tex.name = "PortraitTex"
	portrait_tex.position = Vector2(12, 8)
	portrait_tex.size = Vector2(150, 190)
	portrait_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_tex.visible = false
	panel.add_child(portrait_tex)
	
	# ── FALLBACK: ColorRect portrait (shown when no texture) ──
	portrait_bg = ColorRect.new()
	portrait_bg.position = Vector2(20, 16)
	portrait_bg.size = Vector2(120, 140)
	panel.add_child(portrait_bg)
	
	portrait_head = ColorRect.new()
	portrait_head.position = Vector2(34, 24)
	portrait_head.size = Vector2(52, 54)
	panel.add_child(portrait_head)
	
	portrait_body = ColorRect.new()
	portrait_body.position = Vector2(22, 80)
	portrait_body.size = Vector2(76, 40)
	panel.add_child(portrait_body)
	
	portrait_face = Label.new()
	portrait_face.position = Vector2(40, 22)
	portrait_face.size = Vector2(40, 50)
	portrait_face.add_theme_font_size_override("font_size", 26)
	portrait_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(portrait_face)
	
	# Name — starts right of portrait area
	name_label = Label.new()
	name_label.position = Vector2(175, 16)
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	panel.add_child(name_label)
	
	# Dialogue text — below name, with word wrap
	text_label = Label.new()
	text_label.position = Vector2(175, 52)
	text_label.size = Vector2(750, 120)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 22)
	text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.88))
	text_label.custom_minimum_size = Vector2(750, 0)
	panel.add_child(text_label)

	# 潜台词行：只在抑郁视角且线条带 subtext 时显示
	subtext_label = Label.new()
	subtext_label.position = Vector2(175, 116)
	subtext_label.size = Vector2(750, 72)
	subtext_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtext_label.add_theme_font_size_override("font_size", 20)
	subtext_label.add_theme_color_override("font_color", Color("#f0df9a"))
	subtext_label.custom_minimum_size = Vector2(750, 0)
	subtext_label.visible = false
	panel.add_child(subtext_label)


func open(npc: Dictionary, lines: Array, view: String) -> void:
	current_npc = npc
	active_lines = lines
	current_view = view
	line_index = 0
	visible = true
	show_line()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("advance_dialogue"):
		line_index += 1
		if line_index >= active_lines.size():
			visible = false
			closed.emit()
		else:
			show_line()
		get_viewport().set_input_as_handled()


func show_line() -> void:
	var line: Dictionary = active_lines[line_index]
	
	# Name
	name_label.text = current_npc.get("name", "???")
	
	# Text — handle sign_only NPC with autism view (pattern recognition)
	var text: String = str(line.get("text", "..."))
	var subtext: String = str(line.get("subtext", ""))
	if current_npc.get("sign_only", false):
		if current_view == "autism":
			text = str(line.get("text_autism", text)) if line.has("text_autism") else text
		else:
			text = "她用手语比划着……你看不懂那些手势。"
	
	# Blind NPC special: text hint
	if current_npc.get("blind_npc", false) and current_view != "blind":
		text = "他的眼睛不追随你，但声音温和。"
	
	text_label.text = text
	if is_instance_valid(subtext_label):
		var show_subtext := current_view == "depression" and not subtext.is_empty()
		subtext_label.visible = show_subtext
		subtext_label.text = ("潜台词：%s" % subtext) if show_subtext else ""
	
	# Draw portrait — try texture first, fallback to ColorRect
	var expr: String = line.get("expr", "normal")
	var npc_id: String = current_npc.get("id", "")
	_try_load_portrait_texture(npc_id, expr)


# ─── PORTRAIT LOADING ───────────────────────────────
# Looks for: res://assets/portraits/<npc_id>_<expr>.png
# Falls back: res://assets/portraits/<npc_id>_normal.png
# If neither exists → uses ColorRect fallback

func _try_load_portrait_texture(npc_id: String, expr: String) -> void:
	if npc_id.is_empty():
		_use_fallback_portrait()
		return
	
	# Build paths to try
	var paths := [
		PORTRAIT_DIR + "/" + npc_id + "_" + expr + ".png",
		PORTRAIT_DIR + "/" + npc_id + "_normal.png",
	]
	
	for path in paths:
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				portrait_tex.texture = tex
				portrait_tex.visible = true
				_hide_fallback_portrait()
				return
	
	# No texture found → use ColorRect fallback
	_use_fallback_portrait()


func _use_fallback_portrait() -> void:
	portrait_tex.visible = false
	_hide_fallback_portrait()  # reset visibility
	portrait_bg.visible = true
	portrait_head.visible = true
	portrait_body.visible = true
	portrait_face.visible = true
	var color := Color(current_npc.get("portrait", "#ffffff"))
	var expr: String = ""
	if line_index < active_lines.size():
		expr = active_lines[line_index].get("expr", "normal")
	update_portrait(color, expr, current_npc.get("blind_npc", false))


func _hide_fallback_portrait() -> void:
	portrait_bg.visible = false
	portrait_head.visible = false
	portrait_body.visible = false
	portrait_face.visible = false


func update_portrait(color: Color, expression: String, blind_npc: bool) -> void:
	portrait_bg.color = color.darkened(0.3)
	portrait_head.color = color.lightened(0.15)
	portrait_body.color = color
	
	if blind_npc:
		portrait_face.text = "--"
	else:
		portrait_face.text = {
			"happy": "^_^",
			"sad": ";_;",
			"thinking": "o_O",
			"surprised": "O_O",
		}.get(expression, "·_·")
