extends RefCounted
class_name GameData

# ════════════════════════════════════════════════════════════
#  四种视角: 盲人 / ADHD / 自闭症 / 抑郁症
# ════════════════════════════════════════════════════════════

const VIEWS: Array = ["normal", "blind", "adhd", "autism", "depression"]

const VIEW_NAMES: Dictionary = {
	"normal": "普通视角",
	"blind": "盲人视角（全黑+回声定位）",
	"adhd": "ADHD视角（自动行走+冲刺）",
	"autism": "自闭症视角（细节放大+模式识别）",
	"depression": "抑郁视角（灰暗+潜台词+尖刺）",
}

const VIEW_COLORS: Dictionary = {
	"normal": Color("#f5d58e"),
	"blind": Color("#4ac8ff"),
	"adhd": Color("#ffde4a"),
	"autism": Color("#a0d0ff"),
	"depression": Color("#6b7b8d"),
}

const PLAYER_START: Vector2 = Vector2(3400, 3168)
const WORLD_SIZE: Vector2 = Vector2(11200, 4500)

# ════════════════════════════════════════════════════════════
#  7大关卡定义 — 石墙之后依次排列
# ════════════════════════════════════════════════════════════
const LEVELS: Array = [
	{
		"id": "texture_wall",
		"name": "纹理墙（石门）",
		"region": "forest",
		"pos": Vector2(4200, 3168),
		"type": "texture_wall",
		"prereq": "",
		"reward": "stone_door",
		"hint": "一堵石墙挡住了去路。盲人模式下用手'触摸'它的纹理。",
		"view_hint": "需要盲人模式才能感受纹理解开石门。",
	},
	{
		"id": "find_difference",
		"name": "找不同密室",
		"region": "forest",
		"pos": Vector2(5000, 3170),
		"type": "find_diff",
		"prereq": "",
		"reward": "laser_device_1",
		"hint": "密室内5个物体各有3种状态。不同视角看到不同样子，正确状态是两视角一致的那个。",
		"view_hint": "ADHD/抑郁/自闭视角分别看到物体不同状态，找到两两一致的正确状态。",
	},
	{
		"id": "banquet_painting",
		"name": "宴会厅油画",
		"region": "forest",
		"pos": Vector2(5800, 3100),
		"type": "dance_sequence",
		"prereq": "",
		"reward": "key_1",
		"hint": "油画中的小人在跳舞！记住他们的舞步顺序...",
		"view_hint": "自闭症/抑郁模式看清舞蹈序列。",
	},
	{
		"id": "nine_grid",
		"name": "石台拼图",
		"region": "dam",
		"pos": Vector2(6600, 3165),
		"type": "nine_grid",
		"prereq": "",
		"reward": "laser_device_2",
		"hint": "石台上散落着带抑郁元素的方块。抑郁模式能看到正确答案。",
		"view_hint": "抑郁模式直接显示正确排列图形。",
	},
	{
		"id": "dark_maze",
		"name": "地下黑暗迷宫",
		"region": "underground",
		"pos": Vector2(5400, 4250),
		"type": "audio_maze",
		"prereq": "",
		"reward": "key_3",
		"hint": "从灯塔旁走下去。完全黑暗——只有盲人模式能靠声音导航。",
		"view_hint": "盲人模式：听觉导航是唯一出路。",
	},
	{
		"id": "amusement_lights",
		"name": "游乐园灯板",
		"region": "park",
		"pos": Vector2(7800, 3140),
		"type": "light_board",
		"prereq": "",
		"reward": "key_2",
		"hint": "3个浮空平台上的灯！跳跃上去按数字键点亮。",
		"view_hint": "ADHD模式助你更快跳跃。",
	},
	{
		"id": "npc_password",
		"name": "NPC密码台",
		"region": "observatory",
		"pos": Vector2(9800, 3170),
		"type": "npc_cipher",
		"prereq": "",
		"reward": "key_4",
		"hint": "5个NPC各说一句话。听懂他们没说出口的...",
		"view_hint": "抑郁模式看到潜台词，自闭症模式读密码本。",
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

# ════════════════════════════════════════════════════════════
#  风向标 + 激光联动系统
# ════════════════════════════════════════════════════════════
const LASER_SYSTEM: Dictionary = {
	"laser_device_1": {"name": "激光装置1", "source": "find_difference"},
	"laser_device_2": {"name": "激光装置2", "source": "nine_grid"},
	"wind_vane_1":   {"name": "风向标1",   "pos": Vector2(4200, 3040), "direction": Vector2(1, 0.3)},
	"wind_vane_2":   {"name": "风向标2",   "pos": Vector2(7200, 3040), "direction": Vector2(-1, 0.3)},
	"treasure_pos":  Vector2(5600, 2900),
}

# ════════════════════════════════════════════════════════════
#  NPC 定义
# ════════════════════════════════════════════════════════════
const NPCS: Array = [
	{"id": "guide_old_man", "name": "引导老人", "region": "spawn", "pos": Vector2(3200, 3176), "portrait": "#b98b62"},
	{"id": "map_keeper",    "name": "地图管理员", "region": "spawn", "pos": Vector2(3600, 3176), "portrait": "#80b2d4"},
	{"id": "ranger",        "name": "护林员",    "region": "forest", "pos": Vector2(2600, 3176), "portrait": "#719d64"},
	{"id": "poet",          "name": "诗人",      "region": "forest", "pos": Vector2(3200, 3176), "portrait": "#b1a0d8"},
	{"id": "house_keeper",  "name": "密室看守",  "region": "forest", "pos": Vector2(2900, 3176), "portrait": "#cba0ff"},
	{"id": "dock_elder",    "name": "码头老人",  "region": "lighthouse", "pos": Vector2(4650, 3176), "portrait": "#8d9fba"},
	{"id": "keeper",        "name": "灯塔管理员", "region": "lighthouse", "pos": Vector2(5330, 3176), "portrait": "#d8a25e"},
	{"id": "braille_scholar","name": "盲文学者",  "region": "lighthouse", "pos": Vector2(4430, 3176), "portrait": "#71b8ff", "blind_npc": true},
	{"id": "engineer",      "name": "总工程师",  "region": "dam", "pos": Vector2(5000, 3176), "portrait": "#abb0b8"},
	{"id": "sign_girl",     "name": "手语少女",  "region": "station", "pos": Vector2(6200, 3176), "portrait": "#a8d5bd", "sign_only": true},
	{"id": "painter",       "name": "流浪画家",  "region": "station", "pos": Vector2(6400, 3176), "portrait": "#cba0ff"},
	{"id": "station_master","name": "站长",      "region": "station", "pos": Vector2(6800, 3176), "portrait": "#94adc6"},
	{"id": "clown",         "name": "小丑",      "region": "park", "pos": Vector2(7500, 3176),  "portrait": "#ff7d7d"},
	{"id": "mechanic",      "name": "修理工",    "region": "park", "pos": Vector2(7900, 3176),  "portrait": "#d9be6a"},
	{"id": "ticket",        "name": "售票员",    "region": "park", "pos": Vector2(8300, 3176),  "portrait": "#78d0b8"},
	{"id": "npc_cipher_1",  "name": "站台守卫",  "region": "observatory", "pos": Vector2(9000, 3176), "portrait": "#94adc6"},
	{"id": "npc_cipher_2",  "name": "读书人",    "region": "observatory", "pos": Vector2(9250, 3176), "portrait": "#80b2d4"},
	{"id": "npc_cipher_3",  "name": "工匠",      "region": "observatory", "pos": Vector2(9500, 3176), "portrait": "#abb0b8"},
	{"id": "npc_cipher_4",  "name": "旅人",      "region": "observatory", "pos": Vector2(10100, 3176), "portrait": "#b98b62"},
	{"id": "npc_cipher_5",  "name": "老者",      "region": "observatory", "pos": Vector2(10350, 3176), "portrait": "#cba0ff"},
	{"id": "cave_hermit",   "name": "洞穴隐士",  "region": "underground", "pos": Vector2(5100, 4256), "portrait": "#a3ccff"},
]

const DIALOGUES: Dictionary = {
	"guide_old_man": [
		{"expr": "thinking", "text": "欢迎。前方有一堵石墙挡住了去路..."},
		{"expr": "happy", "text": "闭上眼睛，用手去触摸它。只有放下视觉，才能感知纹理。"},
	],
	"map_keeper": [
		{"expr": "thinking", "text": "石墙后面有7个挑战在等着你。四个区域，四种视角。"},
		{"expr": "happy", "text": "地下入口在灯塔附近——那里一片漆黑。"},
	],
	"ranger": [
		{"expr": "thinking", "text": "石墙不只是石头。它上面有盲文一样的纹理。"},
		{"expr": "happy", "text": "用盲人视角能读懂它的语言。"},
	],
	"poet": [
		{"expr": "sad", "text": "那小楼里的画...在不同视线下完全不一样。像人的心情。"},
	],
	"house_keeper": [
		{"expr": "thinking", "text": "密室里藏着4个秘密。只有转换视角才能看全。"},
	],
	"dock_elder": [
		{"expr": "thinking", "text": "灯塔那边有回声——有些是真的，有些是假的。"},
	],
	"keeper": [
		{"expr": "sad", "text": "灯在转，但声音跟不上。声音迷路了。"},
	],
	"braille_scholar": [
		{"expr": "happy", "text": "触觉是另一种语言。闭上眼睛，你就能听到石头的诗。"},
	],
	"engineer": [
		{"expr": "thinking", "text": "两个激光装置，两个风向标。光的交点就是宝物的位置。"},
	],
	"sign_girl": [
		{"expr": "happy", "text": "...（她用手语比划）...地板在震动..."},
	],
	"painter": [
		{"expr": "thinking", "text": "宴会厅那幅油画...小人跳舞的顺序就是密码。"},
	],
	"station_master": [
		{"expr": "surprised", "text": "站台从来没停过。是我们不会看它的预告。"},
	],
	"clown": [
		{"expr": "happy", "text": "灯板上的灯会唱歌！跳上去听它们的声音~"},
	],
	"mechanic": [
		{"expr": "thinking", "text": "跳跃才能点到灯。ADHD模式让你跳得更高更快。"},
	],
	"ticket": [
		{"expr": "happy", "text": "四把钥匙集齐了？地下深处宝箱在等你。"},
	],
	"npc_cipher_1": [
		{"expr": "neutral", "text": "我守在这里很久了。", "subtext": "第一个位置，像门一样"},
	],
	"npc_cipher_2": [
		{"expr": "neutral", "text": "知识有时是负担。", "subtext": "第二个人，梦总是一对"},
	],
	"npc_cipher_3": [
		{"expr": "neutral", "text": "工具比人更诚实。", "subtext": "第三道裂痕最危险"},
	],
	"npc_cipher_4": [
		{"expr": "neutral", "text": "旅途没有终点。", "subtext": "第四个倒影无人认领"},
	],
	"npc_cipher_5": [
		{"expr": "neutral", "text": "倾听是最难的修行。", "subtext": "第五根手指，沾满墨迹"},
	],
	"cave_hermit": [
		{"expr": "thinking", "text": "迷宫深处有两条路。一条通向钥匙，一条通向宝藏。"},
		{"expr": "happy", "text": "闭上眼睛，用耳朵走路。正确的方向会唱歌。"},
	],
}

const COLLECTIBLE_NAMES: Array = [
	"盲文卡片 A", "手语卡片 问候", "老照片 宴会厅", "老照片 游乐园",
	"儿时玩具 木马", "心灵碎片 微光", "风铃", "旧手套",
	"风筝线", "褪色照片", "纪念徽章"
]

const REGIONS: Dictionary = {
	"spawn":      {"name": "出生点",     "x": 3400, "view": "normal"},
	"forest":     {"name": "左侧森林",   "x": 2800, "view": "depression"},
	"plaza":      {"name": "中央广场",   "x": 3400, "view": "normal"},
	"lighthouse": {"name": "湖泊灯塔",   "x": 4900, "view": "blind"},
	"dam":        {"name": "水坝工业区", "x": 5600, "view": "normal"},
	"station":    {"name": "旧车站",     "x": 6400, "view": "autism"},
	"park":       {"name": "游乐园",     "x": 7700, "view": "adhd"},
	"observatory":{"name": "许愿堂",     "x": 9800, "view": "depression"},
	"underground":{"name": "地下迷宫",   "x": 5400, "view": "blind", "y": 4300},
}

static func default_state() -> Dictionary:
	return {
		"position": PLAYER_START,
		"current_view": "normal",
		"unlocked_views": ["normal", "blind", "adhd", "autism", "depression"],
		"completed_levels": [],
		"collected_keys": [],
		"fragments": [],
		"triggered_story": [],
		"npc_tasks": {},
		"collectibles": [],
		"album": [],
		"visited_anchors": [],
		"play_time": 0.0,
		"finished": false,
		"texture_wall_progress": -1,
		"find_diff_found": [],
		"dance_sequence_memorized": false,
		"lights_solved": false,
		"npc_subtexts_read": [],
		"maze_path_chosen": "",
	"laser_1_placed": false,
	"laser_2_placed": false,
	"laser_1_angle": 0.0,
	"laser_2_angle": 0.0,
	"treasure_unlocked": false,
	}
