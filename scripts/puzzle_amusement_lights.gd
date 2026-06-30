extends Area2D
class_name PuzzleAmusementLights
# ════════════════════════════════════════════════════════════
#  关卡6：游乐园灯板 — 跳跃平台式
#  3个浮空物理平台（玩家可以跳上去）
#  开始键 START → 15秒倒计时 → 数字键点亮灯 → 结束键 END
#  正确图案：X形，超时/错误重来
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false
var challenge_active: bool = false
var time_left: float = 0.0
const TIME_LIMIT: float = 15.0

const CORRECT: Array = [1,0,1, 0,1,0, 1,0,1]  # X形
var lights: Array = [0,0,0, 0,0,0, 0,0,0]

var light_nodes: Array[ColorRect] = []
var platform_bodies: Array[StaticBody2D] = []
var timer_label: Label
var status_label: Label
var start_btn: Button
var end_btn: Button

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(300, 250)
	shape.shape = rect
	shape.position = Vector2(0, -40)
	add_child(shape)
	_build_platforms()
	_build_ui()

func _build_platforms() -> void:
	var heights := [-100, -55, -100]  # row 0, 2 = 高平台, row 1 = 中平台
	for row in range(3):
		var py: int = heights[row]
		for col in range(3):
			var idx := row * 3 + col
			var px := (col - 1) * 70

			# 平台 StaticBody2D
			var body := StaticBody2D.new()
			body.position = Vector2(px, py)
			body.collision_layer = 1
			body.collision_mask = 0
			body.z_index = 1
			var cshape := CollisionShape2D.new()
			var crect := RectangleShape2D.new()
			crect.size = Vector2(50, 8)
			cshape.shape = crect
			cshape.position = Vector2(0, 4)
			body.add_child(cshape)
			# 平台外观
			var plat := ColorRect.new()
			plat.position = Vector2(-25, -4)
			plat.size = Vector2(50, 12)
			plat.color = Color("#5a4a3a")
			body.add_child(plat)
			# 平台边框
			var border := ColorRect.new()
			border.position = Vector2(-27, -6)
			border.size = Vector2(54, 16)
			border.color = Color("#ffaa44", 0.5)
			body.add_child(border)
			add_child(body)
			platform_bodies.append(body)

			# 灯（在平台上方的视觉）
			var light := ColorRect.new()
			light.position = Vector2(px - 10, py - 16)
			light.size = Vector2(20, 12)
			light.color = Color("#332244")
			light.z_index = 2
			add_child(light)
			light_nodes.append(light)

			# 数字标签
			var num := Label.new()
			num.text = str(idx + 1)
			num.position = Vector2(px - 4, py - 14)
			num.add_theme_font_size_override("font_size", 11)
			num.add_theme_color_override("font_color", Color("#9999aa"))
			num.z_index = 3
			add_child(num)

func _build_ui() -> void:
	var title := Label.new()
	title.text = "[ 游乐园灯板 ]"
	title.position = Vector2(-55, -125)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#ffd760"))
	add_child(title)

	# START按钮
	start_btn = Button.new()
	start_btn.text = "START"
	start_btn.position = Vector2(-160, 50)
	start_btn.size = Vector2(80, 36)
	start_btn.pressed.connect(_on_start)
	add_child(start_btn)

	# END按钮
	end_btn = Button.new()
	end_btn.text = "END"
	end_btn.position = Vector2(80, 50)
	end_btn.size = Vector2(80, 36)
	end_btn.pressed.connect(_on_end)
	end_btn.visible = false
	add_child(end_btn)

	# 计时器
	timer_label = Label.new()
	timer_label.text = ""
	timer_label.position = Vector2(-20, 5)
	timer_label.add_theme_font_size_override("font_size", 28)
	timer_label.add_theme_color_override("font_color", Color("#ff6644"))
	timer_label.visible = false
	add_child(timer_label)

	# 状态
	status_label = Label.new()
	status_label.position = Vector2(-130, 75)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "跳到平台上 → 按 START"
	add_child(status_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed or not challenge_active:
		return
	# 数字键1-9点亮灯
	if event is InputEventKey and event.pressed:
		var kn := -1
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			kn = event.keycode - KEY_0
		elif event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			kn = event.keycode - KEY_KP_0
		if kn >= 1 and kn <= 9:
			_toggle_light(kn - 1)

func _on_start() -> void:
	challenge_active = true
	time_left = TIME_LIMIT
	lights = [0,0,0, 0,0,0, 0,0,0]
	for l in light_nodes:
		l.color = Color("#332244")
	timer_label.visible = true
	timer_label.text = "%.1f" % time_left
	end_btn.visible = true
	start_btn.visible = false
	status_label.text = "按数字键1-9点亮灯 (X形)"
	hint_updated.emit("灯板启动！跳到平台上按数字键1-9点亮，15秒后按END提交！")
	set_process(true)

func _on_end() -> void:
	if not challenge_active: return
	challenge_active = false
	set_process(false)
	timer_label.visible = false
	end_btn.visible = false
	start_btn.visible = true

	if _check_pattern():
		is_completed = true
		status_label.text = "✨ 灯板正确！获得钥匙2！"
		hint_updated.emit("✨ 正确！你获得钥匙2！")
		for l in light_nodes:
			l.color = Color("#ffd700")
		puzzle_completed.emit("key_2")
	else:
		status_label.text = "图案不对...按 START 重来"
		hint_updated.emit("灯板图案不正确。X形：灯1,3,5,7,9点亮就是X。按START重试。")

func _process(delta: float) -> void:
	if not challenge_active: return
	time_left -= delta
	timer_label.text = "%.1f" % maxf(0, time_left)
	if time_left <= 3.0:
		timer_label.modulate = Color(1, 0.2, 0.2) if int(time_left * 4) % 2 == 0 else Color(1, 1, 1)
	else:
		timer_label.modulate = Color(1, 1, 1)
	if time_left <= 0:
		_time_up()

func _time_up() -> void:
	challenge_active = false
	set_process(false)
	timer_label.visible = false
	end_btn.visible = false
	start_btn.visible = true
	status_label.text = "超时了！按 START 重新挑战"
	hint_updated.emit("15秒倒计时结束！记住图案是X形，按START重试。")

func _toggle_light(idx: int) -> void:
	lights[idx] = 1 - lights[idx]
	light_nodes[idx].color = Color("#ffdd44") if lights[idx] == 1 else Color("#332244")
	AudioManager.play_tone(440.0 + idx * 50, 0.15)

func _check_pattern() -> bool:
	for i in range(9):
		if lights[i] != CORRECT[i]:
			return false
	return true

func is_solved() -> bool:
	return is_completed
