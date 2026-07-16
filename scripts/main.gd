extends Node

const MAZE_COMPASS_TEXTURE := preload("res://assets/ui/generated/maze_compass.png")
const HIDDEN_DOOR_TEXTURE := preload("res://assets/ui/generated/hidden_stone_door.png")
const UNDERGROUND_ENTRY_AUDIO := preload("res://assets/audio/enter_underground_maze.MP3")
const UNDERGROUND_STAIR_TRANSITION := preload("res://scenes/UndergroundStairTransition.tscn")
const MAIN_WORLD_SCENE := preload("res://map/MainWorld.tscn")
const MENU_BG_TEXTURE := preload("res://assets/town/town_street_background.png")
const INTRO_COMIC_TEXTURE := preload("res://assets/intro_comic.png")
const INTRO_DOCTOR_TEXTURE := preload("res://assets/characters/generated/doctor_handdrawn_spritesheet.png")
const PUZZLE_NOTE_POPUP_SCRIPT := preload("res://scripts/puzzle_note_popup.gd")
const VIEW_WHEEL_UI_SCRIPT := preload("res://scripts/view_wheel_ui.gd")
const PAUSE_MENU_UI_SCRIPT := preload("res://scripts/pause_menu_ui.gd")
const CAMERA_VIEW_OFFSET := Vector2(0.0, 28.0)

var world: MindscapeWorld
var player: MindscapePlayer
var camera: Camera2D
var hud: CanvasLayer
var inventory_canvas: CanvasLayer
var controls_canvas: CanvasLayer
var dialogue: DialogueBox
var note_popup: CanvasLayer
var state: Dictionary
var current_near: Node2D = null
var game_running: bool = false
var save_timer: float = 0.0
var menu_root: Control
var pause_root: Control
var wheel_root: Control
var hud_label: Label
var prompt_label: Label
var objective_label: Label
var monster_hint_cooldown: float = 0.0
var active_toast: Label
var active_toast_tween: Tween
var login_name_input: LineEdit
var agreement_check_box: CheckBox
var login_current_button: Button
var create_profile_button: Button
var agreement_hint_label: Label
var opening_root: Control
var opening_art: TextureRect
var opening_caption: Label
var opening_speaker: Label
var opening_portrait: TextureRect
var opening_progress: Label
var opening_phase_index: int = 0
var opening_phase_elapsed: float = 0.0
var opening_phase_duration: float = 4.6
var opening_phase_regions: Array = [
	Rect2(0, 0, 250, 164), Rect2(0, 164, 250, 164),
	Rect2(0, 328, 250, 164), Rect2(0, 492, 250, 164),
	Rect2(0, 656, 250, 164), Rect2(0, 820, 250, 164),
	Rect2(0, 984, 250, 164), Rect2(0, 1148, 250, 162),
]
var opening_phase_lines: Array = [
	["发明家 · 米洛", "我想做一顶头盔，让人真正看见另一个人眼里的世界。"],
	["发明家 · 米洛", "放下镜片，世界会换一种方式回来。"],
	["记录员", "消息传开以后，四个很久没见的孩子重新走到了一起。"],
	["盲人朋友", "如果长椅还能把我们接回去，也许那份宝藏还在等我们。"],
	["聋人朋友", "我们不必用同一种方式理解，只要愿意一起看。"],
	["四位朋友", "头盔亮起来的那一刻，童年的路又在眼前展开。"],
	["记忆花园", "每一种感知，都会照亮一条别人看不见的路。"],
	["心灵视界", "故事从这里开始。点击画面继续。"],
]
var opening_active: bool = false
var damage_overlay: ColorRect  # red flash on monster hit
var damage_tween: Tween  # for damage overlay animation
var _ladder_space_was_held: bool = false  # 梯子跳跃：检测 Space 刚按下的边沿

# ── 侧边物品栏 + 拖放系统 ──
var sidebar: Panel          # 左侧物品栏面板
var inv_slots: Dictionary = {}  # {item_id: Panel}
var dragging: bool = false
var drag_item_id: String = ""
var drag_preview: Panel
var drag_mouse_offset: Vector2
var laser_owned: Dictionary = {"laser_device_1": false, "laser_device_2": false}
var _laser_unlock_cutscene_played: bool = false
var _maze_compass_texture: Texture2D = null
var _hidden_door_texture: Texture2D = null

# ── 拖放/激光常量 ──
const LASER_ANGLE_STEP: float = 0.03  # 滚轮旋转步长(rad)
const REQUIRED_KEY_COUNT: int = 3

func _ready() -> void:
	add_to_group("main")
	AudioManager.resume_view_bgm()
	_load_runtime_assets()
	if get_tree().has_meta("mindscape_open_profiles_after_ending"):
		get_tree().remove_meta("mindscape_open_profiles_after_ending")
		call_deferred("show_profile_menu")
		return
	var profile: Dictionary = ProfileManager.get_current_profile()
	var saved_state: Dictionary = profile.get("state", {}) as Dictionary
	if bool(saved_state.get("return_to_game", false)):
		saved_state["return_to_game"] = false
		ProfileManager.save_state(saved_state)
		call_deferred("start_game", false)
	elif int(saved_state.get("opening_version", 0)) < 2:
		call_deferred("show_opening_cinematic")
	else:
		show_login_screen()

func _process(delta: float) -> void:
	if opening_active:
		_update_opening_cinematic(delta)
		return
	if not game_running:
		return
	state["play_time"] = float(state.get("play_time", 0.0)) + delta
	monster_hint_cooldown = maxf(0.0, monster_hint_cooldown - delta)
	save_timer += delta
	if save_timer >= 10.0:
		save_timer = 0.0
		autosave()
	current_near = world.nearest_interactable(player.global_position)
	_update_ladder_climb(delta)
	_check_monsters()
	_update_hud()
	_update_audio_region()

func _load_runtime_assets() -> void:
	if _maze_compass_texture == null:
		_maze_compass_texture = MAZE_COMPASS_TEXTURE
	if _hidden_door_texture == null:
		_hidden_door_texture = HIDDEN_DOOR_TEXTURE

func _hide_login_comic_preview() -> void:
	if is_instance_valid(menu_root):
		var comic_preview := menu_root.find_child("ComicPreview", true, false)
		if is_instance_valid(comic_preview):
			comic_preview.queue_free()

func _build_menu_root(tint: Color, frame_glow: Color) -> Control:
	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := TextureRect.new()
	bg.name = "MenuBackground"
	bg.texture = MENU_BG_TEXTURE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(bg)

	var overlay := ColorRect.new()
	overlay.name = "MenuOverlay"
	overlay.color = tint
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)

	var glow := ColorRect.new()
	glow.name = "MenuGlow"
	glow.color = frame_glow
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(glow)
	return root

func _menu_frame_style(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 10
	return style

func _menu_button_style(accent: Color, hovered: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1f29e6") if not hovered else Color("#263245f2")
	style.border_color = accent
	style.set_border_width_all(2 if hovered else 1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 4
	return style

func _make_header_label(text: String, size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	return label

func _make_chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _menu_frame_style(Color("#111620cc"), color, 999))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(margin)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color.lightened(0.2))
	margin.add_child(label)
	return chip

func _set_panel_padding(node: Control, left: int, top: int, right: int, bottom: int) -> void:
	if node is MarginContainer:
		node.add_theme_constant_override("margin_left", left)
		node.add_theme_constant_override("margin_top", top)
		node.add_theme_constant_override("margin_right", right)
		node.add_theme_constant_override("margin_bottom", bottom)

func _build_profile_stat_row(name: String, value: String, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var key := Label.new()
	key.text = name
	key.custom_minimum_size = Vector2(88, 0)
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Color("#ccbca0"))
	row.add_child(key)
	var val := Label.new()
	val.text = value
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", accent)
	row.add_child(val)
	return row

func _build_profile_card(profile: Dictionary) -> Button:
	var stats: Dictionary = profile.get("stats", {})
	var profile_state: Dictionary = profile.get("state", {}) as Dictionary
	var finished := bool(profile_state.get("finished", false))
	var avatar := str(profile.get("avatar", "sun"))
	var accent_map: Dictionary = {
		"sun": Color("#f0c98a"),
		"moon": Color("#a8d0ff"),
		"leaf": Color("#9bd8a2"),
	}
	var accent: Color = accent_map.get(avatar, Color("#f0c98a")) as Color
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 116)
	button.add_theme_stylebox_override("normal", _menu_button_style(accent, false))
	button.add_theme_stylebox_override("hover", _menu_button_style(accent, true))
	button.add_theme_stylebox_override("pressed", _menu_button_style(accent.darkened(0.15), true))
	button.add_theme_stylebox_override("focus", _menu_button_style(accent.lightened(0.12), true))
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func():
		ProfileManager.set_current_profile(str(profile.get("id", "")))
		if ProfileManager.current_profile_has_accepted_agreement():
			show_main_menu()
		else:
			show_login_screen()
	)

	var shell := HBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 16.0
	shell.offset_right = -16.0
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_theme_constant_override("separation", 14)
	button.add_child(shell)

	var avatar_box := PanelContainer.new()
	avatar_box.custom_minimum_size = Vector2(80, 80)
	avatar_box.add_theme_stylebox_override("panel", _menu_frame_style(Color("#141a22d8"), accent))
	shell.add_child(avatar_box)
	var avatar_margin := MarginContainer.new()
	avatar_margin.add_theme_constant_override("margin_left", 10)
	avatar_margin.add_theme_constant_override("margin_top", 8)
	avatar_margin.add_theme_constant_override("margin_right", 10)
	avatar_margin.add_theme_constant_override("margin_bottom", 8)
	avatar_box.add_child(avatar_margin)
	var avatar_label := Label.new()
	avatar_label.text = {"sun": "☀", "moon": "☾", "leaf": "❧"}.get(avatar, "◎")
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.add_theme_font_size_override("font_size", 34)
	avatar_label.add_theme_color_override("font_color", accent)
	avatar_margin.add_child(avatar_label)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 4)
	shell.add_child(text_col)
	var title := Label.new()
	title.text = "%s%s" % [str(profile.get("display_name", "旅行者")), "  ·  已通关" if finished else ""]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#f7ebd6"))
	text_col.add_child(title)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 12)
	text_col.add_child(stats_row)
	stats_row.add_child(_make_chip("完成度 %d%%" % int(stats.get("completion", 0)), accent))
	stats_row.add_child(_make_chip("相册 %d" % int(stats.get("album_count", 0)), Color("#b9d6ff")))
	stats_row.add_child(_make_chip("游玩 %s" % _format_time(stats.get("play_time", 0.0)), Color("#d8c6a2")))
	var updated := Label.new()
	updated.text = "上次记录：%s" % profile.get("updated_at", "—")
	updated.add_theme_font_size_override("font_size", 11)
	updated.add_theme_color_override("font_color", Color("#a6a08f"))
	text_col.add_child(updated)
	return button

# ═══════════════════════════════════════════════════════
#  梯子爬行：玩家在梯子内时禁用重力，按 W/↑ 持续上移，按 S/↓ 持续下移
# ═══════════════════════════════════════════════════════
func _update_ladder_climb(delta: float) -> void:
	if player == null or not is_instance_valid(player): return
	var ladder: Area2D = world.get_ladder_at_point(player.global_position)
	if ladder == null:
		player.is_on_ladder = false
		return

	# 跳跃：按 Space 时直接脱离梯子，赋予向上速度（沿用玩家 JUMP_VELOCITY）
	var space_just: bool = Input.is_action_just_pressed("jump") or (Input.is_key_pressed(KEY_SPACE) and not _ladder_space_was_held)
	_ladder_space_was_held = Input.is_key_pressed(KEY_SPACE)
	if space_just:
		player.is_on_ladder = false
		player.velocity.y = -580.0  # JUMP_VELOCITY，玩家视角倍率后由下次物理 tick 接管
		# 不在梯子区域内，水平方向由玩家自己输入决定（这里先清零）
		player.velocity.x = 0.0
		# 给一个轻微横向推力，让玩家朝面对的方向飞
		var face: float = player.facing_dir
		player.velocity.x = 120.0 * face
		return

	# 检测玩家是否想离开梯子（按 A/D）
	var left_held: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right_held: bool = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	var want_off: bool = left_held or right_held

	player.is_on_ladder = true

	if want_off:
		# 玩家想离开梯子 — 不拉回X，不爬升，让物理系统接管
		# 只重置速度，让玩家自然滑出梯子区域
		player.velocity.y = 0.0
		return

	# 在梯子上且不想离开 — 正常爬行
	var lx: float = ladder.get_meta("ladder_x", player.global_position.x)
	player.global_position.x = lerpf(player.global_position.x, lx, 0.4)
	player.velocity.y = 0.0

	var climb_speed: float = 180.0
	var up_held: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_action_pressed("ui_up")
	var down_held: bool = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down")
	if up_held and not down_held:
		player.global_position.y -= climb_speed * delta
	elif down_held and not up_held:
		player.global_position.y += climb_speed * delta

	var top_y: float = ladder.get_meta("ladder_top_y", 0.0)
	var bot_y: float = ladder.get_meta("ladder_bottom_y", 0.0)
	player.global_position.y = clampf(player.global_position.y, top_y - 4.0, bot_y + 4.0)

func _update_audio_region() -> void:
	if player == null or world == null:
		return
	var region := world.get_region_at(player.global_position)
	AudioManager.set_region(region)
	AudioManager.set_view(str(state.get("current_view", "normal")))

func _input(event: InputEvent) -> void:
	if not game_running:
		return
	
	# ── 拖放激光装置 ──
	if dragging:
		if event is InputEventMouseMotion:
			_update_drag_preview(event.global_position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag(event.global_position)
			get_viewport().set_input_as_handled()
		return
	
func _unhandled_input(event: InputEvent) -> void:
	if opening_active:
		if event.is_action_pressed("pause_menu") or event.is_action_pressed("interact") or event.is_action_pressed("jump"):
			_advance_opening_cinematic(true)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			_advance_opening_cinematic(true)
			get_viewport().set_input_as_handled()
		return
	if not game_running:
		return
	# Don't handle game input while dialogue is open
	if dialogue.visible:
		return
	if event.is_action_pressed("pause_menu"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") and current_near != null and current_near.get_meta("kind", "") == "ladder":
		# W/↑ 爬梯子
		var tx: float = current_near.get_meta("target_x", 5150.0)
		var ty: float = current_near.get_meta("target_y", 3200.0)
		player.global_position = Vector2(tx, ty)
		show_toast("爬回了地面！")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("view_wheel"):
		open_view_wheel()
		get_viewport().set_input_as_handled()
	# 快速切换视角已禁用 — 只能通过记忆长椅切换
	# elif event.is_action_pressed("quick_blind"):
	# 	try_switch_view("blind")
	# elif event.is_action_pressed("quick_depression"):
	# 	try_switch_view("depression")

func show_opening_cinematic() -> void:
	clear_scene()
	opening_active = true
	game_running = false
	AudioManager.stop_bgm()
	AudioManager.stop_walk_sfx()

	opening_root = Control.new()
	opening_root.name = "OpeningCinematic"
	opening_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	opening_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(opening_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#070b13")
	opening_root.add_child(bg)

	opening_art = TextureRect.new()
	opening_art.name = "OpeningSceneArt"
	opening_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	opening_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	opening_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	opening_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	opening_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(opening_art)

	var art_tint := ColorRect.new()
	art_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	art_tint.color = Color("#07101acc")
	art_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(art_tint)

	var scanline := ColorRect.new()
	scanline.name = "CinematicScanline"
	scanline.set_anchors_preset(Control.PRESET_FULL_RECT)
	scanline.color = Color("#84d8ff0b")
	scanline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(scanline)

	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.position = Vector2(46, 28)
	top_bar.size = Vector2(1180, 52)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(top_bar)
	var mark := _make_header_label("MIND / SCAPE", 16, Color("#92d8ff"))
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(mark)
	var skip_button := Button.new()
	skip_button.text = "跳过序章  ›"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.mouse_filter = Control.MOUSE_FILTER_STOP
	skip_button.z_index = 20
	skip_button.add_theme_stylebox_override("normal", _menu_button_style(Color("#9bd8ff"), false))
	skip_button.add_theme_stylebox_override("hover", _menu_button_style(Color("#f0c98a"), true))
	skip_button.pressed.connect(_finish_opening_cinematic)
	top_bar.add_child(skip_button)

	var title := _make_header_label("心灵视界", 52, Color("#f6e2b8"))
	title.position = Vector2(54, 88)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(title)
	var subtitle := _make_header_label("一顶头盔 · 一张长椅 · 五种看见世界的方式", 16, Color("#b7d4e5"))
	subtitle.position = Vector2(58, 148)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(subtitle)

	var dialogue_panel := PanelContainer.new()
	dialogue_panel.name = "OpeningDialogue"
	dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.position = Vector2(46, -196)
	dialogue_panel.size = Vector2(1188, 150)
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.add_theme_stylebox_override("panel", _menu_frame_style(Color("#09121ce8"), Color("#8ec9ff"), 12))
	opening_root.add_child(dialogue_panel)
	var dialogue_margin := MarginContainer.new()
	_set_panel_padding(dialogue_margin, 24, 18, 24, 18)
	dialogue_panel.add_child(dialogue_margin)
	var dialogue_row := HBoxContainer.new()
	dialogue_row.add_theme_constant_override("separation", 18)
	dialogue_margin.add_child(dialogue_row)
	opening_portrait = TextureRect.new()
	opening_portrait.name = "OpeningPortrait"
	opening_portrait.custom_minimum_size = Vector2(92, 110)
	opening_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	opening_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	opening_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	opening_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_row.add_child(opening_portrait)
	var dialogue_copy := VBoxContainer.new()
	dialogue_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_copy.add_theme_constant_override("separation", 5)
	dialogue_row.add_child(dialogue_copy)
	opening_speaker = _make_header_label("", 16, Color("#f0c98a"))
	dialogue_copy.add_child(opening_speaker)
	opening_caption = _make_header_label("", 24, Color("#f4f0e5"))
	opening_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_copy.add_child(opening_caption)
	opening_progress = _make_header_label("", 13, Color("#8ec9ff"))
	dialogue_copy.add_child(opening_progress)

	var click_hint := _make_header_label("点击画面继续", 14, Color("#d5e9f4"))
	click_hint.position = Vector2(56, -34)
	click_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	click_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_root.add_child(click_hint)

	var advance_area := Button.new()
	advance_area.name = "AdvanceOpeningOnClick"
	advance_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	advance_area.flat = true
	advance_area.focus_mode = Control.FOCUS_NONE
	advance_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	advance_area.mouse_filter = Control.MOUSE_FILTER_STOP
	advance_area.pressed.connect(func(): _advance_opening_cinematic(true))
	opening_root.add_child(advance_area)

	opening_phase_index = 0
	opening_phase_elapsed = 0.0
	_sync_opening_cinematic()

func _sync_opening_cinematic() -> void:
	if not opening_active or opening_art == null or not is_instance_valid(opening_art):
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = INTRO_COMIC_TEXTURE
	atlas.region = opening_phase_regions[opening_phase_index]
	opening_art.texture = atlas
	opening_art.modulate = Color(1, 1, 1, 0.0)
	var fade := create_tween()
	fade.tween_property(opening_art, "modulate", Color.WHITE, 0.45)
	var phase: Array = opening_phase_lines[opening_phase_index]
	if opening_speaker != null:
		opening_speaker.text = str(phase[0])
	if opening_caption != null:
		opening_caption.text = str(phase[1])
	if opening_progress != null:
		opening_progress.text = "%02d / %02d    ·    点击画面快进" % [opening_phase_index + 1, opening_phase_regions.size()]
	if opening_portrait != null:
		var portrait := AtlasTexture.new()
		portrait.atlas = INTRO_DOCTOR_TEXTURE
		portrait.region = Rect2(0, 0, 96, 128)
		opening_portrait.texture = portrait

func _update_opening_cinematic(delta: float) -> void:
	if not opening_active:
		return
	opening_phase_elapsed += delta
	if opening_art != null and is_instance_valid(opening_art):
		var pulse := 1.0 + 0.012 * sin(opening_phase_elapsed * 2.2)
		opening_art.scale = Vector2(pulse, pulse)
	if opening_phase_elapsed >= opening_phase_duration:
		_advance_opening_cinematic(false)

func _advance_opening_cinematic(force: bool) -> void:
	if not opening_active:
		return
	if opening_phase_index < opening_phase_regions.size() - 1:
		if force or opening_phase_elapsed >= opening_phase_duration:
			opening_phase_index += 1
			opening_phase_elapsed = 0.0
			_sync_opening_cinematic()
		return
	_finish_opening_cinematic()

func _finish_opening_cinematic() -> void:
	if not opening_active:
		return
	opening_active = false
	if is_instance_valid(opening_root):
		opening_root.queue_free()
	opening_root = null
	opening_art = null
	opening_caption = null
	opening_speaker = null
	opening_portrait = null
	opening_progress = null
	var profile: Dictionary = ProfileManager.get_current_profile()
	var saved_state: Dictionary = profile.get("state", GameData.default_state()) as Dictionary
	saved_state["opening_seen"] = true
	saved_state["opening_version"] = 2
	ProfileManager.save_state(saved_state)
	show_login_screen()

func show_login_screen() -> void:
	clear_scene()
	menu_root = _build_menu_root(Color("#0f1621d8"), Color("#7ec7ff1a"))
	var shell := MarginContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_panel_padding(shell, 56, 42, 56, 36)
	menu_root.add_child(shell)

	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 24)
	shell.add_child(layout)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 18)
	layout.add_child(left)

	var title_block := VBoxContainer.new()
	title_block.add_theme_constant_override("separation", 0)
	left.add_child(title_block)
	var title := _make_header_label("心灵视界", 54, Color("#f6e2b8"))
	title_block.add_child(title)
	var title_sub := _make_header_label("Mindscape", 26, Color("#96d7ff"))
	title_sub.modulate = Color(1, 1, 1, 0.85)
	title_block.add_child(title_sub)
	var opening := _make_header_label("发明、重聚、以及重新看见彼此的方式。", 18, Color("#ddd3c0"))
	opening.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	opening.custom_minimum_size = Vector2(520, 0)
	left.add_child(opening)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _menu_frame_style(Color("#151a23e8"), Color("#88bde5")))
	left.add_child(card)
	var card_margin := MarginContainer.new()
	_set_panel_padding(card_margin, 22, 20, 22, 20)
	card.add_child(card_margin)
	var card_body := VBoxContainer.new()
	card_body.add_theme_constant_override("separation", 12)
	card_margin.add_child(card_body)

	var current_profile: Dictionary = ProfileManager.get_current_profile()
	var intro_line := _make_header_label("当前档案：%s" % current_profile.get("display_name", "旅行者"), 22, Color("#ffe8a0"))
	card_body.add_child(intro_line)
	var intro_note := _make_header_label("输入名字后创建新档案，或直接登录已存在的旅程。", 15, Color("#a9b6c6"))
	intro_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.add_child(intro_note)

	login_name_input = LineEdit.new()
	login_name_input.placeholder_text = "输入新玩家名字"
	login_name_input.custom_minimum_size = Vector2(0, 42)
	login_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_body.add_child(login_name_input)

	agreement_check_box = CheckBox.new()
	agreement_check_box.name = "AgreementCheckBox"
	agreement_check_box.text = "我已阅读并同意用户协议与隐私说明"
	agreement_check_box.add_theme_font_size_override("font_size", 16)
	card_body.add_child(agreement_check_box)

	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 18)
	card_body.add_child(links)
	var terms_link := LinkButton.new()
	terms_link.name = "UserAgreementLink"
	terms_link.text = "用户协议"
	terms_link.pressed.connect(show_agreement_document.bind("terms"))
	links.add_child(terms_link)
	var privacy_link := LinkButton.new()
	privacy_link.name = "PrivacyAgreementLink"
	privacy_link.text = "隐私说明"
	privacy_link.pressed.connect(show_agreement_document.bind("privacy"))
	links.add_child(privacy_link)

	agreement_hint_label = _make_header_label("勾选后才能进入或创建档案。", 14, Color("#f0c98a"))
	card_body.add_child(agreement_hint_label)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	card_body.add_child(buttons)
	login_current_button = _add_button(buttons, "登录当前档案", _accept_agreement_and_show_main_menu)
	login_current_button.name = "LoginCurrentButton"
	create_profile_button = _add_button(buttons, "创建并登录", func():
		var typed_name: String = login_name_input.text.strip_edges()
		if typed_name.is_empty():
			typed_name = "旅行者%d" % (ProfileManager.list_profiles().size() + 1)
		ProfileManager.create_profile(typed_name, "sun")
		ProfileManager.accept_current_agreement()
		show_main_menu()
	)
	create_profile_button.name = "CreateProfileButton"
	var already_accepted := ProfileManager.has_accepted_agreement(current_profile)
	agreement_check_box.button_pressed = already_accepted
	agreement_check_box.disabled = already_accepted
	agreement_check_box.toggled.connect(_update_agreement_gate)
	_update_agreement_gate(already_accepted)
	if already_accepted:
		login_current_button.call_deferred("grab_focus")
	else:
		agreement_check_box.call_deferred("grab_focus")

func _update_agreement_gate(accepted: bool) -> void:
	if is_instance_valid(login_current_button):
		login_current_button.disabled = not accepted
	if is_instance_valid(create_profile_button):
		create_profile_button.disabled = not accepted
	if is_instance_valid(agreement_hint_label):
		agreement_hint_label.text = "已同意当前版本" if accepted and agreement_check_box.disabled else "勾选后才能进入或创建档案"
		agreement_hint_label.modulate = Color("#9ed7bb") if accepted else Color("#f0c98a")

func _accept_agreement_and_show_main_menu() -> void:
	if not is_instance_valid(agreement_check_box) or not agreement_check_box.button_pressed:
		return
	if not ProfileManager.current_profile_has_accepted_agreement():
		ProfileManager.accept_current_agreement()
	show_main_menu()

func show_agreement_document(kind: String) -> void:
	var dialog := Window.new()
	dialog.name = "AgreementDocument"
	dialog.title = "隐私说明" if kind == "privacy" else "用户协议"
	dialog.size = Vector2i(720, 520)
	dialog.transient = true
	dialog.exclusive = true
	dialog.unresizable = true
	dialog.close_requested.connect(dialog.queue_free)
	menu_root.add_child(dialog)
	var background := ColorRect.new()
	background.color = Color("#17232f")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(background)
	var document := RichTextLabel.new()
	document.name = "AgreementDocumentText"
	document.position = Vector2(36, 32)
	document.size = Vector2(648, 396)
	document.fit_content = false
	document.scroll_active = true
	document.add_theme_font_size_override("normal_font_size", 19)
	document.text = _agreement_document_text(kind)
	background.add_child(document)
	var close_button := Button.new()
	close_button.text = "我已阅读"
	close_button.position = Vector2(270, 448)
	close_button.size = Vector2(180, 46)
	close_button.pressed.connect(dialog.queue_free)
	background.add_child(close_button)
	dialog.popup_centered()

func _agreement_document_text(kind: String) -> String:
	if kind == "privacy":
		return """隐私说明（体验版）\n\n1. 《心灵视界 Mindscape》当前为本地单机游戏。\n\n2. 玩家输入的档案名、游戏进度、设置以及协议接受记录保存在本机 user:// 目录。\n\n3. 当前版本不会把上述数据上传到服务器，也不会用于广告追踪。\n\n4. 若未来加入联网、云存档或统计功能，本说明应先更新，并在新版本中重新征得同意。\n\n5. 本文本适用于项目体验与测试阶段；正式公开发行前应由项目负责人完成法律复核。"""
	return """用户协议（体验版）\n\n1. 本游戏通过艺术化互动呈现不同人的感知与心理体验。\n\n2. 盲人、ADHD、自闭症与抑郁症相关内容不代表所有人的真实经历，也不能替代医疗诊断、治疗或专业建议。\n\n3. 请尊重游戏中的人物以及现实中具有不同身心体验的人。\n\n4. 游戏进度仅保存在本机；请自行保管设备与本地存档。\n\n5. 本文本适用于项目体验与测试阶段；正式公开发行前应由项目负责人完成法律复核。"""

func show_main_menu() -> void:
	clear_scene()
	menu_root = _build_menu_root(Color("#13202ad8"), Color("#8ec9ff18"))
	var shell := MarginContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_panel_padding(shell, 56, 40, 56, 38)
	menu_root.add_child(shell)

	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 26)
	shell.add_child(layout)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(540, 0)
	left.add_theme_constant_override("separation", 18)
	layout.add_child(left)

	left.add_child(_make_header_label("心灵视界", 56, Color("#f6e2b8")))
	left.add_child(_make_header_label("Mindscape", 24, Color("#8ec9ff")))
	var current_profile: Dictionary = ProfileManager.get_current_profile()
	var current_state: Dictionary = current_profile.get("state", {}) as Dictionary
	var summary := PanelContainer.new()
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary.add_theme_stylebox_override("panel", _menu_frame_style(Color("#111821ea"), Color("#8ec9ff")))
	left.add_child(summary)
	var summary_margin := MarginContainer.new()
	_set_panel_padding(summary_margin, 22, 20, 22, 20)
	summary.add_child(summary_margin)
	var summary_body := VBoxContainer.new()
	summary_body.add_theme_constant_override("separation", 10)
	summary_margin.add_child(summary_body)
	summary_body.add_child(_make_header_label("当前档案", 20, Color("#f0c98a")))
	summary_body.add_child(_make_header_label("%s%s" % [current_profile.get("display_name", "旅行者"), "  ·  已通关" if bool(current_state.get("finished", false)) else ""], 22, Color("#ffe8a0")))
	summary_body.add_child(_make_header_label("时间胶囊已经被重新理解，但纪念仍可以继续收集。", 15, Color("#b7c6d6")))
	summary_body.add_child(_build_profile_stat_row("完成度", "%d%%" % int((current_profile.get("stats", {}) as Dictionary).get("completion", 0)), Color("#f0c98a")))
	summary_body.add_child(_build_profile_stat_row("相册", "%d 张" % int((current_profile.get("stats", {}) as Dictionary).get("album_count", 0)), Color("#8ec9ff")))
	summary_body.add_child(_build_profile_stat_row("游玩", _format_time((current_profile.get("stats", {}) as Dictionary).get("play_time", 0.0)), Color("#b9d6ff")))
	summary_body.add_child(_make_chip("已通关" if bool(current_state.get("finished", false)) else "未通关", Color("#9bd8a2") if bool(current_state.get("finished", false)) else Color("#f0c98a")))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	summary_body.add_child(buttons)
	var continue_button := _add_button(buttons, "继续游戏", func(): start_game(false))
	_add_button(buttons, "新游戏", func():
		ProfileManager.reset_current_profile()
		start_game(true)
	)
	_add_button(buttons, "切换档案", func(): show_profile_menu())
	_add_button(buttons, "设置", func(): show_settings())
	_add_button(buttons, "退出", func(): get_tree().quit())
	continue_button.call_deferred("grab_focus")

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", _menu_frame_style(Color("#10141be8"), Color("#86d9ff")))
	layout.add_child(right)
	var right_margin := MarginContainer.new()
	_set_panel_padding(right_margin, 18, 18, 18, 18)
	right.add_child(right_margin)
	var right_body := VBoxContainer.new()
	right_body.add_theme_constant_override("separation", 12)
	right_margin.add_child(right_body)
	right_body.add_child(_make_header_label("开篇漫画 / 记忆长卷", 22, Color("#f6e2b8"), true))
	var comic_note := _make_header_label("按“继续游戏”回到中央广场，按“新游戏”从序章开始。", 14, Color("#a9b6c6"), true)
	comic_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_body.add_child(comic_note)
	var comic_frame := PanelContainer.new()
	comic_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comic_frame.add_theme_stylebox_override("panel", _menu_frame_style(Color("#0e1118e6"), Color("#86d9ff")))
	right_body.add_child(comic_frame)
	var comic_scroll := ScrollContainer.new()
	comic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	comic_scroll.custom_minimum_size = Vector2(0, 510)
	comic_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comic_frame.add_child(comic_scroll)
	var comic := TextureRect.new()
	comic.texture = INTRO_COMIC_TEXTURE
	comic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	comic.custom_minimum_size = Vector2(0, 1310)
	comic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comic_scroll.add_child(comic)
	right_body.add_child(_make_header_label("故事已经翻开，旅程可以继续。", 13, Color("#8ec9ff"), true))

func show_profile_menu() -> void:
	clear_scene()
	menu_root = _build_menu_root(Color("#101823dc"), Color("#8ec9ff16"))
	var shell := MarginContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_panel_padding(shell, 56, 40, 56, 38)
	menu_root.add_child(shell)
	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 24)
	shell.add_child(layout)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 14)
	layout.add_child(left)
	left.add_child(_make_header_label("玩家档案", 46, Color("#f6e2b8")))
	left.add_child(_make_header_label("每个档案都保留独立进度、头像和完成统计。", 15, Color("#b7c6d6")))
	var current_profile: Dictionary = ProfileManager.get_current_profile()
	var current_stats: Dictionary = current_profile.get("stats", {}) as Dictionary
	var current_card := PanelContainer.new()
	current_card.add_theme_stylebox_override("panel", _menu_frame_style(Color("#111821ea"), Color("#8ec9ff")))
	left.add_child(current_card)
	var current_margin := MarginContainer.new()
	_set_panel_padding(current_margin, 18, 18, 18, 18)
	current_card.add_child(current_margin)
	var current_body := VBoxContainer.new()
	current_body.add_theme_constant_override("separation", 8)
	current_margin.add_child(current_body)
	current_body.add_child(_make_header_label("当前档案：%s" % current_profile.get("display_name", "旅行者"), 20, Color("#ffe8a0")))
	current_body.add_child(_build_profile_stat_row("完成度", "%d%%" % int(current_stats.get("completion", 0)), Color("#f0c98a")))
	current_body.add_child(_build_profile_stat_row("相册", "%d 张" % int(current_stats.get("album_count", 0)), Color("#8ec9ff")))
	current_body.add_child(_build_profile_stat_row("游玩", _format_time(current_stats.get("play_time", 0.0)), Color("#b9d6ff")))
	current_body.add_child(_make_chip("已通关" if bool((current_profile.get("state", {}) as Dictionary).get("finished", false)) else "进行中", Color("#9bd8a2") if bool((current_profile.get("state", {}) as Dictionary).get("finished", false)) else Color("#f0c98a")))
	_add_button(current_body, "返回登录", func(): show_login_screen())

	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(600, 0)
	right.add_theme_stylebox_override("panel", _menu_frame_style(Color("#111821ea"), Color("#8ec9ff")))
	layout.add_child(right)
	var right_margin := MarginContainer.new()
	_set_panel_padding(right_margin, 18, 18, 18, 18)
	right.add_child(right_margin)
	var right_body := VBoxContainer.new()
	right_body.add_theme_constant_override("separation", 12)
	right_margin.add_child(right_body)
	right_body.add_child(_make_header_label("存档卡片墙", 22, Color("#f6e2b8"), true))
	right_body.add_child(_make_header_label("点击任意一张卡片切换档案。", 14, Color("#a9b6c6"), true))
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_body.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)
	for profile in ProfileManager.list_profiles():
		list.add_child(_build_profile_card(profile))
	_add_button(list, "创建新档案", func():
		ProfileManager.create_profile("旅行者%d" % (ProfileManager.list_profiles().size() + 1), ["sun", "moon", "leaf"][ProfileManager.list_profiles().size() % 3])
		show_profile_menu()
	)
	right_body.add_child(_make_header_label("存档页保留独立头像、完成度、相册数和游玩时长。", 12, Color("#8ec9ff"), true))

func show_settings() -> void:
	var box := AcceptDialog.new()
	box.title = "设置"
	box.dialog_text = "A/D移动 Space跳跃 E互动 F能力 TAB视角轮盘 ESC暂停\n四种视角：盲人/ADHD/自闭症/抑郁症"
	add_child(box)
	box.popup_centered()

func start_game(new_game: bool) -> void:
	clear_scene()
	get_tree().paused = false
	var profile: Dictionary = ProfileManager.get_current_profile()
	var loaded_state: Dictionary = profile.get("state", GameData.default_state()) as Dictionary
	state = loaded_state.duplicate(true)
	_normalize_state()
	world = MAIN_WORLD_SCENE.instantiate() as MindscapeWorld
	if world == null:
		push_error("MainWorld.tscn root must use scripts/world.gd")
		return
	add_child(world)
	world.build(state)
	# 恢复激光装置状态
	_restore_laser_state()
	# 恢复激光聚焦台安装状态
	_restore_laser_focus_state()
	# 连接新系统信号
	world.puzzle_completed.connect(on_level_completed)
	player = MindscapePlayer.create()
	var spawn_position := world.get_player_spawn()
	var start_position: Vector2 = state.get("position", spawn_position) as Vector2
	# Safety: reset stale/out-of-map saves to the scene-authored spawn.
	var authored_bounds := world.get_world_bounds()
	if not authored_bounds.grow(-80.0).has_point(start_position):
		start_position = spawn_position
	player.global_position = start_position
	add_child(player)
	player.add_to_group("player")
	player.set_view(str(state.get("current_view", "normal")))
	player.special_used.connect(_on_player_special)
	camera = Camera2D.new()
	camera.enabled = true
	camera.zoom = Vector2(1.0, 1.0)
	camera.offset = CAMERA_VIEW_OFFSET
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = int(authored_bounds.position.x)
	camera.limit_top = int(authored_bounds.position.y)
	camera.limit_right = int(authored_bounds.end.x)
	camera.limit_bottom = int(authored_bounds.end.y)
	player.add_child(camera)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	dialogue.closed.connect(_on_dialogue_closed)
	note_popup = PUZZLE_NOTE_POPUP_SCRIPT.new()
	note_popup.name = "PuzzleNotePopup"
	add_child(note_popup)
	note_popup.visible = false
	note_popup.connect("closed", func():
		if player != null and is_instance_valid(player):
			player.resume_after_interaction()
	)
	_make_hud()
	world.set_view_palette(str(state.get("current_view", "normal")))
	_set_blind_hud_visible(str(state.get("current_view", "normal")) == "blind")
	# Connect all monster damage signals
	for node in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(node) and node.has_signal("player_touched"):
			node.player_touched.connect(_on_monster_damage)
	game_running = true
	autosave()

func _normalize_state() -> void:
	var fragments: Array = state.get("fragments", []) as Array
	var unlocked: Array = state.get("unlocked_views", []) as Array
	if fragments.is_empty() and unlocked.has("blind") and unlocked.size() <= 2:
		unlocked = ["normal"]
	state["unlocked_views"] = unlocked
	if not state.has("current_view") or not unlocked.has(str(state.get("current_view", "normal"))):
		state["current_view"] = "normal"
	var raw_keys: Array = state.get("collected_keys", []) as Array
	var valid_keys: Array = []
	for key in raw_keys:
		var key_id := str(key)
		if GameData.KEYS.has(key_id) and not valid_keys.has(key_id):
			valid_keys.append(key_id)
	state["collected_keys"] = valid_keys
	var completed: Array = state.get("completed_levels", []) as Array
	completed.erase("dark_maze")
	state["completed_levels"] = completed

func show_intro() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.suspend_for_interaction()

	var intro := Control.new()
	intro.name = "OpeningComic"
	intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(intro)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#0a1118f0")
	intro.add_child(bg)

	var shell := MarginContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_panel_padding(shell, 40, 32, 40, 32)
	intro.add_child(shell)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _menu_frame_style(Color("#111821f2"), Color("#86d9ff"), 12))
	shell.add_child(frame)
	var margin := MarginContainer.new()
	_set_panel_padding(margin, 20, 18, 20, 18)
	frame.add_child(margin)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(340, 0)
	left.add_theme_constant_override("separation", 12)
	layout.add_child(left)
	left.add_child(_make_header_label("开篇漫画", 38, Color("#f6e2b8")))
	left.add_child(_make_header_label("发明家、头盔、记忆长椅，以及回到童年冒险的路。", 16, Color("#b7c6d6")))
	left.add_child(_make_chip("可跳过", Color("#8ec9ff")))
	left.add_child(_make_chip("按 Enter 继续", Color("#f0c98a")))
	var story := RichTextLabel.new()
	story.fit_content = true
	story.scroll_active = false
	story.bbcode_enabled = true
	story.custom_minimum_size = Vector2(0, 0)
	story.add_theme_font_size_override("normal_font_size", 18)
	story.add_theme_color_override("default_color", Color("#ebe6d8"))
	story.text = "[center]发明家做出了一顶能看见他人世界的头盔。[/center]\n\n[center]一张记忆长椅，把不同视角重新接回同一个世界。[/center]\n\n[center]童年的伙伴们听见这个消息后，一个个重新聚了起来。[/center]\n\n[center]他们回到熟悉的地方，准备找回那份被封住的宝藏记忆。[/center]"
	left.add_child(story)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	left.add_child(buttons)
	var start_button := _add_button(buttons, "开始序章", func():
		state["intro_seen"] = true
		ProfileManager.save_state(state)
		player.resume_after_interaction()
		intro.queue_free()
	)
	var skip_button := _add_button(buttons, "跳过开篇", func():
		state["intro_seen"] = true
		ProfileManager.save_state(state)
		player.resume_after_interaction()
		intro.queue_free()
	)
	start_button.call_deferred("grab_focus")
	skip_button.focus_neighbor_top = start_button.get_path()

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", _menu_frame_style(Color("#10141bf0"), Color("#86d9ff")))
	layout.add_child(right)
	var right_margin := MarginContainer.new()
	_set_panel_padding(right_margin, 12, 12, 12, 12)
	right.add_child(right_margin)
	var comic_scroll := ScrollContainer.new()
	comic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	comic_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comic_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_child(comic_scroll)
	var comic := TextureRect.new()
	comic.texture = INTRO_COMIC_TEXTURE
	comic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	comic.custom_minimum_size = Vector2(0, 1310)
	comic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comic_scroll.add_child(comic)

func clear_scene() -> void:
	game_running = false
	for child in get_children():
		child.queue_free()

func _make_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 20
	add_child(hud)
	# Inventory stays visible above the blind vision mask.
	inventory_canvas = CanvasLayer.new()
	inventory_canvas.name = "InventoryCanvas"
	inventory_canvas.layer = 600
	inventory_canvas.follow_viewport_enabled = false
	add_child(inventory_canvas)
	# Menus are intentionally above the mask so the player can change views or pause.
	controls_canvas = CanvasLayer.new()
	controls_canvas.name = "ViewControlsCanvas"
	controls_canvas.layer = 700
	controls_canvas.follow_viewport_enabled = false
	add_child(controls_canvas)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 16)
	hud_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(hud_label)
	objective_label = Label.new()
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.position = Vector2(340, 48)
	objective_label.size = Vector2(600, 36)
	objective_label.add_theme_font_size_override("font_size", 22)
	objective_label.modulate = Color("#ffe8a0")
	hud.add_child(objective_label)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(300, 566)
	prompt_label.size = Vector2(680, 44)
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(prompt_label)
	# Damage overlay (red flash + vignette on monster hit)
	damage_overlay = ColorRect.new()
	damage_overlay.name = "DamageOverlay"
	damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	hud.add_child(damage_overlay)
	
	_create_sidebar_inventory()

func _update_hud() -> void:
	var view: String = str(state.get("current_view", "normal"))
	var fragment_list: Array = state.get("fragments", [])
	var collectible_list: Array = state.get("collectibles", [])
	
	# 游戏内不再常驻显示档案、完成度和长目标，避免与关卡画面争夺注意力。
	hud_label.text = ""
	hud_label.visible = false
	
	# 关卡说明改为首次触发时出现的纸条，HUD 不再常驻长篇目标。
	objective_label.text = ""
	objective_label.visible = false
	
	# Build prompt text for nearby interactions.
	var parts: PackedStringArray = []
	if current_near != null:
		parts.append("[E] 互动")
	prompt_label.text = "  ".join(parts)
	
	# 更新侧边物品栏
	_update_inventory_sidebar()

func _get_objective() -> String:
	var completed: Array = state.get("completed_levels", [])
	var keys: Array = state.get("collected_keys", [])
	
	if state.get("finished", false):
		return "🎆 恭喜！你完成了所有挑战，开启了时间胶囊！"
	
	if not completed.has("texture_wall"):
		return "→ 往左走，找到[纹理墙] — 用键盘按键感受纹理开启左侧区域"
	if not completed.has("find_difference") and not completed.has("banquet_painting"):
		return "→ 左侧已解锁：进入[找不同密室]和[宴会厅油画]探索"
	if not completed.has("amusement_lights"):
		return "→ 往右走到[游乐园灯板]，用盲人模式听音+ADHD模式快速点亮"
	if not completed.has("npc_password"):
		return "→ 最右侧[许愿堂]的[NPC密码台]等待着你"
	
	if keys.size() < REQUIRED_KEY_COUNT:
		var missing := REQUIRED_KEY_COUNT - keys.size()
		return "→ 收集剩余%d把钥匙后，用两束激光找到时间胶囊。" % missing
	
	return "→ 三把钥匙集齐！把两台激光装置带到中央广场的激光聚焦台。"

func _describe_interactable(node: Node) -> String:
	# 优先按实例类型识别新关卡节点
	if node is PuzzleTextureWall:    return "[关卡1] 纹理墙 — 触觉按键谜题"
	if node is PuzzleFindDifference: return "[关卡2] 找不同密室 — 视角找差异"
	if node is PuzzleBanquetPainting: return "[关卡3] 宴会厅油画 — 舞蹈序列"
	if node is PuzzleAmusementLights: return "[关卡4] 游乐园灯板 — 音频+速度"
	if node is PuzzleNPCPassword:    return "[关卡5] NPC密码台 — 潜台词解码"
	if node is PuzzleLaserFocus:     return "[关卡] 激光聚焦台 — 双激光校准挑战"
	
	match node.get_meta("kind", ""):
		"npc":
			var npc: MindscapeNPC = node as MindscapeNPC
			return npc.display_name if npc != null else "居民"
		"anchor":
			return "记忆长椅 / 存档 / 视角切换"
		"collectible":
			return "纪念物"
		"puzzle":
			return str(_puzzle_by_id(str(node.get_meta("id", ""))).get("name", "机关"))
		"treasure_chest":
			var keys: Array = state.get("collected_keys", [])
			if keys.size() >= REQUIRED_KEY_COUNT:
				return "★ 时间胶囊宝箱（已解锁！）"
			return "★ 宝箱（%d/%d钥匙）" % [keys.size(), REQUIRED_KEY_COUNT]
		"key_chest":
			return "🔑 钥匙箱（按E拾取）"
		"zone_indicator":
			return "关卡区域"
		"treasure_spot":
			if node.has_meta("solved"):
				return "★ 宝藏已就位！按E开启"
			return "两条激光交汇之处..."
		"bush_clue":
			var bush_index := int(node.get_meta("bush_idx", -1))
			var opened := false
			if bush_index >= 0 and bush_index < world._bush_clues.size():
				opened = bool(world._bush_clues[bush_index].get("opened", false))
			return "【自闭视角】灌木丛（按 E %s）" % ("合上" if opened else "拨开")
	return "某个东西"

func interact() -> void:
	if current_near == null:
		return
	if _show_puzzle_note_once(current_near):
		return
	# 找不同密室：直接转发 interact（不走 meta 分发）
	if current_near is PuzzleFindDifference:
		var fd := current_near as PuzzleFindDifference
		if fd.room_open:
			fd._close_room()
		else:
			fd._open_room()
		return
	# 游乐园灯板：完全由灯板自己的 _input 处理，这里不介入
	if current_near is PuzzleAmusementLights:
		return
	# 激光聚焦台：直接转发 interact → _try_start()（不走 meta 分发）
	if current_near is PuzzleLaserFocus:
		(current_near as PuzzleLaserFocus)._try_start()
		return
	match current_near.get_meta("kind", ""):
		"npc":
			talk_to_npc(current_near)
		"anchor":
			rest_at_anchor(current_near)
		"collectible":
			collect_item(current_near)
		"puzzle":
			solve_puzzle(current_near)
		"treasure_chest":
			try_open_treasure_chest(current_near)
		"zone_indicator":
			show_toast("关卡区域：%s" % _describe_interactable(current_near))
		"key_chest":
			var key_id: String = current_near.get_meta("key_id", "")
			if key_id != "":
				collect_key(key_id)
				# 拾取后从地图上消失
				world.remove_interactable(current_near)
				current_near = null
			else:
				show_toast("宝箱是空的...", 2.0)
		"treasure_spot":
			if current_near.has_meta("solved"):
				state["finished"] = true
				state["treasure_unlocked"] = true
				show_toast("🎆🎆🎆 时间胶囊开启了！！！ 🎆🎆🎆", 6.0)
				AudioManager.play_sfx("collect")
				autosave()
				show_ending()
			else:
				show_toast("两束激光需要对到正确角度，交汇在一点...", 3.0)
		"underground_entry":
			enter_underground_maze()
		"bush_clue":
			if str(state.get("current_view", "normal")) != "autism":
				return
			var bush_index := int(current_near.get_meta("bush_idx", -1))
			var opened := world.toggle_bush_clue(bush_index)
			AudioManager.play_sfx("light_on")
			show_toast("拨开草丛，发现第 %d 块彩色线索。" % (bush_index + 1) if opened else "草丛重新合上了。", 1.8)
		_:
			# 新式谜题实例（PuzzleTextureWall等）自带交互处理
			if current_near.has_method("_input"):
				pass  # 谜题自己处理输入

func enter_underground_maze() -> void:
	if player == null or not is_instance_valid(player):
		return
	state["position"] = player.global_position
	state["return_to_game"] = false
	ProfileManager.save_state(state)
	player.suspend_for_interaction()
	game_running = false
	AudioManager.stop_bgm()

	var transition := UNDERGROUND_STAIR_TRANSITION.instantiate()
	add_child(transition)
	transition.configure(UNDERGROUND_ENTRY_AUDIO)
	transition.play()
	await transition.completed
	get_tree().change_scene_to_file("res://maze/UndergroundMaze.tscn")

# ══════════════════════════════════════════════════════════════
#  底部物品栏 + 拖放系统
# ══════════════════════════════════════════════════════════════

const SIDEBAR_W: float = 1256.0
const SLOT_W: float = 118.0
const SLOT_H: float = 54.0

func _create_sidebar_inventory() -> void:
	sidebar = Panel.new()
	sidebar.name = "BottomInventory"
	sidebar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sidebar.offset_left = 12.0
	sidebar.offset_top = -102.0
	sidebar.offset_right = -12.0
	sidebar.offset_bottom = -8.0
	sidebar.z_index = 10
	
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color("#0a0a18", 0.9)
	sbg.border_color = Color("#4b5269")
	sbg.set_border_width_all(2)
	sbg.set_corner_radius_all(6)
	sidebar.add_theme_stylebox_override("panel", sbg)
	inventory_canvas.add_child(sidebar)

	var title := Label.new()
	title.text = "物品栏"
	title.position = Vector2(14, 10)
	title.size = Vector2(82, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#ffe8a0"))
	sidebar.add_child(title)
	_add_sidebar_divider(104.0)

	var key_header := Label.new()
	key_header.text = "钥匙"
	key_header.position = Vector2(118, 4)
	key_header.size = Vector2(496, 20)
	key_header.add_theme_font_size_override("font_size", 13)
	key_header.add_theme_color_override("font_color", Color("#ffd700"))
	sidebar.add_child(key_header)

	var key_data := [
		{"id": "key_1", "name": "宴会厅钥匙", "icon": "🔑", "color": Color("#ffd700")},
		{"id": "key_2", "name": "游乐园钥匙", "icon": "🔑", "color": Color("#ff6b6b")},
		{"id": "key_4", "name": "天文台钥匙", "icon": "🔑", "color": Color("#a29bfe")},
		{"id": "maze_key", "name": "迷宫钥匙", "icon": "🔑", "color": Color("#73d6d2")},
	]
	for i in range(key_data.size()):
		var slot := _make_inv_slot(Vector2(118 + i * 124, 26), key_data[i], "key", false)
		inv_slots[key_data[i]["id"]] = slot
		sidebar.add_child(slot)
	_add_sidebar_divider(622.0)

	var laser_header := Label.new()
	laser_header.text = "激光装置"
	laser_header.position = Vector2(638, 4)
	laser_header.size = Vector2(244, 20)
	laser_header.add_theme_font_size_override("font_size", 13)
	laser_header.add_theme_color_override("font_color", Color("#88ccff"))
	sidebar.add_child(laser_header)

	var laser_data := [
		{"id": "laser_device_1", "name": "激光装置 1", "icon": "💡", "color": Color("#ff4444")},
		{"id": "laser_device_2", "name": "激光装置 2", "icon": "💡", "color": Color("#44aaff")},
	]
	for i in range(2):
		var slot := _make_inv_slot(Vector2(638 + i * 124, 26), laser_data[i], "laser", true)
		inv_slots[laser_data[i]["id"]] = slot
		sidebar.add_child(slot)
	_add_sidebar_divider(892.0)

	var tool_header := Label.new()
	tool_header.text = "探索工具"
	tool_header.position = Vector2(908, 4)
	tool_header.size = Vector2(300, 20)
	tool_header.add_theme_font_size_override("font_size", 13)
	tool_header.add_theme_color_override("font_color", Color("#8deaf0"))
	sidebar.add_child(tool_header)

	var compass_data := {"id": "maze_compass", "name": "地下指南针", "icon": "🧭", "color": Color("#8deaf0"), "texture": _maze_compass_texture}
	var compass_slot := _make_inv_slot(Vector2(908, 26), compass_data, "tool", false)
	inv_slots["maze_compass"] = compass_slot
	sidebar.add_child(compass_slot)

func _add_sidebar_divider(x: float) -> void:
	var div := ColorRect.new()
	div.position = Vector2(x, 10)
	div.size = Vector2(1, 72)
	div.color = Color("#3a3a5a")
	sidebar.add_child(div)

func _make_inv_slot(pos: Vector2, item_data: Dictionary, category: String, draggable: bool) -> Panel:
	var slot := Panel.new()
	slot.position = pos
	slot.size = Vector2(SLOT_W, SLOT_H)
	slot.set_meta("item_id", item_data["id"])
	slot.set_meta("draggable", draggable)
	slot.set_meta("item_data", item_data)  # 存储完整数据供更新用
	
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("#181825")
	ss.set_corner_radius_all(6)
	ss.border_width_left = 2
	ss.border_width_right = 2
	ss.border_width_top = 2
	ss.border_width_bottom = 2
	ss.border_color = Color("#2a2a40")
	slot.add_theme_stylebox_override("panel", ss)
	
	# 图标 — 初始显示 "?"，获得后才显示 emoji
	var icon := Label.new()
	icon.text = "?"
	icon.position = Vector2(6, 6)
	icon.size = Vector2(28, 28)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 16)
	icon.add_theme_color_override("font_color", Color("#444466"))
	icon.name = "Icon"
	slot.add_child(icon)

	if item_data.has("texture"):
		var tex := TextureRect.new()
		tex.name = "TextureIcon"
		tex.texture = item_data.get("texture")
		tex.position = Vector2(6, 6)
		tex.size = Vector2(28, 28)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.visible = false
		slot.add_child(tex)
	
	# 名称 — 初始显示 "空"
	var name_label := Label.new()
	name_label.text = "空"
	name_label.position = Vector2(38, 6)
	name_label.size = Vector2(SLOT_W - 44, SLOT_H - 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color("#444466"))
	name_label.name = "Name"
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	slot.add_child(name_label)
	
	# 鼠标事件
	slot.gui_input.connect(_on_slot_gui_input.bind(slot))
	slot.mouse_entered.connect(func():
		var st := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if st: st.border_color = Color("#8888bb")
	)
	slot.mouse_exited.connect(func():
		var st := slot.get_theme_stylebox("panel") as StyleBoxFlat
		if st: st.border_color = Color("#3a3a5a")
	)
	
	return slot

func _on_slot_gui_input(event: InputEvent, slot: Panel) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	
	var item_id: String = slot.get_meta("item_id", "")
	var draggable: bool = slot.get_meta("draggable", false)
	
	if event.pressed:
		if draggable and _can_drag(item_id):
			_start_drag(item_id, event)
		else:
			_show_item_info(item_id)
		
func _can_drag(item_id: String) -> bool:
	return false

func _show_item_info(item_id: String) -> void:
	var info := ""
	match item_id:
		"key_1": info = "宴会厅钥匙 — 金色的钥匙"
		"key_2": info = "游乐园钥匙 — 红色的钥匙"
		"key_4": info = "天文台钥匙 — 紫色的钥匙"
		"maze_key": info = "迷宫钥匙 — 从地下迷宫出口带回来的钥匙"
		"maze_compass":
			if bool(state.get("maze_compass_owned", false)):
				info = "地下指南针 — 在地下迷宫中指向正确路线；进入地下后点击它或按 C 切换"
				if bool(state.get("maze_compass_enabled", false)):
					info += "\n当前：已启用"
				else:
					info += "\n当前：未启用"
			else:
				info = "地下指南针 — 完成激光聚焦后获得"
		"laser_device_1":
			if not laser_owned["laser_device_1"]: info = "在找不同密室获得"
			elif state.get("laser_focus_1_installed", false): info = "激光装置1 — 已安装到聚焦台"
			else: info = "激光装置1 — 前往中央广场的激光聚焦台安装"
		"laser_device_2":
			if not laser_owned["laser_device_2"]: info = "在石台拼图获得"
			elif state.get("laser_focus_2_installed", false): info = "激光装置2 — 已安装到聚焦台"
			else: info = "激光装置2 — 前往中央广场的激光聚焦台安装"
	show_toast(info, 2.0)

func _start_drag(item_id: String, event: InputEventMouseButton) -> void:
	dragging = true
	drag_item_id = item_id
	
	# 创建拖拽预览（稍大一些便于看清）
	drag_preview = Panel.new()
	drag_preview.size = Vector2(52, 52)
	drag_preview.z_index = 1000
	
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("#ff8844", 0.85)
	ss.set_corner_radius_all(8)
	drag_preview.add_theme_stylebox_override("panel", ss)
	
	var icon := Label.new()
	icon.text = "💡"
	icon.position = Vector2(0, 0)
	icon.size = Vector2(52, 52)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 18)
	drag_preview.add_child(icon)
	
	inventory_canvas.add_child(drag_preview)
	
	drag_mouse_offset = event.position + sidebar.position + inv_slots[item_id].position
	_update_drag_preview(event.global_position)

func _update_drag_preview(screen_pos: Vector2) -> void:
	if not dragging or not is_instance_valid(drag_preview):
		return
	drag_preview.position = screen_pos - drag_preview.size / 2.0

func _end_drag(screen_pos: Vector2) -> void:
	if not dragging:
		return
	dragging = false
	if is_instance_valid(drag_preview):
		drag_preview.queue_free()
		drag_preview = null
	
	# 转换屏幕坐标到世界坐标，检测风向标
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var zoom := camera.zoom
	var center := camera.get_screen_center_position()
	var world_pos: Vector2 = center + (screen_pos - vs / 2.0) * zoom
	
	var vane_idx: int = world.get_nearest_vane_at(world_pos, 90.0)
	if vane_idx < 1:
		drag_item_id = ""
		return
	
	var vane_num := 1 if drag_item_id == "laser_device_1" else 2
	if vane_idx != vane_num:
		show_toast("这是%s的风向标，请放到正确的风向标上。" % ("左侧" if vane_idx == 1 else "右侧"), 2.0)
		drag_item_id = ""
		return
	
	# 放置装置
	var ok: bool = world.place_laser_device(drag_item_id, vane_idx)
	if ok:
		if drag_item_id == "laser_device_1":
			state["laser_1_placed"] = true
			state["laser_1_angle"] = 0.0
		else:
			state["laser_2_placed"] = true
			state["laser_2_angle"] = 0.0
		show_toast("激光装置已放置到风向标%d！用鼠标滚轮旋转角度。" % vane_idx, 3.0)
		AudioManager.play_sfx("collect")
		_update_inventory_sidebar()
		autosave()
	else:
		show_toast("该风向标已有装置。", 2.0)
	
	drag_item_id = ""

func _update_inventory_sidebar() -> void:
	if inv_slots.is_empty():
		return
	# ── 修复：确保 collected_keys 是普通 Array（不依赖类型推断）──
	var raw_keys = state.get("collected_keys", [])
	var keys: Array = []
	if raw_keys is Array:
		for k in raw_keys:
			keys.append(str(k))
	
	for item_id in inv_slots:
		var slot: Panel = inv_slots[item_id] as Panel
		var st: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat
		if st == null:
			continue
		var icon_lbl: Label = slot.get_node_or_null("Icon") as Label
		var name_lbl: Label = slot.get_node_or_null("Name") as Label
		if icon_lbl == null:
			continue
		var tex_icon: TextureRect = slot.get_node_or_null("TextureIcon") as TextureRect
		
		var idata: Dictionary = slot.get_meta("item_data", {})
		
		if item_id.begins_with("key_") or item_id == "maze_key":
			if keys.has(str(item_id)):
				var kd: Dictionary = GameData.KEYS.get(item_id, {}) as Dictionary
				var kc: Color = kd.get("color", Color.WHITE) as Color
				st.bg_color = kc.darkened(0.6)
				st.border_color = kc.lightened(0.3)
				icon_lbl.add_theme_color_override("font_color", kc)
				icon_lbl.text = "🔑"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", kc)
					name_lbl.text = str(kd.get("name", "钥匙"))
			else:
				st.bg_color = Color("#181825")
				st.border_color = Color("#2a2a40")
				icon_lbl.add_theme_color_override("font_color", Color("#444466"))
				icon_lbl.text = "?"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", Color("#444466"))
					name_lbl.text = "空"
				if tex_icon != null:
					tex_icon.visible = false
		elif item_id.begins_with("laser_"):
			var owned: bool = laser_owned.get(item_id, false)
			match item_id:
				"laser_device_1": owned = laser_owned["laser_device_1"]
				"laser_device_2": owned = laser_owned["laser_device_2"]
			
			var placed := false
			if item_id == "laser_device_1":
				placed = state.get("laser_1_placed", false)
			elif item_id == "laser_device_2":
				placed = state.get("laser_2_placed", false)
			
			if placed:
				st.bg_color = Color("#2a4a2a")
				st.border_color = Color("#44ff44")
				icon_lbl.add_theme_color_override("font_color", Color("#44ff44"))
				icon_lbl.text = "💡"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", Color("#44ff44"))
					name_lbl.text = "已放置"
				slot.set_meta("tooltip", "已放置")
			elif owned:
				var lc: Color = idata.get("color", Color("#ff6644")) as Color
				st.bg_color = lc.darkened(0.6)
				st.border_color = lc
				icon_lbl.add_theme_color_override("font_color", lc)
				icon_lbl.text = "💡"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", lc)
					name_lbl.text = str(idata.get("name", "激光装置"))
			else:
				st.bg_color = Color("#181825")
				st.border_color = Color("#2a2a40")
				icon_lbl.add_theme_color_override("font_color", Color("#444466"))
				icon_lbl.text = "?"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", Color("#444466"))
					name_lbl.text = "空"
				if tex_icon != null:
					tex_icon.visible = false
		elif item_id == "maze_compass":
			var owned_compass := bool(state.get("maze_compass_owned", false))
			var enabled_compass := bool(state.get("maze_compass_enabled", false))
			if owned_compass:
				st.bg_color = Color("#1f3940") if not enabled_compass else Color("#224d52")
				st.border_color = Color("#5b8f96") if not enabled_compass else Color("#8deaf0")
				icon_lbl.visible = false
				if tex_icon != null:
					tex_icon.visible = true
					tex_icon.modulate = Color("#8deaf0")
				icon_lbl.add_theme_color_override("font_color", Color("#8deaf0"))
				icon_lbl.text = "🧭"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", Color("#8deaf0"))
					name_lbl.text = "已启用" if enabled_compass else "地下指南针"
			else:
				st.bg_color = Color("#181825")
				st.border_color = Color("#2a2a40")
				icon_lbl.visible = true
				if tex_icon != null:
					tex_icon.visible = false
				icon_lbl.add_theme_color_override("font_color", Color("#444466"))
				icon_lbl.text = "?"
				if name_lbl:
					name_lbl.add_theme_color_override("font_color", Color("#444466"))
					name_lbl.text = "空"

func talk_to_npc(npc_node: MindscapeNPC) -> void:
	var data: Dictionary = {}
	for npc in GameData.NPCS:
		if npc.get("id", "") == npc_node.npc_id:
			data = npc
			break
	var view: String = str(state.get("current_view", "normal"))
	if view == "autism":
		show_toast("自闭视角下不能和NPC交谈。", 2.0)
		return
	var raw_lines: Array = GameData.DIALOGUES.get(npc_node.npc_id, [{"expr": "normal", "text": "你好。"}])
	# 根据视角过滤：抑郁模式才能看到 subtext
	var lines: Array = []
	for line in raw_lines:
		var filtered: Dictionary = line.duplicate()
		if view == "depression" and line.has("subtext"):
			filtered["subtext"] = str(line["subtext"])
		lines.append(filtered)
	player.suspend_for_interaction()
	dialogue.open(data, lines, view)
	if npc_node.npc_id == "braille_scholar" and not state.get("album", []).has("盲文 A-D"):
		state["album"].append("盲文 A-D")
		show_toast("纪念相册加入：盲文 A-D")
		autosave()

func rest_at_anchor(anchor: Node) -> void:
	var id: String = str(anchor.get_meta("id", "plaza"))
	if not state.get("visited_anchors", []).has(id):
		state["visited_anchors"].append(id)
	state["position"] = player.global_position
	autosave()
	show_toast("你在记忆长椅旁坐下……", 2.0)
	player.suspend_for_interaction()
	# Short delay before wheel to simulate "sitting down"
	var timer := get_tree().create_timer(0.4)
	timer.timeout.connect(func():
		open_view_wheel()
	)

func _on_dialogue_closed() -> void:
	if is_instance_valid(player):
		player.resume_after_interaction()

func collect_item(node: Node) -> void:
	var id: String = str(node.get_meta("id", ""))
	if not state.get("collectibles", []).has(id):
		state["collectibles"].append(id)
		var album_name: String = GameData.COLLECTIBLE_NAMES[int(id.get_slice("_", 1)) % GameData.COLLECTIBLE_NAMES.size()]
		state["album"].append(album_name)
		world.remove_interactable(node)
		show_toast("加入纪念相册：%s" % album_name)
		AudioManager.play_sfx("collect")
		autosave()

# ══════════════ 新系统：钥匙收集 + 宝箱 ══════════════

func collect_key(key_id: String) -> void:
	# ── 修复：先确保 collected_keys 是普通 Array（不依赖类型推断）──
	var raw_keys = state.get("collected_keys", [])
	var keys: Array = []
	if raw_keys is Array:
		for k in raw_keys:
			keys.append(str(k))
	if keys.has(key_id):
		# 已获得，仍刷新一次物品栏（防御性，避免之前漏刷新）
		_update_inventory_sidebar()
		return
	keys.append(key_id)
	state["collected_keys"] = keys
	
	var key_data: Dictionary = GameData.KEYS.get(key_id, {})
	var key_name: String = key_data.get("name", key_id)
	show_toast("🔑 获得钥匙：%s（%d/%d）" % [key_name, keys.size(), REQUIRED_KEY_COUNT])
	AudioManager.play_sfx("collect")
	
	# 更新宝箱显示
	world.update_treasure_key_count(keys)
	
	# 检查是否集齐全部钥匙
	if keys.size() >= REQUIRED_KEY_COUNT:
		show_toast("✨ 三把钥匙全部集齐！把两台激光装置带到中央广场的聚焦台。", 5.0)
	
	_update_inventory_sidebar()
	autosave()

func get_collected_keys() -> Array:
	# ── 修复：返回普通 Array（避免 typed array 导致下游代码出错）──
	var raw = state.get("collected_keys", [])
	var out: Array = []
	if raw is Array:
		for k in raw:
			out.append(str(k))
	return out

func try_open_treasure_chest(chest_node: Node) -> void:
	var keys: Array = state.get("collected_keys", [])
	if keys.size() >= REQUIRED_KEY_COUNT:
		# 开启宝箱 → 结局
		state["finished"] = true
		state["treasure_unlocked"] = true
		state["album"].append("★ 时间胶囊 ★")
		world.remove_interactable(chest_node)
		show_toast("🎆🎆🎆 时间胶囊开启了！！！ 🎆🎆🎆", 6.0)
		AudioManager.play_sfx("collect")  # 或特殊音效
		autosave()
		show_ending()
	else:
		show_toast("宝箱锁住了...你需要收集%d把钥匙。（当前：%d/%d）" % [REQUIRED_KEY_COUNT, keys.size(), REQUIRED_KEY_COUNT], 3.0)

# 当关卡完成时的回调（由 world._on_puzzle_completed 触发）
func on_level_completed(level_id: String, reward_id: String = "") -> void:
	# 记录关卡完成
	if not state.get("completed_levels", []):
		state["completed_levels"] = []
	if not state["completed_levels"].has(level_id):
		state["completed_levels"].append(level_id)
	
	# 处理奖励
	match reward_id:
		"key_1", "key_2", "key_4":
			collect_key(reward_id)
		"laser_device_1":
			laser_owned["laser_device_1"] = true
			state["laser_1_placed"] = false
			state["laser_1_angle"] = 0.0
			show_toast("获得激光装置1！可带到中央广场的激光聚焦台。", 3.0)
			_update_inventory_sidebar()
		"laser_device_2":
			laser_owned["laser_device_2"] = true
			state["laser_2_placed"] = false
			state["laser_2_angle"] = 0.0
			show_toast("获得激光装置2！可带到中央广场的激光聚焦台。", 3.0)
			_update_inventory_sidebar()
		"stone_door":
			show_toast("石门打开了！左侧区域现已可通行。", 3.0)
		"laser_focus_master":
			_handle_laser_focus_reward(true)
		"laser_focus_pass":
			_handle_laser_focus_reward(false)
		"treasure":
			if state.get("collected_keys", []).size() >= REQUIRED_KEY_COUNT:
				state["finished"] = true
				state["treasure_unlocked"] = true
				show_toast("🎆🎆🎆 时间胶囊开启了！！！ 🎆🎆🎆", 6.0)
				AudioManager.play_sfx("collect")
				show_ending()
			else:
				show_toast("时间胶囊需要%d把钥匙！" % REQUIRED_KEY_COUNT, 3.0)
		"":
			pass  # 无特殊奖励
	
	autosave()

func _handle_laser_focus_reward(perfect: bool) -> void:
	var first_unlock := GameData.unlock_hidden_door(state)
	_update_inventory_sidebar()
	autosave()
	if first_unlock and not _laser_unlock_cutscene_played:
		_laser_unlock_cutscene_played = true
		await _play_hidden_door_cutscene()
	if perfect:
		show_toast("🎉 激光聚焦挑战完美通关！地下隐藏门已打开。", 4.0)
	else:
		show_toast("👍 激光聚焦挑战完成！地下隐藏门已打开。", 3.0)
	AudioManager.play_sfx("collect")

func _play_hidden_door_cutscene() -> void:
	if player != null:
		player.suspend_for_interaction()
	var overlay := CanvasLayer.new()
	overlay.name = "LaserUnlockCutscene"
	overlay.layer = 5000
	add_child(overlay)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0.0)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(fade)
	var stage := Panel.new()
	stage.position = Vector2(430, 150)
	stage.size = Vector2(420, 310)
	stage.modulate.a = 0.0
	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color("#101922")
	stage_style.border_color = Color("#526772")
	stage_style.set_border_width_all(3)
	stage_style.set_corner_radius_all(6)
	stage.add_theme_stylebox_override("panel", stage_style)
	overlay.add_child(stage)
	var glow := ColorRect.new()
	glow.position = Vector2(116, 54)
	glow.size = Vector2(188, 190)
	glow.color = Color("#8deaf0", 0.18)
	stage.add_child(glow)
	var door_atlas := AtlasTexture.new()
	door_atlas.atlas = _hidden_door_texture
	door_atlas.region = Rect2(0, 0, 790, 995)
	var door_image := TextureRect.new()
	door_image.texture = door_atlas
	door_image.position = Vector2(116, 20)
	door_image.size = Vector2(188, 226)
	door_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	door_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.add_child(door_image)
	var label := Label.new()
	label.text = "地下深处，某扇石门回应了光..."
	label.position = Vector2(0, 258)
	label.size = Vector2(420, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("#8deaf0"))
	stage.add_child(label)
	var compass := TextureRect.new()
	compass.texture = _maze_compass_texture
	compass.position = Vector2(160, 82)
	compass.size = Vector2(100, 100)
	compass.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	compass.modulate = Color(1, 1, 1, 0)
	stage.add_child(compass)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.86, 0.45)
	tween.parallel().tween_property(stage, "modulate:a", 1.0, 0.45)
	tween.tween_interval(0.7)
	tween.tween_callback(func(): AudioManager.play_sfx("stone_door"))
	tween.tween_property(door_image, "modulate", Color("#8deaf0", 0.55), 0.55)
	tween.tween_callback(func(): door_atlas.region = Rect2(791, 0, 790, 995))
	tween.tween_property(door_image, "modulate", Color.WHITE, 0.6)
	tween.tween_callback(func(): label.text = "地下隐藏门已经打开\n获得：地下指南针")
	tween.tween_property(compass, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.25)
	tween.tween_property(stage, "modulate:a", 0.0, 0.45)
	tween.parallel().tween_property(fade, "color:a", 0.0, 0.45)
	await tween.finished
	overlay.queue_free()
	if player != null and is_instance_valid(player):
		player.resume_after_interaction()

func solve_puzzle(node: Node) -> void:
	var puzzle: Dictionary = _puzzle_by_id(str(node.get_meta("id", "")))
	if puzzle.is_empty():
		return
	if puzzle.get("need_final", false):
		try_finish_game(node)
		return
	var view: String = str(state.get("current_view", "normal"))
	var unlocked: Array = state.get("unlocked_views", [])
	var allowed: bool = true
	if puzzle.has("need"):
		allowed = view == puzzle["need"] and unlocked.has(view)
	if puzzle.has("need_combo"):
		allowed = unlocked_all(puzzle["need_combo"]) and view in puzzle["need_combo"]
	if not allowed:
		show_toast(puzzle.get("hint", "换个视角再试试。"))
		return
	complete_puzzle(puzzle, node)

func complete_puzzle(puzzle: Dictionary, node: Node) -> void:
	var id: String = str(puzzle.get("id", ""))
	if not state.get("triggered_story", []).has(id):
		state["triggered_story"].append(id)
	if puzzle.has("fragment") and not state.get("fragments", []).has(puzzle["fragment"]):
		state["fragments"].append(puzzle["fragment"])
		show_toast("获得信物：%s （%d/7 件）" % [puzzle["fragment"], state["fragments"].size()], 3.5)
	
	# Unlock views
	if puzzle.has("reward_view"):
		unlock_view(puzzle["reward_view"])
	
	if not state.get("completed_regions", []).has(puzzle.get("region", "")) and puzzle.has("fragment"):
		state["completed_regions"].append(puzzle.get("region", ""))
	
	state["album"].append("记忆片段：%s" % puzzle.get("name", "机关"))
	world.remove_interactable(node)
	show_memory(puzzle)
	autosave()
	
	# Guide player to next objective
	match id:
		"texture_wall":
			show_toast("石门已开启！继续向右探索广阔区域。", 4.0)

func try_finish_game(node: Node) -> void:
	var needed: Array = ["碎片1：回声的理解", "碎片2：沉默的节奏", "碎片3：奔跑的自由", "碎片4：安静的注视", "信物：水坝恢复", "信物：星图", "最后信物：心灵完整"]
	for fragment in needed:
		if not state.get("fragments", []).has(fragment):
			show_toast("时间胶囊还在等待更多信物——收集全部7件后方可开启。")
			return
	state["finished"] = true
	state["album"].append("最终合照")
	world.remove_interactable(node)
	autosave()
	show_ending()

func show_memory(puzzle: Dictionary) -> void:
	var text: String = str({
		"lighthouse_pipe": "记忆：有人摸着树皮，另一个人轻声描述风从湖面来的颜色。",
		"station_cargo": "记忆：手语慢慢变成共同的节奏，大家笑着学会说 谢谢。",
		"park_wheel": "记忆：风筝追着孩子跑，跑得最快的人不用停下来解释自己。",
		"forest_memorial": "记忆：篝火旁有人把手套递回来——我看见你把它落下了。",
		"dam_turbine": "记忆：水流和齿轮一起转动，两个人从不同方向找到同一节奏。",
		"observatory_scope": "记忆：三个人站在望远镜前，用各自的频率对准同一颗星。",
	}.get(puzzle.get("id", ""), "记忆：这里重新亮起了一点颜色。"))
	show_toast(text, 5.0)

func show_ending() -> void:
	if player != null and is_instance_valid(player):
		player.suspend_for_interaction()
	GameData.begin_ending(state, "time_capsule")
	state["return_to_game"] = false
	ProfileManager.save_state(state)
	get_tree().set_meta("mindscape_play_formal_ending", true)
	get_tree().set_meta("mindscape_ending_source", "time_capsule")
	get_tree().change_scene_to_file("res://maze/UndergroundMaze.tscn")

func unlock_view(view: String) -> void:
	if not state.get("unlocked_views", []).has(view):
		state["unlocked_views"].append(view)
		show_toast("新的视角靠近了：%s" % GameData.VIEW_NAMES.get(view, view))

func unlocked_all(views: Array) -> bool:
	for view in views:
		if not state.get("unlocked_views", []).has(view):
			return false
	return true

func open_view_wheel() -> void:
	# 视角轮盘随时可用（按 Tab）
	if is_instance_valid(player):
		player.suspend_for_interaction()
	if wheel_root != null and is_instance_valid(wheel_root):
		wheel_root.queue_free()
	var unlocked: Array = state.get("unlocked_views", [])
	wheel_root = VIEW_WHEEL_UI_SCRIPT.new()
	wheel_root.call("configure", unlocked, str(state.get("current_view", "normal")))
	wheel_root.connect("view_selected", func(view: String):
		try_switch_view(view)
		_close_view_wheel()
	)
	wheel_root.connect("close_requested", _close_view_wheel)
	controls_canvas.add_child(wheel_root)

func _close_view_wheel() -> void:
	if wheel_root != null and is_instance_valid(wheel_root):
		wheel_root.queue_free()
	wheel_root = null
	if is_instance_valid(player):
		player.resume_after_interaction()

func get_view() -> String:
	return str(state.get("current_view", "normal"))

func try_switch_view(view: String) -> void:
	if not state.get("unlocked_views", []).has(view):
		show_toast("这个视角还没有被理解。")
		return
	state["current_view"] = view
	player.set_view(view)
	world.set_view_palette(view)
	_set_blind_hud_visible(view == "blind")
	AudioManager.set_view(view)
	_notify_puzzles_view_changed(view)
	autosave()

# 通知所有谜题实例视角已切换
func _notify_puzzles_view_changed(view: String) -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		if is_instance_valid(node) and node.has_method("update_on_view_change"):
			node.update_on_view_change(view)

func toggle_pause() -> void:
	if pause_root != null and is_instance_valid(pause_root):
		pause_root.queue_free()
		pause_root = null
		get_tree().paused = false
		return
	get_tree().paused = true
	pause_root = PAUSE_MENU_UI_SCRIPT.new()
	pause_root.call("configure", OS.is_debug_build())
	pause_root.connect("resume_requested", toggle_pause)
	pause_root.connect("album_requested", show_album)
	pause_root.connect("notes_requested", show_note_log)
	pause_root.connect("debug_requested", _open_debug_tools)
	pause_root.connect("save_exit_requested", func():
		autosave()
		get_tree().paused = false
		show_main_menu()
	)
	controls_canvas.add_child(pause_root)

func show_album() -> void:
	var album := AlbumPuzzleUI.new()
	album.name = "AlbumPuzzleUI"
	controls_canvas.add_child(album)
	album.setup(state, func(): ProfileManager.save_state(state))

func show_note_log() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "纸条日志"
	var seen: Array = state.get("seen_notes", []) as Array
	var lines: PackedStringArray = []
	for note_id in GameData.PUZZLE_NOTES:
		if seen.has(note_id):
			var note: Dictionary = GameData.PUZZLE_NOTES[note_id]
			lines.append("【%s】\n%s" % [note.get("title", "纸条"), note.get("text", "")])
	if lines.is_empty():
		dialog.dialog_text = "还没有发现纸条。"
	else:
		dialog.dialog_text = "\n\n".join(lines)
	dialog.add_theme_font_size_override("font_size", 18)
	controls_canvas.add_child(dialog)
	dialog.popup_centered(Vector2(620, 520))

func _toggle_debug_lasers() -> void:
	if not OS.is_debug_build():
		return
	state["debug_laser_loadout"] = not bool(state.get("debug_laser_loadout", false))
	_restore_laser_state()
	_update_inventory_sidebar()
	ProfileManager.save_state(state)
	var enabled := bool(state.get("debug_laser_loadout", false))
	show_toast("已领取两个测试激光" if enabled else "已收回未安装的测试激光", 2.0)
	if pause_root != null and is_instance_valid(pause_root):
		pause_root.queue_free()
		pause_root = null
		get_tree().paused = false

func _open_debug_tools() -> void:
	if not OS.is_debug_build() or pause_root == null:
		return
	pause_root.queue_free()
	pause_root = Panel.new()
	pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	controls_canvas.add_child(pause_root)
	pause_root.position = Vector2(220, 70)
	pause_root.size = Vector2(840, 580)
	var title := Label.new()
	title.text = "后期测试工具  ·  仅调试版本"
	title.position = Vector2(28, 18)
	title.size = Vector2(650, 42)
	title.add_theme_font_size_override("font_size", 26)
	pause_root.add_child(title)
	var close_button := Button.new()
	close_button.text = "返回"
	close_button.position = Vector2(704, 16)
	close_button.size = Vector2(108, 40)
	close_button.pressed.connect(func():
		pause_root.queue_free()
		pause_root = null
		get_tree().paused = false
		call_deferred("toggle_pause")
	)
	pause_root.add_child(close_button)
	if not ProfileManager.is_current_profile_debug():
		var warning := Label.new()
		warning.text = "为保护正式进度，测试操作会先复制当前档案。\n原档案不会被传送、解锁或重置。"
		warning.position = Vector2(90, 150)
		warning.size = Vector2(660, 100)
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning.add_theme_font_size_override("font_size", 22)
		pause_root.add_child(warning)
		var clone_button := Button.new()
		clone_button.text = "创建 [TEST] 副本并进入"
		clone_button.position = Vector2(250, 285)
		clone_button.size = Vector2(340, 56)
		clone_button.pressed.connect(_create_debug_profile)
		pause_root.add_child(clone_button)
		return
	var profile_label := Label.new()
	profile_label.text = "当前档案：%s" % ProfileManager.get_current_profile().get("display_name", "[TEST]")
	profile_label.position = Vector2(30, 60)
	profile_label.size = Vector2(760, 28)
	profile_label.add_theme_color_override("font_color", Color("#ffe08a"))
	pause_root.add_child(profile_label)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 96)
	scroll.size = Vector2(792, 450)
	pause_root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.custom_minimum_size = Vector2(760, 0)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	_add_debug_header(grid, "主世界传送")
	_add_button(grid, "中央广场", func(): _debug_restart_main(world.get_player_spawn(), "central"))
	_add_button(grid, "九宫格", func(): _debug_restart_main(world.get_marker_position(&"puzzles", &"nine_grid"), "nine_grid"))
	_add_button(grid, "激光聚焦", func(): _debug_restart_main(world.get_marker_position(&"puzzles", &"laser_focus"), "laser_focus"))
	_add_button(grid, "地下入口", func(): _debug_restart_main(world.get_marker_position(&"specials", &"underground_portal"), "underground_entry"))
	_add_debug_header(grid, "地下 Marker 传送")
	_add_button(grid, "地下起点", func(): _debug_enter_maze("PlayerSpawn"))
	_add_button(grid, "隐藏门", func(): _debug_enter_maze("HiddenDoor"))
	_add_button(grid, "隐藏宝箱", func(): _debug_enter_maze("Chest"))
	_add_button(grid, "迷宫出口", func(): _debug_enter_maze("PortalExit"))
	_add_debug_header(grid, "进度预设")
	_add_button(grid, "九宫格线索", func(): _debug_apply_preset("nine_grid"))
	_add_button(grid, "两个激光", func(): _debug_apply_preset("lasers"))
	_add_button(grid, "隐藏门已开", func(): _debug_apply_preset("hidden_door"))
	_add_button(grid, "指南针路线", func(): _debug_apply_preset("compass"))
	_add_button(grid, "宝箱结局", func(): _debug_apply_preset("ending"))
	_add_button(grid, "通关后广场", func(): _debug_apply_preset("postgame"))
	_add_debug_header(grid, "单项与维护")
	_add_button(grid, "切换测试激光", _debug_toggle_lasers)
	_add_button(grid, "解锁全部视角", _debug_unlock_views)
	_add_button(grid, "补齐全部钥匙", _debug_grant_keys)
	_add_button(grid, "切换指南针", _debug_toggle_compass)
	_add_button(grid, "重置最近谜题", _debug_reset_nearest_puzzle)
	_add_button(grid, "重载当前场景", func(): _debug_restart_main(player.global_position, "reload"))

func _add_debug_header(grid: GridContainer, text_value: String) -> void:
	var header := Label.new()
	header.text = text_value
	header.custom_minimum_size = Vector2(230, 34)
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color("#8deaf0"))
	grid.add_child(header)
	for index in range(2):
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(1, 1)
		grid.add_child(spacer)

func _create_debug_profile() -> void:
	state["position"] = player.global_position
	ProfileManager.save_state(state)
	var clone := ProfileManager.create_debug_clone(state)
	state = (clone.get("state", GameData.default_state()) as Dictionary).duplicate(true)
	_debug_restart_main(state.get("position", world.get_player_spawn()) as Vector2, "cloned")

func _debug_require_profile() -> bool:
	return OS.is_debug_build() and ProfileManager.is_current_profile_debug()

func _debug_close_pause() -> void:
	if pause_root != null and is_instance_valid(pause_root):
		pause_root.queue_free()
	pause_root = null
	get_tree().paused = false

func _debug_restart_main(target: Vector2, preset: String) -> void:
	if not _debug_require_profile():
		return
	state["position"] = target
	state["debug_preset"] = preset
	state["debug_spawn_target"] = ""
	ProfileManager.save_state(state)
	_debug_close_pause()
	call_deferred("start_game", false)

func _debug_enter_maze(marker_name: String) -> void:
	if not _debug_require_profile():
		return
	state["debug_spawn_target"] = marker_name
	state["debug_preset"] = "maze_%s" % marker_name.to_snake_case()
	ProfileManager.save_state(state)
	_debug_close_pause()
	get_tree().change_scene_to_file("res://maze/UndergroundMaze.tscn")

func _debug_apply_preset(preset: String) -> void:
	if not _debug_require_profile():
		return
	state["debug_preset"] = preset
	match preset:
		"nine_grid":
			(state.get("completed_levels", []) as Array).erase("nine_grid")
			if not (state.get("unlocked_views", []) as Array).has("depression"):
				(state.get("unlocked_views", []) as Array).append("depression")
			state["current_view"] = "depression"
			_debug_restart_main(world.get_marker_position(&"puzzles", &"nine_grid"), preset)
			return
		"lasers":
			state["debug_laser_loadout"] = true
			_debug_restart_main(world.get_marker_position(&"puzzles", &"laser_focus"), preset)
			return
		"hidden_door", "compass", "ending":
			GameData.unlock_hidden_door(state)
			state["maze_compass_owned"] = preset != "hidden_door"
			state["maze_compass_enabled"] = preset == "compass"
			if preset == "ending":
				state["hidden_chest_opened"] = false
				state["ending_seen"] = false
				state["ending_pending"] = false
				_debug_enter_maze("Chest")
			else:
				_debug_enter_maze("HiddenDoor" if preset == "hidden_door" else "PlayerSpawn")
			return
		"postgame":
			state["finished"] = true
			state["ending_seen"] = true
			state["ending_pending"] = false
			_debug_restart_main(world.get_player_spawn(), preset)

func _debug_toggle_lasers() -> void:
	state["debug_laser_loadout"] = not bool(state.get("debug_laser_loadout", false))
	_debug_restart_main(player.global_position, "lasers_toggle")

func _debug_unlock_views() -> void:
	state["unlocked_views"] = GameData.VIEWS.duplicate()
	_debug_restart_main(player.global_position, "all_views")

func _debug_grant_keys() -> void:
	state["collected_keys"] = GameData.KEYS.keys()
	_debug_restart_main(player.global_position, "all_keys")

func _debug_toggle_compass() -> void:
	state["maze_compass_owned"] = true
	state["maze_compass_enabled"] = not bool(state.get("maze_compass_enabled", false))
	_debug_restart_main(player.global_position, "compass_toggle")

func _debug_reset_nearest_puzzle() -> void:
	var nearest_id := ""
	var nearest_position := player.global_position
	var nearest_distance := INF
	for level in GameData.LEVELS:
		var level_id := str(level.get("id", ""))
		var level_position := world.get_marker_position(&"puzzles", StringName(level_id))
		var distance := player.global_position.distance_squared_to(level_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = level_id
			nearest_position = level_position
	(state.get("completed_levels", []) as Array).erase(nearest_id)
	if nearest_id == "nine_grid":
		state["current_view"] = "depression"
	_debug_restart_main(nearest_position, "reset_%s" % nearest_id)

func _set_blind_hud_visible(is_blind: bool) -> void:
	if hud_label != null:
		hud_label.visible = not is_blind
	if objective_label != null:
		objective_label.visible = not is_blind
	if prompt_label != null:
		prompt_label.visible = not is_blind
	if damage_overlay != null:
		damage_overlay.visible = not is_blind

func autosave_with_laser_angles() -> void:
	if not game_running:
		return
	state["position"] = player.global_position
	state["laser_1_angle"] = world.get_laser_angle(1)
	state["laser_2_angle"] = world.get_laser_angle(2)
	ProfileManager.save_state(state)

func _restore_laser_state() -> void:
	# 旧版风向标系统已移除；把旧存档中放置的装置收回物品栏。
	state["laser_1_placed"] = false
	state["laser_2_placed"] = false
	# 恢复激光装置拥有状态
	laser_owned["laser_device_1"] = bool(state.get("debug_laser_loadout", false))
	laser_owned["laser_device_2"] = bool(state.get("debug_laser_loadout", false))
	for level in GameData.LEVELS:
		if state.get("completed_levels", []).has(level["id"]):
			var reward: String = str(level.get("reward", ""))
			if reward == "laser_device_1":
				laser_owned["laser_device_1"] = true
			elif reward == "laser_device_2":
				laser_owned["laser_device_2"] = true
	
func _restore_laser_focus_state() -> void:
	# 找到场景中的 PuzzleLaserFocus 节点，恢复其安装状态
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is PuzzleLaserFocus:
			(node as PuzzleLaserFocus).restore_installation_state(state)


## 激光聚焦台：检查指定激光装置是否可以安装到聚焦台（已拥有且尚未放置在风向标上）
func is_laser_available_for_focus(id: String) -> bool:
	if not laser_owned.get(id, false):
		return false
	var slot_index := 1 if id == "laser_device_1" else 2
	if bool(state.get("laser_focus_%d_installed" % slot_index, false)):
		return false
	# 已拖放到世界中的风向标上则不可用
	if id == "laser_device_1" and state.get("laser_1_placed", false):
		return false
	if id == "laser_device_2" and state.get("laser_2_placed", false):
		return false
	return true


## 激光聚焦台：将装置安装到聚焦台（slot_idx=1或2），成功返回true
func install_laser_in_focus(slot_idx: int) -> bool:
	var id := "laser_device_%d" % slot_idx
	if not is_laser_available_for_focus(id):
		return false
	# 记录安装状态（与风向标放置分开存储）
	state["laser_focus_%d_installed" % slot_idx] = true
	autosave()
	return true


func autosave() -> void:
	if not game_running:
		return
	state["position"] = player.global_position
	ProfileManager.save_state(state)
	AudioManager.play_sfx("save")

func _on_player_special(view: String) -> void:
	match view:
		"adhd":
			show_toast("冲刺！——沿当前方向继续奔跑。", 0.8)
			AudioManager.play_sfx("dash")
		"autism":
			show_toast("细节放大——模式变得清晰。", 1.6)
		"depression":
			show_toast("潜台词浮现，地面尖刺显露。", 1.6)

# ── Monster Damage Visual Effects ──
func _on_monster_damage(monster_type: String) -> void:
	if damage_overlay == null or not is_instance_valid(damage_overlay):
		return
	
	# Kill old tween if running
	if damage_tween != null and damage_tween.is_valid():
		damage_tween.kill()
	
	# Flash red based on monster type
	var flash_color: Color
	var shake_power: float
	match monster_type:
		"noise":
			flash_color = Color(0.4, 0.7, 1.0, 0.0)  # blue disorientation
			shake_power = 4.0
		"silent_mouth":
			flash_color = Color(0.6, 0.3, 0.9, 0.0)  # purple/vibration
			shake_power = 5.0
		"shadow":
			flash_color = Color(0.8, 0.0, 0.0, 0.0)  # red dread
			shake_power = 6.0
	
	# Red flash + shake
	damage_tween = create_tween()
	damage_overlay.color = Color(flash_color.r, flash_color.g, flash_color.b, 0.55)
	damage_tween.tween_property(damage_overlay, "color", Color(flash_color.r, flash_color.g, flash_color.b, 0.0), 0.5)
	
	# Camera shake
	_camera_shake(shake_power)

func _camera_shake(power: float) -> void:
	if camera == null:
		return
	var original_offset := camera.offset
	var shake_tween := create_tween()
	shake_tween.set_loops(6)
	shake_tween.tween_property(camera, "offset", Vector2(randf_range(-power, power), randf_range(-power * 0.6, power * 0.6)), 0.04)
	shake_tween.tween_property(camera, "offset", Vector2(randf_range(-power, power), randf_range(-power * 0.6, power * 0.6)), 0.04)
	shake_tween.finished.connect(func(): camera.offset = original_offset)

func _check_monsters() -> void:
	if monster_hint_cooldown > 0.0:
		return
	for node in get_tree().get_nodes_in_group("monster"):
		if not is_instance_valid(node):
			continue
		var monster: MindscapeMonster = node as MindscapeMonster
		if monster == null or not monster.is_active:
			continue
		var dist: float = player.global_position.distance_to(monster.global_position)
		if dist > 60.0:
			continue
		# Show warning toast
		match monster.monster_type:
			"noise":
				show_toast("⚠ 信息噪音制造假回声！靠近真实物体更安全。", 1.2)
			"silent_mouth":
				show_toast("⚠ 无声嘴巴挡住振动路线！换个角度观察地面。", 1.2)
			"shadow":
				show_toast("⚠ 阴影让脚步沉重……寻找环境里的光。", 1.2)
		monster_hint_cooldown = 1.6
		return

func show_toast(text: String, duration: float = 3.0) -> void:
	if hud == null:
		return
	if is_instance_valid(active_toast):
		active_toast.queue_free()
	if active_toast_tween != null and active_toast_tween.is_valid():
		active_toast_tween.kill()
	var toast := Label.new()
	active_toast = toast
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.position = Vector2(240, 88)
	toast.size = Vector2(800, 70)
	toast.add_theme_font_size_override("font_size", 24)
	hud.add_child(toast)
	active_toast_tween = create_tween()
	active_toast_tween.tween_interval(duration)
	active_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.45)
	active_toast_tween.tween_callback(func():
		if active_toast == toast:
			active_toast = null
		toast.queue_free()
	)

func _show_puzzle_note_once(node: Node) -> bool:
	if note_popup == null or not is_instance_valid(note_popup):
		return false
	var note_id := ""
	if node is PuzzleTextureWall:
		note_id = "texture_wall"
	elif node is PuzzleFindDifference:
		note_id = "find_difference"
	elif node is PuzzleBanquetPainting:
		note_id = "banquet_painting"
	elif node is PuzzleAmusementLights:
		note_id = "amusement_lights"
	elif node is PuzzleNPCPassword:
		note_id = "npc_password"
	elif node is PuzzleLaserFocus:
		var lasers_installed := bool(state.get("laser_focus_1_installed", false)) and bool(state.get("laser_focus_2_installed", false))
		note_id = "laser_focus_ready" if lasers_installed else "laser_focus"
	else:
		var kind := str(node.get_meta("kind", ""))
		if kind == "puzzle":
			note_id = str(node.get_meta("id", ""))
	if note_id.is_empty() or not GameData.PUZZLE_NOTES.has(note_id):
		return false
	var seen: Array = state.get("seen_notes", []) as Array
	if seen.has(note_id):
		return false
	seen.append(note_id)
	state["seen_notes"] = seen
	ProfileManager.save_state(state)
	player.suspend_for_interaction()
	note_popup.call("open_note", GameData.PUZZLE_NOTES[note_id], str(state.get("current_view", "normal")))
	return true

func _puzzle_by_id(id: String) -> Dictionary:
	# 在新 LEVELS 数据中查找
	for level in GameData.LEVELS:
		if level.get("id", "") == id:
			return level
	return {}

func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#f5ead7"))
	button.add_theme_stylebox_override("normal", _menu_button_style(Color("#8ec9ff"), false))
	button.add_theme_stylebox_override("hover", _menu_button_style(Color("#8ec9ff"), true))
	button.add_theme_stylebox_override("pressed", _menu_button_style(Color("#5ba8ff"), true))
	button.add_theme_stylebox_override("focus", _menu_button_style(Color("#f0c98a"), true))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_profile_button(parent: Control, text: String, profile_id: String) -> Button:
	var button := _add_button(parent, text, func():
		ProfileManager.set_current_profile(profile_id)
		if ProfileManager.current_profile_has_accepted_agreement():
			show_main_menu()
		else:
			show_login_screen()
	)
	button.custom_minimum_size = Vector2(0, 116)
	return button

func _add_view_button(parent: Control, view: String) -> Button:
	return _add_button(parent, GameData.VIEW_NAMES[view], func():
		try_switch_view(view)
		_close_view_wheel()
	)

func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
