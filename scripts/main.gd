extends Node

var world: MindscapeWorld
var player: MindscapePlayer
var camera: Camera2D
var hud: CanvasLayer
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
var key_inventory_panel: Panel  # 钥匙物品栏面板
var key_slot_bgs: Array[ColorRect] = []  # 4个钥匙槽背景
var key_slot_icons: Array[Label] = []  # 4个钥匙槽图标

func _ready() -> void:
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
	_check_monsters()
	_update_hud()
	_update_audio_region()

func _update_audio_region() -> void:
	if player == null:
		return
	var px := player.global_position.x
	var py := player.global_position.y
	var region := "spawn"
	if py > 4150:                    # 地下层
		region = "underground"
	elif px < 2200:                   # 左侧森林（纹理墙+找不同+宴会场）
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
	var player_name := Label.new()
	player_name.text = "玩家：%s" % ProfileManager.get_current_profile().get("display_name", "旅行者")
	player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_name.position = Vector2(330, 230)
	player_name.size = Vector2(620, 32)
	player_name.add_theme_font_size_override("font_size", 22)
	player_name.modulate = Color("#ffe8a0")
	menu_root.add_child(player_name)
	var capsule := Label.new()
	capsule.text = "中央广场的时间胶囊正在等待被重新理解"
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
	menu_root.queue_free()
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
		var text := "%s  ·  完成度 %d%%  ·  相册 %d  ·  游玩 %s" % [
			profile.get("display_name", "旅行者"),
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
	dialogue.closed.connect(func(): player.controls_enabled = true)
	_make_hud()
	world.set_view_palette(str(state.get("current_view", "normal")))
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
	prompt_label.position = Vector2(340, 650)
	prompt_label.size = Vector2(600, 40)
	prompt_label.add_theme_font_size_override("font_size", 24)
	hud.add_child(prompt_label)
	# Damage overlay (red flash + vignette on monster hit)
	damage_overlay = ColorRect.new()
	damage_overlay.name = "DamageOverlay"
	damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	hud.add_child(damage_overlay)
	
	# ── 钥匙物品栏 ──
	key_inventory_panel = Panel.new()
	key_inventory_panel.position = Vector2(1050, 14)
	key_inventory_panel.size = Vector2(210, 50)
	hud.add_child(key_inventory_panel)
	
	var key_label := Label.new()
	key_label.text = "钥匙"
	key_label.position = Vector2(8, 4)
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", Color("#ffd700"))
	key_inventory_panel.add_child(key_label)
	
	for i in range(4):
		var slot := ColorRect.new()
		slot.position = Vector2(10 + i * 48, 22)
		slot.size = Vector2(38, 22)
		slot.color = Color("#1a1a2e")
		key_inventory_panel.add_child(slot)
		key_slot_bgs.append(slot)
		# 钥匙图标
		var icon := Label.new()
		icon.text = "·"
		icon.position = Vector2(10 + i * 48 + 14, 23)
		icon.add_theme_font_size_override("font_size", 14)
		icon.add_theme_color_override("font_color", Color("#444466"))
		key_inventory_panel.add_child(icon)
		key_slot_icons.append(icon)

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
	
	# 更新钥匙物品栏
	_update_key_inventory()

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
	if not completed.has("dark_maze"):
		return "→ 灯塔附近往下走台阶——[地下黑暗迷宫]需要盲人模式"
	
	if keys.size() < 4:
		var missing := 4 - keys.size()
		return "→ 收集剩余%d把钥匙后，去地下迷宫岔路B开启宝箱！" % missing
	
	return "→ 四把钥匙集齐！去地下迷宫深处的宝箱..."

func _describe_interactable(node: Node) -> String:
	# 优先按实例类型识别新关卡节点
	if node is PuzzleTextureWall:    return "[关卡1] 纹理墙 — 触觉按键谜题"
	if node is PuzzleFindDifference: return "[关卡2] 找不同密室 — 视角找差异"
	if node is PuzzleBanquetPainting: return "[关卡3] 宴会厅油画 — 舞蹈序列"
	if node is PuzzleAmusementLights: return "[关卡4] 游乐园灯板 — 音频+速度"
	if node is PuzzleNPCPassword:    return "[关卡5] NPC密码台 — 潜台词解码"
	if node is PuzzleDarkMaze:       return "[关卡6] 黑暗迷宫 — 听觉导航"
	
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
		"teleport":
			return "传送"
		"treasure_chest":
			var keys: Array = state.get("collected_keys", [])
			if keys.size() >= 4:
				return "★ 时间胶囊宝箱（已解锁！）"
			return "★ 宝箱（%d/4钥匙）" % keys.size()
		"zone_indicator":
			return "关卡区域"
	return "某个东西"

func interact() -> void:
	if current_near == null:
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
		"teleport":
			var target: Vector2 = current_near.get_meta("target", GameData.PLAYER_START) as Vector2
			player.global_position = target
			show_toast("回到了地面。")
		"treasure_chest":
			try_open_treasure_chest(current_near)
		"zone_indicator":
			show_toast("关卡区域：%s" % _describe_interactable(current_near))
		"maze_fork_a":
			show_toast("岔路A尽头：钥匙3可能就在这里...再往前走走。", 2.0)
		"maze_fork_b":
			var keys := get_collected_keys()
			show_toast("岔路B尽头：宝箱（%d/4钥匙）。" % keys.size(), 2.0)
		_:
			# 新式谜题实例（PuzzleTextureWall等）自带交互处理
			if current_near.has_method("_input"):
				pass  # 谜题自己处理输入

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
	player.controls_enabled = false
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
	player.controls_enabled = false
	# Short delay before wheel to simulate "sitting down"
	var timer := get_tree().create_timer(0.4)
	timer.timeout.connect(func():
		open_view_wheel()
		player.controls_enabled = true
	)

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
	if state.get("collected_keys", []).has(key_id):
		return
	var keys: Array = state.get("collected_keys", [])
	keys.append(key_id)
	state["collected_keys"] = keys
	
	var key_data: Dictionary = GameData.KEYS.get(key_id, {})
	var key_name: String = key_data.get("name", key_id)
	show_toast("🔑 获得钥匙：%s（%d/4）" % [key_name, keys.size()])
	AudioManager.play_sfx("collect")
	
	# 更新宝箱显示
	world.update_treasure_key_count(keys)
	
	# 检查是否集齐4把钥匙
	if keys.size() >= 4:
		show_toast("✨ 四把钥匙全部集齐！去地下迷宫岔路B开启宝箱！", 5.0)
	
	autosave()

func get_collected_keys() -> Array:
	return state.get("collected_keys", [])

func _update_key_inventory() -> void:
	if key_slot_bgs.is_empty():
		return
	var keys: Array = state.get("collected_keys", [])
	var key_colors: Dictionary = {}
	for kdata in GameData.KEYS.values():
		key_colors[kdata.get("source", "")] = kdata.get("color", Color.WHITE)
	
	# 按获得顺序对应的来源颜色
	var source_order := ["banquet_painting", "amusement_lights", "dark_maze", "npc_password"]
	
	for i in range(4):
		if i < keys.size():
			var key_id: String = keys[i]
			var idx := -1
			for j in range(source_order.size()):
				if GameData.KEYS.get(source_order[j], {}).get("source", "") == source_order[j] and source_order[j] == _key_to_source(key_id):
					idx = j
					break
			# Fallback: just use index
			if idx < 0:
				idx = i % source_order.size()
			var kc: Color = GameData.KEYS.get(key_id, {}).get("color", Color("#ffd700")) as Color
			key_slot_bgs[i].color = kc.darkened(0.5)
			key_slot_icons[i].text = "🔑"
			key_slot_icons[i].add_theme_color_override("font_color", kc)
		else:
			key_slot_bgs[i].color = Color("#1a1a2e")
			key_slot_icons[i].text = "·"
			key_slot_icons[i].add_theme_color_override("font_color", Color("#444466"))

func _key_to_source(key_id: String) -> String:
	for k in GameData.KEYS:
		if k == key_id:
			return GameData.KEYS[k].get("source", "")
	return ""

func try_open_treasure_chest(chest_node: Node) -> void:
	var keys: Array = state.get("collected_keys", [])
	if keys.size() >= 4:
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
		show_toast("宝箱锁住了...你需要收集4把钥匙。（当前：%d/4）" % keys.size(), 3.0)

# 当关卡完成时的回调（由 world._on_puzzle_completed 触发）
func on_level_completed(level_id: String, reward_id: String = "") -> void:
	# 记录关卡完成
	if not state.get("completed_levels", []):
		state["completed_levels"] = []
	if not state["completed_levels"].has(level_id):
		state["completed_levels"].append(level_id)
	
	# 处理奖励
	match reward_id:
		"key_1", "key_2", "key_3", "key_4":
			collect_key(reward_id)
		"laser_device_1":
			state["laser_1_placed"] = false  # 获得装置，待放入风向标
			show_toast("获得激光装置1！带到左侧风向标使用。", 3.0)
		"laser_device_2":
			state["laser_2_placed"] = false
			show_toast("获得激光装置2！带到右侧风向标使用。", 3.0)
		"stone_door":
			show_toast("石门打开了！左侧区域现已可通行。", 3.0)
		"treasure":
			# 来自地下迷宫岔路B的宝箱终点
			if state.get("collected_keys", []).size() >= 4:
				state["finished"] = true
				state["treasure_unlocked"] = true
				show_toast("🎆🎆🎆 时间胶囊开启了！！！ 🎆🎆🎆", 6.0)
				AudioManager.play_sfx("collect")
				show_ending()
			else:
				show_toast("迷宫深处的宝箱需要4把钥匙！", 3.0)
		"":
			pass  # 无特殊奖励
	
	autosave()

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
		"underground_pump": "记忆：五个人把不同的线索摊在地上，拼成同一张回家的地图。",
	}.get(puzzle.get("id", ""), "记忆：这里重新亮起了一点颜色。"))
	show_toast(text, 5.0)

func show_ending() -> void:
	player.controls_enabled = false
	var ending := AcceptDialog.new()
	ending.title = "时间胶囊开启"
	ending.dialog_text = """风铃、手套、风筝、照片和纪念徽章——
回到了它们该在的位置。

旧照片、纸条和儿时玩具，安静地躺在光里。

五位朋友重新聚在一起。
怪物们化作了温暖的光点。
中央广场恢复了完整的色彩。

每个人都拥有看见世界的一种方式。
而理解，是愿意停下来看看对方眼中的风景。

—— 心灵视界 Mindscape ——"""
	add_child(ending)
	ending.confirmed.connect(func():
		player.controls_enabled = true
		show_toast("感谢你的旅程。")
	)
	ending.popup_centered(Vector2(640, 500))

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
	if wheel_root != null and is_instance_valid(wheel_root):
		wheel_root.queue_free()
	if wheel_root != null and is_instance_valid(wheel_root):
		wheel_root.queue_free()
	wheel_root = Panel.new()
	wheel_root.position = Vector2(440, 180)
	wheel_root.size = Vector2(400, 320)
	hud.add_child(wheel_root)
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
	close_btn.pressed.connect(func():
		if wheel_root != null and is_instance_valid(wheel_root):
			wheel_root.queue_free()
			wheel_root = null
	)
	wheel_root.add_child(close_btn)

func try_switch_view(view: String) -> void:
	if not state.get("unlocked_views", []).has(view):
		show_toast("这个视角还没有被理解。")
		return
	state["current_view"] = view
	player.set_view(view)
	world.set_view_palette(view)
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
	hud.add_child(pause_root)
	var list := VBoxContainer.new()
	list.position = Vector2(70, 45)
	list.size = Vector2(240, 240)
	list.add_theme_constant_override("separation", 12)
	pause_root.add_child(list)
	_add_button(list, "继续", func(): toggle_pause())
	_add_button(list, "纪念相册", func(): show_album())
	_add_button(list, "保存并回主菜单", func():
		autosave()
		get_tree().paused = false
		show_main_menu()
	)

func show_album() -> void:
	var album := AcceptDialog.new()
	album.process_mode = Node.PROCESS_MODE_ALWAYS
	album.title = "纪念相册"
	var lines: PackedStringArray = PackedStringArray(state.get("album", []))
	album.dialog_text = "还没有照片。" if lines.is_empty() else "\n".join(lines)
	add_child(album)
	album.popup_centered(Vector2(520, 420))

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
			show_toast("冲刺！——按住方向键持续奔跑。", 0.8)
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
		if wheel_root != null and is_instance_valid(wheel_root):
			wheel_root.queue_free()
	)

func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
