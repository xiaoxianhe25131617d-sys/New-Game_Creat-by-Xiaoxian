extends Area2D
class_name PuzzleTextureWall
# ════════════════════════════════════════════════════════════
#  关卡：纹理墙（石门）
#  4个隐藏石块，正确顺序 = E → L → C → H
#  盲人模式：按任意键盘按键"触摸"墙面，获得方向+距离反馈
#  像真正的摸索一样，越靠近目标提示越精确
# ════════════════════════════════════════════════════════════

signal puzzle_completed
signal hint_updated(text: String)

# ── 完整 QWERTY 键盘坐标图 ──
# [row, col] — row越大越靠下，col越大越靠右
# 使用小数 col 模拟键盘行的交错排列
const KEYBOARD := {
	# Row 0: 数字行
	"`": [0, 0], "1": [0, 1], "2": [0, 2], "3": [0, 3], "4": [0, 4],
	"5": [0, 5], "6": [0, 6], "7": [0, 7], "8": [0, 8], "9": [0, 9],
	"0": [0, 10], "-": [0, 11], "=": [0, 12],
	# Row 1: QWERTY 上排
	"Q": [1, 1.25], "W": [1, 2.25], "E": [1, 3.25], "R": [1, 4.25],
	"T": [1, 5.25], "Y": [1, 6.25], "U": [1, 7.25], "I": [1, 8.25],
	"O": [1, 9.25], "P": [1, 10.25], "[": [1, 11.25], "]": [1, 12.25],
	"\\": [1, 13.25],
	# Row 2: ASDF 中排
	"A": [2, 1.5], "S": [2, 2.5], "D": [2, 3.5], "F": [2, 4.5],
	"G": [2, 5.5], "H": [2, 6.5], "J": [2, 7.5], "K": [2, 8.5],
	"L": [2, 9.5], ";": [2, 10.5], "'": [2, 11.5],
	# Row 3: ZXCV 下排
	"Z": [3, 1.75], "X": [3, 2.75], "C": [3, 3.75], "V": [3, 4.75],
	"B": [3, 5.75], "N": [3, 6.75], "M": [3, 7.75], ",": [3, 8.75],
	".": [3, 9.75], "/": [3, 10.75],
	# 空格
	" ": [4, 3.0],
}

# ── 答案（永远不显示给玩家）──
const TARGETS: Array[String] = ["E", "L", "C", "H"]

# ── Keycode → 字符映射 ──
const KC_CHAR := {
	KEY_A: "A", KEY_B: "B", KEY_C: "C", KEY_D: "D", KEY_E: "E",
	KEY_F: "F", KEY_G: "G", KEY_H: "H", KEY_I: "I", KEY_J: "J",
	KEY_K: "K", KEY_L: "L", KEY_M: "M", KEY_N: "N", KEY_O: "O",
	KEY_P: "P", KEY_Q: "Q", KEY_R: "R", KEY_S: "S", KEY_T: "T",
	KEY_U: "U", KEY_V: "V", KEY_W: "W", KEY_X: "X", KEY_Y: "Y",
	KEY_Z: "Z",
	KEY_0: "0", KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4",
	KEY_5: "5", KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9",
	KEY_QUOTELEFT: "`", KEY_MINUS: "-", KEY_EQUAL: "=",
	KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_BACKSLASH: "\\", KEY_SEMICOLON: ";",
	KEY_APOSTROPHE: "'", KEY_COMMA: ",",
	KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SPACE: " ",
}

var current_step: int = -1
var player_in_range: bool = false
var is_completed: bool = false
const WALL_TEXTURE_PATH := "res://assets/environment/generated/stone_wall.png"

var wall_visual: Sprite2D
var hint_label: Label
var stone_visuals: Array[Polygon2D] = []


# ════════════════════════════════════════════════════════════
#  初始化
# ════════════════════════════════════════════════════════════

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200, 280)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)
	_make_wall_visual()
	_make_stones()
	_make_hint_label()


func _make_wall_visual() -> void:
	var texture := load(WALL_TEXTURE_PATH) as Texture2D
	wall_visual = Sprite2D.new()
	wall_visual.name = "WallTexture"
	wall_visual.texture = texture
	wall_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture != null:
		var texture_size := texture.get_size()
		var scale_factor := minf(190.0 / texture_size.x, 300.0 / texture_size.y)
		wall_visual.scale = Vector2(scale_factor, scale_factor)
		_align_texture_base(wall_visual, texture.get_image(), 32.0)
	add_child(wall_visual)

func _align_texture_base(sprite: Sprite2D, image: Image, target_y: float) -> void:
	var min_x := image.get_width()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.8:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_y < 0:
		return
	var center := Vector2(image.get_width(), image.get_height()) * 0.5
	sprite.position.x = -(((min_x + max_x) * 0.5) - center.x) * sprite.scale.x
	sprite.position.y = target_y - (max_y - center.y) * sprite.scale.y


func _make_stones() -> void:
	# 4个无标签凸起石块（从左到右均匀排列）
	for i in range(4):
		var bx := -45.0 + float(i) * 30.0
		var by := -52.0

		var stone := Polygon2D.new()
		var sp := PackedVector2Array()
		for j in range(8):
			var a := TAU * j / 8.0 + (i * 0.3)
			sp.append(Vector2(cos(a) * 12, sin(a) * 11))
		stone.polygon = sp
		stone.position = Vector2(bx, by)
		stone.color = Color("#7a6a5a")
		stone.name = "Stone%d" % i
		add_child(stone)
		stone_visuals.append(stone)


func _make_hint_label() -> void:
	hint_label = Label.new()
	hint_label.position = Vector2(-135, -238)
	hint_label.size = Vector2(270, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.text = "靠近后按 [E] 触摸墙面"
	add_child(hint_label)


# ════════════════════════════════════════════════════════════
#  交互入口
# ════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if not is_completed and current_step == -1:
			hint_label.text = "按 [E] 开始触摸石墙..."
			_pulse_all_stones()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if current_step >= 0 and not is_completed:
			hint_label.text = "手离开了墙面..."
			hint_updated.emit("手指离开了石墙。")


func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return

	if current_step == -1:
		if event.is_action_pressed("interact"):
			_try_start()
		return

	if event is InputEventKey and event.pressed:
		_on_key_press(event)


func _try_start() -> void:
	var view := _get_view()
	if view != "blind":
		hint_label.text = "墙面凹凸不平...但光靠看分不清哪块是哪块。试试盲人模式。"
		hint_updated.emit("墙上好像有几块凸起的石头，但看不清细节。")
		return
	_start_puzzle()


func _start_puzzle() -> void:
	current_step = 0
	hint_label.text = "你伸手摸向石墙..."
	hint_updated.emit("手指触碰到了粗糙的石面。墙上似乎有几个凸起的石块。试着按任意键触摸不同的位置...")
	_disable_player(true)
	_tween_wall_pulse()
	_pulse_all_stones()


# ════════════════════════════════════════════════════════════
#  按键处理 → 键盘坐标方向计算 → 个性化反馈
# ════════════════════════════════════════════════════════════

func _on_key_press(event: InputEventKey) -> void:
	var key_name := _keycode_to_name(event.keycode)
	if key_name == "":
		# 不认识的键（F1-F12等）
		hint_label.text = "手指拂过，这里好像不是石面..."
		hint_updated.emit("这个方向没有碰到石块。试试按字母键。")
		return

	if not KEYBOARD.has(key_name):
		# 键盘上有但不在我们的坐标体系中
		hint_label.text = "手指摸到了一片光滑..."
		return

	_evaluate_touch(key_name)


func _keycode_to_name(kc: int) -> String:
	if KC_CHAR.has(kc):
		return KC_CHAR[kc]
	return ""


func _evaluate_touch(touched_key: String) -> void:
	var target_key := TARGETS[current_step]
	var tpos: Array = KEYBOARD[touched_key]
	var goal: Array = KEYBOARD[target_key]

	var dx: float = goal[1] - tpos[1]   # >0 目标在右边
	var dy: float = goal[0] - tpos[0]   # >0 目标在下方
	var dist: float = sqrt(dx * dx + dy * dy)

	# ── 正确！──
	if touched_key == target_key:
		_on_correct_key(touched_key)
		return

	# ── 生成个性化"摸索"反馈 ──
	var direction := _describe_direction(dx, dy)
	var hint_text := _compose_feel_hint(touched_key, dx, dy, dist, direction)
	var toast_text := _compose_toast_hint(touched_key, dx, dy, dist, direction)

	hint_label.text = hint_text
	hint_updated.emit(toast_text)

	# 视觉反馈：墙面微闪
	_tween_wall_flash(dist < 2.0)
	_flash_stone_closest_to(touched_key)


# ════════════════════════════════════════════════════════════
#  方向描述
# ════════════════════════════════════════════════════════════

func _describe_direction(dx: float, dy: float) -> String:
	# 是否大致同行/同列
	var same_row: bool = abs(dy) < 0.6
	var same_col: bool = abs(dx) < 0.6

	if same_row and same_col:
		return "这里"

	var h := ""
	var v := ""

	if not same_col:
		h = "右" if dx > 0 else "左"
	if not same_row:
		v = "下" if dy > 0 else "上"

	return v + h


# ════════════════════════════════════════════════════════════
#  生成"摸索"提示文字
# ════════════════════════════════════════════════════════════

func _compose_feel_hint(key: String, _dx: float, _dy: float, dist: float, dir: String) -> String:
	if dist < 1.5:
		var pool := [
			"指尖碰到了什么...往%s再摸一点点！" % dir,
			"差一点！就%s方向...再试试" % dir,
			"几乎碰到了！%s边..." % dir,
			"快了快了，往%s轻轻一碰" % dir,
		]
		return pool[randi() % pool.size()]

	if dist < 2.5:
		var pool := [
			"石纹的走向像是%s...很近了" % dir,
			"往%s摸过去，不远了" % dir,
			"%s方有凸起的触感" % dir,
			"手指滑过，好像要往%s一点" % dir,
		]
		return pool[randi() % pool.size()]

	if dist < 4.0:
		var pool := [
			"不是这里的手感...往%s方向找找" % dir,
			"石头很粗糙，但%s方好像不一样" % dir,
			"纹理不对，试试%s边" % dir,
			"指尖触感不对，往%s摸索" % dir,
		]
		return pool[randi() % pool.size()]

	if dist < 6.0:
		var pool := [
			"离得有点远...往%s方向摸过去" % dir,
			"这里一片光滑，凸起在%s方" % dir,
			"手够不太到，往%s伸" % dir,
		]
		return pool[randi() % pool.size()]

	# 很远
	var pool := [
		"好远...手指悬空够不着，得往%s边大幅移动" % dir,
		"完全不在附近...凸起在遥远的%s方" % dir,
		"太远了！往%s方向摸索很远才行" % dir,
	]
	return pool[randi() % pool.size()]


func _compose_toast_hint(key: String, _dx: float, _dy: float, dist: float, dir: String) -> String:
	if dist < 1.5:
		var pool := [
			"「%s」...指尖碰到边缘了！就差%s一点点" % [key, dir],
			"「%s」...很接近了，往%s再试" % [key, dir],
		]
		return pool[randi() % pool.size()]

	if dist < 2.5:
		var pool := [
			"「%s」的纹理指向%s方向..." % [key, dir],
			"按下「%s」，手感告知正确的在%s" % [key, dir],
		]
		return pool[randi() % pool.size()]

	if dist < 4.0:
		return "「%s」不是这个...往%s方向摸" % [key, dir]

	return "「%s」离目标太远了，向%s方向摸索" % [key, dir]


# ════════════════════════════════════════════════════════════
#  正确按键
# ════════════════════════════════════════════════════════════

func _on_correct_key(key_name: String) -> void:
	# 视觉：对应石块沉下去
	_depress_stone(current_step)

	hint_label.text = "石块「%s」凹陷下去了！（%d/4）" % [key_name, current_step + 1]
	hint_updated.emit("指尖陷入了石块！「%s」的纹理吻合——石块沉入墙中。（%d/4）" % [key_name, current_step + 1])

	current_step += 1
	_tween_wall_flash(true)

	if current_step >= TARGETS.size():
		_complete_puzzle()
	else:
		# 给一个提示描述下一个要找的
		var next_hint := _describe_next_target()
		hint_label.text += "\n" + next_hint


func _describe_next_target() -> String:
	# 用模糊描述暗示下一个目标的位置特征
	var target := TARGETS[current_step]
	var pos: Array = KEYBOARD[target]
	var row := int(pos[0])
	var col: float = pos[1]

	var v := ""
	match row:
		0: v = "很高"
		1: v = "偏高"
		2: v = "中间"
		3: v = "偏低"

	var h := ""
	if col < 4.0: h = "偏左"
	elif col < 7.0: h = "中间"
	else: h = "偏右"

	return "接下来手往%s%s的方向摸..." % [v, h]


# ════════════════════════════════════════════════════════════
#  视觉特效
# ════════════════════════════════════════════════════════════

func _depress_stone(idx: int) -> void:
	if idx < 0 or idx >= stone_visuals.size():
		return
	var stone := stone_visuals[idx]
	var tween := create_tween()
	tween.tween_property(stone, "color", Color("#404030"), 0.2)
	tween.tween_property(stone, "scale", Vector2(0.85, 0.65), 0.25)
	tween.tween_property(stone, "position", stone.position + Vector2(0, 8), 0.25)


func _flash_stone_closest_to(key: String) -> void:
	# 根据按键位置，让最近的石块微闪一下
	var kpos: Array = KEYBOARD.get(key, [99, 99])
	var best_idx := -1
	var best_dist := 999.0
	for i in range(TARGETS.size()):
		var tpos: Array = KEYBOARD[TARGETS[i]]
		var d := sqrt(pow(kpos[1] - tpos[1], 2) + pow(kpos[0] - tpos[0], 2))
		if d < best_dist:
			best_dist = d
			best_idx = i
	if best_idx >= 0 and best_idx < stone_visuals.size():
		var tween := create_tween()
		tween.tween_property(stone_visuals[best_idx], "modulate", Color("#ffcc88"), 0.08)
		tween.tween_property(stone_visuals[best_idx], "modulate", Color.WHITE, 0.3)


func _pulse_all_stones() -> void:
	for stone in stone_visuals:
		var tween := create_tween()
		tween.tween_property(stone, "modulate", Color("#a09070"), 0.4)
		tween.tween_property(stone, "modulate", Color.WHITE, 0.4)


func _tween_wall_pulse() -> void:
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(wall_visual, "modulate", Color("#8a7a6a"), 0.35)
	tween.tween_property(wall_visual, "modulate", Color("#5b4b3a"), 0.35)


func _tween_wall_flash(near: bool) -> void:
	var flash_color := Color("#a0e080") if near else Color("#e0a080")
	var tween := create_tween()
	tween.tween_property(wall_visual, "modulate", flash_color, 0.1)
	tween.tween_property(wall_visual, "modulate", Color.WHITE, 0.3)


func _tween_celebration() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(wall_visual, "modulate", Color("#ffe28a"), 0.5)


# ════════════════════════════════════════════════════════════
#  完成
# ════════════════════════════════════════════════════════════

func _complete_puzzle() -> void:
	is_completed = true
	_disable_player(false)
	hint_label.text = "四块石头全部凹陷！石门颤动..."
	hint_updated.emit("石门上所有凸起的石块都沉入墙中——门缓缓打开了！")
	puzzle_completed.emit("stone_door")
	_tween_celebration()


# ════════════════════════════════════════════════════════════
#  工具方法
# ════════════════════════════════════════════════════════════

func _disable_player(v: bool) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if "controls_enabled" in node:
			node.controls_enabled = not v


func _get_view() -> String:
	for node in get_tree().get_nodes_in_group("world"):
		if node.has_method("get_current_view"):
			return node.get_current_view()
	return "normal"


func get_progress() -> int:
	return current_step


func is_solved() -> bool:
	return is_completed
