extends Area2D
class_name PuzzleNPCPassword
# ════════════════════════════════════════════════════════════
#  关卡5：NPC密码台 (NPC Password Console)
#  位置：右侧深处（天文台附近）
#  规则：
#    5个NPC各说一段话
#    抑郁症模式 → 看到NPC"潜台词"（括号内真实字符）
#    自闭症模式 → 阅读密码本（字符→数字对应表）
#    按NPC站位顺序将潜台词字符转为数字输入
#  产出：钥匙4
# ════════════════════════════════════════════════════════════

signal puzzle_completed(key_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_completed: bool = false

# 5个NPC的数据
const NPC_DIALOGUE_DATA: Array = [
	{"id": "cipher_1", "name": "守卫A", "visible_text": "我守护这个地方很久了。",     "subtext": "我其实很想休息"},
	{"id": "cipher_2", "name": "学者B", "visible_text": "知识就是力量。",           "subtext": "但我害怕力量被滥用"},
	{"id": "cipher_3", "name": "工匠C", "visible_text": "工具应该服务于人。",         "subtext": "可人们总是被工具驱使"},
	{"id": "cipher_4", "name": "旅者D", "visible_text": "旅途的意义在于过程。",       "subtext": "想找个可以停留的地方"},
	{"id": "cipher_5", "name": "智者E", "visible_text": "智慧来自于倾听。",           "subtext": "没人真正听我说过话"},
]

# 密码本（自闭症模式可见）：潜台词首字→数字映射
const CIPHER_BOOK: Dictionary = {
	"我": "1", "但": "2", "可": "3", "想": "4", "没": "5",
}
# 正确答案：按站位顺序取每个潜台词的首字符 → 数字序列
# 实际上我们用 subtext 首字的组合
const CORRECT_ANSWER: String = "12345"

# 已读取的潜台词
var read_subtexts: Array[bool] = [false, false, false, false, false]
var input_answer: String = ""

# UI元素
var npc_markers: Array = []          # NPC站位标记
var ui_panel: Panel                 # 输入面板
var status_label: Label
var cipher_book_visible: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_npc_console()
	_make_ui_panel()

func _make_npc_console() -> void:
	# 控制台底座
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-90, -20), Vector2(90, -20),
		Vector2(90, 30), Vector2(-90, 30),
	])
	base.color = Color("#5a5060")
	add_child(base)
	
	# 控制台面板
	var panel := ColorRect.new()
	panel.position = Vector2(-85, -60)
	panel.size = Vector2(170, 38)
	panel.color = Color("#3a3050")
	add_child(panel)
	
	# 5个NPC站位标记
	for i in range(NPC_DIALOGUE_DATA.size()):
		var data: Dictionary = NPC_DIALOGUE_DATA[i]
		var nx: float = -65.0 + float(i) * 33.0
		
		# NPC位置标记
		var marker := Polygon2D.new()
		var mp := PackedVector2Array()
		for j in range(6):
			var a: float = TAU * j / 6.0
			mp.append(Vector2(cos(a) * 10, sin(a) * 10))
		marker.polygon = mp
		marker.position = Vector2(nx, -42)
		marker.color = Color("#8080a0")
		add_child(marker)
		npc_markers.append(marker)
		
		# NPC名字标签
		var name_lbl := Label.new()
		name_lbl.text = data["name"]
		name_lbl.position = Vector2(nx - 12, -56)
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color("#c0c0e0"))
		add_child(name_lbl)
	
	# 对话显示区
	var dialogue_area := RichTextLabel.new()
	dialogue_area.name = "DialogueArea"
	dialogue_area.position = Vector2(-82, -18)
	dialogue_area.size = Vector2(164, 44)
	dialogue_area.bbcode_enabled = true
	dialogue_area.text = "按 [E] 与NPC对话..."
	add_child(dialogue_area)
	
	# 标题
	var title := Label.new()
	title.text = "[ NPC密码台 ]"
	title.position = Vector2(-45, -88)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#b0a0f0"))
	add_child(title)
	
	status_label = Label.new()
	status_label.position = Vector2(-75, 42)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "按 [E] 开始对话"
	add_child(status_label)

func _make_ui_panel() -> void:
	ui_panel = Panel.new()
	ui_panel.visible = false
	ui_panel.position = Vector2(-100, -130)
	ui_panel.size = Vector2(200, 62)
	add_child(ui_panel)
	
	var plabel := Label.new()
	plabel.text = "输入密码（数字）:"
	plabel.position = Vector2(10, 8)
	plabel.size = Vector2(180, 16)
	ui_panel.add_child(plabel)
	
	var pinput := LineEdit.new()
	pinput.name = "AnswerInput"
	pinput.position = Vector2(10, 28)
	pinput.size = Vector2(180, 26)
	ui_panel.add_child(pinput)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range or is_completed:
		return
	
	# 数字键盘直接输入密码（当面板打开时）
	if ui_panel.visible and event is InputEventKey and event.pressed:
		var key: String = event.as_text_key_label()
		if key in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			var input: LineEdit = ui_panel.get_node_or_null("AnswerInput") as LineEdit
			if input:
				input.text += key
			return
		elif key == "BackSpace":
			var input: LineEdit = ui_panel.get_node_or_null("AnswerInput") as LineEdit
			if input and input.text.length() > 0:
				input.text = input.text.left(input.text.length() - 1)
			return
		elif key == "Return":
			_submit_answer()
			return
	
	if event.is_action_pressed("interact"):
		if ui_panel.visible:
			_submit_answer()
		else:
			_talk_to_next_npc()

func _talk_to_next_npc() -> void:
	# 找下一个未读取的NPC
	var next_idx: int = -1
	for i in range(read_subtexts.size()):
		if not read_subtexts[i]:
			next_idx = i
			break
	
	if next_idx == -1:
		# 所有NPC都读过了
		status_label.text = "全部已读取！输入密码..."
		ui_panel.visible = true
		hint_updated.emit("全部潜台词已收集！请查阅密码本转换数字。")
		return
	
	var data: Dictionary = NPC_DIALOGUE_DATA[next_idx]
	var view: String = _get_current_view()
	var dialogue: RichTextLabel = get_node_or_null("DialogueArea") as RichTextLabel
	
	if dialogue:
		match view:
			"depression":
				dialogue.text = "[color=#ffa0a0]%s[/color]\n[color=#a0a0ff](%s)[/color]" % [data["visible_text"], data["subtext"]]
				read_subtexts[next_idx] = true
				highlight_marker(next_idx, Color("#a0a0ff"))
				hint_updated.emit("发现%s的潜台词：%s" % [data["name"], data["subtext"]])
			"autism":
				# 自闭症模式：显示可见文本+密码本提示
				var first_char: String = data["subtext"].left(1)
				var code_num: String = CIPHER_BOOK.get(first_char, "?")
				dialogue.text = "[color=#e0e0e0]%s[/color]\n[color=#ffff00]密码本: '%s' → %s[/color]" % [data["visible_text"], first_char, code_num]
				read_subtexts[next_idx] = true
				highlight_marker(next_idx, Color("#ffff00"))
				hint_updated.emit("密码本翻译：%s = %s" % [first_char, code_num])
			_:
				dialogue.text = "[color=#c0c0c0]%s[/color]\n[color=gray](切换视角查看更多信息)[/color]" % [data["visible_text"]]
				hint_updated.emit("%s说了什么...换个视角试试？" % data["name"])
	
	var read_count: int = 0
	for r in read_subtexts:
		if r: read_count += 1
	status_label.text = "NPC对话 (%d/5)" % read_count

func highlight_marker(idx: int, color: Color) -> void:
	if idx < npc_markers.size():
		var m: Polygon2D = npc_markers[idx]
		var tween := create_tween()
		tween.tween_property(m, "color", color, 0.25)
		tween.tween_property(m, "color", Color("#8080a0"), 0.5)

func _submit_answer() -> void:
	var input: LineEdit = ui_panel.get_node_or_null("AnswerInput") as LineEdit
	if input == null:
		return
	input_answer = input.text.strip_edges()
	
	if input_answer == CORRECT_ANSWER:
		_complete_puzzle()
	else:
		status_label.text = "密码错误...再检查密码本"
		hint_updated.emit("密码错误。按站位顺序翻译每个NPC的潜台词。")
		input.text = ""

func _complete_puzzle() -> void:
	is_completed = true
	ui_panel.visible = false
	status_label.text = "✨ 获得钥匙4（天文台钥匙）！"
	hint_updated.emit("✨ 你获得了钥匙4！")
	puzzle_completed.emit("key_4")

func _get_current_view() -> String:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world and world.has_method("get_current_view"):
		return world.get_current_view()
	return "normal"

func is_solved() -> bool:
	return is_completed
