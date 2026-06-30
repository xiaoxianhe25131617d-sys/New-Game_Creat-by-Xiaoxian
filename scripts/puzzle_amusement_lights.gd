extends Area2D
class_name PuzzleAmusementLights
# ════════════════════════════════════════════════════════════
#  关卡4：游乐园灯板 (Amusement Park Light Board)
#  位置：出生点往右第一个场景（游乐园区域）
#  规则：
#    3×3灯板网格
#    盲人模式：每个灯有不同声音（正确=清晰音，错误=杂音）
#    ADHD模式：快速跑动点亮所有正确位置的灯板
#  产出：钥匙2
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false

# 3x3 灯板配置 — 正确位置(1=需要点亮, 0=不需要)
const GRID_SIZE := 3
@export var correct_pattern: Array = [1, 0, 1, 0, 1, 0, 1, 0, 1]  # X形图案
var current_state: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]       # 当前状态

# 每个格子的声音频率（盲人模式用）
const TONE_FREQUENCIES: Array = [440.0, 493.9, 523.3, 587.3, 659.3, 698.5, 784.0, 880.0, 987.8]

var light_nodes: Array = []        # 灯板节点数组
var board_container: Node2D       # 整体容器
var hint_label: Label

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_light_board()
	_make_hint()

func _make_light_board() -> void:
	board_container = Node2D.new()
	board_container.name = "LightBoard"
	board_container.position = Vector2(0, -20)
	add_child(board_container)
	
	# 底板
	var back := ColorRect.new()
	back.position = Vector2(-55, -55)
	back.size = Vector2(110, 110)
	back.color = Color("#2a2040")
	back.z_index = -1
	board_container.add_child(back)
	
	# 外框
	var border := ColorRect.new()
	border.position = Vector2(-58, -58)
	border.size = Vector2(116, 116)
	border.color = Color("#8a7060")
	border.z_index = -2
	board_container.add_child(border)
	
	# 创建3x3灯板格子
	for idx in range(GRID_SIZE * GRID_SIZE):
		var gx: int = idx % GRID_SIZE
		var gy: int = idx / GRID_SIZE
		var cell_pos: Vector2 = Vector2(gx * 36 - 36, gy * 36 - 36)
		
		var cell := Area2D.new()
		cell.name = "Cell_%d" % idx
		cell.position = cell_pos
		cell.set_meta("idx", idx)
		board_container.add_child(cell)
		
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(32, 32)
		shape.shape = box
		cell.add_child(shape)
		
		# 灯板视觉
		var light := Polygon2D.new()
		light.name = "Light"
		var lp := PackedVector2Array()
		for i in range(8):
			var a: float = TAU * i / 8.0
			lp.append(Vector2(cos(a) * 14, sin(a) * 14))
		light.polygon = lp
		light.color = Color("#403050")
		cell.add_child(light)
		light_nodes.append(light)
		
		# 格子编号（调试用，正式版可隐藏）
		var num := Label.new()
		num.text = "%d" % (idx + 1)
		num.position = Vector2(-4, -6)
		num.add_theme_font_size_override("font_size", 10)
		num.add_theme_color_override("font_color", Color("#666668"))
		cell.add_child(num)
	
	# 标题
	var title := Label.new()
	title.text = "[ 游乐园灯板 ]"
	title.position = Vector2(-50, -95)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#ffd760"))
	add_child(title)

func _make_hint() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-80, 70)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.text = "按 [E] 开始挑战"
	add_child(hint_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if not is_completed:
			hint_label.text = "按 [E] 开始灯板挑战"

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	if event.is_action_pressed("interact"):
		_start_challenge()

func _start_challenge() -> void:
	hint_updated.emit("灯板已激活！走到灯前踩亮它。盲人模式听音，ADHD快速跑！")
	hint_label.text = "踩亮正确的灯！(F键听音)"
	# 高亮所有应该亮的灯的边框提示一瞬
	for idx in range(correct_pattern.size()):
		if correct_pattern[idx] == 1:
			var tween := create_tween()
			tween.tween_property(light_nodes[idx], "color", Color("#ffffff"), 0.15)
			tween.tween_property(light_nodes[idx], "color", Color("#403050"), 0.3)

# 检测玩家踩到哪个格子
var press_cooldowns: Dictionary = {}

func _process(_delta: float) -> void:
	if is_completed:
		return
	
	# 持续检测碰撞
	var player: Node2D = _get_player()
	if player == null:
		return
	
	for idx in range(light_nodes.size()):
		var cell: Area2D = board_container.get_node_or_null("Cell_%d" % idx) as Area2D
		if cell == null:
			continue
		if cell.get_overlapping_bodies().has(player):
			_on_cell_stepped(idx)

func _on_cell_stepped(idx: int) -> void:
	# 冷却防重复触发
	if press_cooldowns.get(idx, 0.0) > Time.get_ticks_msec():
		return
	press_cooldowns[idx] = Time.get_ticks_msec() + 400
	
	# 切换状态
	current_state[idx] = 1 - current_state[idx]
	var is_on: bool = current_state[idx] == 1
	
	# 更新视觉效果 + 播放声音
	var light: Polygon2D = light_nodes[idx]
	if is_on:
		light.color = Color("#ffdd44")
	else:
		light.color = Color("#403050")
	
	_play_cell_tone(idx, correct_pattern[idx] == 1)
	_check_completion()

func _play_cell_tone(cell_idx: int, is_correct_position: bool) -> void:
	# 根据当前视角决定播放方式
	var view: String = _get_current_view()
	var freq: float = TONE_FREQUENCIES[cell_idx]
	
	if view == "blind":
		# 盲人模式：正确位置=清晰正弦波，错误位置=噪音/杂音
		AudioManager.play_tone(freq if is_correct_position else freq * 1.03, 0.35)
		if is_correct_position:
			hint_updated.emit("♪ 清晰的声音...这里是对的！")
		else:
			hint_updated.emit("♩ 杂音...不是这里")
	elif view == "adhd":
		# ADHD模式：快速反馈闪烁
		pass
	else:
		# 其他模式：简单音效
		AudioManager.play_tone(freq, 0.2)

func _check_completion() -> void:
	# 检查是否所有正确位置的灯都已点亮，且错误位置都未点亮
	var all_correct: bool = true
	for idx in range(correct_pattern.size()):
		if correct_pattern[idx] != current_state[idx]:
			all_correct = false
			break
	
	if all_correct:
		_complete_puzzle()

func _complete_puzzle() -> void:
	is_completed = true
	hint_label.text = "✨ 获得钥匙2（游乐园钥匙）！"
	hint_updated.emit("✨ 你获得了钥匙2！")
	puzzle_completed.emit("key_2")
	
	# 全部灯变金色庆祝
	for light in light_nodes:
		var tween := create_tween()
		tween.tween_property(light, "color", Color("#ffd700"), 0.3)

func _get_current_view() -> String:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world and world.has_method("get_current_view"):
		return world.get_current_view()
	return "normal"

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func is_solved() -> bool:
	return is_completed
