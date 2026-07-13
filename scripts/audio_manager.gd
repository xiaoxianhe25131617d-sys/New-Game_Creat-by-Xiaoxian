extends Node
## AudioManager - 使用真实MP3音效文件
## BGM 循环播放，视角切换自动换曲

const AUDIO_DIR := "res://assets/audio"

# ── 音效映射表：sfx_type → 文件名 ──
const SFX_MAP: Dictionary = {
	"btn_click": "按钮被按下.MP3",
	"jump": "落地.MP3",
	"land": "落地.MP3",
	"walk": "走路.MP3",
	"laser_place": "把激光放到装置里.MP3",
	"laser_rotate": "激光装置转动.MP3",
	"laser_fire": "发射激光.MP3",
	"chest_open": "宝箱开启.MP3",
	"maze_correct": "黑色迷宫正确声音.MP3",
	"maze_wrong": "黑色迷宫错误.MP3",
	"grid_slide": "九宫格滑动声音.MP3",
	"light_on": "开灯.MP3",
	"blind_correct": "盲人模式灯的正确音效.MP3",
	"blind_wrong": "盲人模式灯的错误音效.MP3",
	"blind_cane": "盲杖.MP3",
	"wall_correct": "墙按到正确的按钮.MP3",
	"stone_door": "石门开启.MP3",
	"enter_underground": "enter_underground_maze.MP3",
	"lock_turn": "转动密码锁.MP3",
	# 小鸟音效
	"bird_chirp": "小鸟音效.MP3",
	# 动物音效
	"dog_bark":      "小狗叫.MP3",
	"cat_meow":      "小猫叫.MP3",
	"dog_triggered": "小狗被触发.MP3",
	"cat_triggered": "小猫被触发.MP3",
	# NPC 对话开始音
	"npc_talk": "触发npc对话音效.MP3",
	"npc_talk_depression": "抑郁模式npc被触发音效.MP3",
	# 密码本/书翻开
	"book_open": "转动密码锁.MP3",  # 翻书感
	# 开门（点开房间/找不同等关卡）
	"door_open": "开门（就是触发和房子有关系的关卡放置，比如找不同.MP3",
	# 别名：某些代码用了简写或通用名
	"collect": "宝箱开启.MP3",     # 收集物 → 宝箱音
	"echo": "盲杖.MP3",            # 回声 → 盲杖音
	"dash": "按钮被按下.MP3",      # 冲刺 → 按钮音暂代
	# "save" 故意不加 → autosave 静默，避免随机出现"奇怪音效"
}

# 各音效类型的音量覆盖（db）：未配置则用默认 -5.0
const SFX_VOLUME: Dictionary = {
	"jump":       -14.0,   # 跳跃音不要太大
	"land":       -12.0,
	"grid_slide": -10.0,   # 九宫格滑动不要太响
	"btn_click":  -10.0,
	"npc_talk":   -2.0,
	"book_open":  -8.0,
	"door_open":  -6.0,
	"stone_door": -6.0,
}

# ── BGM 映射 ──
const BGM_MAP: Dictionary = {
	"normal":     "正常模式的音乐.MP3",
	"depression": "抑郁模式音乐.MP3",
	"autism":     "自闭症模式背景音乐.MP3",
	"adhd":       "ADHD背景音乐.MP3",
	"blind":      "盲人模式背景音乐.MP3",
}

var bgm_player: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_cache: Dictionary = {}       # filename → AudioStream (预加载)
var bgm_cache: Dictionary = {}       # view → AudioStream (预加载)
var current_view: String = "normal"
var current_region: String = "spawn"

# 走路专用 channel（防止叠加）
var _walk_channel: AudioStreamPlayer
var _walk_should_loop: bool = false  # 控制 finished 信号是否触发循环

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preload_all()
	_setup_bgm()
	_setup_sfx_pool()

func _preload_all() -> void:
	# 预加载所有 SFX
	for sfx_type in SFX_MAP:
		var fname: String = SFX_MAP[sfx_type]
		if not sfx_cache.has(fname):
			var path := AUDIO_DIR + "/" + fname
			if ResourceLoader.exists(path):
				sfx_cache[fname] = load(path) as AudioStream
			else:
				push_warning("AudioManager: SFX not found: " + path)
	# 预加载所有 BGM
	for view_name in BGM_MAP:
		var fname: String = BGM_MAP[view_name]
		var path := AUDIO_DIR + "/" + fname
		if ResourceLoader.exists(path):
			bgm_cache[view_name] = load(path) as AudioStream
		else:
			push_warning("AudioManager: BGM not found: " + path)

# 各视角 BGM 音量（db），未配置则用默认 -12.0
const BGM_VOLUME: Dictionary = {
	"normal":     -12.0,
	"depression": -4.0,   # 抑郁模式调大
	"adhd":       -4.0,   # ADHD模式调大
	"autism":     -12.0,
	"blind":      -12.0,
}

func _setup_bgm() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM"
	bgm_player.bus = "Master"
	bgm_player.volume_db = BGM_VOLUME.get("normal", -12.0)
	add_child(bgm_player)
	# 预加载默认 BGM 并连接循环
	var stream: AudioStream = bgm_cache.get("normal")
	if stream:
		bgm_player.stream = stream
		bgm_player.finished.connect(_on_bgm_finished)
		bgm_player.play()

func _on_bgm_finished() -> void:
	# BGM 播完后自动循环
	if bgm_player != null and bgm_player.stream != null:
		bgm_player.play()

func _setup_sfx_pool() -> void:
	# 走路专用 channel：音量单独控制，stop_walk() 专用停止
	_walk_channel = AudioStreamPlayer.new()
	_walk_channel.name = "SFX_Walk"
	_walk_channel.bus = "Master"
	_walk_channel.volume_db = -6.0   # 走路音量
	add_child(_walk_channel)
	# 用 finished 信号实现循环（比设置 loop 属性更可靠）
	_walk_channel.finished.connect(_on_walk_finished)

	for i in range(8):
		var sfx := AudioStreamPlayer.new()
		sfx.name = "SFX_%d" % i
		sfx.bus = "Master"
		sfx.volume_db = -5.0
		add_child(sfx)
		sfx_pool.append(sfx)

# ── SFX Methods ──

## 播放指定类型的音效。走路使用专用 channel 防叠加。
func play_sfx(sfx_type: String) -> void:
	var fname: String = SFX_MAP.get(sfx_type, "")
	if fname.is_empty():
		return  # "save" 等故意留空 → 静默
	var stream: AudioStream = sfx_cache.get(fname)
	if stream == null:
		return

	var vol: float = SFX_VOLUME.get(sfx_type, -5.0)

	# 走路专用 channel：循环播放（finished信号触发重播），停时由 stop_walk_sfx 中断
	if sfx_type == "walk":
		_walk_should_loop = true
		if _walk_channel != null and not _walk_channel.playing:
			_walk_channel.stream = stream
			_walk_channel.play()
		return

	# 找一个空闲 channel
	for sfx in sfx_pool:
		if not sfx.playing:
			sfx.volume_db = vol
			sfx.stream = stream
			sfx.play()
			return
	# 所有 channel 都在用 → 切到第一个（覆盖最旧的短音效）
	var first := sfx_pool[0] as AudioStreamPlayer
	first.stop()
	first.volume_db = vol
	first.stream = stream
	first.play()

## 走路音效播完后自动循环（只要 _walk_channel.stream 不为空且未被 stop）
func _on_walk_finished() -> void:
	# stop() 会触发 finished 信号，但此时 playing=false；重播前检查是否主动停止
	# 用 _walk_should_loop 标志区分"循环继续"和"主动停止"
	if _walk_should_loop and _walk_channel != null and _walk_channel.stream != null:
		_walk_channel.play()

## 立即停止走路音效（玩家停下时调用）
func stop_walk_sfx() -> void:
	_walk_should_loop = false
	if _walk_channel != null and _walk_channel.playing:
		_walk_channel.stop()

# ── BGM Region / View ──

func set_region(region: String) -> void:
	current_region = region

## 切换视角时切换 BGM，并确保循环
func set_view(view: String) -> void:
	if view == current_view:
		return
	current_view = view
	var stream: AudioStream = bgm_cache.get(view)
	if stream == null or bgm_player == null:
		return
	# 断开旧连接、切流、重播
	if bgm_player.finished.is_connected(_on_bgm_finished):
		bgm_player.finished.disconnect(_on_bgm_finished)
	bgm_player.stop()
	bgm_player.stream = stream
	bgm_player.volume_db = BGM_VOLUME.get(view, -12.0)
	bgm_player.finished.connect(_on_bgm_finished)
	bgm_player.play()

# ── TONE GENERATOR (保留，用于无法替代的谜题音高反馈) ──

func play_tone(freq: float, duration: float = 0.3) -> void:
	for sfx in sfx_pool:
		if not sfx.playing:
			_play_tone_on(sfx, freq, duration)
			return

func _play_tone_on(player: AudioStreamPlayer, freq: float, duration: float) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = maxf(duration + 0.05, 0.1)
	player.stream = generator
	player.play()
	var playback := player.get_stream_playback()
	var frames := int(44100.0 * duration)
	for i in range(frames):
		var t: float = float(i) / 44100.0
		var envelope: float = sin(t * PI / duration)
		var s: float = sin(t * freq * TAU) * envelope * 0.25
		playback.push_frame(Vector2(s, s))
