extends Node

const MAZE_COMPASS_TEXTURE := preload("res://assets/ui/generated/maze_compass.png")
const HIDDEN_DOOR_TEXTURE := preload("res://assets/ui/generated/hidden_stone_door.png")
const UNDERGROUND_ENTRY_AUDIO := preload("res://assets/audio/enter_underground_maze.MP3")

var world: MindscapeWorld
var player: MindscapePlayer
var camera: Camera2D
var hud: CanvasLayer
var inventory_canvas: CanvasLayer
var controls_canvas: CanvasLayer
var dialogue: DialogueBox
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
var login_name_input: LineEdit
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
	else:
		show_login_screen()

func _process(delta: float) -> void:
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
	if player == null:
		return
	var px := player.global_position.x
	var region := "spawn"
	if px < 2200:                    # 左侧森林（纹理墙+找不同+宴会场）
		region = "forest"
	elif px < 4200:                  # 出生点/中央广场
		region = "spawn"
	elif px < 5600:                  # 湖泊灯塔区
		region = "lighthouse"
	elif px < 6800:                  # 水坝工业区
		region = "dam"
	elif px < 8400:                  # 旧车站
		region = "station"
	elif px < 9800:                  # 游乐园
		region = "park"
	else:                              # 许愿堂
		region = "observatory"
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

func show_login_screen() -> void:
	clear_scene()
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)
	var bg := ColorRect.new()
	bg.color = Color("#17232f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var title := Label.new()
	title.text = "心灵视界\nMindscape"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(410, 70)
	title.size = Vector2(460, 120)
	title.add_theme_font_size_override("font_size", 52)
	menu_root.add_child(title)
	var card := Panel.new()
	card.position = Vector2(410, 230)
	card.size = Vector2(460, 330)
	menu_root.add_child(card)
	var current_profile: Dictionary = ProfileManager.get_current_profile()
	var avatar := Label.new()
	avatar.text = "本地档案"
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.position = Vector2(135, 28)
	avatar.size = Vector2(190, 34)
	avatar.add_theme_font_size_override("font_size", 28)
	card.add_child(avatar)
	var profile_label := Label.new()
	profile_label.text = "当前玩家：%s" % current_profile.get("display_name", "旅行者")
	profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile_label.position = Vector2(45, 78)
	profile_label.size = Vector2(370, 36)
	profile_label.add_theme_font_size_override("font_size", 22)
	card.add_child(profile_label)
	login_name_input = LineEdit.new()
	login_name_input.placeholder_text = "输入新玩家名字"
	login_name_input.position = Vector2(80, 135)
	login_name_input.size = Vector2(300, 42)
	card.add_child(login_name_input)
	var buttons := VBoxContainer.new()
	buttons.position = Vector2(115, 198)
	buttons.size = Vector2(230, 100)
	buttons.add_theme_constant_override("separation", 12)
	card.add_child(buttons)
	_add_button(buttons, "登录当前档案", func(): show_main_menu())
	_add_button(buttons, "创建并登录", func():
		var typed_name: String = login_name_input.text.strip_edges()
		if typed_name.is_empty():
			typed_name = "旅行者%d" % (ProfileManager.list_profiles().size() + 1)
		ProfileManager.create_profile(typed_name, "sun")
		show_main_menu()
	)

func show_main_menu() -> void:
	clear_scene()
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)
	var bg := ColorRect.new()
	bg.color = Color("#25384a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var title := Label.new()
	title.text = "心灵视界\nMindscape"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(420, 90)
	title.size = Vector2(440, 130)
	title.add_theme_font_size_override("font_size", 54)
	menu_root.add_child(title)
	var current_profile: Dictionary = ProfileManager.get_current_profile()
	var current_state: Dictionary = current_profile.get("state", {}) as Dictionary
	var player_name := Label.new()
	player_name.text = "玩家：%s%s" % [current_profile.get("display_name", "旅行者"), "  ·  已通关" if bool(current_state.get("finished", false)) else ""]
	player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_name.position = Vector2(330, 230)
	player_name.size = Vector2(620, 32)
	player_name.add_theme_font_size_override("font_size", 22)
	player_name.modulate = Color("#ffe8a0")
	menu_root.add_child(player_name)
	var capsule := Label.new()
	capsule.text = "旅程已经完成，仍可继续寻找遗漏的纪念物" if bool(current_state.get("finished", false)) else "中央广场的时间胶囊正在等待被重新理解"
	capsule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capsule.position = Vector2(330, 268)
	capsule.size = Vector2(620, 42)
	capsule.add_theme_font_size_override("font_size", 22)
	menu_root.add_child(capsule)
	var buttons := VBoxContainer.new()
	buttons.position = Vector2(510, 340)
	buttons.size = Vector2(260, 280)
	buttons.add_theme_constant_override("separation", 14)
	menu_root.add_child(buttons)
	_add_button(buttons, "继续游戏", func(): start_game(false))
	_add_button(buttons, "新游戏", func():
		ProfileManager.reset_current_profile()
		start_game(true)
	)
	_add_button(buttons, "切换档案", func(): show_profile_menu())
	_add_button(buttons, "设置", func(): show_settings())
	_add_button(buttons, "退出", func(): get_tree().quit())

func show_profile_menu() -> void:
	clear_scene()
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)
	var bg := ColorRect.new()
	bg.color = Color("#1f3141")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)
	var title := Label.new()
	title.text = "玩家档案"
	title.position = Vector2(90, 60)
	title.add_theme_font_size_override("font_size", 44)
	menu_root.add_child(title)
	var list := VBoxContainer.new()
	list.position = Vector2(90, 140)
	list.size = Vector2(760, 420)
	list.add_theme_constant_override("separation", 10)
	menu_root.add_child(list)
	for profile in ProfileManager.list_profiles():
		var stats: Dictionary = profile.get("stats", {})
		var profile_state: Dictionary = profile.get("state", {}) as Dictionary
		var status := "已通关  ·  " if bool(profile_state.get("finished", false)) else ""
		var text := "%s  ·  %s完成度 %d%%  ·  相册 %d  ·  游玩 %s" % [
			profile.get("display_name", "旅行者"),
			status,
			stats.get("completion", 0),
			stats.get("album_count", 0),
			_format_time(stats.get("play_time", 0.0)),
		]
		_add_profile_button(list, text, profile.get("id", ""))
	_add_button(list, "创建新档案", func():
		ProfileManager.create_profile("旅行者%d" % (ProfileManager.list_profiles().size() + 1), ["sun", "moon", "leaf"][ProfileManager.list_profiles().size() % 3])
		show_profile_menu()
	)
	_add_button(list, "返回登录", func(): show_login_screen())

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
	world = MindscapeWorld.new()
	add_child(world)
	world.build(state)
	# 恢复激光装置状态
	_restore_laser_state()
	# 恢复激光聚焦台安装状态
	_restore_laser_focus_state()
	# 连接新系统信号
	world.puzzle_completed.connect(on_level_completed)
	world.hint_updated.connect(func(txt: String): show_toast(txt, 3.0))
	player = MindscapePlayer.create()
	var start_position: Vector2 = state.get("position", GameData.PLAYER_START) as Vector2
	# Safety: if saved position is out of world bounds, reset to safe spawn
	var world_max_y: float = GameData.WORLD_SIZE.y - 80.0
	var world_max_x: float = GameData.WORLD_SIZE.x - 80.0
	if start_position.y > world_max_y or start_position.y < 200.0:
		start_position = GameData.PLAYER_START
	if start_position.x < 0.0 or start_position.x > world_max_x:
		start_position = GameData.PLAYER_START
	player.global_position = start_position
	add_child(player)
	player.add_to_group("player")
	player.set_view(str(state.get("current_view", "normal")))
	player.special_used.connect(_on_player_special)
	camera = Camera2D.new()
	camera.enabled = true
	camera.zoom = Vector2(1.0, 1.0)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameData.WORLD_SIZE.x)
	camera.limit_bottom = int(GameData.WORLD_SIZE.y)
	player.add_child(camera)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	dialogue.closed.connect(_on_dialogue_closed)
	_make_hud()
	world.set_view_palette(str(state.get("current_view", "normal")))
	_set_blind_hud_visible(str(state.get("current_view", "normal")) == "blind")
	# Connect all monster damage signals
	for node in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(node) and node.has_signal("player_touched"):
			node.player_touched.connect(_on_monster_damage)
	game_running = true
	autosave()
	if new_game:
		show_intro()

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
	player.controls_enabled = false
	var intro := AcceptDialog.new()
	intro.title = "心灵花园 · 序章"
	intro.dialog_text = """━━━━━━ 心灵花园 Mindscape ━━━━━━

五个人曾经是最好的朋友。

阿明——看不见光，但听得见风从湖面来的颜色。
阿冲——总是停不下来，跑得最快的人不用解释自己。
小静——安静地注视，只有她能看见被忽略的痕迹。
小远——从细节中发现规律，把混乱变成秩序。
而你——你学会了理解每个人眼中的风景。

后来，时间胶囊被封印了。
怪物侵入了每个区域，把真正的感知
变成了噪音、干扰和阴影。

要打开胶囊，你需要重新走入四种视角——
在记忆长椅旁坐下来，切换感知方式。

━━━━━━━━━━━━━━━━━━
【操作】
A/D 左右移动    Space 跳跃
E   互动（对话/解谜/收集）
F   特殊能力（盲人回声探测/ADHD冲刺）
TAB 视角轮盘    ESC 暂停

【四种视角】
盲人模式：画面全黑，靠F键回声定位
ADHD模式：按方向键自动持续行走，跳跃更高
自闭症模式：细节放大，能发现隐藏模式
抑郁模式：画面灰暗，地面尖刺显露，能看到潜台词

━━━━━━━━━━━━━━━━━━
━━━━━━━━━━━━━━━━━━

风铃、手套、风筝、照片和纪念徽章，
还在等你把它们带回家。"""
	add_child(intro)
	intro.confirmed.connect(func():
		player.controls_enabled = true
		show_toast("→ 沿地面金色光点向右走，触摸发光的回声共鸣石。", 4.0)
	)
	intro.popup_centered(Vector2(680, 580))

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
	
	# HUD - player name + view + progress
	var profile_name: String = ProfileManager.get_current_profile().get("display_name", "旅行者")
	var view_color: Color = GameData.VIEW_COLORS.get(view, Color.WHITE)
	var frag_text := ""
	if fragment_list.size() > 0:
		frag_text = " | 信物 %d/7" % fragment_list.size()
	hud_label.text = "%s  [%s]%s | 收集 %d" % [
		profile_name,
		GameData.VIEW_NAMES.get(view, view),
		frag_text,
		collectible_list.size(),
	]
	hud_label.modulate = view_color.lightened(0.3)
	
	# Objective line — always visible
	objective_label.text = _get_objective()
	
	# Build prompt text (E for interact, F for echo in blind mode)
	var parts: PackedStringArray = []
	if current_near != null:
		parts.append("[E] %s" % _describe_interactable(current_near))
	var v: String = str(state.get("current_view", "normal"))
	if v == "blind":
		parts.append("[F] 声波探测 — 按下释放回音感知怪物和地形")
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

	var fade_canvas := CanvasLayer.new()
	fade_canvas.name = "UndergroundTransition"
	fade_canvas.layer = 2000
	add_child(fade_canvas)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_canvas.add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.42)
	await tween.finished
	var transition_audio := AudioStreamPlayer.new()
	transition_audio.name = "UndergroundEntryAudio"
	transition_audio.stream = UNDERGROUND_ENTRY_AUDIO
	transition_audio.volume_db = -2.0
	fade_canvas.add_child(transition_audio)
	transition_audio.play()
	await transition_audio.finished
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
		
		if item_id.begins_with("key_"):
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
	var raw_lines: Array = GameData.DIALOGUES.get(npc_node.npc_id, [{"expr": "normal", "text": "你好。"}])
	# 根据视角过滤：抑郁模式才能看到 subtext
	var lines: Array = []
	for line in raw_lines:
		var filtered: Dictionary = line.duplicate()
		if view == "depression" and line.has("subtext"):
			filtered["text"] = str(line["text"]) + "\n[潜台词] " + str(line["subtext"])
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
	wheel_root = Panel.new()
	wheel_root.position = Vector2(440, 180)
	wheel_root.size = Vector2(400, 320)
	controls_canvas.add_child(wheel_root)
	var title := Label.new()
	title.text = "切换视角"
	title.position = Vector2(130, 20)
	title.add_theme_font_size_override("font_size", 30)
	wheel_root.add_child(title)
	
	var unlocked: Array = state.get("unlocked_views", [])
	var views_available := false
	var list := VBoxContainer.new()
	list.position = Vector2(70, 75)
	list.size = Vector2(260, 220)
	wheel_root.add_child(list)
	
	for view in GameData.VIEWS:
		if unlocked.has(view):
			views_available = true
			_add_view_button(list, view)
	
	if not views_available:
		var hint := Label.new()
		hint.text = "还没有理解新的视角。\n去灯塔区域触碰回声共鸣石吧。"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.position = Vector2(20, 60)
		hint.size = Vector2(220, 80)
		hint.add_theme_font_size_override("font_size", 18)
		list.add_child(hint)
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "起身"
	close_btn.position = Vector2(70, 260)
	close_btn.size = Vector2(260, 44)
	close_btn.pressed.connect(_close_view_wheel)
	wheel_root.add_child(close_btn)

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
	pause_root = Panel.new()
	pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_root.position = Vector2(450, 190)
	pause_root.size = Vector2(380, 320)
	controls_canvas.add_child(pause_root)
	var list := VBoxContainer.new()
	list.position = Vector2(70, 45)
	list.size = Vector2(240, 240)
	list.add_theme_constant_override("separation", 12)
	pause_root.add_child(list)
	_add_button(list, "继续", func(): toggle_pause())
	_add_button(list, "纪念相册", func(): show_album())
	if OS.is_debug_build():
		_add_button(list, "测试工具", _open_debug_tools)
	_add_button(list, "保存并回主菜单", func():
		autosave()
		get_tree().paused = false
		show_main_menu()
	)

func show_album() -> void:
	var album := AlbumPuzzleUI.new()
	album.name = "AlbumPuzzleUI"
	controls_canvas.add_child(album)
	album.setup(state, func(): ProfileManager.save_state(state))

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
	for child in pause_root.get_children():
		child.queue_free()
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
	_add_button(grid, "中央广场", func(): _debug_restart_main(GameData.PLAYER_START, "central"))
	_add_button(grid, "九宫格", func(): _debug_restart_main(Vector2(6600, 3165), "nine_grid"))
	_add_button(grid, "激光聚焦", func(): _debug_restart_main(Vector2(3900, 3168), "laser_focus"))
	_add_button(grid, "地下入口", func(): _debug_restart_main(Vector2(9000, 3168), "underground_entry"))
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
	_debug_restart_main(state.get("position", GameData.PLAYER_START) as Vector2, "cloned")

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
			_debug_restart_main(Vector2(6600, 3165), preset)
			return
		"lasers":
			state["debug_laser_loadout"] = true
			_debug_restart_main(Vector2(3900, 3168), preset)
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
			_debug_restart_main(GameData.PLAYER_START, preset)

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
		var level_position: Vector2 = level.get("pos", Vector2.ZERO) as Vector2
		var distance := player.global_position.distance_squared_to(level_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = str(level.get("id", ""))
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
		"blind":
			world.trigger_echo_pulse(Vector2(0.5, 0.5))
			show_toast("回声扩散——真实物体轮廓浮现。", 1.6)
			AudioManager.play_sfx("echo")
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
		"distractor":
			flash_color = Color(1.0, 0.5, 0.0, 0.0)  # orange confusion
			shake_power = 3.0
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
			"distractor":
				show_toast("⚠ 干扰者让你迷失方向！稳定发光才是真的。", 1.2)
			"shadow":
				show_toast("⚠ 阴影让脚步沉重……寻找环境里的光。", 1.2)
		monster_hint_cooldown = 1.6
		return

func show_toast(text: String, duration: float = 3.0) -> void:
	if hud == null:
		return
	var toast := Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.position = Vector2(240, 88)
	toast.size = Vector2(800, 70)
	toast.add_theme_font_size_override("font_size", 24)
	hud.add_child(toast)
	var tween: Tween = create_tween()
	tween.tween_interval(duration)
	tween.tween_property(toast, "modulate:a", 0.0, 0.45)
	tween.tween_callback(toast.queue_free)

func _puzzle_by_id(id: String) -> Dictionary:
	# 在新 LEVELS 数据中查找
	for level in GameData.LEVELS:
		if level.get("id", "") == id:
			return level
	return {}

func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(230, 48)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_profile_button(parent: Control, text: String, profile_id: String) -> Button:
	return _add_button(parent, text, func():
		ProfileManager.set_current_profile(profile_id)
		show_main_menu()
	)

func _add_view_button(parent: Control, view: String) -> Button:
	return _add_button(parent, GameData.VIEW_NAMES[view], func():
		try_switch_view(view)
		_close_view_wheel()
	)

func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
