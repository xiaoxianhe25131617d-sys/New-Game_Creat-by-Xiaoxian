extends CharacterBody2D
class_name MindscapePlayer

signal special_used(view: String)

const SPEED: float = 320.0
const AIR_SPEED: float = 280.0
const DASH_SPEED: float = 720.0
const JUMP_VELOCITY: float = -580.0
const GRAVITY: float = 1600.0
const MAX_FALL_SPEED: float = 900.0
const COYOTE_TIME: float = 0.08
const JUMP_BUFFER: float = 0.1

var current_view: String = "normal"
var dash_time: float = 0.0
var controls_enabled: bool = true
var special_cooldown: float = 0.0
var jump_held: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false
var is_on_ladder: bool = false  # 梯子上（由 main.gd 设置）
var _drop_cooldown: float = 0.0  # 穿透地板冷却（防止反复触发）

# ADHD 自动行走
var adhd_auto_dir: float = 0.0     # -1向左, 0停止, 1向右
var adhd_speed_mult: float = 1.0   # ADHD速度倍率

# 视角跳跃倍率
const VIEW_JUMP_MULT: Dictionary = {
	"normal": 1.0,
	"blind": 1.0,      # 盲人模式与普通一致，确保可达所有平台
	"adhd": 1.4,        # ADHD跳得最高
	"autism": 1.0,
	"depression": 0.6,  # 抑郁模式跳得最低(沉重)
}
const VIEW_SPEED_MULT: Dictionary = {
	"normal": 1.0,
	"blind": 0.85,
	"adhd": 1.25,
	"autism": 1.0,
	"depression": 0.75,
}

@onready var body: Polygon2D = $Body
@onready var aura: Line2D = $Aura
@onready var sprite: Sprite2D = $CharacterTexture

func _physics_process(delta: float) -> void:
	# ── 梯子上：跳过普通物理（由 main.gd 接管位置）──
	if is_on_ladder:
		# 仍然允许水平移动（按 A/D 离开梯子）
		var hdir: float = 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			hdir = -1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			hdir = 1.0
		velocity.x = hdir * SPEED * 0.5
		if hdir != 0:
			scale.x = signf(hdir)
		# y 速度归零（由 main.gd 直接控制 y）
		velocity.y = 0.0
		move_and_slide()
		_update_animation(hdir)
		return

	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	was_on_floor = is_on_floor()

	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y = minf(velocity.y, MAX_FALL_SPEED)

	# ── 穿透地板（按 ↓ 从可穿透平台掉下去）──
	# 关键：玩家**踩在** drop tile 上时，drop tile 在物理层2（独立 tileset）
	# 玩家 mask 同时启用 layer 1+2，所以能站在 drop tile 上
	# 当玩家按下 S/Down/Ui_Down 时，临时关闭 mask bit 2 → drop tile 对玩家透明 → 玩家掉下去
	# 掉到下层 (y>=269) 之后重新开启 mask bit 2
	if _drop_cooldown > 0.0:
		_drop_cooldown -= delta
		# 掉下去后重新开启碰撞层2（当玩家 y 已掉到主层地面以下）
		var feet_tile_y := floori((global_position.y + 31) / 16.0)
		if feet_tile_y >= 269:  # 已经掉到主层地板(y=268)以下
			set_collision_mask_value(2, true)
			_drop_cooldown = 0.0
	elif _drop_cooldown <= 0.0:
		# 确保层2开启
		set_collision_mask_value(2, true)

	var down_held: bool = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down")
	# 也支持 jump（S）+drop 组合 — 但 jump 优先级更高
	if down_held and is_on_floor() and _drop_cooldown <= 0.0:
		# 检查玩家脚下是否有可穿透地板
		var world_node := get_tree().get_first_node_in_group("world") as MindscapeWorld
		if world_node != null:
			var feet_x := floori(global_position.x / 16.0)
			var feet_y := floori((global_position.y + 31) / 16.0)
			# 玩家2tile宽，检测脚下多个位置
			# 同时检测 feet_y 和 feet_y+1（浮点精度可能导致差1行）
			var on_drop := false
			for dx in range(-1, 2):
				if world_node.is_drop_through_tile(Vector2i(feet_x + dx, feet_y)):
					on_drop = true
					break
				if world_node.is_drop_through_tile(Vector2i(feet_x + dx, feet_y + 1)):
					on_drop = true
					break
			if on_drop:
				# 暂时禁用穿透地板碰撞层 → drop tile 对玩家透明
				set_collision_mask_value(2, false)
				_drop_cooldown = 0.5  # 500ms 内不再触发
				velocity.y = 30  # 轻微下推确保脱离地板

	var direction: float = 0.0
	var spd_mult: float = VIEW_SPEED_MULT.get(current_view, 1.0)

	if controls_enabled:
		# 原始方向输入
		var raw_dir: float = 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			raw_dir = -1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			raw_dir = 1.0

		# ADHD 自动行走：按键一次即持续移动
		if current_view == "adhd":
			if raw_dir != 0.0:
				adhd_auto_dir = raw_dir
			elif Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("special"):
				# E/F中断自动行走
				adhd_auto_dir = 0.0
			direction = adhd_auto_dir
			spd_mult *= adhd_speed_mult
		else:
			direction = raw_dir
			adhd_auto_dir = 0.0

		# 跳跃（带视角倍率）
		var space_now := Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("jump")
		var space_just := Input.is_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("jump")
		var jmp_mult: float = VIEW_JUMP_MULT.get(current_view, 1.0)

		if space_just:
			jump_buffer_timer = JUMP_BUFFER
		else:
			jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)

		var can_jump := coyote_timer > 0.0 and jump_buffer_timer > 0.0 and not jump_held
		if can_jump:
			velocity.y = JUMP_VELOCITY * jmp_mult
			jump_held = true
			coyote_timer = 0.0
			jump_buffer_timer = 0.0
		if not space_now:
			jump_held = false

		if not space_now and velocity.y < -200.0:
			velocity.y *= 0.55

		# 特殊能力
		special_cooldown -= delta
		if Input.is_action_just_pressed("special") and special_cooldown <= 0.0:
			use_special()

	# 加速度
	if dash_time > 0.0:
		dash_time -= delta
		velocity.x = signf(scale.x) * DASH_SPEED
	else:
		var target_speed: float = (SPEED if is_on_floor() else AIR_SPEED) * spd_mult
		var accel: float = target_speed * 12.0 * delta
		velocity.x = move_toward(velocity.x, direction * target_speed, accel)
		if direction != 0:
			scale.x = signf(direction)

	move_and_slide()
	_update_animation(direction)

func _update_animation(dir: float) -> void:
	if sprite == null:
		return
	if abs(velocity.x) < 5.0 and is_on_floor():
		sprite.scale.y = lerp(sprite.scale.y, 0.72 + sin(Time.get_ticks_msec() * 0.004) * 0.02, 0.1)
	else:
		sprite.scale.y = lerp(sprite.scale.y, 0.72, 0.2)
	if dir != 0:
		sprite.scale.x = abs(sprite.scale.x) * signf(dir)

func use_special() -> void:
	if current_view == "adhd":
		dash_time = 0.18
		special_cooldown = 0.35
	elif current_view == "blind":
		pulse_echo()
		special_cooldown = 1.2
	special_used.emit(current_view)

func set_view(view: String) -> void:
	current_view = view
	var color: Color = GameData.VIEW_COLORS.get(view, Color.WHITE)
	body.color = color
	aura.default_color = color.lightened(0.25)
	# ADHD模式：重置自动行走
	if view != "adhd":
		adhd_auto_dir = 0.0

func pulse_echo() -> void:
	var tween: Tween = create_tween()
	aura.width = 10.0
	aura.modulate.a = 1.0
	aura.scale = Vector2.ONE
	tween.parallel().tween_property(aura, "scale", Vector2(5.0, 5.0), 0.55)
	tween.parallel().tween_property(aura, "modulate:a", 0.0, 0.55)

static func create() -> MindscapePlayer:
	var player := MindscapePlayer.new()
	player.name = "Player"
	player.collision_layer = 1
	player.collision_mask = 3  # 层1(普通碰撞) + 层2(可穿透地板)
	player.z_index = 100

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(34, 62)
	shape.shape = rect
	player.add_child(shape)

	var poly := Polygon2D.new()
	poly.name = "Body"
	poly.polygon = PackedVector2Array([Vector2(-18, 28), Vector2(-14, -22), Vector2(0, -34), Vector2(14, -22), Vector2(18, 28)])
	poly.color = Color("#f5d58e")
	poly.visible = false
	player.add_child(poly)

	var sprite := Sprite2D.new()
	sprite.name = "CharacterTexture"
	var player_tex := load("res://assets/characters/player.svg")
	if player_tex != null:
		sprite.texture = player_tex
	sprite.scale = Vector2(0.72, 0.72)
	sprite.position = Vector2(0, -12)
	player.add_child(sprite)

	var aura := Line2D.new()
	aura.name = "Aura"
	aura.closed = true
	aura.points = PackedVector2Array([Vector2(-32, 0), Vector2(-20, -30), Vector2(0, -42), Vector2(20, -30), Vector2(32, 0), Vector2(20, 30), Vector2(0, 42), Vector2(-20, 30)])
	aura.width = 4
	aura.default_color = Color("#f5d58e")
	aura.modulate.a = 0.0
	aura.z_index = 99
	player.add_child(aura)
	return player
