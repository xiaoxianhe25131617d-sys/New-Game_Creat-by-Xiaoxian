extends Area2D
class_name PuzzleDarkMaze
# ════════════════════════════════════════════════════════════
#  关卡5：地下迷宫 — 可见迷宫，双岔路
#  玩家在地图中实际走入迷宫走廊
#  岔路A终点 = 钥匙3  岔路B终点 = 宝箱(需4钥匙)
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var player_in_range: bool = false
var fork_a_done: bool = false
var fork_b_done: bool = false

# 岔路端点位置
const FORK_A_POS := Vector2(5000, UG_GROUND_Y_PX)
const FORK_B_POS := Vector2(6000, UG_GROUND_Y_PX)
const UG_GROUND_Y_PX := 269 * 16  # 4304

var title_label: Label
var status_label: Label

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(800, 200)
	shape.shape = rect
	shape.position = Vector2(0, -60)
	add_child(shape)
	_make_labels()

func _make_labels() -> void:
	title_label = Label.new()
	title_label.text = "[ 地下迷宫 ]"
	title_label.position = Vector2(-50, -95)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color("#c0b0ff"))
	add_child(title_label)

	status_label = Label.new()
	status_label.position = Vector2(-140, 85)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#ffe8a0"))
	status_label.text = "走入迷宫，选择岔路..."
	add_child(status_label)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _process(_delta: float) -> void:
	if player_in_range and not (fork_a_done and fork_b_done):
		var player := _get_player()
		if player == null: return
		var pp := player.global_position

		# 检测到达岔路A终点（钥匙3）
		if not fork_a_done and _near(pp, FORK_A_POS, 80):
			fork_a_done = true
			status_label.text = "✨ 到达岔路A！获得钥匙3！"
			hint_updated.emit("✨ 你在岔路A找到了迷宫钥匙（钥匙3）！")
			puzzle_completed.emit("key_3")
			_play_sparkles(FORK_A_POS, Color.GREEN)

		# 检测到达岔路B终点（宝箱）
		if not fork_b_done and _near(pp, FORK_B_POS, 80):
			var keys := _get_collected_keys()
			if keys.size() >= 4:
				fork_b_done = true
				status_label.text = "🎆 宝箱开启！集齐了4把钥匙！"
				hint_updated.emit("🎆🎆 宝箱开启！时间胶囊！")
				puzzle_completed.emit("treasure")
				_play_sparkles(FORK_B_POS, Color.GOLD)
			else:
				status_label.text = "宝箱锁住了...需要4把钥匙 (%d/4)" % keys.size()
				hint_updated.emit("宝箱需要4把钥匙。目前只有%d把。" % keys.size())
				# 推开玩家
				var tween := create_tween()
				tween.tween_property(player, "global_position", FORK_B_POS + Vector2(100, -30), 0.3)

func _near(a: Vector2, b: Vector2, d: float) -> bool:
	return a.distance_to(b) < d

func _play_sparkles(pos: Vector2, color: Color) -> void:
	for i in range(12):
		var s := Polygon2D.new()
		var sp := PackedVector2Array()
		for j in range(8):
			var a := TAU * j / 8.0
			sp.append(Vector2(cos(a) * 6, sin(a) * 6))
		s.polygon = sp
		s.color = color
		s.position = pos + Vector2(randf_range(-30, 30), randf_range(-20, 0))
		add_child(s)
		var t := create_tween()
		t.tween_property(s, "position", s.position + Vector2(randf_range(-40, 40), -randf_range(40, 80)), 1.0)
		t.parallel().tween_property(s, "modulate:a", 0.0, 1.0)
		t.tween_callback(s.queue_free)

func _get_player() -> Node2D:
	for n in get_tree().get_nodes_in_group("player"): return n
	return null

func _get_collected_keys() -> Array:
	var main := get_tree().current_scene
	if main and main.has_method("get_collected_keys"):
		return main.get_collected_keys()
	return []

func is_solved() -> bool:
	return fork_a_done
