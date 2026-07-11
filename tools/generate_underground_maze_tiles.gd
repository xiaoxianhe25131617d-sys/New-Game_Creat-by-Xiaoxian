extends SceneTree

const SCENE_PATH := "res://maze/UndergroundMaze.tscn"
const REFERENCE_PATH := "res://assets/maze/underground_maze_reference.png"
const MAP_SCALE := 1.5
const TILE_SIZE := 8.0
const MIN_GRAY_PIXELS_PER_CELL := 7
const STAIR_SEGMENTS := [
	[Vector2(639, 214), Vector2(693, 149)],
	[Vector2(374, 514), Vector2(423, 453)],
	[Vector2(473, 677), Vector2(550, 573)],
	[Vector2(729, 941), Vector2(768, 886)],
	[Vector2(1367, 705), Vector2(1434, 764)],
	[Vector2(1548, 717), Vector2(1642, 828)],
	[Vector2(1264, 1058), Vector2(1326, 979)],
]

func _init() -> void:
	var source_image := Image.load_from_file(REFERENCE_PATH)
	if source_image == null or source_image.is_empty():
		push_error("Cannot load maze reference image")
		quit(1)
		return

	var packed := load(SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	var walls := root.get_node("Walls") as TileMapLayer
	var stairs := root.get_node("OneWayStairs") as TileMapLayer
	walls.clear()
	stairs.clear()

	var gray_counts: Dictionary = {}
	for source_y in range(source_image.get_height()):
		for source_x in range(source_image.get_width()):
			var pixel := source_image.get_pixel(source_x, source_y)
			if not _is_layout_gray(pixel):
				continue
			var game_position := Vector2(source_x, source_y) * MAP_SCALE
			var cell := Vector2i(floori(game_position.x / TILE_SIZE), floori(game_position.y / TILE_SIZE))
			gray_counts[cell] = int(gray_counts.get(cell, 0)) + 1

	for cell in gray_counts:
		if int(gray_counts[cell]) >= MIN_GRAY_PIXELS_PER_CELL:
			walls.set_cell(cell, 0, Vector2i(0, 0), 0)

	for segment in STAIR_SEGMENTS:
		_paint_one_way_stair(stairs, segment[0], segment[1])

	var output := PackedScene.new()
	var pack_error := output.pack(root)
	if pack_error != OK:
		push_error("Failed to pack maze scene: %s" % error_string(pack_error))
		quit(1)
		return
	var save_error := ResourceSaver.save(output, SCENE_PATH)
	if save_error != OK:
		push_error("Failed to save maze scene: %s" % error_string(save_error))
		quit(1)
		return
	print("Generated %d wall cells and %d one-way stair cells" % [walls.get_used_cells().size(), stairs.get_used_cells().size()])
	quit(0)

func _is_layout_gray(pixel: Color) -> bool:
	var channel_spread := maxf(pixel.r, maxf(pixel.g, pixel.b)) - minf(pixel.r, minf(pixel.g, pixel.b))
	var luminance := (pixel.r + pixel.g + pixel.b) / 3.0
	return pixel.a > 0.9 and channel_spread < 0.035 and luminance >= 0.45 and luminance <= 0.72

func _paint_one_way_stair(layer: TileMapLayer, source_start: Vector2, source_end: Vector2) -> void:
	var start_cell := Vector2i((source_start * MAP_SCALE / TILE_SIZE).round())
	var end_cell := Vector2i((source_end * MAP_SCALE / TILE_SIZE).round())
	var x0 := mini(start_cell.x, end_cell.x)
	var x1 := maxi(start_cell.x, end_cell.x)
	for cell_x in range(x0, x1 + 1):
		var amount := 0.0 if x0 == x1 else float(cell_x - start_cell.x) / float(end_cell.x - start_cell.x)
		var cell_y := roundi(lerpf(float(start_cell.y), float(end_cell.y), amount))
		layer.set_cell(Vector2i(cell_x, cell_y), 0, Vector2i(1, 0), 0)
