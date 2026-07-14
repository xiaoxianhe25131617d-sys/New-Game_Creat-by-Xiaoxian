# 主世界地图编辑清单

主世界的空间布局以 `MainWorld.tscn` 为准。运行时脚本只根据这些节点创建玩法对象，不再决定它们的位置。

## 在 Godot 中编辑

1. 打开 `map/MainWorld.tscn`，使用 2D 视图编辑。
2. 在 `Visuals/TileMaps` 修改现有 TileMap；PNG 地图可作为 `Sprite2D` 添加到 `Visuals`。
3. 普通碰撞放在 `Collisions`，使用 `StaticBody2D` 和 `CollisionShape2D` 或 `CollisionPolygon2D`。
4. 单向平台放在 `DropThroughPlatforms`，碰撞层设置为 2，并在碰撞形状上启用 `one_way_collision`。
5. 在 `Markers` 的对应分类中移动 `Marker2D`，即可调整玩家、NPC、谜题、收集物、怪物和特殊装置位置。
6. 在 `Regions` 移动或缩放 `Area2D` 的矩形碰撞，即可调整区域音乐范围。
7. 移动 `WorldBounds/top_left` 和 `bottom_right` 可以修改存档合法范围和相机边界。

## 必须保持稳定的内容

- 不要修改 `Markers` 下现有分类名和标记 ID；这些名称与存档、对话及谜题配置关联。
- 新增玩法对象时，先在对应分类添加唯一命名的 `Marker2D`，再在 `GameData` 添加非空间配置。
- `TextureWallBlocker` 是可被谜题移除的特殊碰撞体，不要改名。
- `.godot/` 是编辑器缓存，不属于地图源文件。

## 验证

```bash
godot --headless --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/world_layout_contract_test.gd
godot --headless --rendering-method gl_compatibility --audio-driver Dummy --path . res://tests/WorldRuntimeSmokeTest.tscn
```

最后使用 F5 检查移动、跳跃、互动、视角切换、谜题和存档恢复。
