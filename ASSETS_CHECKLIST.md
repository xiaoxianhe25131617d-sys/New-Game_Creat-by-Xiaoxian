# 🎨 心灵视界 Mindscape — 美术素材清单 & AI生成提示词

> 游戏分辨率：**1280 × 720**（建议素材按此基准制作，或 2x 高清 2560×1440）

---

## 📁 一、文件命名规范

```
assets/
├── characters/       # 角色精灵
├── npcs/             # NPC 精灵
├── monsters/         # 怪物精灵
├── environments/     # 环境/地形/背景
│   ├── parallax/     # 视差背景层
│   ├── buildings/    # 建筑
│   └── props/        # 小物件
├── ui/               # 界面元素
├── effects/          # 特效
├── collectibles/     # 收集品
└── icons/            # 图标
```

建议格式：**PNG**（透明背景），精灵用 **精灵图集(spritesheet)** 或 **单帧 PNG**。

---

## 📋 二、完整素材清单（共 72 项）

### 🧑 1. 角色（Characters）

| # | 素材名 | 尺寸建议 | 说明 |
|---|--------|---------|------|
| 1 | 玩家主角 | 128×128 或 256×256 | 正太/少女风格，冒险装扮。需要 idle/walk/jump/dash 动画帧 |
| 2 | 盲人模式 — 玩家轮廓 | 128×128 | 通体发光轮廓（#4ac8ff），只勾勒形状，内部透明 |
| 3 | 聋人模式 — 玩家轮廓 | 128×128 | 柔和蓝灰发光轮廓（#8fb4d6） |
| 4 | ADHD模式 — 玩家轮廓 | 128×128 | 金色跳动轮廓（#ffde4a），边缘有残影效果 |
| 5 | 抑郁模式 — 玩家轮廓 | 128×128 | 淡蓝灰轮廓（#8ca7bd），半透明、边缘朦胧 |

#### 🤖 AI 提示词（玩家主角）

```
Sprite sheet for a 2D platformer game character. A young adventurer (age 12-14), 
androgynous, short messy hair, wearing a hooded traveler's cloak in warm earth tones 
(brown/orange). Simple anime/cartoon style, cel-shaded, 128x128 pixels per frame. 
Includes: idle standing (4 frames breathing), walking cycle (6 frames), jumping (2 frames), 
dashing (2 frames with speed lines). Clean transparent background, game asset style, 
Ghibli-inspired soft shading. --ar 1:1 --style 2d game asset
```

---

### 👥 2. NPC（非玩家角色）— 场景精灵

| # | NPC ID | 素材名 | 场景精灵尺寸 | 说明 |
|---|--------|--------|------------|------|
| 6 | bench_elder | 长椅老人 | 128×128 | 慈祥老人，戴帽子，坐在长椅旁 |
| 7 | florist | 花店老板 | 128×128 | 年轻女性，围裙，手持花束 |
| 8 | map_keeper | 地图管理员 | 128×128 | 中年男性，眼镜，手持地图/书本 |
| 9 | dock_elder | 码头老人 | 128×128 | 渔夫装扮，戴斗笠 |
| 10 | lighthouse | 灯塔管理员 | 128×128 | 穿工作服，手持提灯 |
| 11 | braille_scholar | 盲文学者 | 128×128 | 盲人，戴墨镜，手持盲文板 |
| 12 | sign_girl | 手语少女 | 128×128 | 年轻女孩，用手语比划 |
| 13 | painter | 流浪画家 | 128×128 | 背画架，手持画笔 |
| 14 | station_master | 站长 | 128×128 | 穿制服，戴站长帽 |
| 15 | clown | 小丑 | 128×128 | 彩色小丑服，红鼻子 |
| 16 | repairman | 修理工 | 128×128 | 工装裤，扳手 |
| 17 | ticket_seller | 售票员 | 128×128 | 窗口售票员装扮 |
| 18 | ranger | 护林员 | 128×128 | 户外装扮，望远镜 |
| 19 | poet | 诗人 | 128×128 | 文雅装扮，笔记本 |
| 20 | camper | 露营者 | 128×128 | 背包客装扮 |
| 21 | astronomer | 天文学家 | 128×128 | 白大褂，星图 |
| 22 | engineer | 老工程师 | 128×128 | 安全帽，蓝图 |

#### 🤖 AI 提示词（NPC 场景精灵）

```
2D game character sprite, [角色描述], side-view standing pose, 
128x128 pixels, cel-shaded anime style, soft Ghibli-inspired colors, 
transparent background, game asset for platformer. --style 2d game asset
```

---

### 🖼️ 2B. NPC 对话立绘（Portraits）⭐ 重要

> **立绘用于对话框左侧的人物半身像显示。** 当 NPC 对话时，对话框左边会展示其表情立绘。
> 如果没有提供立绘 PNG，游戏会自动降级为纯色方块 + 文字表情（^_^ / ;_; / o_O）。

#### 📐 立绘规格

| 参数 | 推荐值 |
|------|--------|
| **立绘图片尺寸** | **300 × 380 px**（2x 高清）或 **450 × 570 px**（3x 超清） |
| 对话框内显示尺寸 | 150 × 190 px（自动等比缩放） |
| 格式 | **PNG**，透明背景（RGBA） |
| 构图 | 半身像（胸部以上），人物居中偏上 |
| 风格 | 与场景精灵一致：赛璐璐/吉卜力柔和风 |

#### 📁 文件命名规范

```
assets/portraits/{npc_id}_{表情}.png
```

示例：
```
assets/portraits/bench_elder_normal.png
assets/portraits/bench_elder_happy.png
assets/portraits/bench_elder_thinking.png
assets/portraits/sign_girl_normal.png
assets/portraits/sign_girl_happy.png
assets/portraits/clown_surprised.png
```

#### 每个 NPC 至少准备的表情

| 表情 key | 用途 | 推荐数量 |
|----------|------|---------|
| `normal` | 默认表情，**必须有**（fallback） | 必选 ×1 |
| `happy` | 高兴/微笑 | 推荐 |
| `sad` | 悲伤 | 推荐 |
| `thinking` | 思考/回忆 | 推荐 |
| `surprised` | 惊讶 | 可选 |

> ⚠️ **`_normal` 是所有表情找不到时的 fallback**，所以每个 NPC 至少要有一张 `{npc_id}_normal.png`。

#### 📋 17 个 NPC 立绘清单

| # | NPC ID | NPC 名称 | 立绘文件名 | AI 生成提示词 |
|---|--------|----------|-----------|-------------|
| 1 | bench_elder | 长椅老人 | `bench_elder_normal/happy/thinking.png` | `Elderly man portrait for game dialog, bust-up, warm gentle expression, wearing a soft brown hat, kind eyes, Ghibli-inspired watercolor style, 300x380 px, transparent background, character art for visual novel RPG. --style character portrait` |
| 2 | florist | 花店老板 | `florist_normal/happy/sad.png` | `Young woman portrait, florist with apron, holding a flower near her chest, soft smile, warm sunlight feel, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 3 | map_keeper | 地图管理员 | `map_keeper_normal/thinking.png` | `Middle-aged man portrait, glasses, holding an old map, studious expression, warm brown tones, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 4 | dock_elder | 码头老人 | `dock_elder_normal/happy.png` | `Old fisherman portrait, wearing a bamboo hat (douli), weathered kind face, sea-blue accents, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 5 | lighthouse | 灯塔管理员 | `lighthouse_normal/happy/thinking.png` | `Lighthouse keeper portrait, work uniform, holding a small lantern with warm glow, dedicated expression, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 6 | braille_scholar | 盲文学者 | `braille_scholar_normal/happy.png` | `Blind scholar portrait, wearing dark round sunglasses, holding a braille slate, gentle smile, calm warm colors, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 7 | sign_girl | 手语少女 | `sign_girl_normal/happy/sad.png` | `Young girl portrait, hands posed near her face doing sign language, cheerful bright expression, soft pastel colors, Ghibli-inspired anime portrait style, 300x380 px, transparent background. --style character portrait` |
| 8 | painter | 流浪画家 | `painter_normal/happy/thinking.png` | `Wandering artist portrait, paintbrush in hand, paint smudge on cheek, dreamy artistic expression, colorful scarf, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 9 | station_master | 站长 | `station_master_normal/happy.png` | `Station master portrait, wearing a formal uniform and cap, proud but warm expression, vintage railway aesthetic, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 10 | clown | 小丑 | `clown_normal/happy/surprised.png` | `Clown portrait, colorful costume, red nose, playful theatrical expression, slightly melancholic undertone, circus warm colors, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 11 | repairman | 修理工 | `repairman_normal/thinking.png` | `Repairman portrait, in overalls, holding a wrench, grease smudge, reliable friendly expression, industrial warm tones, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 12 | ticket_seller | 售票员 | `ticket_seller_normal/happy.png` | `Ticket seller portrait, behind a window counter, neat uniform, helpful smile, vintage ticket booth vibe, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 13 | ranger | 护林员 | `ranger_normal/happy.png` | `Forest ranger portrait, outdoor gear, binoculars around neck, nature-loving expression, earthy green tones, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 14 | poet | 诗人 | `poet_normal/thinking/sad.png` | `Poet portrait, elegant literary attire, holding a small leather notebook, contemplative dreamy expression, sepia warm tones, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 15 | camper | 露营者 | `camper_normal/happy.png` | `Young camper portrait, backpack visible, outdoorsy casual clothes, cheerful adventurous expression, warm campfire tones, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 16 | astronomer | 天文学家 | `astronomer_normal/happy/thinking.png` | `Astronomer portrait, white lab coat, holding a star chart, wonder-filled expression, deep blue and gold cosmic accents, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |
| 17 | engineer | 老工程师 | `engineer_normal/thinking.png` | `Old engineer portrait, safety helmet, holding a blueprint, focused experienced expression, warm industrial tones, Ghibli watercolor style, 300x380 px, transparent background. --style character portrait` |

#### 🤖 立绘生成通用提示词模板

```
Bust-up character portrait for a visual novel / RPG dialog box, [NPC描述], 
half-body, chest-up composition, facing slightly left (toward dialog text), 
soft cel-shaded Ghibli-inspired watercolor style, 300x380 pixels, 
clean transparent background PNG, character isolated, 
warm natural lighting, no text or UI elements. --style character portrait --ar 3:4
```

> 💡 **提示**：每个 NPC 批量生成时，保持 `seed` 和风格描述一致，只改表情描述即可保证是同一个角色。

---

### 👾 3. 怪物（Monsters）

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 23 | 信息噪音球 (Noise) | 128×128 或 256×256 | 蓝色(#4fc8ff)扭曲球体，表面波动的混乱文字/符号，发光 |
| 24 | 无声嘴巴 (Silent Mouth) | 128×128 | 苍白(#d4e4f4)的悬浮嘴巴，紧闭不发声，周围有振动波纹 |
| 25 | 干扰者 (Distractor) | 128×128 | 金色(#ffdf41)多面体，不断变换形状，周围有假箭头/幻影 |
| 26 | 阴影 (Shadow) | 128×128 | 深黑(#2a2d38)不定形阴影，边缘模糊，眼睛是暗红色光点 |

#### 🤖 AI 提示词（怪物）

```
【信息噪音球】
A floating sphere made of chaotic glowing text and symbols, electric blue (#4fc8ff) 
with white noise static on its surface, pulsing with distorted waves, 
2D game enemy sprite, 256x256, dark fantasy style, transparent background. 
Emitting particles of garbled data. --style digital art

【无声嘴巴】
A pale floating disembodied mouth (#d4e4f4), lips tightly sealed, 
surrounded by faint vibration ripples in the air, quiet and eerie, 
2D game enemy sprite, 128x128, minimalist horror style, transparent background. 
--style 2d game asset

【干扰者】
A golden (#ffdf41) geometric polyhedron that seems to flicker between shapes, 
surrounded by phantom arrows pointing in conflicting directions and afterimages, 
2D game enemy sprite, 128x128, glitch art style, transparent background. 
--style digital art

【阴影】
An amorphous dark shadow creature (#2a2d38), barely visible against darkness, 
its edges blurring into the surroundings, two faint red glowing eyes, 
2D game enemy sprite, 128x128, atmospheric horror style, transparent background. 
--style 2d game asset
```

---

### 🌍 4. 环境 — 视差背景层（Parallax）

> 视差背景应该是宽幅长条，可以 **无缝循环拼接(seamless tile)**

| # | 素材名 | 建议尺寸 | 说明 |
|---|--------|---------|------|
| 27 | 远景山脉 | 1920×600 | 淡蓝灰色远山剪影，最慢视差层(0.05) |
| 28 | 中景丘陵 | 1920×500 | 绿色丘陵起伏，第二层(0.15) |
| 29 | 云朵 | 1920×400 | 蓬松白云，单独一层便于移动(0.08) |
| 30 | 前景树木剪影 | 1920×500 | 深绿色树木剪影，最快视差层(0.3) |
| 31 | 天空渐变底 | 1920×1080 | 从上到下：淡蓝→暖白→米黄 的柔和渐变 |
| 32 | 地下洞穴背景 | 1920×600 | 深蓝灰色洞穴岩壁，有发光水晶点缀 |
| 33 | 星空夜空背景 | 1920×600 | 夜空 + 星星，用于天文台区域 |

#### 🤖 AI 提示词（视差背景）

```
【远景山脉】
Distant mountain silhouette, soft watercolor style, pale blue-grey (#c8dae8), 
misty atmosphere, horizontal landscape banner, 1920x600 pixels, seamless tileable, 
Ghibli-inspired background art, minimal detail for parallax scrolling. --style landscape

【云朵层】
Fluffy white clouds on transparent background, horizontal layer 1920x400 pixels, 
soft painted style, warm sunlight glow from upper left, seamless tileable for game parallax. 
--style 2d game background

【前景树木】
Dark green tree silhouettes (#5a8f4a) on transparent background, 
horizontal forest canopy layer 1920x500 pixels, varying tree heights, 
silhouette style, seamless tileable for game parallax scrolling. --style silhouette
```

---

### 🏗️ 5. 建筑/场景地标（Buildings）

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 34 | 灯塔 | 160×500 | 白色灯塔，顶部发光，带红色条纹 |
| 35 | 水坝 | 400×250 | 混凝土水坝，有水流效果 |
| 36 | 旧车站 | 800×200 | 红砖老式火车站建筑 |
| 37 | 摩天轮 | 400×400 | 彩色摩天轮，8个吊舱 |
| 38 | 天文台穹顶 | 200×150 | 白色圆顶，望远镜开口 |
| 39 | 时间胶囊 | 150×100 | 金属胶囊/宝箱，发出暖光 |
| 40 | 地下泵站 | 300×200 | 蒸汽朋克风格管道机械 |

---

### 🪨 6. 地形/地面素材

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 41 | 草地地表瓦片 | 64×64 或 256×64 | 绿色草地，可无缝拼接 |
| 42 | 泥土/石层 | 64×64 | 地下横截面，分层颜色 |
| 43 | 木质平台 | 256×32 | 可行走的木板平台 |
| 44 | 石质平台 | 256×32 | 石砖平台 |
| 45 | 洞穴地表 | 256×64 | 深色洞穴地面 |

#### 🤖 AI 提示词（地形）

```
2D platformer ground tile, grassy surface with dark soil underneath, 
256x64 pixels, side-view, cel-shaded game art style, seamless tileable, 
bright green grass on top, brown dirt layers below. --style 2d game asset --tile
```

---

### 🌸 7. 装饰小物件（Props）

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 46 | 花卉 (4色变体) | 32×32 | 粉/黄/紫/白四色小花 |
| 47 | 草丛 | 32×32 | 地面草丛 |
| 48 | 岩石 | 32×32 | 小石头，3种大小 |
| 49 | 地下水晶 | 32×48 | 发光蓝白水晶 |
| 50 | 记忆长椅 | 128×64 | 公园长椅，暖色光辉 |
| 51 | 金色引导光点 | 16×16 | 地面引导轨迹的小光点 |

---

### ⭐ 8. 收集品 & 标记

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 52 | 纪念物图标 | 64×64 | 星形/纪念品图标 (#f9f4bf) |
| 53 | 回声共鸣石 | 128×128 | 发光符文石 (#ffea5c)，带粒子效果 |
| 54 | 机关标记 | 64×64 | 金色齿轮/机关图标 (#ffe08c) |
| 55 | 传送点标记 | 64×64 | 上下箭头标记 |
| 56 | 5个信物碎片 | 128×128 | 风铃/手套/风筝/照片/徽章 |

---

### 🖥️ 9. UI 界面素材

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 57 | 主菜单背景 | 1280×720 | 深蓝/星空氛围，标题居中 |
| 58 | 对话框背景 | 800×200 | 半透明深色面板，圆角 |
| 59 | 暂停菜单面板 | 420×300 | 半透明面板 |
| 60 | 视角轮盘面板 | 400×380 | 半透明面板，圆角 |
| 61 | 按钮样式 (普通) | 280×52 | 米色/暖色调按钮 |
| 62 | 按钮样式 (悬停) | 280×52 | 高亮版按钮 |
| 63 | HUD 顶栏 | 1280×40 | 半透明深色条 |
| 64 | 登录界面背景 | 1280×720 | 深蓝灰背景 |
| 65 | NPC 头像框 | 64×64 | 圆形头像框（每位NPC一个） |

#### 🤖 AI 提示词（UI）

```
Game UI panel, semi-transparent dark background with warm gold border, 
rounded corners, parchment/paper texture overlay, fantasy storybook aesthetic, 
400x380 pixels, clean and minimal design. --style ui design
```

---

### ✨ 10. 特效（Effects）

| # | 素材名 | 尺寸 | 说明 |
|---|--------|------|------|
| 66 | 回声脉冲环 | 256×256 | 白色同心圆环，从中心向外扩散 |
| 67 | 冲刺残影 | 128×128 | 水平模糊残影 |
| 68 | 振动波纹 | 256×64 | 水平振动波纹（聋人视角） |
| 69 | 脚印痕迹 | 64×64 | 发光脚印（抑郁视角追踪） |
| 70 | 粒子 — 星光 | 32×32 | 金色/白色小光点粒子 |
| 71 | 粒子 — 灰尘 | 16×16 | 棕色小尘粒 |
| 72 | 屏幕伤害闪烁 | 1280×720 | 红色/蓝色半透明覆盖，用于怪物攻击反馈 |

---

## 📐 三、推荐制作流程

### 阶段 1：核心角色（优先）
1. 玩家主角精灵 + 4种视角轮廓
2. 4个怪物

### 阶段 2：环境基础
3. 天空渐变底 + 3层视差背景
4. 草地/地形瓦片

### 阶段 3：建筑地标
5. 灯塔、车站、摩天轮、天文台

### 阶段 4：NPC + UI
6. 12个NPC + 头像
7. UI面板和按钮

### 阶段 5：润色
8. 装饰物件、特效、收集品

---

## 🔧 四、技术建议

| 参数 | 推荐值 |
|------|--------|
| 精灵尺寸 | 128×128（角色），可放大到 256×256 |
| 精灵格式 | 单帧 PNG（Godot 支持 spritesheet 切分） |
| 背景格式 | PNG（透明需保留的地方）/ JPG（纯色背景） |
| 无缝拼接 | 256px 或 512px 宽为一个循环单元 |
| UI素材 | 9-slice 缩放友好，考虑使用 NinePatchRect |
| 色彩深度 | 32-bit RGBA |
| 动画帧数 | idle 4帧 / walk 6帧 / jump 2帧 |

---

> 💡 **提示**：建议先出 3-5 张关键素材看风格方向对不对，再批量生成。可用 Midjourney / DALL-E / Stable Diffusion 生成后，在 Aseprite 或 Photoshop 中裁剪修整。
