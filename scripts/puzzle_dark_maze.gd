extends Area2D
class_name PuzzleDarkMaze
# ════════════════════════════════════════════════════════════
#  关卡5：地下迷宫 — 物理可走迷宫，多层高低地形
#  玩家走路进入迷宫，自由行走探索
#  岔路A(左下/下层) → 钥匙3  岔路B(右上/上层) → 宝箱
# ════════════════════════════════════════════════════════════

signal puzzle_completed(reward_id: String)
signal hint_updated(text: String)

var fork_a_claimed: bool = false
var fork_b_claimed: bool = false

# 下层钥匙房位置 (tile: x≈275, y≈UG_GROUND_ROW+5 ≈ 274*16=4384)
const KEY_ROOM_POS := Vector2(275 * 16 + 10, (269 + 5) * 16 - 16)
# 上层宝箱房位置 (tile: x≈430, y≈UG_GROUND_ROW-7 ≈ 262*16=4192)  
const TREASURE_ROOM_POS := Vector2(430 * 16, (269 - 7) * 16 - 16)

var title_label: Label
var status_label: Label
var toast_timer: float = 0.0

func _ready() -> void:
	# This puzzle is triggered by world zones, not direct collision
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	status_label.text = "走入迷宫..."
	add_child(status_label)

func _process(delta: float) -> void:
	if fork_a_claimed and fork_b_claimed:
		return

	var player := _get_player()
	if player == null:
		return
	var pp := player.global_position

	# 检测到达钥匙房（下层左侧区域）
	if not fork_a_claimed and is_in_rect(pp, 270 * 16, 4400, 284 * 16, 4460):
		fork_a_claimed = true
		status_label.text = "✨ 找到钥匙3！"
		hint_updated.emit("✨ 你在迷宫深处找到了钥匙3！")
		puzzle_completed.emit("key_3")
		_play_sparkles(KEY_ROOM_POS, Color.GREEN)

	# 检测到达宝箱房（上层右侧区域）
	if not fork_b_claimed and is_in_rect(pp, 425 * 16, 4160, 439 * 16, 4220):
		var keys := _get_collected_keys()
		if keys.size() >= 4:
			fork_b_claimed = true
			status_label.text = "🎆 宝箱开启！时间胶囊！"
			hint_updated.emit("🎆 宝箱已开启！获得了时间胶囊！")
			puzzle_completed.emit("treasure")
			_play_sparkles(TREASURE_ROOM_POS, Color.GOLD)
		else:
			status_label.text = "宝箱锁住了...需要4把钥匙 (%d/4)" % keys.size()
			hint_updated.emit("宝箱需要4把钥匙。你目前只有%d把。" % keys.size())
			# 轻轻推开
			var tween := create_tween()
			tween.tween_property(player, "global_position:x", pp.x - 60, 0.2)

	toast_timer -= delta
	if toast_timer > 0:
		return
	if not fork_a_claimed and player_below_main_level(pp):
		status_label.text = "下层区域...远处有微光（钥匙在左边深处）"
		toast_timer = 4.0
	elif not fork_b_claimed and player_above_main_level(pp):
		var ks := _get_collected_keys()
		status_label.text = "上层平台...宝箱在右上方（%d/4钥匙）" % ks.size()
		toast_timer = 4.0

func is_in_rect(p: Vector2, x0: float, y0: float, x1: float, y1: float) -> bool:
	return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1

func player_below_main_level(pp: Vector2) -> bool:
	return pp.y > (UG_GROUND_Y + 48)

func player_above_main_level(pp: Vector2) -> bool:
	return pp.y < (UG_GROUND_Y - 32)

const UG_GROUND_Y := 269 * 16

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
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null

func _get_collected_keys() -> Array:
	var main := get_tree().current_scene
	if main and main.has_method("get_collected_keys"):
		return main.get_collected_keys()
	return []

func is_solved() -> bool:
	return fork_a_claimed
