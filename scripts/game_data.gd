extends RefCounted
class_name GameData

# ════════════════════════════════════════════════════════════
#  四种视角: 盲人 / ADHD / 自闭症 / 抑郁症
# ════════════════════════════════════════════════════════════

const VIEWS: Array = ["normal", "blind", "adhd", "autism", "depression"]

const VIEW_NAMES: Dictionary = {
	"normal": "普通视角",
	"blind": "盲人视角（全黑+听觉感知）",
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

# Legacy spatial defaults remain for old saves and standalone tests only.
# Runtime placement, regions and bounds come from map/MainWorld.tscn.
const PLAYER_START: Vector2 = Vector2(3400, 3168)
const WORLD_SIZE: Vector2 = Vector2(11200, 3600)

# ════════════════════════════════════════════════════════════
#  6大关卡定义 — 石墙之后依次排列
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
	"key_4":  {"name": "天文台钥匙",  "source": "npc_password",      "color": Color("#a29bfe")},
	"maze_key": {"name": "迷宫钥匙", "source": "underground_maze", "color": Color("#73d6d2")},
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
	{"id": "guide_old_man", "name": "引导老人", "region": "spawn", "pos": Vector2(3200, 3200), "portrait": "#b98b62", "sprite_index": 0},
	{"id": "map_keeper",    "name": "地图管理员", "region": "spawn", "pos": Vector2(3600, 3200), "portrait": "#80b2d4", "sprite_index": 1},
	{"id": "ranger",        "name": "护林员",    "region": "forest", "pos": Vector2(2600, 3200), "portrait": "#719d64", "sprite_index": 2},
	{"id": "poet",          "name": "诗人",      "region": "forest", "pos": Vector2(3200, 3200), "portrait": "#b1a0d8", "sprite_index": 3},
	{"id": "house_keeper",  "name": "密室看守",  "region": "forest", "pos": Vector2(2900, 3200), "portrait": "#cba0ff", "sprite_index": 4},
	{"id": "dock_elder",    "name": "码头老人",  "region": "lighthouse", "pos": Vector2(4650, 3200), "portrait": "#8d9fba", "sprite_index": 5},
	{"id": "keeper",        "name": "灯塔管理员", "region": "lighthouse", "pos": Vector2(5330, 3200), "portrait": "#d8a25e", "sprite_index": 6},
	{"id": "braille_scholar","name": "盲文学者",  "region": "lighthouse", "pos": Vector2(4430, 3200), "portrait": "#71b8ff", "blind_npc": true, "sprite_index": 7},
	{"id": "engineer",      "name": "总工程师",  "region": "dam", "pos": Vector2(5000, 3200), "portrait": "#abb0b8", "sprite_index": 8},
	{"id": "sign_girl",     "name": "手语少女",  "region": "station", "pos": Vector2(6200, 3200), "portrait": "#a8d5bd", "sign_only": true, "sprite_index": 9},
	{"id": "painter",       "name": "流浪画家",  "region": "station", "pos": Vector2(6400, 3200), "portrait": "#cba0ff", "sprite_index": 10},
	{"id": "station_master","name": "看报老人",  "region": "station", "pos": Vector2(6800, 3200), "portrait": "#94adc6", "sprite_index": 11},
	{"id": "clown",         "name": "小丑",      "region": "park", "pos": Vector2(7500, 3200),  "portrait": "#ff7d7d", "sprite_index": 12},
	{"id": "mechanic",      "name": "修理工",    "region": "park", "pos": Vector2(7900, 3200),  "portrait": "#d9be6a", "sprite_index": 13},
	{"id": "ticket",        "name": "售票员",    "region": "park", "pos": Vector2(8300, 3200),  "portrait": "#78d0b8", "sprite_index": 14},
	{"id": "npc_cipher_5",  "name": "智者E",     "region": "observatory", "pos": Vector2(9000, 3198), "portrait": "#cba0ff", "sprite_index": 19},
	{"id": "npc_cipher_4",  "name": "旅者D",     "region": "observatory", "pos": Vector2(9400, 3200), "portrait": "#b98b62", "sprite_index": 18},
	{"id": "npc_cipher_3",  "name": "工匠C",     "region": "observatory", "pos": Vector2(9800, 3202), "portrait": "#abb0b8", "sprite_index": 17},
	{"id": "npc_cipher_2",  "name": "学者B",     "region": "observatory", "pos": Vector2(10220, 3202), "portrait": "#80b2d4", "sprite_index": 16},
	{"id": "npc_cipher_1",  "name": "守卫A",     "region": "observatory", "pos": Vector2(10940, 3198), "portrait": "#94adc6", "sprite_index": 15},
]

const DIALOGUES: Dictionary = {
	"guide_old_man": [
		{"expr": "thinking", "text": "我每天都在长椅边扫落叶。那几个孩子小时候总爱把树叶排成一列，摸一摸就知道哪片最厚。"},
	],
	"map_keeper": [
		{"expr": "thinking", "text": "我把地图上的旧钉子都换过一遍了。孩子们以前会在地图边上画小记号，提醒彼此别走丢。"},
	],
	"ranger": [
		{"expr": "thinking", "text": "我巡林时常摸树皮辨方向。那几个孩子也这样玩过，谁先认出老橡树，谁就能挑今天的游戏。"},
	],
	"poet": [
		{"expr": "sad", "text": "我喜欢在画廊门口晒墨水。孩子们以前会盯着一幅画看很久，每个人都说自己先看见了不一样的东西。"},
	],
	"house_keeper": [
		{"expr": "thinking", "text": "我看门很多年了，最有用的习惯是先记住原来的样子，再换个角度确认。孩子们玩找不同时也是这么做的。"},
	],
	"dock_elder": [
		{"expr": "thinking", "text": "我在码头听潮声吃饭，声音从哪里回来，往往比声音本身更重要。孩子们小时候会在岸边喊彼此的名字。"},
	],
	"keeper": [
		{"expr": "sad", "text": "灯塔的齿轮一转，我就知道该给它上油了。孩子们小时候拿手电筒照墙，玩过一整晚的光影。"},
	],
	"braille_scholar": [
		{"expr": "happy", "text": "我把每一块盲文板都摸过一遍。那些孩子小时候会用手指摸树皮，然后把摸到的感觉讲给朋友听。"},
	],
	"engineer": [
		{"expr": "thinking", "text": "我修机器时喜欢先找两条线的交点。孩子们小时候用镜子和手电筒玩光影，倒也摸到了这个道理。"},
	],
	"sign_girl": [
		{"expr": "happy", "text": "...她比划着：我记得那天的地板一直在震动。孩子们笑着用脚步回答她。", "text_autism": "地板在震动。她说，孩子们以前用脚步互相回答。"},
	],
	"painter": [
		{"expr": "thinking", "text": "我画画先画动作，再补颜色。孩子们以前会看着画里的小人学跳舞，顺序一乱就笑成一团。"},
	],
	"station_master": [
		{"expr": "surprised", "text": "我每天在站台边看报，字看久了会自己排成小路。镇子最右边那几个人，说话里常有和书上相似的字。"},
	],
	"clown": [
		{"expr": "happy", "text": "啊呀，你说那个密码本啊？那个专心的孩子总在书里写写画画，说是在模仿谍战片。顺序才是关键。"},
	],
	"mechanic": [
		{"expr": "thinking", "text": "我修灯板时会先听声音，再看哪盏灯亮。小房子那边有人说了假话，可孩子在意的还有那个人没说出口的心里话。"},
	],
	"ticket": [
		{"expr": "happy", "text": "我每天撕票根，孩子们以前会把票根折成小风筝，跑到风最大的地方去放。"},
	],
	"npc_cipher_1": [
		{"expr": "thinking", "text": "你说那些孩子们啊，他们以前可顽皮啊。他们过去常常爬那棵老橡树，最高那个枝丫只有最小的那个敢爬上去。"},
	],
	"npc_cipher_2": [
		{"expr": "neutral", "text": "嘿我和你说，我家屋檐上那块松了的瓦，前天我自己爬上去修好了，没请人，省了两块钱工钱。", "subtext": "我才不会说其实我爬不上去呢，让别人笑话"},
	],
	"npc_cipher_3": [
		{"expr": "neutral", "text": "傍晚那会儿风大，把我晾在外头的被单吹到篱笆上，还好没掉泥地里。"},
	],
	"npc_cipher_4": [
		{"expr": "happy", "text": "诶诶诶你问我可问对了，这里好玩的事情不少，我家公鸡昨天下了一个蛋，你说神不神奇？", "subtext": "诶呀逗逗外乡人玩，公鸡怎么会下蛋呢？"},
	],
	"npc_cipher_5": [
		{"expr": "thinking", "text": "等等别打扰我，我还在等邮差送信呢。"},
	],
}

const PUZZLE_NOTES: Dictionary = {
	"texture_wall": {
		"title": "纹理墙",
		"text": "石墙上面的机关很难感觉出来，\n要触感特别敏锐的人才可以......\n那时候我们只有一个人能摸出来。"
	},
	"find_difference": {
		"title": "找不同密室",
		"text": "我们布置了一个小房间，这个房间按我们都记得的那个样子布置就会打开机关！\n我们也许都会记混一些事情，但是找到共同点，能行！\n只要我们一起合作..."
	},
	"banquet_painting": {
		"title": "宴会厅",
		"text": "我想，我是不是也能跳出那样的舞蹈。\n跳得高一些就跳得远一些，看清方向，从红色开始。\n我还藏了更多提示在这个小镇里，是一些小方块。"
	},
	"nine_grid": {
		"title": "九宫格",
		"text": "我有点难过的时候会想到这些。\n所以我把它们一格一格画下来了。"
	},
	"amusement_lights": {
		"title": "游乐园灯板",
		"text": "在空的地方按开始后，就可以很快地按下所有正确的灯了。\n要快，十五秒内！",
		"braille": "⠕⠄\t⠝⠼⠂\t⠞⠡⠁⠙⠖⠆\t⠌⠼⠆⠅⠾⠆\t⠙⠢\t⠙⠼⠁\n⠋⠔⠁⠟⠥⠁\t⠅⠡⠁⠉⠺⠆\t⠙⠢\t⠱⠼⠁⠣⠁",
		"translation": "我能听到正确的灯发出清脆的声音。"
	},
	"npc_password": {
		"title": "密码本",
		"text": "细心就能看出哪些字是关键。\n五句线索的顺序也很重要。"
	},
	"laser_focus": {
		"title": "激光聚焦台",
		"text": "我们藏了两个激光仪哦，需要都找到才能玩这个。"
	},
	"laser_focus_ready": {
		"title": "激光聚焦台",
		"text": "两个激光可以确定一个点嘿嘿，但是贼快，只有动作很快的人才能更容易地玩。"
	},
	"underground_maze": {
		"title": "地下迷宫",
		"text": "这里的路不会告诉你答案。\n走对时，声音会越来越近；走偏时，先停下来听一听。"
	}
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
		"album_piece_positions": {},
		"album_puzzles_completed": [],
		"seen_notes": [],
		"visited_anchors": [],
		"play_time": 0.0,
		"finished": false,
		"texture_wall_progress": -1,
		"find_diff_found": [],
		"dance_sequence_memorized": false,
		"lights_solved": false,
		"npc_subtexts_read": [],
		"laser_1_placed": false,
		"laser_2_placed": false,
		"laser_focus_1_installed": false,
		"laser_focus_2_installed": false,
		"laser_1_angle": 0.0,
		"laser_2_angle": 0.0,
		"treasure_unlocked": false,
		"hidden_door_opened": false,
		"maze_compass_owned": false,
		"maze_compass_enabled": false,
		"maze_compass_route_index": 0,
		"hidden_chest_opened": false,
		"ending_seen": false,
		"ending_pending": false,
		"ending_source": "",
		"debug_laser_loadout": false,
		"is_debug_profile": false,
		"debug_preset": "",
		"debug_spawn_target": "",
		"intro_seen": false,
		"opening_seen": false,
		"opening_version": 0,
	}

static func migrate_state(state: Dictionary) -> bool:
	var changed := false
	var defaults := {
		"hidden_door_opened": false,
		"maze_compass_owned": false,
		"maze_compass_enabled": false,
		"maze_compass_route_index": 0,
		"hidden_chest_opened": false,
		"ending_seen": false,
		"ending_pending": false,
		"ending_source": "",
		"debug_laser_loadout": false,
		"is_debug_profile": false,
		"debug_preset": "",
		"debug_spawn_target": "",
		"intro_seen": false,
		"opening_seen": false,
		"opening_version": 0,
		"album_piece_positions": {},
		"album_puzzles_completed": [],
		"seen_notes": [],
	}
	for key in defaults:
		if not state.has(key):
			state[key] = defaults[key]
			changed = true
	var completed: Array = state.get("completed_levels", []) as Array
	if completed.has("laser_focus"):
		if not bool(state.get("hidden_door_opened", false)):
			state["hidden_door_opened"] = true
			changed = true
		if not bool(state.get("maze_compass_owned", false)):
			state["maze_compass_owned"] = true
			changed = true
	return changed

static func unlock_hidden_door(state: Dictionary) -> bool:
	var first_unlock := not bool(state.get("hidden_door_opened", false))
	state["hidden_door_opened"] = true
	state["maze_compass_owned"] = true
	if not state.has("maze_compass_enabled"):
		state["maze_compass_enabled"] = false
	return first_unlock

static func toggle_maze_compass(state: Dictionary) -> bool:
	if not bool(state.get("maze_compass_owned", false)):
		state["maze_compass_enabled"] = false
		return false
	var enabled := not bool(state.get("maze_compass_enabled", false))
	state["maze_compass_enabled"] = enabled
	return enabled

static func open_hidden_chest(state: Dictionary) -> bool:
	if bool(state.get("ending_seen", false)) or bool(state.get("hidden_chest_opened", false)):
		return false
	var keys: Array = state.get("collected_keys", []) as Array
	if not keys.has("maze_key"):
		return false
	keys.erase("maze_key")
	state["collected_keys"] = keys
	state["hidden_chest_opened"] = true
	state["finished"] = true
	state["maze_compass_enabled"] = false
	state["ending_pending"] = true
	state["ending_source"] = "hidden_chest"
	return true

static func begin_ending(state: Dictionary, source: String) -> bool:
	if bool(state.get("ending_seen", false)):
		return false
	state["ending_pending"] = true
	state["ending_source"] = source
	if source == "hidden_chest":
		state["hidden_chest_opened"] = true
		state["maze_compass_enabled"] = false
	return true

static func complete_ending(state: Dictionary) -> void:
	state["ending_seen"] = true
	state["ending_pending"] = false
	state["finished"] = true
	state["maze_compass_enabled"] = false
	state["position"] = PLAYER_START
	var album: Array = state.get("album", []) as Array
	var entries := ["结局：理解的风景", "最终合照"]
	if str(state.get("ending_source", "")) == "hidden_chest":
		entries.append("童年旧物：陀螺、弹珠、纸飞机与手绳")
	for entry in entries:
		if not album.has(entry):
			album.append(entry)
	state["album"] = album

static func mark_ending_seen(state: Dictionary) -> void:
	complete_ending(state)
