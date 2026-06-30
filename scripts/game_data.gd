extends RefCounted
class_name GameData

# ════════════════════════════════════════════════════════════
#  视角之谜 (Perspective Puzzle) — 游戏数据定义
#  修订版：基于完整设计文档重建
# ════════════════════════════════════════════════════════════

const VIEWS: Array = ["normal", "blind", "deaf", "adhd", "depression"]

const VIEW_NAMES: Dictionary = {
	"normal": "普通视角",
	"blind": "盲人视角（全黑+回声定位）",
	"deaf": "聋人视角（灰度+振动波纹）",
	"adhd": "ADHD视角（高对比+高速移动）",
	"depression": "抑郁视角（暗淡+潜台词可见）",
}

const VIEW_COLORS: Dictionary = {
	"normal": Color("#f5d58e"),
	"blind": Color("#4ac8ff"),
	"deaf": Color("#8fb4d6"),
	"adhd": Color("#ffde4a"),
	"depression": Color("#8ca7bd"),
}

# 玩家出生点（中央广场区域）—— Y 值是角色中心点
# 角色高 62px，地面顶面在 Y=3200，所以中心应在 3200-31=3169
const PLAYER_START: Vector2 = Vector2(3400, 3168)
const WORLD_SIZE: Vector2 = Vector2(11200, 4500)

# ════════════════════════════════════════════════════════════
#  区域定义（按地图从左到右排列）
# ════════════════════════════════════════════════════════════
const REGIONS: Dictionary = {
	"spawn":      {"name": "出生点",     "x": 3400, "view": "normal"},
	"forest":     {"name": "左侧森林",   "x": 600,  "view": "depression"},
	"plaza":      {"name": "中央广场",   "x": 3400, "view": "normal"},
	"lighthouse": {"name": "湖泊灯塔",   "x": 4900, "view": "blind"},
	"dam":        {"name": "水坝工业区", "x": 6200, "view": "blind"},
	"station":    {"name": "旧车站",     "x": 7300, "view": "deaf"},
	"park":       {"name": "游乐园",     "x": 8800, "view": "adhd"},
	"observatory":{"name": "许愿堂",     "x": 10200, "view": "adhd"},
	"underground": {"name": "地下迷宫",   "x": 5200, "view": "blind", "y": 4300},
}

# ════════════════════════════════════════════════════════════
#  六大关卡定义
# ════════════════════════════════════════════════════════════
const LEVELS: Array = [
	{
		"id": "texture_wall",
		"name": "纹理墙",
		"region": "forest",
		"pos": Vector2(480, 3170),
		"type": "texture_wall",
		"prereq": "",           # 无前置
		"reward": "stone_door", # 打开石门 → 解锁左侧其他关卡
		"hint": "这面墙表面凹凸不平。用键盘按键感受它的纹理...\n左侧有深坑，需要ADHD模式冲刺才能跳过。",
		"view_hint": "普通视角即可，需要仔细触摸。过深坑需要ADHD冲刺。",
	},
	{
		"id": "find_difference",
		"name": "找不同密室",
		"region": "forest",
		"pos": Vector2(1200, 3170),
		"type": "find_diff",
		"prereq": "texture_wall", # 纹理墙通过后
		"reward": "laser_device_1",
		"hint": "进入小楼，在不同视角下观察场景...找出隐藏的差异。",
		"view_hint": "自闭症视角能看到细节差异，抑郁症视角看到潜台词。",
	},
	{
		"id": "banquet_painting",
		"name": "宴会厅油画",
		"region": "forest",
		"pos": Vector2(2000, 3100),
		"type": "dance_sequence",
		"prereq": "texture_wall",
		"reward": "key_1",
		"hint": "墙上的油画在动！小人在跳舞...记住他们的舞步顺序。",
		"view_hint": "自闭症/抑郁症模式下能看清舞蹈序列。",
	},
	{
		"id": "amusement_lights",
		"name": "游乐园灯板",
		"region": "park",
		"pos": Vector2(8800, 3170),
		"type": "light_board",
		"prereq": "",
		"reward": "key_2",
		"hint": "3×3灯板...每个灯都有不同的声音。盲人模式听，ADHD模式跑！",
		"view_hint": "盲人模式听音辨位，ADHD模式快速点亮。",
	},
	{
		"id": "npc_password",
		"name": "NPC密码台",
		"region": "observatory",
		"pos": Vector2(10500, 3170),
		"type": "npc_cipher",
		"prereq": "",
		"reward": "key_4",
		"hint": "5个NPC各说一段话...他们真正想表达的是什么？",
		"view_hint": "抑郁症模式看潜台词，ADHD模式读密码本。",
	},
	{
		"id": "dark_maze",
		"name": "地下黑暗迷宫",
		"region": "underground",
		"pos": Vector2(5200, 4250),
		"type": "audio_maze",
		"prereq": "",
		"reward": "key_3",
		"hint": "从灯塔旁的台阶走下去...完全黑暗的迷宫，靠声音辨别方向。",
		"view_hint": "盲人模式——听觉导航是唯一出路。F键回声探测。",
	},
	{
		"id": "nine_grid",
		"name": "石台拼图",
		"region": "dam",
		"pos": Vector2(6000, 3165),
		"type": "nine_grid",
		"prereq": "",
		"reward": "laser_device_2",
		"hint": "石台上的3×3拼图...滑动方块到正确位置。抑郁症模式每10秒闪烁正确图案。",
		"view_hint": "抑郁症模式每10秒能看到正确排列的提示。",
	},
]

# ════════════════════════════════════════════════════════════
#  钥匙系统
# ════════════════════════════════════════════════════════════
const KEYS: Dictionary = {
	"key_1":  {"name": "宴会厅钥匙",  "source": "banquet_painting",  "color": Color("#ffd700")},
	"key_2":  {"name": "游乐园钥匙",  "source": "amusement_lights",   "color": Color("#ff6b6b")},
	"key_3":  {"name": "迷宫钥匙",    "source": "dark_maze",         "color": Color("#4ecdc4")},
	"key_4":  {"name": "天文台钥匙",  "source": "npc_password",      "color": Color("#a29bfe")},
}
# 四把钥匙集齐 → 地下迷宫岔路B开启宝箱

# ════════════════════════════════════════════════════════════
#  风向标 + 激光联动系统
# ════════════════════════════════════════════════════════════
const LASER_SYSTEM: Dictionary = {
	"laser_device_1": {"name": "激光装置1", "source": "find_difference"},
	"laser_device_2": {"name": "激光装置2", "source": "nine_grid"},  # 石台拼图奖励
	"wind_vane_1":   {"name": "风向标1",   "pos": Vector2(2800, 2900), "direction": Vector2(1, 0.3)},
	"wind_vane_2":   {"name": "风向标2",   "pos": Vector2(7200, 2900), "direction": Vector2(-1, 0.3)},
	"treasure_pos":  Vector2(5000, 2700),  # 两束激光交叉点 = 宝藏位置
}

# 石台拼图（九宫格滑动拼图，产出激光装置2）
const NINE_GRID: Dictionary = {
	"pos": Vector2(6000, 3165),
	"hint": "石台上的3×3拼图...抑郁症模式每10秒闪烁显示正确图案轮廓。",
	"reward": "laser_device_2",
}

# ════════════════════════════════════════════════════════════
#  NPC 定义（更新版：关联新关卡）
# ════════════════════════════════════════════════════════════
const NPCS: Array = [
	# ── 出生点/中央广场 ──
	{"id": "guide_old_man", "name": "引导老人", "region": "spawn", "pos": Vector2(3200, 3176), "portrait": "#b98b62"},
	{"id": "map_keeper",     "name": "地图管理员", "region": "spawn", "pos": Vector2(3600, 3176), "portrait": "#80b2d4"},

	# ── 左侧森林区域 ──
	{"id": "ranger",         "name": "护林员",    "region": "forest", "pos": Vector2(700, 3176),   "portrait": "#719d64"},
	{"id": "poet",           "name": "诗人",      "region": "forest", "pos": Vector2(1400, 3176),  "portrait": "#b1a0d8"},
	{"id": "house_keeper",   "name": "密室看守",  "region": "forest", "pos": Vector2(1200, 3176), "portrait": "#cba0ff"},

	# ── 湖泊灯塔 ──
	{"id": "dock_elder",     "name": "码头老人",  "region": "lighthouse", "pos": Vector2(4650, 3176), "portrait": "#8d9fba"},
	{"id": "keeper",         "name": "灯塔管理员", "region": "lighthouse", "pos": Vector2(5330, 3176), "portrait": "#d8a25e"},
	{"id": "braille_scholar","name": "盲文学者",  "region": "lighthouse", "pos": Vector2(4430, 3176), "portrait": "#71b8ff", "blind_npc": true},

	# ── 水坝工业区 ──
	{"id": "engineer",       "name": "总工程师",  "region": "dam", "pos": Vector2(6200, 3176), "portrait": "#abb0b8"},

	# ── 旧车站 ──
	{"id": "sign_girl",      "name": "手语少女",  "region": "station", "pos": Vector2(7200, 3176), "portrait": "#a8d5bd", "sign_only": true},
	{"id": "painter",        "name": "流浪画家",  "region": "station", "pos": Vector2(7260, 3176), "portrait": "#cba0ff"},
	{"id": "station_master", "name": "站长",      "region": "station", "pos": Vector2(8130, 3176), "portrait": "#94adc6"},

	# ── 游乐园 ──
	{"id": "clown",          "name": "小丑",      "region": "park", "pos": Vector2(8650, 3176),  "portrait": "#ff7d7d"},
	{"id": "mechanic",       "name": "修理工",    "region": "park", "pos": Vector2(8680, 3176),  "portrait": "#d9be6a"},
	{"id": "ticket",         "name": "售票员",    "region": "park", "pos": Vector2(9460, 3176),  "portrait": "#78d0b8"},

	# ── 天文台（NPC密码台5个NPC）──
	{"id": "npc_cipher_1",   "name": "守卫A",    "region": "observatory", "pos": Vector2(10300, 3176), "portrait": "#94adc6"},
	{"id": "npc_cipher_2",   "name": "学者B",    "region": "observatory", "pos": Vector2(10400, 3176), "portrait": "#80b2d4"},
	{"id": "npc_cipher_3",   "name": "工匠C",    "region": "observatory", "pos": Vector2(10500, 3176), "portrait": "#abb0b8"},
	{"id": "npc_cipher_4",   "name": "旅者D",    "region": "observatory", "pos": Vector2(10600, 3176), "portrait": "#b98b62"},
	{"id": "npc_cipher_5",   "name": "智者E",    "region": "observatory", "pos": Vector2(10700, 3176), "portrait": "#cba0ff"},

	# ── 地下迷宫 ──
	{"id": "cave_hermit",    "name": "洞穴隐士",  "region": "underground", "pos": Vector2(5000, 4256), "portrait": "#a3ccff"},
]

# ════════════════════════════════════════════════════════════
#  对话文本（精简版，后续可扩展）
# ════════════════════════════════════════════════════════════
const DIALOGUES: Dictionary = {
	"guide_old_man": [
		{"expr": "thinking", "text": "欢迎来到这片被遗忘的土地。左边森林里有奇怪的石墙，右边游乐园传来欢快的音乐声..."},
		{"expr": "happy", "text": "去探索吧。有些门需要用特殊的方式才能打开。"},
	],
	"map_keeper": [
		{"expr": "thinking", "text": "地图上标着六个关键地点。左边三个需要依次解锁，右边可以并行探索。"},
		{"expr": "happy", "text": "地下入口在瀑布附近...那里非常黑，只有最勇敢的人才能找到出口。"},
	],
	"ranger": [
		{"expr": "thinking", "text": "林子西边有面奇怪的墙。上面的纹路...像是在说什么。"},
		{"expr": "happy", "text": "别用眼睛看，用手去'读'它。"},
	],
	"poet": [
		{"expr": "sad", "text": "那座小楼里的画...在不同光线下看起来不一样。就像人的心情一样。"},
	],
	"house_keeper": [
		{"expr": "thinking", "text": "密室里藏着重要的东西。但你得先找到所有不同之处。"},
	],
	"dock_elder": [
		{"expr": "thinking", "text": "最近灯塔那边老是传来奇怪回音..."},
	],
	"keeper": [
		{"expr": "sad", "text": "共振器没坏，只是管道顺序乱了。声音还在，只是找不到回家的路。"},
	],
	"braille_scholar": [
		{"expr": "happy", "text": "这些凸点不是谜语，是文字。黑暗中也能阅读。"},
	],
	"engineer": [
		{"expr": "thinking", "text": "风向标的齿轮需要两个激光装置才能激活。一个来自密室，另一个...来自九宫格石台。"},
	],
	"sign_girl": [
		{"expr": "happy", "text": "...（她用手语比划着）...车站地板会说话..."},
		{"expr": "happy", "text_deaf": "她说：车站不是安静，它有很多从地板传来的话。"},
	],
	"painter": [
		{"expr": "thinking", "text": "宴会厅那幅油画...我看过小人在上面跳舞。那是给懂细节的人看的信号。"},
	],
	"station_master": [
		{"expr": "surprised", "text": "货运平台没停过，只是我们太晚才学会看它的预告。"},
	],
	"clown": [
		{"expr": "happy", "text": "游乐园的灯板会唱歌！但只有关掉灯才能听见它们真正的声音~"},
	],
	"mechanic": [
		{"expr": "thinking", "text": "灯板的正确按钮很稳定。假的总是急着吸引你的注意。"},
	],
	"ticket": [
		{"expr": "happy", "text": "如果你收集齐四把钥匙，地下深处有个宝箱在等你..."},
	],
	# NPC密码台 - 5个NPC的对话（含潜台词）
	"npc_cipher_1": [
		{"expr": "neutral", "text": "我守护这个地方已经很久了。（我其实很想休息）"},
		{"expr": "neutral", "text_depression": "他说：（我其实很想休息）"},
	],
	"npc_cipher_2": [
		{"expr": "neutral", "text": "知识就是力量。（但我害怕力量被滥用）"},
		{"expr": "neutral", "text_depression": "他说：（但我害怕力量被滥用）"},
	],
	"npc_cipher_3": [
		{"expr": "neutral", "text": "工具应该服务于人。（可人们总是被工具驱使）"},
		{"expr": "neutral", "text_depression": "他说：（可人们总是被工具驱使）"},
	],
	"npc_cipher_4": [
		{"expr": "neutral", "text": "旅途的意义在于过程。（我只想要一个家）"},
		{"expr": "neutral", "text_depression": "他说：（我只想要一个家）"},
	],
	"npc_cipher_5": [
		{"expr": "neutral", "text": "智慧来自于倾听。（没人真正听我说过话）"},
		{"expr": "neutral", "text_depression": "他说：（没人真正听我说过话）"},
	],
	"cave_hermit": [
		{"expr": "thinking", "text": "迷宫里有两岔路。左边通向一把钥匙，右边通往宝藏...但没有四把钥匙你打不开它。"},
		{"expr": "happy", "text": "闭上眼睛，用耳朵走路。正确的路会告诉你方向。"},
	],
}

# ════════════════════════════════════════════════════════════
#  收集品（纪念物）
# ════════════════════════════════════════════════════════════
const COLLECTIBLE_NAMES: Array = [
	"盲文卡片 A", "盲文卡片 B", "手语卡片 问候", "手语卡片 谢谢",
	"老照片 宴会厅", "老照片 游乐园", "儿时玩具 木马", "心灵碎片 微光",
	"风铃", "旧手套", "风筝线", "褪色照片", "纪念徽章"
]

# ════════════════════════════════════════════════════════════
#  默认游戏状态
# ════════════════════════════════════════════════════════════
static func default_state() -> Dictionary:
	return {
		"position": PLAYER_START,
		"current_view": "normal",
		"unlocked_views": ["normal"],
		"completed_levels": [],      # 已完成的关卡ID列表
		"collected_keys": [],         # 已收集的钥匙ID列表
		"fragments": [],
		"triggered_story": [],
		"npc_tasks": {},
		"collectibles": [],
		"album": [],
		"visited_anchors": [],
		"play_time": 0.0,
		"finished": false,
		# 关卡特定状态
		"texture_wall_progress": -1,  # 纹理墙进度 (-1=未开始, >=0=当前步骤)
		"find_diff_found": [],        # 找不同已发现的差异
		"dance_sequence_memorized": false,  # 舞蹈是否已记住
		"lights_solved": false,       # 灯板是否已解决
		"npc_subtexts_read": [],      # 已读取的NPC潜台词
		"maze_path_chosen": "",       # 迷宫选择的路径 ("A"/"B")
		# 激光系统状态
		"laser_1_placed": false,      # 激光装置1是否放入风向标1
		"laser_2_placed": false,      # 激光装置2是否放入风向标2
		"treasure_unlocked": false,   # 宝箱是否已开启
	}
