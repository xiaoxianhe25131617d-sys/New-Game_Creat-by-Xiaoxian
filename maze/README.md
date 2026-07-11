# Underground Maze Authoring

Open `UndergroundMaze.tscn` directly in Godot and press F6 to run it independently.

- Toggle `ReferenceImage` through the root `show_reference_in_editor` property. It is always hidden in the running game.
- Edit solid gray geometry on the `Walls` TileMapLayer with atlas tile `(0, 0)`.
- Edit jump-through diagonal steps on `OneWayStairs` with atlas tile `(1, 0)`.
- Move or scale each `Ladders/LadderXX` Area2D to change a climb route. Its collision and drawn rungs scale together.
- Move the five `Markers` freely. Their `persistent_id` metadata must remain unique.
- Keep content inside the `Bounds` rectangle (`3096 x 1758`).

`tools/generate_underground_maze_tiles.gd` rebuilds wall and stair cells from the source image. Running it again replaces manual TileMap edits, so use it only when intentionally resetting the traced layout.
