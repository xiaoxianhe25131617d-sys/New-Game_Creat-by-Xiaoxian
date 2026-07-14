# 地下迷宫下楼转场规格

## 目标

玩家在地面入口按 E 后，以第一人称视角走下一段石阶，并在现有入场音乐结束时进入地下迷宫。转场强化空间连续性，不改变迷宫、进度或存档规则。

## 技术与结构

- Godot 4.x / GDScript；不新增第三方依赖或位图素材。
- `scripts/underground_stair_transition.gd` 负责程序化画面、音乐播放和时序。
- `scenes/UndergroundStairTransition.tscn` 提供可复用转场场景。
- `scripts/main.gd` 只负责保存、锁定玩家、启动转场和切换迷宫场景。
- `tests/` 中的 headless 场景验证音乐时长映射、动画进度和完成信号。

## 行为与验收标准

- 转场与 `enter_underground_maze.MP3` 同时开始，时长从音频资源读取；当前资源约为 9.64 秒。
- 画面包含入口压暗、透视石阶向玩家移动、轻微步伐起伏、墙灯掠过和结尾黑场。
- 转场期间现有玩家输入和地面 BGM 保持暂停，状态在转场开始前保存。
- 完成信号只发出一次，随后进入 `res://maze/UndergroundMaze.tscn`。
- 音频缺失或长度无效时使用 9.64 秒兜底，不造成永久黑屏。

## 验证命令

```sh
godot --headless --rendering-method gl_compatibility --audio-driver Dummy --path . res://tests/UndergroundStairTransitionTest.tscn
godot --headless --rendering-method gl_compatibility --audio-driver Dummy --path . res://tests/LoginScreenTest.tscn
godot --headless --rendering-method gl_compatibility --audio-driver Dummy --path . res://tests/UndergroundMazeRuntimeTest.tscn
```

## 边界

- 始终：保留现有存档和场景切换语义；避免依赖 `.godot/` 缓存。
- 先询问：替换音乐、添加新美术资源、改变迷宫玩法或允许跳过转场。
- 禁止：修改未关联的地图编辑内容、缓存文件或用户现有工作。
