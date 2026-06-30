extends Area2D
class_name PuzzleDarkMaze
# ════════════════════════════════════════════════════════════
#  关卡6：地下黑暗迷宫 (Underground Dark Maze)
#  位置：地图地下某处（有明确入口，出口唯一不可逆）
#  结构：
#    入口 → 岔路A（通往钥匙3）+ 岔路B（通往宝藏，需四把钥匙）
#    全黑环境
#    盲人模式：正确路线发出"正确"音，错误路线发出"错误"音
#  产出：岔路A=钥匙3 / 岔路B=宝箱（需四把钥匙开启）
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var is_inside: bool = false          # 玩家是否在迷宫内
var chosen_path: String = ""         # "" / "A" / "B"

# 迷宫路径定义
# 每个节点：position + 连接的邻居 + 是否是终点
const MAZE_NODES: Dictionary = {
	"entry":   {"pos": Vector2(5200, 4300), "neighbors": ["n1"]},
	"n1":      {"pos": Vector2(5200, 4370), "neighbors": ["entry", "n2", "n3"]},
	"n2":      {"pos": Vector2(5120, 4370), "neighbors": ["n1", "n4"], "is_correct": true},  # 通向岔路A的正确路
	"n3":      {"pos": Vector2(5280, 4370), "neighbors": ["n1", "n5"]},
	"n4":      {"pos": Vector2(5120, 4440), "neighbors": ["n2", "key_a"]},
	"n5":      {"pos": Vector2(5280, 4440), "neighbors": ["n3", "n6", "n7"]},
	"n6":      {"pos": Vector2(5220, 4500), "neighbors": ["n5"], "wrong_path": true},
	"n7":      {"pos": Vector2(5340, 4500), "neighbors": ["n5", "treasure"], "is_correct": true},  # 通向岔路B的正确路
	"key_a":   {"pos": Vector2(5000, 4500), "neighbors": [], "endpoint": true, "reward": "key_3"},     # 岔路A终点：钥匙3
	"treasure":{"pos": Vector2(5500, 4550), "neighbors": [], "endpoint": true, "reward": "final"},   # 岔路B终点：宝箱
}

# 当前玩家所在节点
var current_node: String = ""
var visited_nodes: Array[String] = []

# 迷宫可视化
var maze_container: Node2D
var path_visuals: Dictionary = {}    # 路径线段
var node_markers: Dictionary = {}    # 节点标记（仅盲人模式下微弱发光）

var entrance_marker: Area2D         # 入口标记
var exit_a_marker: Area2D           # 岔路A出口（钥匙3）
var exit_b_marker: Area2D           # 岔路B出口（宝箱）
var status_label: Label
var chest_unlocked: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_maze_structure()
	_make_labels()

func _make_maze_structure() -> void:
	maze_container = Node2D.new()
	maze_container.name = "MazeStructure"
	add_child(maze_container)
	
	# 绘制所有路径连接
	var drawn_edges: Array = []
	for node_id in MAZE_NODES.keys():
		var node: Dictionary = MAZE_NODES[node_id]
		var pos: Vector2 = node["pos"]
		for neighbor_id in node["neighbors"]:
			var edge_key: String = node_id + "_" + neighbor_id
			if drawn_edges.has(edge_key):
				continue
			drawn_edges.append(edge_key)
			
			var npos: Vector2 = MAZE_NODES[neighbor_id]["pos"]
			var line := Line2D.new()
			line.width = 12
			line.default_color = Color("#2a2035")
			line.z_index = -5
			line.add_point(pos - maze_container.global_position)
			line.add_point(npos - maze_container.global_position)
			maze_container.add_child(line)
			
			path_visuals[edge_key] = line
	
	# 绘制节点标记
	for node_id in MAZE_NODES.keys():
		var node: Dictionary = MAZE_NODES[node_id]
		var pos: Vector2 = node["pos"]
		
		var marker := Area2D.new()
		marker.name = "Node_" + str(node_id)
		marker.position = pos - maze_container.global_position
		marker.set_meta("node_id", node_id)
		maze_container.add_child(marker)
		
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 18
		shape.shape = circle
		marker.add_child(shape)
		
		# 节点视觉
		var vis := Polygon2D.new()
		var vp := PackedVector2Array()
		for i in range(8):
			var a: float = TAU * i / 8.0
			vp.append(Vector2(cos(a) * 16, sin(a) * 16))
		vis.polygon = vp
		vis.color = Color("#251830")
		marker.add_child(vis)
		node_markers[node_id] = marker
		
		# 终点特殊标记
		if node.get("endpoint", false):
			var end_label := Label.new()
			end_label.text = "☆" if node["reward"] == "key_3" else "★"
			end_label.position = Vector2(-6, -10)
			end_label.add_theme_font_size_override("font_size", 18)
			end_label.add_theme_color_override("font_color", Color("#ffd700"))
			marker.add_child(end_label)
	
	# 入口
	entrance_marker = Area2D.new()
	entrance_marker.name = "Entrance"
	entrance_marker.position = MAZE_NODES["entry"]["pos"] - maze_container.global_position
	var eshape := CollisionShape2D.new()
	var ecircle := CircleShape2D.new()
	ecircle.radius = 24
	eshape.shape = ecircle
	entrance_marker.add_child(eshape)
	
	var evis := Polygon2D.new()
	var ep := PackedVector2Array()
	for i in range(12):
		var a: float = TAU * i / 12.0
		ep.append(Vector2(cos(a) * 22, sin(a) * 22))
	evis.polygon = ep
	evis.color = Color("#3a3060")
	entrance_marker.add_child(evis)
	
	var elabel := Label.new()
	elabel.text = "↓ 入口 ↓"
	elabel.position = Vector2(-24, -34)
	elabel.add_theme_font_size_override("font_size", 11)
	elabel.add_theme_color_override("font_color", Color("#8090e0"))
	entrance_marker.add_child(elabel)
	maze_container.add_child(entrance_marker)
	
	# 出口A（钥匙3）
	exit_a_marker = Area2D.new()
	exit_a_marker.name = "ExitA"
	exit_a_marker.position = MAZE_NODES["key_a"]["pos"] - maze_container.global_position
	var ashape := CollisionShape2D.new()
	var acircle := CircleShape2D.new()
	acircle.radius = 20
	ashape.shape = acircle
	exit_a_marker.add_child(ashape)
	var avis := Polygon2D.new()
	var ap := PackedVector2Array()
	for i in range(8):
		var a: float = TAU * i / 8.0
		ap.append(Vector2(cos(a) * 18, sin(a) * 18))
	avis.polygon = ap
	avis.color = Color("#40a060")
	exit_a_marker.add_child(avis)
	var alabel := Label.new()
	alabel.text = "钥匙3"
	alabel.position = Vector2(-16, -8)
	alabel.add_theme_font_size_override("font_size", 10)
	alabel.add_theme_color_override("font_color", Color("#60e080"))
	exit_a_marker.add_child(alabel)
	maze_container.add_child(exit_a_marker)
	
	# 出口B（宝藏）
	exit_b_marker = Area2D.new()
	exit_b_marker.name = "ExitB"
	exit_b_marker.position = MAZE_NODES["treasure"]["pos"] - maze_container.global_position
	var bshape := CollisionShape2D.new()
	var bcircle := CircleShape2D.new()
	bcircle.radius = 24
	bshape.shape = bcircle
	exit_b_marker.add_child(bshape)
	var bvis := Polygon2D.new()
	var bp := PackedVector2Array()
	for i in range(16):
		var a: float = TAU * i / 16.0
		bp.append(Vector2(cos(a) * 22, sin(a) * 22))
	bvis.polygon = bp
	bvis.color = Color("#605030")
	exit_b_marker.add_child(bvis)
	var blabel := Label.new()
	blabel.text = "宝箱\n(需4钥匙)"
	blabel.position = Vector2(-22, -16)
	blabel.add_theme_font_size_override("font_size", 9)
	blabel.add_theme_color_override("font_color", Color("#ffd700"))
	exit_b_marker.add_child(blabel)
	maze_container.add_child(exit_b_marker)

func _make_labels() -> void:
	var title := Label.new()
	title.text = "[ 地下黑暗迷宫 ]"
	title.position = Vector2(-60, -95)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#808098"))
	add_child(title)
	
	status_label = Label.new()
	status_label.position = Vector2(-80, 105)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "按 [E] 进入迷宫（需要盲人模式）"
	add_child(status_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _input(event: InputEvent) -> void:
	if not player_in_range:
		return
	if event.is_action_pressed("interact"):
		_enter_maze()

func _enter_maze() -> void:
	var view: String = _get_current_view()
	if view != "blind":
		status_label.text = "太黑了...需要盲人模式才能进入"
		hint_updated.emit("迷宫完全黑暗——切换到盲人模式后进入！")
		return
	
	is_inside = true
	current_node = "entry"
	visited_nodes = ["entry"]
	status_label.text = "进入迷宫...靠听觉导航！（F键回声定位）"
	hint_updated.emit("进入迷宫了！正确的路会发出'叮'声，错误的会发出'咚'声。")

func _process(_delta: float) -> void:
	if not is_inside:
		return
	
	# 在盲人模式下，持续检测玩家位置与最近节点的距离
	var view: String = _get_current_view()
	if view != "blind":
		# 非盲人模式 → 迷宫中什么都看不见
		return
	
	var player: Node2D = _get_player()
	if player == null:
		return
	
	# 检查是否到达某个节点
	var best_node: String = ""
	var best_dist: float = 99999.0
	for node_id in MAZE_NODES.keys():
		var npos: Vector2 = MAZE_NODES[node_id]["pos"]
		var dist: float = player.global_position.distance_to(npos)
		if dist < best_dist:
			best_dist = dist
			best_node = node_id
	
	if best_dist < 30.0 and best_node != current_node:
		# 到达新节点
		_arrive_at_node(best_node, player)

# 到达节点时的处理
func _arrive_at_node(node_id: String, player: Node2D) -> void:
	if visited_nodes.has(node_id):
		return  # 已经访问过
	visited_nodes.append(node_id)
	current_node = node_id
	
	var node_data: Dictionary = MAZE_NODES[node_id]
	
	# 播放声音反馈
	if node_data.get("is_correct", false):
		# 正确路径
		AudioManager.play_tone(880.0, 0.3)  # 清脆高音
		hint_updated.emit("♪ 叮！方向正确...")
		_flash_node(node_id, Color("#60e080"))
	elif node_data.get("wrong_path", false):
		# 错误路径
		AudioManager.play_tone(180.0, 0.4)  # 低沉嗡鸣
		hint_updated.emit("♪ 咚...这条路不对。退回去吧。")
		_flash_node(node_id, Color("#e06060"))
		# 把玩家弹回上一个节点
		_push_back(player)
	else:
		# 中间节点
		AudioManager.play_tone(523.0, 0.2)
	
	# 检查是否到达终点
	if node_data.get("endpoint", false):
		_reach_endpoint(node_id)

func _push_back(player: Node2D) -> void:
	if visited_nodes.size() >= 2:
		var prev: String = visited_nodes[visited_nodes.size() - 2]
		var target_pos: Vector2 = MAZE_NODES[prev]["pos"]
		# 平滑移动玩家回退
		var tween := create_tween()
		tween.tween_property(player, "global_position", target_pos, 0.3)
		current_node = prev

func _reach_endpoint(node_id: String) -> void:
	var node_data: Dictionary = MAZE_NODES[node_id]
	var reward: String = node_data.get("reward", "")
	
	if reward == "key_3":
		# 岔路A：获得钥匙3
		chosen_path = "A"
		is_inside = false
		status_label.text = "✨ 获得钥匙3（迷宫钥匙）！"
		hint_updated.emit("✨ 你在岔路A找到了钥匙3！")
		puzzle_completed.emit("key_3")
	elif reward == "final":
		# 岔路B：宝箱
		chosen_path = "B"
		_check_chest_open()
	
	_flash_node(node_id, Color("#ffd700"))

func _check_chest_open() -> void:
	# 检查是否拥有4把钥匙
	var keys: Array = _get_collected_keys()
	
	if keys.size() >= 4:
		# 开启宝箱！
		chest_unlocked = true
		is_inside = false
		status_label.text = "✨✨ 宝箱开启！！时间胶囊！！！ ✨✨"
		hint_updated.emit("🎆🎆🎆 四把钥匙集齐！宝箱开启！你完成了游戏！ 🎆🎆🎆")
		puzzle_completed.emit("treasure")
		_celebrate_victory()
	else:
		# 钥匙不足
		status_label.text = "宝箱锁住了...(%d/4钥匙)" % keys.size()
		hint_updated.emit("宝箱需要4把钥匙！你只有%d把。" % keys.size())
		# 弹出迷宫
		is_inside = false
		current_node = "entry"

func _celebrate_victory() -> void:
	# 大量庆祝粒子
	for i in range(30):
		await get_tree().create_timer(0.05).timeout
		var spark := CPUParticles2D.new()
		spark.amount = 15
		spark.lifetime = 1.5
		spark.emitting = true
		spark.gravity = Vector2(0, -60)
		spark.initial_velocity_min = 40
		spark.initial_velocity_max = 120
		var colors: Array = [Color.GOLD, Color.ORANGE, Color.CYAN, Color.MAGENTA, Color.WHITE]
		spark.color = colors[i % colors.size()]
		spark.position = Vector2(randf_range(-80, 80), randf_range(-60, 20))
		add_child(spark)

func _flash_node(node_id: String, flash_color: Color) -> void:
	var marker: Area2D = node_markers.get(node_id) as Area2D
	if marker == null:
		return
	var vis: Polygon2D = marker.get_child(1) as Polygon2D  # 第二个子是视觉
	if vis == null:
		return
	var tween := create_tween()
	tween.tween_property(vis, "color", flash_color, 0.15)
	tween.tween_property(vis, "color", Color("#251830"), 0.4)

func _get_current_view() -> String:
	var world: Node = get_tree().get_nodes_in_group("world").front()
	if world and world.has_method("get_current_view"):
		return world.get_current_view()
	return "normal"

func _get_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		return node
	return null

func _get_collected_keys() -> Array:
	var main: Node = get_tree().current_scene
	if main and main.has_method("get_collected_keys"):
		return main.get_collected_keys()
	return []

func is_solved() -> bool:
	return chest_unlocked
